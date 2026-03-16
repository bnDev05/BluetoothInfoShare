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

    // Track whether the service has already been added so we never call
    // peripheralManager.add(service) twice — doing so replaces
    // transferCharacteristic with an unregistered object and breaks notify.
    private(set) static var serviceAdded = false

    // MARK: - Publishers (eagerly initialised — never nil)

    public static let peripheralStateSubject     = PassthroughSubject<CBManagerState, Never>()
    public static let isAdvertisingSubject       = PassthroughSubject<Bool, Never>()
    public static let dataReceivedSubject        = PassthroughSubject<Data, Never>()
    public static let centralDidSubscribeSubject = PassthroughSubject<CBCentral, Never>()

    public static var peripheralStatePublisher: AnyPublisher<CBManagerState, Never> {
        peripheralStateSubject.eraseToAnyPublisher()
    }
    public static var isAdvertisingPublisher: AnyPublisher<Bool, Never> {
        isAdvertisingSubject.eraseToAnyPublisher()
    }
    public static var dataReceivedPublisher: AnyPublisher<Data, Never> {
        dataReceivedSubject.eraseToAnyPublisher()
    }
    public static var centralDidSubscribePublisher: AnyPublisher<CBCentral, Never> {
        centralDidSubscribeSubject.eraseToAnyPublisher()
    }

    // MARK: - Data Transfer State

    public static var dataToSend:        Data?
    public static var sendDataIndex      = 0
    public static let chunkSize          = 182
    public static var receivedDataBuffer = Data()

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

        // Only create and register the characteristic + service ONCE.
        // Calling peripheralManager.add() again would replace
        // transferCharacteristic with an unregistered object, breaking notify.
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
        sendNextChunk()
    }

    public func sendNextChunk() {
        guard
            let data              = BluetoothManager.dataToSend,
            let characteristic    = BluetoothManager.transferCharacteristic,
            let peripheralManager = BluetoothManager.peripheralManager
        else {
            print("[BluetoothInfoShare] sendNextChunk: missing data/characteristic/manager.")
            return
        }

        if BluetoothManager.sendDataIndex >= data.count {
            guard let eomData = "EOM".data(using: .utf8) else { return }
            let sent = peripheralManager.updateValue(
                eomData, for: characteristic, onSubscribedCentrals: nil
            )
            print("[BluetoothInfoShare] EOM sent: \(sent)")
            BluetoothManager.dataToSend    = nil
            BluetoothManager.sendDataIndex = 0
            return
        }

        let endIndex = min(
            BluetoothManager.sendDataIndex + BluetoothManager.chunkSize,
            data.count
        )
        let chunk = data.subdata(in: BluetoothManager.sendDataIndex..<endIndex)
        let didSend = peripheralManager.updateValue(
            chunk, for: characteristic, onSubscribedCentrals: nil
        )
        print("[BluetoothInfoShare] Chunk [\(BluetoothManager.sendDataIndex)..<\(endIndex)] sent: \(didSend)")

        if didSend {
            BluetoothManager.sendDataIndex = endIndex
            sendNextChunk()
        }
        // If didSend == false, peripheralManagerIsReady resumes.
    }

    // MARK: - Data Receiving (peripheral ← central via write)

    public static func handleReceivedData(_ data: Data) {
        if let marker = String(data: data, encoding: .utf8), marker == "EOM" {
            guard !receivedDataBuffer.isEmpty else { return }
            print("[BluetoothInfoShare] EOM received — emitting \(receivedDataBuffer.count) bytes.")
            dataReceivedSubject.send(receivedDataBuffer)
            receivedDataBuffer = Data()
        } else {
            print("[BluetoothInfoShare] Received chunk: \(data.count) bytes.")
            receivedDataBuffer.append(data)
        }
    }

    // MARK: - Peripheral Manager Callbacks

    public static func peripheralManagerDidUpdateState(_ state: CBManagerState) {
        peripheralStateSubject.send(state)
    }

    public static func peripheralManagerIsReadyToSend() {
        guard let data = dataToSend, sendDataIndex < data.count else { return }
        BluetoothManager.shared.sendNextChunk()
    }
}
