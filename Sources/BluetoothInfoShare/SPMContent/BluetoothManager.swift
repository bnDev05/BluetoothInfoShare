import Foundation
import CoreBluetooth
import Combine

public class BluetoothManager: NSObject {
    
    static public let shared = BluetoothManager()

    public let bluetoothQueue = DispatchQueue(label: "com.app.bluetooth", qos: .userInitiated)

    public var centralManager: CBCentralManager!

    public var connectContinuations:    [UUID: CheckedContinuation<CBPeripheral, Error>] = [:]
    public var disconnectContinuations: [UUID: CheckedContinuation<CBPeripheral, Never>]  = [:]

    public let statePublisher: AnyPublisher<CBManagerState, Never>
    public let stateSubject = PassthroughSubject<CBManagerState, Never>()

    public let discoveryPublisher: AnyPublisher<CBPeripheral, Never>
    public let discoverySubject = PassthroughSubject<CBPeripheral, Never>()

    public let scanningPublisher: AnyPublisher<Bool, Never>
    public let scanningSubject = PassthroughSubject<Bool, Never>()

    public let connectedPublisher: AnyPublisher<CBPeripheral, Never>
    public let connectedSubject = PassthroughSubject<CBPeripheral, Never>()

    public let disconnectedPublisher: AnyPublisher<CBPeripheral, Never>
    public let disconnectedSubject = PassthroughSubject<CBPeripheral, Never>()

    public let connectionErrorPublisher: AnyPublisher<(CBPeripheral, Error), Never>
    public let connectionErrorSubject = PassthroughSubject<(CBPeripheral, Error), Never>()

    override init() {
        statePublisher           = stateSubject.eraseToAnyPublisher()
        discoveryPublisher       = discoverySubject.eraseToAnyPublisher()
        scanningPublisher        = scanningSubject.eraseToAnyPublisher()
        connectedPublisher       = connectedSubject.eraseToAnyPublisher()
        disconnectedPublisher    = disconnectedSubject.eraseToAnyPublisher()
        connectionErrorPublisher = connectionErrorSubject.eraseToAnyPublisher()
        super.init()

        centralManager = CBCentralManager(delegate: self, queue: bluetoothQueue)
    }

    public var state: CBManagerState { centralManager.state }

    public var isScanning: Bool { centralManager.isScanning }

    public func startScan(serviceUUIDs: [CBUUID]? = nil, options: [String: Any]? = nil) {
        guard state == .poweredOn else { return }
        centralManager.scanForPeripherals(withServices: serviceUUIDs, options: options)
        scanningSubject.send(true)
    }

    public func stopScan() {
        centralManager.stopScan()
        scanningSubject.send(false)
    }

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

    public func disconnect(_ peripheral: CBPeripheral) async -> CBPeripheral {
        if peripheral.state == .disconnected { return peripheral }

        return await withCheckedContinuation { continuation in
            disconnectContinuations[peripheral.identifier] = continuation
            centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}
