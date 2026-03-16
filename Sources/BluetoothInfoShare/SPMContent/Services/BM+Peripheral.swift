//
//  BluetoothManager+Peripheral.swift
//  BluetoothInfoShare
//

import Foundation
import CoreBluetooth
import Combine

extension BluetoothManager {

    // MARK: - Service & Characteristic UUIDs

    public static let dataSharingServiceUUID = CBUUID(
        string: "A1B2C3D4-E5F6-7890-1234-56789ABCDEF0"
    )
    public static let dataSharingCharacteristicUUID = CBUUID(
        string: "A1B2C3D4-E5F6-7890-1234-56789ABCDEF1"
    )

    // MARK: - Static Peripheral State

    public static var peripheralManager: CBPeripheralManager?
    public static var transferCharacteristic: CBMutableCharacteristic?
    private(set) static var advertisementInfo: AdvertisementInfo?
    private(set) static var serviceAdded = false

    // MARK: - Publishers

    public static let peripheralStateSubject      = PassthroughSubject<CBManagerState, Never>()
    public static let isAdvertisingSubject        = PassthroughSubject<Bool, Never>()
    public static let centralDidSubscribeSubject  = PassthroughSubject<CBCentral, Never>()

    // Separate subjects for the two receive paths so their buffers never mix:
    //   • dataReceivedSubject   — notify path (peripheral → central via updateValue)
    //   • writeReceivedSubject  — write path  (central → peripheral via writeValue)
    public static let dataReceivedSubject         = PassthroughSubject<Data, Never>()
    public static let writeReceivedSubject        = PassthroughSubject<Data, Never>()

    public static var peripheralStatePublisher: AnyPublisher<CBManagerState, Never> {
        peripheralStateSubject.eraseToAnyPublisher()
    }
    public static var isAdvertisingPublisher: AnyPublisher<Bool, Never> {
        isAdvertisingSubject.eraseToAnyPublisher()
    }
    public static var centralDidSubscribePublisher: AnyPublisher<CBCentral, Never> {
        centralDidSubscribeSubject.eraseToAnyPublisher()
    }
    /// Emits complete payloads received via BLE notify (peripheral → central).
    public static var dataReceivedPublisher: AnyPublisher<Data, Never> {
        dataReceivedSubject.eraseToAnyPublisher()
    }
    /// Emits complete payloads received via BLE write (central → peripheral).
    public static var writeReceivedPublisher: AnyPublisher<Data, Never> {
        writeReceivedSubject.eraseToAnyPublisher()
    }

    // MARK: - Data Transfer State

    public static var dataToSend:        Data?
    public static var sendDataIndex      = 0
    public static let chunkSize          = 182
    public static var eomPending         = false

    // Two separate receive buffers — one per direction.
    public static var notifyReceiveBuffer = Data()   // central side  (notify path)
    public static var writeReceiveBuffer  = Data()   // peripheral side (write path)

    // MARK: - Setup

    public func setupPeripheralManager(delegate: CBPeripheralManagerDelegate) {
        guard BluetoothManager.peripheralManager == nil else { return }
        BluetoothManager.peripheralManager = CBPeripheralManager(
            delegate: delegate,
            queue: bluetoothQueue
        )
    }

    public func setAdvertisementInfo(_ info: AdvertisementInfo) {
        BluetoothManager.advertisementInfo = info
    }

    // MARK: - Advertising

