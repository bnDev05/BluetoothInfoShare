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

    // MARK: - Publishers (all eagerly initialised — never nil)

    public static let peripheralStateSubject    = PassthroughSubject<CBManagerState, Never>()
    public static let isAdvertisingSubject      = PassthroughSubject<Bool, Never>()
    /// Emits fully reassembled Data payloads once an EOM marker is received.
    public static let dataReceivedSubject       = PassthroughSubject<Data, Never>()
    /// Emits the CBCentral that just subscribed to the transfer characteristic.
    /// BluetoothService observes this to immediately push the sensitive payload.
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
    /// Fires when a central subscribes — use this to trigger sensitive payload transmission.
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

    // MARK: - Advertising (userName only in local name — fits passive scan limit)

    public func startAdvertising() {
        guard
            let peripheralManager = BluetoothManager.peripheralManager,
            peripheralManager.state == .poweredOn,
            let info = BluetoothManager.advertisementInfo
        else {
            print("[BluetoothInfoShare] startAdvertising ignored — manager not ready or no AdvertisementInfo set.")
            return
        }

        let characteristic = CBMutableCharacteristic(
            type: BluetoothManager.dataSharingCharacteristicUUID,
            properties: [.notify, .writeWithoutResponse, .write],
            value: nil,
            permissions: [.readable, .writeable]
        )
        BluetoothManager.transferCharacteristic = characteristic

        let service = CBMutableService(type: BluetoothManager.dataSharingServiceUUID, primary: true)
        service.characteristics = [characteristic]

        peripheralManager.add(service)
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BluetoothManager.dataSharingServiceUUID],
            CBAdvertisementDataLocalNameKey:    info.advertisementLocalName()
        ])

        BluetoothManager.isAdvertisingSubject.send(true)
    }

    public func stopAdvertising() {
        BluetoothManager.peripheralManager?.stopAdvertising()
        BluetoothManager.isAdvertisingSubject.send(false)
    }

    public var isAdvertising: Bool {
        BluetoothManager.peripheralManager?.isAdvertising ?? false
    }

    // MARK: - Data Sending

    public func sendData(_ data: Data) {
        BluetoothManager.dataToSend    = data
        BluetoothManager.sendDataIndex = 0
        sendNextChunk()
    }

    public func sendNextChunk() {
        guard
            let data              = BluetoothManager.dataToSend,
            let characteristic    = BluetoothManager.transferCharacteristic,
            let peripheralManager = BluetoothManager.peripheralManager
        else { return }

        if BluetoothManager.sendDataIndex >= data.count {
            guard let eomData = "EOM".data(using: .utf8) else { return }
            peripheralManager.updateValue(eomData, for: characteristic, onSubscribedCentrals: nil)
            BluetoothManager.dataToSend    = nil
            BluetoothManager.sendDataIndex = 0
            return
        }

        let endIndex = min(
            BluetoothManager.sendDataIndex + BluetoothManager.chunkSize,
            data.count
        )
        let chunk = data.subdata(in: BluetoothManager.sendDataIndex..<endIndex)

        let didSend = peripheralManager.updateValue(chunk, for: characteristic, onSubscribedCentrals: nil)
        if didSend {
            BluetoothManager.sendDataIndex = endIndex
            sendNextChunk()
        }
    }

    // MARK: - Data Receiving

    public static func handleReceivedData(_ data: Data) {
        if let marker = String(data: data, encoding: .utf8), marker == "EOM" {
            guard !receivedDataBuffer.isEmpty else { return }
            dataReceivedSubject.send(receivedDataBuffer)
            receivedDataBuffer = Data()
        } else {
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
