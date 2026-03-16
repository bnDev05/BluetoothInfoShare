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
        let err = error ?? NSError(
            domain: "com.bluetoothinfoshare", code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Connection failed with no error detail."]
        )
        connectionErrorSubject.send((peripheral, err))
        if let c = connectContinuations.removeValue(forKey: peripheral.identifier) {
            c.resume(throwing: err)
        }
    }

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        print("[BluetoothInfoShare] didDisconnect: \(peripheral.identifier) error=\(error?.localizedDescription ?? "none")")
        disconnectedSubject.send(peripheral)
        if let c = disconnectContinuations.removeValue(forKey: peripheral.identifier) {
            c.resume(returning: peripheral)
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
            print("[BluetoothInfoShare] dataSharingService NOT found.")
            return
        }
        peripheral.discoverCharacteristics([BluetoothManager.dataSharingCharacteristicUUID], for: service)
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

        // Subscribe to notifications. centralGATTReadySubject fires only after
        // the subscription is CONFIRMED in didUpdateNotificationStateFor,
        // ensuring the peripheral has processed the subscription before we write.
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
            print("[BluetoothInfoShare] setNotifyValue(true) sent.")
        } else {
            // No notify support — signal ready immediately for write-only path.
            centralGATTReadySubject.send(peripheral)
        }
    }

    /// Fires when the peripheral confirms our subscription request.
    /// THIS is the correct moment to write — not a fixed timer.
    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BluetoothInfoShare] didUpdateNotificationState ERROR: \(error.localizedDescription)")
            return
        }
        print("[BluetoothInfoShare] Notify state confirmed: \(characteristic.isNotifying) — signalling GATT ready.")
        if characteristic.isNotifying {
            // Subscription confirmed — safe to write now.
            centralGATTReadySubject.send(peripheral)
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
        BluetoothManager.handleNotifyData(value)
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
            // Write confirmed — signal that central-side exchange is complete.
            centralWriteCompleteSubject.send(peripheral)
        }
    }
}