    public func startAdvertising() {
        guard
            let peripheralManager = BluetoothManager.peripheralManager,
            peripheralManager.state == .poweredOn,
            let info = BluetoothManager.advertisementInfo
        else {
            print("[BluetoothInfoShare] startAdvertising ignored — not ready.")
            return
        }

        if !BluetoothManager.serviceAdded {
            let characteristic = CBMutableCharacteristic(
                type: BluetoothManager.dataSharingCharacteristicUUID,
                properties: [.notify, .writeWithoutResponse, .write],
                value: nil,
                permissions: [.readable, .writeable]
            )
            BluetoothManager.transferCharacteristic = characteristic

            let service = CBMutableService(
                type: BluetoothManager.dataSharingServiceUUID,
                primary: true
            )
            service.characteristics = [characteristic]
            peripheralManager.add(service)
            BluetoothManager.serviceAdded = true
            print("[BluetoothInfoShare] Service registered.")
        }

        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BluetoothManager.dataSharingServiceUUID],
            CBAdvertisementDataLocalNameKey:    info.advertisementLocalName()
        ])

        BluetoothManager.isAdvertisingSubject.send(true)
        print("[BluetoothInfoShare] Advertising started: \(info.advertisementLocalName())")
    }

    public func stopAdvertising() {
        BluetoothManager.peripheralManager?.stopAdvertising()
        BluetoothManager.isAdvertisingSubject.send(false)
    }

    public var isAdvertising: Bool {
        BluetoothManager.peripheralManager?.isAdvertising ?? false
    }

    // MARK: - Data Sending (peripheral → central via notify)

    public func sendData(_ data: Data) {
        print("[BluetoothInfoShare] sendData: \(data.count) bytes queued.")
        BluetoothManager.dataToSend    = data
        BluetoothManager.sendDataIndex = 0
        BluetoothManager.eomPending    = false
        sendNextChunk()
    }

    public func sendNextChunk() {
        guard
            let characteristic    = BluetoothManager.transferCharacteristic,
            let peripheralManager = BluetoothManager.peripheralManager
        else { return }

        if BluetoothManager.eomPending {
            guard let eomData = "EOM".data(using: .utf8) else { return }
            let sent = peripheralManager.updateValue(
                eomData, for: characteristic, onSubscribedCentrals: nil
            )
            print("[BluetoothInfoShare] EOM retry sent: \(sent)")
            if sent {
                BluetoothManager.eomPending    = false
                BluetoothManager.dataToSend    = nil
                BluetoothManager.sendDataIndex = 0
            }
            return
        }

        guard let data = BluetoothManager.dataToSend else { return }

        if BluetoothManager.sendDataIndex >= data.count {
            guard let eomData = "EOM".data(using: .utf8) else { return }
            let sent = peripheralManager.updateValue(
                eomData, for: characteristic, onSubscribedCentrals: nil
            )
            print("[BluetoothInfoShare] EOM sent: \(sent)")
            if sent {
                BluetoothManager.dataToSend    = nil
                BluetoothManager.sendDataIndex = 0
                BluetoothManager.eomPending    = false
            } else {
                BluetoothManager.eomPending = true
            }
            return
        }

        let endIndex = min(
            BluetoothManager.sendDataIndex + BluetoothManager.chunkSize,
            data.count
        )
        let chunk    = data.subdata(in: BluetoothManager.sendDataIndex..<endIndex)
        let didSend  = peripheralManager.updateValue(
            chunk, for: characteristic, onSubscribedCentrals: nil
        )
        print("[BluetoothInfoShare] Chunk [\(BluetoothManager.sendDataIndex)..<\(endIndex)] sent: \(didSend)")
        if didSend {
            BluetoothManager.sendDataIndex = endIndex
            sendNextChunk()
        }
    }

    // MARK: - Data Receiving — notify path (central receives from peripheral)
    // Called from CBPeripheralDelegate.didUpdateValueFor in BM_Central.

    public static func handleNotifyData(_ data: Data) {
        if let marker = String(data: data, encoding: .utf8), marker == "EOM" {
            guard !notifyReceiveBuffer.isEmpty else { return }
            print("[BluetoothInfoShare] Notify EOM — emitting \(notifyReceiveBuffer.count) bytes.")
            dataReceivedSubject.send(notifyReceiveBuffer)
            notifyReceiveBuffer = Data()
        } else {
            print("[BluetoothInfoShare] Notify chunk: \(data.count) bytes.")
            notifyReceiveBuffer.append(data)
        }
    }

    // MARK: - Data Receiving — write path (peripheral receives from central)
    // Called from PeripheralManagerDelegateHandler.didReceiveWrite.

    public static func handleWriteData(_ data: Data) {
        if let marker = String(data: data, encoding: .utf8), marker == "EOM" {
            guard !writeReceiveBuffer.isEmpty else { return }
            print("[BluetoothInfoShare] Write EOM — emitting \(writeReceiveBuffer.count) bytes.")
            writeReceivedSubject.send(writeReceiveBuffer)
            writeReceiveBuffer = Data()
        } else {
            print("[BluetoothInfoShare] Write chunk: \(data.count) bytes.")
            writeReceiveBuffer.append(data)
        }
    }

    // MARK: - Peripheral Manager Callbacks

    public static func peripheralManagerDidUpdateState(_ state: CBManagerState) {
        peripheralStateSubject.send(state)
    }

    public static func peripheralManagerIsReadyToSend() {
        if eomPending || (dataToSend != nil && sendDataIndex < (dataToSend?.count ?? 0)) {
            BluetoothManager.shared.sendNextChunk()
        }
    }
}
