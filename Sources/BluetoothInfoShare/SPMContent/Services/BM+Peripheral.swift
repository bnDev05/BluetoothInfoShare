//
//  BluetoothManager+Peripheral.swift
//  BluetoothInfoShare
//
//  Peripheral-side logic: advertising structured payment info and
//  sending / receiving chunked data over BLE notify/write characteristics.
//

import Foundation
import CoreBluetooth
import Combine

extension BluetoothManager {

    // MARK: - Service & Characteristic UUIDs

    /// BLE service UUID used by BluetoothInfoShare.
    ///
    /// Use this when scanning so only matching peripherals are returned:
    /// ```swift
    /// manager.startScan(serviceUUIDs: [BluetoothManager.dataSharingServiceUUID])
    /// ```
    public static let dataSharingServiceUUID = CBUUID(
        string: "A1B2C3D4-E5F6-7890-1234-56789ABCDEF0"
    )

    /// BLE characteristic UUID for data exchange within ``dataSharingServiceUUID``.
    public static let dataSharingCharacteristicUUID = CBUUID(
        string: "A1B2C3D4-E5F6-7890-1234-56789ABCDEF1"
    )

    // MARK: - Static Peripheral State

    /// The underlying `CBPeripheralManager`. Created by ``setupPeripheralManager(delegate:)``.
    public static var peripheralManager: CBPeripheralManager?

    /// The mutable characteristic used for notify/write data exchange.
    public static var transferCharacteristic: CBMutableCharacteristic?

    /// Structured payload advertised as the BLE local name.
    /// Set via ``setAdvertisementInfo(_:)``.
    private(set) static var advertisementInfo: AdvertisementInfo?

    // MARK: - Peripheral State Publisher

    /// Emits whenever the peripheral manager's Bluetooth state changes.
    public static let peripheralStatePublisher: AnyPublisher<CBManagerState, Never> = {
        let subject = PassthroughSubject<CBManagerState, Never>()
        peripheralStateSubject = subject
        return subject.eraseToAnyPublisher()
    }()
    public static var peripheralStateSubject: PassthroughSubject<CBManagerState, Never>?

    // MARK: - Advertising Publisher

    /// Emits `true` when advertising starts, `false` when it stops.
    public static let isAdvertisingPublisher: AnyPublisher<Bool, Never> = {
        let subject = PassthroughSubject<Bool, Never>()
        isAdvertisingSubject = subject
        return subject.eraseToAnyPublisher()
    }()
    public static var isAdvertisingSubject: PassthroughSubject<Bool, Never>?

    // MARK: - Data Received Publisher

    /// Emits fully reassembled `Data` payloads once an `EOM` marker is received.
    ///
    /// ```swift
    /// BluetoothManager.dataReceivedPublisher
    ///     .receive(on: DispatchQueue.main)
    ///     .sink { data in
    ///         let model = try? JSONDecoder().decode(MyModel.self, from: data)
    ///     }
    ///     .store(in: &cancellables)
    /// ```
    public static let dataReceivedPublisher: AnyPublisher<Data, Never> = {
        let subject = PassthroughSubject<Data, Never>()
        dataReceivedSubject = subject
        return subject.eraseToAnyPublisher()
    }()
    public static var dataReceivedSubject: PassthroughSubject<Data, Never>?

    // MARK: - Data Transfer State

    /// Data currently queued for chunked transmission.
    public static var dataToSend: Data?
    /// Byte offset of the next chunk to send.
    public static var sendDataIndex = 0
    /// Maximum bytes per BLE update (fits inside a standard MTU).
    public static let chunkSize = 182
    /// Accumulation buffer for incoming chunks.
    public static var receivedDataBuffer = Data()

    // MARK: - Setup

    /// Creates and configures the `CBPeripheralManager`.
    ///
    /// Must be called **before** ``startAdvertising()`` or ``setAdvertisementInfo(_:)``.
    /// Safe to call multiple times — subsequent calls are no-ops.
    ///
    /// - Parameter delegate: Receives peripheral manager callbacks.
    ///   Use ``PeripheralManagerDelegateHandler`` unless you need custom handling.
    public func setupPeripheralManager(delegate: CBPeripheralManagerDelegate) {
        guard BluetoothManager.peripheralManager == nil else { return }
        BluetoothManager.peripheralManager = CBPeripheralManager(
            delegate: delegate,
            queue: bluetoothQueue
        )
    }

    // MARK: - Advertisement Info

    /// Sets the structured payload to advertise as the BLE local name.
    ///
    /// Call this before ``startAdvertising()``.  If advertising is already
    /// running you must stop and restart it for the new info to take effect.
    ///
    /// - Parameter info: The ``AdvertisementInfo`` to broadcast.
    public func setAdvertisementInfo(_ info: AdvertisementInfo) {
        BluetoothManager.advertisementInfo = info
    }

    // MARK: - Advertising

