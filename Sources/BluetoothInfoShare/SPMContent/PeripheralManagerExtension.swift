//
//  PeripheralManagerExtension.swift
//  ExampleProject
//
//  Created by Behruz on 13/02/26.
//

import Foundation
import CoreBluetooth

class PeripheralManagerDelegateHandler: NSObject, CBPeripheralManagerDelegate {
    private weak var bluetoothManager: BluetoothManager?
//    weak var dataSharingManager: DataSharingManager?
    
    init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }
    
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        BluetoothManager.peripheralManagerDidUpdateState(peripheral.state)
        
        if peripheral.state == .poweredOn {
            bluetoothManager?.startAdvertising()
        }
    }
    
    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didAdd service: CBService,
                           error: Error?) {
        if let error = error {
            print("❌ Error adding service: \(error)")
        }
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didSubscribeTo characteristic: CBCharacteristic) {
        print("📲 Central subscribed: \(central.identifier)")
//        dataSharingManager?.centralDidSubscribe(central)
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           central: CBCentral,
                           didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("📴 Central unsubscribed: \(central.identifier)")
//        dataSharingManager?.centralDidUnsubscribe(central)
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        bluetoothManager?.sendNextChunk()
    }

    func peripheralManager(_ peripheral: CBPeripheralManager,
                           didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                BluetoothManager.handleReceivedData(value)
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }
}
