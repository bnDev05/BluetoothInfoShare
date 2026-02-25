//
//  BluetoothManager + CentralManagerExtension.swift
//  ExampleProject
//
//  Created by Behruz on 13/02/26.
//

import Foundation
import CoreBluetooth

extension BluetoothManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateSubject.send(central.state)
    }

    public func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        discoverySubject.send(peripheral)
    }

    public func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        connectedSubject.send(peripheral)

        if let continuation = connectContinuations.removeValue(forKey: peripheral.identifier) {
            continuation.resume(returning: peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager,
                        didFailToConnect peripheral: CBPeripheral,
                        error: Error?) {
        let connectionError = error ?? NSError(
            domain: "BluetoothManager",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Connection failed with no error detail."]
        )

        connectionErrorSubject.send((peripheral, connectionError))

        if let continuation = connectContinuations.removeValue(forKey: peripheral.identifier) {
            continuation.resume(throwing: connectionError)
        }
    }

    public func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        disconnectedSubject.send(peripheral)

        if let continuation = disconnectContinuations.removeValue(forKey: peripheral.identifier) {
            continuation.resume(returning: peripheral)
        }

        if let error = error {
            connectionErrorSubject.send((peripheral, error))
        }
    }
}
