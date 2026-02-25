import Foundation
import UIKit
import CoreBluetooth
import Combine

extension BluetoothManager {

    public static let dataSharingServiceUUID        = CBUUID(string: "A1B2C3D4-E5F6-7890-1234-56789ABCDEF0")
    public static let dataSharingCharacteristicUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-1234-56789ABCDEF1")

    public  static var peripheralManager: CBPeripheralManager?
    public  static var transferCharacteristic: CBMutableCharacteristic?

    public static let peripheralStatePublisher: AnyPublisher<CBManagerState, Never> = {
        let subject = PassthroughSubject<CBManagerState, Never>()
        peripheralStateSubject = subject
        return subject.eraseToAnyPublisher()
    }()
    public  static var peripheralStateSubject: PassthroughSubject<CBManagerState, Never>?

    public static let isAdvertisingPublisher: AnyPublisher<Bool, Never> = {
        let subject = PassthroughSubject<Bool, Never>()
        isAdvertisingSubject = subject
        return subject.eraseToAnyPublisher()
    }()
    public  static var isAdvertisingSubject: PassthroughSubject<Bool, Never>?

    public static let dataReceivedPublisher: AnyPublisher<Data, Never> = {
        let subject = PassthroughSubject<Data, Never>()
        dataReceivedSubject = subject
        return subject.eraseToAnyPublisher()
    }()
    public static var dataReceivedSubject: PassthroughSubject<Data, Never>?

    public  static var dataToSend: Data?
    public  static var sendDataIndex = 0
    public  static let chunkSize = 182
    public  static var receivedData = Data()

    public func setupPeripheralManager(delegate: CBPeripheralManagerDelegate) {
        if BluetoothManager.peripheralManager == nil {
            BluetoothManager.peripheralManager = CBPeripheralManager(
                delegate: delegate,
                queue: bluetoothQueue
            )
        }
    }

    public func startAdvertising() {
        guard let peripheralManager = BluetoothManager.peripheralManager,
              peripheralManager.state == .poweredOn else { return }

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
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BluetoothManager.dataSharingServiceUUID],
            CBAdvertisementDataLocalNameKey: "\(AppConstants.lastFourCardNumber)\(AppConstants.objectID)\(AppConstants.userID)\(AppConstants.userName)"
        ])

        BluetoothManager.isAdvertisingSubject?.send(true)
    }
    
    public func stopAdvertising() {
        BluetoothManager.peripheralManager?.stopAdvertising()
        BluetoothManager.isAdvertisingSubject?.send(false)
    }
    
    public var isAdvertising: Bool {
        BluetoothManager.peripheralManager?.isAdvertising ?? false
    }
    
    public func sendData(_ data: Data) {
        BluetoothManager.dataToSend = data
        BluetoothManager.sendDataIndex = 0
        sendNextChunk()
    }
    
    public func sendNextChunk() {
        guard let data = BluetoothManager.dataToSend,
              let characteristic = BluetoothManager.transferCharacteristic,
              let peripheralManager = BluetoothManager.peripheralManager else { return }

        if BluetoothManager.sendDataIndex >= data.count {
            let eomData = "EOM".data(using: .utf8)!
            peripheralManager.updateValue(eomData, for: characteristic, onSubscribedCentrals: nil)
            BluetoothManager.dataToSend = nil
            BluetoothManager.sendDataIndex = 0
            return
        }

        let endIndex = min(BluetoothManager.sendDataIndex + BluetoothManager.chunkSize, data.count)
        let chunk = data.subdata(in: BluetoothManager.sendDataIndex..<endIndex)

        let didSend = peripheralManager.updateValue(chunk, for: characteristic, onSubscribedCentrals: nil)

        if didSend {
            BluetoothManager.sendDataIndex = endIndex
            sendNextChunk()
        }
    }
    
    public static func handleReceivedData(_ data: Data) {
        if let string = String(data: data, encoding: .utf8), string == "EOM" {
            if !receivedData.isEmpty {
                dataReceivedSubject?.send(receivedData)
                receivedData = Data()
            }
        } else {
            receivedData.append(data)
        }
    }
    
    public static func peripheralManagerDidUpdateState(_ state: CBManagerState) {
        peripheralStateSubject?.send(state)
    }
    
    public static func peripheralManagerIsReadyToSend() {
        guard let _ = dataToSend, sendDataIndex < (dataToSend?.count ?? 0) else { return }
    }
}
