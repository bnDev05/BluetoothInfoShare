//
//  PeripheralManagerDelegateHandler.swift
//  BluetoothInfoShare
//

import Foundation
import CoreBluetooth

/// Default `CBPeripheralManagerDelegate` that wires peripheral-manager callbacks
/// into the ``BluetoothManager`` infrastructure.
public final class PeripheralManagerDelegateHandler: NSObject, CBPeripheralManagerDelegate {

    // MARK: - Properties

    private weak var bluetoothManager: BluetoothManager?

    // MARK: - Init

    public init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }

    // MARK: - CBPeripheralManagerDelegate

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        BluetoothManager.peripheralManagerDidUpdateState(peripheral.state)
        if peripheral.state == .poweredOn {
            bluetoothManager?.startAdvertising()
        }
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didAdd service: CBService,
        error: Error?
    ) {
        if let error = error {
            print("[BluetoothInfoShare] Error adding service: \(error.localizedDescription)")
        }
    }

    /// A central subscribed — fire the publisher so BluetoothService can
    /// immediately send the encrypted sensitive payload to that central.
    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        print("[BluetoothInfoShare] Central subscribed: \(central.identifier)")
        BluetoothManager.centralDidSubscribeSubject.send(central)
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        print("[BluetoothInfoShare] Central unsubscribed: \(central.identifier)")
    }

    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        BluetoothManager.peripheralManagerIsReadyToSend()
    }

    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        for request in requests {
            if let value = request.value {
                BluetoothManager.handleReceivedData(value)
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }
}
