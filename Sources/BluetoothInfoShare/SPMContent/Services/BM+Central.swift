//
//  BluetoothManager+Central.swift
//  BluetoothInfoShare
//

import Foundation
import CoreBluetooth

extension BluetoothManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateSubject.send(central.state)
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoverySubject.send((peripheral, advertisementData))
    }

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        print("[BluetoothInfoShare] didConnect: \(peripheral.identifier)")
        connectedSubject.send(peripheral)

        if let continuation = connectContinuations.removeValue(forKey: peripheral.identifier) {
            continuation.resume(returning: peripheral)
        }

        peripheral.delegate = self
        peripheral.discoverServices([BluetoothManager.dataSharingServiceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        print("[BluetoothInfoShare] didFailToConnect: \(peripheral.identifier) — \(error?.localizedDescription ?? "unknown")")
        let connectionError = error ?? NSError(
            domain: "com.bluetoothinfoshare",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Connection failed with no error detail."]
        )
        connectionErrorSubject.send((peripheral, connectionError))
        if let continuation = connectContinuations.removeValue(forKey: peripheral.identifier) {
            continuation.resume(throwing: connectionError)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        print("[BluetoothInfoShare] didDisconnect: \(peripheral.identifier) error=\(error?.localizedDescription ?? "none")")
        disconnectedSubject.send(peripheral)
        if let continuation = disconnectContinuations.removeValue(forKey: peripheral.identifier) {
            continuation.resume(returning: peripheral)
        }
        if let error = error {
            connectionErrorSubject.send((peripheral, error))
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            print("[BluetoothInfoShare] didDiscoverServices ERROR: \(error.localizedDescription)")
            return
        }
        let found = peripheral.services?.map { $0.uuid.uuidString } ?? []
        print("[BluetoothInfoShare] didDiscoverServices: \(found)")

        guard let service = peripheral.services?.first(where: {
            $0.uuid == BluetoothManager.dataSharingServiceUUID
        }) else {
            print("[BluetoothInfoShare] dataSharingService NOT found — peripheral may not have added it yet.")
            return
        }
        peripheral.discoverCharacteristics(
            [BluetoothManager.dataSharingCharacteristicUUID],
            for: service
        )
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error = error {
            print("[BluetoothInfoShare] didDiscoverCharacteristics ERROR: \(error.localizedDescription)")
            return
        }
        let found = service.characteristics?.map { $0.uuid.uuidString } ?? []
        print("[BluetoothInfoShare] didDiscoverCharacteristics: \(found)")

        guard let characteristic = service.characteristics?.first(where: {
            $0.uuid == BluetoothManager.dataSharingCharacteristicUUID
        }) else {
            print("[BluetoothInfoShare] dataSharingCharacteristic NOT found.")
            return
        }

        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
            print("[BluetoothInfoShare] setNotifyValue(true) sent.")
        }

        // 300ms delay — let peripheral confirm the subscription before we write.
        bluetoothQueue.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            print("[BluetoothInfoShare] centralGATTReady firing for \(peripheral.identifier)")
            self?.centralGATTReadySubject.send(peripheral)
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BluetoothInfoShare] didUpdateNotificationState ERROR: \(error.localizedDescription)")
        } else {
            print("[BluetoothInfoShare] Notify state confirmed: \(characteristic.isNotifying)")
        }
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BluetoothInfoShare] didUpdateValueFor ERROR: \(error.localizedDescription)")
            return
        }
        guard let value = characteristic.value else { return }
        print("[BluetoothInfoShare] didUpdateValueFor: \(value.count) bytes received.")
        BluetoothManager.handleReceivedData(value)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BluetoothInfoShare] didWriteValueFor ERROR: \(error.localizedDescription)")
        } else {
            print("[BluetoothInfoShare] didWriteValueFor: write confirmed.")
        }
    }
}
