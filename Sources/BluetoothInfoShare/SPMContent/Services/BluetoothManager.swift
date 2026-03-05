//
//  BluetoothManager.swift
//  BluetoothInfoShare
//
//  Central entry-point for all BLE operations.
//  Acts as both a CBCentralManager delegate (scanning / connecting) and
//  hosts the peripheral-side (advertising / data transfer) via extensions.
//

import Foundation
import CoreBluetooth
import Combine

/// Singleton manager for all Bluetooth Low Energy operations.
///
/// ## Roles
/// - **Central** – scans for and connects to remote peripherals.
/// - **Peripheral** – advertises the local device's payment info and
///   exchanges chunked data with connected centrals.
///
/// ## Setup
/// ```swift
/// let manager = BluetoothManager.shared
///
/// // Peripheral side — call before startAdvertising()
/// let handler = PeripheralManagerDelegateHandler(bluetoothManager: manager)
/// manager.setupPeripheralManager(delegate: handler)
/// manager.setAdvertisementInfo(AdvertisementInfo(
///     lastFourCardNumber: "1234",
///     objectID: "dscd34",
///     userID: "hskad7",
///     userName: "UserABCDEF"
/// ))
///
/// // Central side
/// manager.startScan(serviceUUIDs: [BluetoothManager.dataSharingServiceUUID])
/// ```
public final class BluetoothManager: NSObject {

    // MARK: - Singleton

    /// Shared instance. Use this in production code.
    public static let shared = BluetoothManager()

    // MARK: - Internal queue

    /// Serial queue on which all CoreBluetooth callbacks are dispatched.
    public let bluetoothQueue = DispatchQueue(
        label: "com.bluetoothinfoshare.queue",
        qos: .userInitiated
    )

    // MARK: - Central manager

    /// Underlying `CBCentralManager`. Avoid calling its methods directly;
    /// use the higher-level helpers on `BluetoothManager` instead.
    public private(set) var centralManager: CBCentralManager!

    // MARK: - Async continuations

    /// Pending `connect(_:)` continuations keyed by peripheral UUID.
    var connectContinuations:    [UUID: CheckedContinuation<CBPeripheral, Error>] = [:]
    /// Pending `disconnect(_:)` continuations keyed by peripheral UUID.
    var disconnectContinuations: [UUID: CheckedContinuation<CBPeripheral, Never>] = [:]

    // MARK: - Publishers

    /// Emits whenever the central manager's Bluetooth state changes.
    public let statePublisher: AnyPublisher<CBManagerState, Never>
    let stateSubject = PassthroughSubject<CBManagerState, Never>()

    /// Emits a peripheral and its raw advertisement data each time one is discovered.
    public let discoveryPublisher: AnyPublisher<(CBPeripheral, [String: Any]), Never>
    let discoverySubject = PassthroughSubject<(CBPeripheral, [String: Any]), Never>()

    /// Emits `true` when scanning starts, `false` when it stops.
    public let scanningPublisher: AnyPublisher<Bool, Never>
    let scanningSubject = PassthroughSubject<Bool, Never>()

    /// Emits a peripheral immediately after it is successfully connected.
    public let connectedPublisher: AnyPublisher<CBPeripheral, Never>
    let connectedSubject = PassthroughSubject<CBPeripheral, Never>()

    /// Emits a peripheral after it disconnects (cleanly or due to an error).
    public let disconnectedPublisher: AnyPublisher<CBPeripheral, Never>
    let disconnectedSubject = PassthroughSubject<CBPeripheral, Never>()

    /// Emits `(peripheral, error)` whenever a connection attempt fails, or a
    /// connected peripheral drops with an error.
    public let connectionErrorPublisher: AnyPublisher<(CBPeripheral, Error), Never>
    let connectionErrorSubject = PassthroughSubject<(CBPeripheral, Error), Never>()

    // MARK: - Init

    override public init() {
        statePublisher           = stateSubject.eraseToAnyPublisher()
        discoveryPublisher       = discoverySubject.eraseToAnyPublisher()
        scanningPublisher        = scanningSubject.eraseToAnyPublisher()
        connectedPublisher       = connectedSubject.eraseToAnyPublisher()
        disconnectedPublisher    = disconnectedSubject.eraseToAnyPublisher()
        connectionErrorPublisher = connectionErrorSubject.eraseToAnyPublisher()
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: bluetoothQueue)
    }

    // MARK: - State

    /// Current state of the central manager.
    public var state: CBManagerState { centralManager.state }

    /// Whether the central manager is currently scanning.
    public var isScanning: Bool { centralManager.isScanning }

    // MARK: - Scanning

    /// Begins scanning for peripherals advertising the given service UUIDs.
    ///
    /// Has no effect when Bluetooth is not powered on.
    ///
    /// - Parameters:
    ///   - serviceUUIDs: Filter to peripherals advertising these services.
    ///     Pass `nil` to discover all peripherals (not recommended in production).
    ///   - options: Optional `CBCentralManager` scan options dictionary.
    public func startScan(serviceUUIDs: [CBUUID]? = nil, options: [String: Any]? = nil) {
        guard state == .poweredOn else {
            print("[BluetoothInfoShare] startScan ignored — Bluetooth is not powered on.")
            return
        }
        centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
        scanningSubject.send(true)
    }

    /// Stops an in-progress scan.
    public func stopScan() {
        centralManager.stopScan()
        scanningSubject.send(false)
    }

    // MARK: - Connecting

    /// Connects to `peripheral` and awaits the result asynchronously.
    ///
    /// If the peripheral is already connected the call returns immediately.
    ///
    /// - Parameter peripheral: The peripheral to connect to.
    /// - Returns: The connected peripheral.
    /// - Throws: Any error produced by `CBCentralManager` during connection.
    public func connect(_ peripheral: CBPeripheral) async throws -> CBPeripheral {
        if peripheral.state == .connected { return peripheral }

        return try await withCheckedThrowingContinuation { continuation in
            connectContinuations[peripheral.identifier] = continuation
            centralManager.connect(peripheral, options: nil)
        }
    }

    /// Starts advertising the local device **and** connects to `peripheral`.
    ///
    /// Use this when both devices need to exchange data bidirectionally.
    /// Requires ``setupPeripheralManager(delegate:)`` and
    /// ``setAdvertisementInfo(_:)`` to have been called first.
    ///
    /// - Parameter peripheral: The remote peripheral to connect to.
    /// - Returns: The connected peripheral.
    /// - Throws: Any error produced during connection.
    public func connectBidirectional(_ peripheral: CBPeripheral) async throws -> CBPeripheral {
        startAdvertising()
        return try await connect(peripheral)
    }

    // MARK: - Disconnecting

    /// Disconnects from `peripheral` and awaits completion asynchronously.
    ///
    /// If the peripheral is already disconnected the call returns immediately.
    ///
    /// - Parameter peripheral: The peripheral to disconnect from.
    /// - Returns: The disconnected peripheral.
    public func disconnect(_ peripheral: CBPeripheral) async -> CBPeripheral {
        if peripheral.state == .disconnected { return peripheral }

        return await withCheckedContinuation { continuation in
            disconnectContinuations[peripheral.identifier] = continuation
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}
