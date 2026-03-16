//
//  BluetoothManager.swift
//  BluetoothInfoShare
//

import Foundation
import CoreBluetooth
import Combine

public final class BluetoothManager: NSObject {

    // MARK: - Singleton
    public static let shared = BluetoothManager()

    // MARK: - Internal queue
    public let bluetoothQueue = DispatchQueue(
        label: "com.bluetoothinfoshare.queue",
        qos: .userInitiated
    )

    // MARK: - Central manager
    public private(set) var centralManager: CBCentralManager!

    // MARK: - Async continuations
    var connectContinuations:    [UUID: CheckedContinuation<CBPeripheral, Error>] = [:]
    var disconnectContinuations: [UUID: CheckedContinuation<CBPeripheral, Never>] = [:]

    // MARK: - Publishers

    public let statePublisher: AnyPublisher<CBManagerState, Never>
    let stateSubject = PassthroughSubject<CBManagerState, Never>()

    public let discoveryPublisher: AnyPublisher<(CBPeripheral, [String: Any]), Never>
    let discoverySubject = PassthroughSubject<(CBPeripheral, [String: Any]), Never>()

    public let scanningPublisher: AnyPublisher<Bool, Never>
    let scanningSubject = PassthroughSubject<Bool, Never>()

    public let connectedPublisher: AnyPublisher<CBPeripheral, Never>
    let connectedSubject = PassthroughSubject<CBPeripheral, Never>()

    public let disconnectedPublisher: AnyPublisher<CBPeripheral, Never>
    let disconnectedSubject = PassthroughSubject<CBPeripheral, Never>()

    public let connectionErrorPublisher: AnyPublisher<(CBPeripheral, Error), Never>
    let connectionErrorSubject = PassthroughSubject<(CBPeripheral, Error), Never>()

    /// Fires when the central has discovered the GATT characteristic and
    /// the peripheral has confirmed the notify subscription — safe to write.
    public let centralGATTReadyPublisher: AnyPublisher<CBPeripheral, Never>
    let centralGATTReadySubject = PassthroughSubject<CBPeripheral, Never>()

    /// Fires when the peripheral confirms our write (didWriteValueFor, no error).
    /// BluetoothService uses this to know both directions are done and can disconnect.
    public let centralWriteCompletePublisher: AnyPublisher<CBPeripheral, Never>
    let centralWriteCompleteSubject = PassthroughSubject<CBPeripheral, Never>()

    // MARK: - Init

    override public init() {
        statePublisher           = stateSubject.eraseToAnyPublisher()
        discoveryPublisher       = discoverySubject.eraseToAnyPublisher()
        scanningPublisher        = scanningSubject.eraseToAnyPublisher()
        connectedPublisher       = connectedSubject.eraseToAnyPublisher()
        disconnectedPublisher    = disconnectedSubject.eraseToAnyPublisher()
        connectionErrorPublisher = connectionErrorSubject.eraseToAnyPublisher()
        centralGATTReadyPublisher     = centralGATTReadySubject.eraseToAnyPublisher()
        centralWriteCompletePublisher = centralWriteCompleteSubject.eraseToAnyPublisher()
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: bluetoothQueue)
    }

    // MARK: - State

    public var state: CBManagerState { centralManager.state }
    public var isScanning: Bool { centralManager.isScanning }

    // MARK: - Scanning

    public func startScan(serviceUUIDs: [CBUUID]? = nil, options: [String: Any]? = nil) {
        guard state == .poweredOn else {
            print("[BluetoothInfoShare] startScan ignored — Bluetooth is not powered on.")
            return
        }
        centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
        scanningSubject.send(true)
    }

    public func stopScan() {
        centralManager.stopScan()
        scanningSubject.send(false)
    }

    // MARK: - Connecting

    public func connect(_ peripheral: CBPeripheral) async throws -> CBPeripheral {
        if peripheral.state == .connected { return peripheral }
        return try await withCheckedThrowingContinuation { continuation in
            connectContinuations[peripheral.identifier] = continuation
            centralManager.connect(peripheral, options: nil)
        }
    }

    public func connectBidirectional(_ peripheral: CBPeripheral) async throws -> CBPeripheral {
        startAdvertising()
        return try await connect(peripheral)
    }

    // MARK: - Disconnecting

    public func disconnect(_ peripheral: CBPeripheral) async -> CBPeripheral {
        if peripheral.state == .disconnected { return peripheral }
        return await withCheckedContinuation { continuation in
            disconnectContinuations[peripheral.identifier] = continuation
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }

    // MARK: - Write to peripheral characteristic (central role)

    /// Writes data to the data-sharing characteristic of a connected peripheral.
    /// Use `.withResponse` when you need confirmation; `.withoutResponse` for speed.
    public func writeToPeripheral(
        _ peripheral: CBPeripheral,
        data: Data,
        type: CBCharacteristicWriteType = .withResponse
    ) {
        guard
            let service = peripheral.services?.first(where: {
                $0.uuid == BluetoothManager.dataSharingServiceUUID
            }),
            let characteristic = service.characteristics?.first(where: {
                $0.uuid == BluetoothManager.dataSharingCharacteristicUUID
            })
        else {
            print("[BluetoothInfoShare] writeToPeripheral: characteristic not yet discovered.")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: type)
    }
}
