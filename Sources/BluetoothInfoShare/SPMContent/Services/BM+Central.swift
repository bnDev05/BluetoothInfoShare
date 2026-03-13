//
//  BluetoothManager+Central.swift
//  BluetoothInfoShare
//
//  CBCentralManagerDelegate + CBPeripheralDelegate implementation.
//
//  ## Central-side GATT flow for sensitive payload exchange
//
//  After connecting to a peripheral, the central must:
//    1. discoverServices([dataSharingServiceUUID])
//    2. discoverCharacteristics([dataSharingCharacteristicUUID], for: service)
//    3. setNotifyValue(true, for: characteristic)   ← triggers didSubscribeTo on peripheral side
//    4. writeValue(encryptedPayload, for: characteristic, type: .withResponse)
//
//  The peripheral then pushes its own payload back via notify, which fires
//  didUpdateValueFor on the central side → handleReceivedData.
//

import Foundation
import CoreBluetooth

extension BluetoothManager: CBCentralManagerDelegate {

    // MARK: - State

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateSubject.send(central.state)
    }

    // MARK: - Discovery

    public func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoverySubject.send((peripheral, advertisementData))
    }

    // MARK: - Connection

    public func centralManager(
        _ central: CBCentralManager,
        didConnect peripheral: CBPeripheral
    ) {
        connectedSubject.send(peripheral)

        // Resume any async continuation waiting on connect(_:)
        if let continuation = connectContinuations.removeValue(forKey: peripheral.identifier) {
            continuation.resume(returning: peripheral)
        }

        // Assign self as peripheral delegate and start GATT discovery
        // so we can write our sensitive payload and receive theirs.
        peripheral.delegate = self
        peripheral.discoverServices([BluetoothManager.dataSharingServiceUUID])
    }

    public func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
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

    // MARK: - Disconnection

    public func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
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

    // Step 1: services discovered → discover our characteristic
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverServices error: Error?
    ) {
        guard error == nil else {
            print("[BluetoothInfoShare] didDiscoverServices error: \(error!.localizedDescription)")
            return
        }
        guard let service = peripheral.services?.first(where: {
            $0.uuid == BluetoothManager.dataSharingServiceUUID
        }) else { return }

        peripheral.discoverCharacteristics(
            [BluetoothManager.dataSharingCharacteristicUUID],
            for: service
        )
    }

    // Step 2: characteristic discovered → subscribe (notify) + signal ready to write
    public func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil else {
            print("[BluetoothInfoShare] didDiscoverCharacteristics error: \(error!.localizedDescription)")
            return
        }
        guard let characteristic = service.characteristics?.first(where: {
            $0.uuid == BluetoothManager.dataSharingCharacteristicUUID
        }) else { return }

        // Subscribe so the peripheral's notify pushes its payload to us.
        if characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }

        // Signal that the central-side GATT channel is open.
        // BluetoothService observes this to write our sensitive payload.
        centralGATTReadySubject.send(peripheral)
    }

    // Step 3: peripheral pushed data via notify → feed into receive buffer
    public func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let value = characteristic.value else { return }
        BluetoothManager.handleReceivedData(value)
    }

    public func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error = error {
            print("[BluetoothInfoShare] didWriteValue error: \(error.localizedDescription)")
        }
    }
}