    /// Registers the data-sharing service and begins BLE advertising.
    ///
    /// The local-name string is derived from the ``AdvertisementInfo`` set via
    /// ``setAdvertisementInfo(_:)``.  When no info has been set the call is
    /// silently ignored.
    ///
    /// Requires ``setupPeripheralManager(delegate:)`` to have been called first
    /// and the peripheral manager to be in the `.poweredOn` state.
    public func startAdvertising() {
        guard
            let peripheralManager = BluetoothManager.peripheralManager,
            peripheralManager.state == .poweredOn,
            let info = BluetoothManager.advertisementInfo
        else {
            print("[BluetoothInfoShare] startAdvertising ignored — manager not ready or no AdvertisementInfo set.")
            return
        }

        let characteristic = CBMutableCharacteristic(
            type: BluetoothManager.dataSharingCharacteristicUUID,
            properties: [.notify, .writeWithoutResponse, .write],
            value: nil,
            permissions: [.readable, .writeable]
        )
        BluetoothManager.transferCharacteristic = characteristic

        let service = CBMutableService(
            type: BluetoothManager.dataSharingServiceUUID,
            primary: true
        )
        service.characteristics = [characteristic]

        peripheralManager.add(service)
        peripheralManager.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [BluetoothManager.dataSharingServiceUUID],
            CBAdvertisementDataLocalNameKey: info.encoded()
        ])

        BluetoothManager.isAdvertisingSubject?.send(true)
    }

    /// Stops BLE advertising.
    public func stopAdvertising() {
        BluetoothManager.peripheralManager?.stopAdvertising()
        BluetoothManager.isAdvertisingSubject?.send(false)
    }

    /// Whether the peripheral manager is currently advertising.
    public var isAdvertising: Bool {
        BluetoothManager.peripheralManager?.isAdvertising ?? false
    }

    // MARK: - Data Sending

    /// Enqueues `data` for chunked delivery to all subscribed centrals.
    ///
    /// Data is split into ``BluetoothManager/chunkSize``-byte chunks and sent
    /// sequentially.  An `EOM` marker is transmitted after the final chunk.
    ///
    /// - Parameter data: The raw bytes to send.
    public func sendData(_ data: Data) {
        BluetoothManager.dataToSend = data
        BluetoothManager.sendDataIndex = 0
        sendNextChunk()
    }

    /// Sends the next pending chunk, or the `EOM` marker when done.
    ///
    /// Called automatically by ``sendData(_:)`` and by
    /// `PeripheralManagerDelegateHandler` when the peripheral manager is
    /// ready to send more data.
    public func sendNextChunk() {
        guard
            let data = BluetoothManager.dataToSend,
            let characteristic = BluetoothManager.transferCharacteristic,
            let peripheralManager = BluetoothManager.peripheralManager
        else { return }

        // All chunks sent — transmit end-of-message marker.
        if BluetoothManager.sendDataIndex >= data.count {
            guard let eomData = "EOM".data(using: .utf8) else { return }
            peripheralManager.updateValue(eomData, for: characteristic, onSubscribedCentrals: nil)
            BluetoothManager.dataToSend = nil
            BluetoothManager.sendDataIndex = 0
            return
        }

        let endIndex = min(
            BluetoothManager.sendDataIndex + BluetoothManager.chunkSize,
            data.count
        )
        let chunk = data.subdata(in: BluetoothManager.sendDataIndex..<endIndex)

        let didSend = peripheralManager.updateValue(
            chunk,
            for: characteristic,
            onSubscribedCentrals: nil
        )

        if didSend {
            BluetoothManager.sendDataIndex = endIndex
            sendNextChunk()
            // If didSend == false, peripheralManagerIsReady(toUpdateSubscribers:)
            // will call sendNextChunk() once the queue drains.
        }
    }

    // MARK: - Data Receiving

    /// Appends an incoming chunk to the receive buffer, or flushes it on `EOM`.
    ///
    /// Called from `PeripheralManagerDelegateHandler.peripheralManager(_:didReceiveWrite:)`.
    ///
    /// - Parameter data: A single BLE write value.
    public static func handleReceivedData(_ data: Data) {
        if let marker = String(data: data, encoding: .utf8), marker == "EOM" {
            guard !receivedDataBuffer.isEmpty else { return }
            dataReceivedSubject?.send(receivedDataBuffer)
            receivedDataBuffer = Data()
        } else {
            receivedDataBuffer.append(data)
        }
    }

    // MARK: - Peripheral Manager Callbacks (forwarded from delegate handler)

    /// Forwards a peripheral manager state update to ``peripheralStatePublisher``.
    public static func peripheralManagerDidUpdateState(_ state: CBManagerState) {
        peripheralStateSubject?.send(state)
    }

    /// Called when the peripheral manager is ready to send more data.
    /// Resumes chunked transmission if a send is in progress.
    public static func peripheralManagerIsReadyToSend() {
        guard
            let data = dataToSend,
            sendDataIndex < data.count
        else { return }
        BluetoothManager.shared.sendNextChunk()
    }
}
