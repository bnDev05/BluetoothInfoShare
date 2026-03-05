//
//  PeripheralManagerExtension.swift
//  ExampleProject
//
//  Created by Behruz on 13/02/26.
//
//
//  PeripheralManagerDelegateHandler.swift
//  BluetoothInfoShare
//
//  Default CBPeripheralManagerDelegate implementation.
//  Forwards all events to BluetoothManager's static helpers.
//

import Foundation
import CoreBluetooth

/// Default `CBPeripheralManagerDelegate` that wires peripheral-manager callbacks
/// into the ``BluetoothManager`` infrastructure.
///
/// Create one instance and pass it to ``BluetoothManager/setupPeripheralManager(delegate:)``:
/// ```swift
/// let handler = PeripheralManagerDelegateHandler(bluetoothManager: .shared)
/// BluetoothManager.shared.setupPeripheralManager(delegate: handler)
/// ```
///
/// You may subclass or provide your own `CBPeripheralManagerDelegate` if you need
/// custom behaviour beyond what this handler provides.
public final class PeripheralManagerDelegateHandler: NSObject, CBPeripheralManagerDelegate {

    // MARK: - Properties

    private weak var bluetoothManager: BluetoothManager?

    // MARK: - Init

    /// Creates a handler linked to the given `BluetoothManager`.
    ///
    /// - Parameter bluetoothManager: The manager whose `startAdvertising()` and
    ///   `sendNextChunk()` methods will be invoked from this delegate.
    public init(bluetoothManager: BluetoothManager) {
        self.bluetoothManager = bluetoothManager
    }

    // MARK: - CBPeripheralManagerDelegate

    /// Forwards the new state and automatically begins advertising when powered on.
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

    /// Called when a central subscribes to the transfer characteristic.
    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didSubscribeTo characteristic: CBCharacteristic
    ) {
        print("[BluetoothInfoShare] Central subscribed: \(central.identifier)")
    }

    /// Called when a central unsubscribes from the transfer characteristic.
    public func peripheralManager(
        _ peripheral: CBPeripheralManager,
        central: CBCentral,
        didUnsubscribeFrom characteristic: CBCharacteristic
    ) {
        print("[BluetoothInfoShare] Central unsubscribed: \(central.identifier)")
    }

    /// Resumes chunked transmission when the peripheral manager's queue drains.
    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        BluetoothManager.peripheralManagerIsReadyToSend()
    }

    /// Reassembles incoming write requests and passes each value to
    /// ``BluetoothManager/handleReceivedData(_:)``.
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
