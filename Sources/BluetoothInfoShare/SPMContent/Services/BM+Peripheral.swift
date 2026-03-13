//
//  BluetoothManager+Peripheral.swift
//  BluetoothInfoShare
//
//  Peripheral-side logic: advertising encrypted payment info and
//  sending / receiving chunked data over BLE notify/write characteristics.
//

import Foundation
import CoreBluetooth
import Combine

extension BluetoothManager {

    // MARK: - Service & Characteristic UUIDs

    public static let dataSharingServiceUUID = CBUUID(
        string: "A1B2C3D4-E5F6-7890-1234-56789ABCDEF0"
    )
    public static let dataSharingCharacteristicUUID = CBUUID(
        string: "A1B2C3D4-E5F6-7890-1234-56789ABCDEF1"
    )

    // MARK: - Static Peripheral State

    public static var peripheralManager: CBPeripheralManager?
    public static var transferCharacteristic: CBMutableCharacteristic?

    /// Structured payload to advertise.  Set via ``setAdvertisementInfo(_:)``.
    private(set) static var advertisementInfo: AdvertisementInfo?

    /// The 32-byte AES-GCM key used to encrypt the advertisement payload.
    ///
    /// Must be set before ``startAdvertising()`` is called.  The same key must
    /// be supplied to ``CellInfoModel/makeInfo(advertisementLocalName:peripheral:isConnected:decryptingWith:)``
    /// on the scanning side.
    ///
    /// - Important: Derive this key from a secure session (server-issued token,
    ///   ECDH handshake, QR pairing, etc.).  Never hard-code it.
    private(set) static var advertisementEncryptionKey: Data?

    // MARK: - Publishers

    public static let peripheralStatePublisher: AnyPublisher<CBManagerState, Never> = {
        let subject = PassthroughSubject<CBManagerState, Never>()
        peripheralStateSubject = subject
        return subject.eraseToAnyPublisher()
    }()
    public static var peripheralStateSubject: PassthroughSubject<CBManagerState, Never>?

    public static let isAdvertisingPublisher: AnyPublisher<Bool, Never> = {
        let subject = PassthroughSubject<Bool, Never>()
        isAdvertisingSubject = subject
        return subject.eraseToAnyPublisher()
    }()
    public static var isAdvertisingSubject: PassthroughSubject<Bool, Never>?

    /// Emits fully reassembled `Data` payloads once an `EOM` marker is received.
    public static let dataReceivedPublisher: AnyPublisher<Data, Never> = {
        let subject = PassthroughSubject<Data, Never>()
        dataReceivedSubject = subject
        return subject.eraseToAnyPublisher()
    }()
    public static var dataReceivedSubject: PassthroughSubject<Data, Never>?

    // MARK: - Data Transfer State

    public static var dataToSend:        Data?
    public static var sendDataIndex      = 0
    public static let chunkSize          = 182
    public static var receivedDataBuffer = Data()

    // MARK: - Setup

    /// Creates and configures the `CBPeripheralManager`.
    public func setupPeripheralManager(delegate: CBPeripheralManagerDelegate) {
        guard BluetoothManager.peripheralManager == nil else { return }
        BluetoothManager.peripheralManager = CBPeripheralManager(
            delegate: delegate,
            queue: bluetoothQueue
        )
    }

    // MARK: - Advertisement Info & Encryption Key

    /// Sets the structured payload to advertise.
    ///
    /// Call this together with ``setAdvertisementEncryptionKey(_:)`` before
    /// ``startAdvertising()``.
    public func setAdvertisementInfo(_ info: AdvertisementInfo) {
        BluetoothManager.advertisementInfo = info
    }

    /// Sets the 32-byte AES-GCM key used to encrypt the advertisement payload.
    ///
    /// Must be called before ``startAdvertising()``.  The scanning peer must
    /// use the identical key to decrypt.
    ///
    /// - Parameter key: Exactly 32 bytes.  Pass `nil` to clear the key.
    public func setAdvertisementEncryptionKey(_ key: Data?) {
        BluetoothManager.advertisementEncryptionKey = key
    }

    // MARK: - Advertising

    /// Registers the data-sharing service and begins BLE advertising with an
    /// **encrypted** local-name payload.
    ///
    /// Prerequisites:
    /// - ``setupPeripheralManager(delegate:)`` called.
    /// - ``setAdvertisementInfo(_:)`` called with valid info.
    /// - ``setAdvertisementEncryptionKey(_:)`` called with a 32-byte key.
    /// - Peripheral manager in `.poweredOn` state.
    ///
    /// If any prerequisite is unmet the call is silently ignored and a log
    /// message is printed.
    public func startAdvertising() {
        guard
            let peripheralManager = BluetoothManager.peripheralManager,
            peripheralManager.state == .poweredOn,
            let info = BluetoothManager.advertisementInfo
        else {
            print("[BluetoothInfoShare] startAdvertising ignored — manager not ready or no AdvertisementInfo set.")
            return
        }
        guard let encryptionKey = BluetoothManager.advertisementEncryptionKey else {
            print("[BluetoothInfoShare] startAdvertising ignored — no encryption key set. Call setAdvertisementEncryptionKey(_:) first.")
            return
        }

        // Encrypt the payload.  On failure, refuse to advertise plaintext.
        let encryptedLocalName: String
        do {
            encryptedLocalName = try info.encoded(encryptedWith: encryptionKey)
        } catch {
            print("[BluetoothInfoShare] startAdvertising aborted — encryption failed: \(error.localizedDescription)")
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
            CBAdvertisementDataLocalNameKey:    encryptedLocalName
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
    public func sendData(_ data: Data) {
        BluetoothManager.dataToSend      = data
        BluetoothManager.sendDataIndex   = 0
        sendNextChunk()
    }

    /// Sends the next pending chunk, or the `EOM` marker when done.
    public func sendNextChunk() {
        guard
            let data              = BluetoothManager.dataToSend,
            let characteristic    = BluetoothManager.transferCharacteristic,
            let peripheralManager = BluetoothManager.peripheralManager
        else { return }

        if BluetoothManager.sendDataIndex >= data.count {
            guard let eomData = "EOM".data(using: .utf8) else { return }
            peripheralManager.updateValue(eomData, for: characteristic, onSubscribedCentrals: nil)
            BluetoothManager.dataToSend    = nil
            BluetoothManager.sendDataIndex = 0
            return
        }

        let endIndex = min(
            BluetoothManager.sendDataIndex + BluetoothManager.chunkSize,
            data.count
        )
        let chunk = data.subdata(in: BluetoothManager.sendDataIndex..<endIndex)

        let didSend = peripheralManager.updateValue(chunk, for: characteristic, onSubscribedCentrals: nil)
        if didSend {
            BluetoothManager.sendDataIndex = endIndex
            sendNextChunk()
        }
        // If didSend == false, peripheralManagerIsReady(toUpdateSubscribers:) resumes.
    }

    // MARK: - Data Receiving

    /// Appends an incoming chunk to the receive buffer, or flushes it on `EOM`.
    public static func handleReceivedData(_ data: Data) {
        if let marker = String(data: data, encoding: .utf8), marker == "EOM" {
            guard !receivedDataBuffer.isEmpty else { return }
            dataReceivedSubject?.send(receivedDataBuffer)
            receivedDataBuffer = Data()
        } else {
            receivedDataBuffer.append(data)
        }
    }

    // MARK: - Peripheral Manager Callbacks

    public static func peripheralManagerDidUpdateState(_ state: CBManagerState) {
        peripheralStateSubject?.send(state)
    }

    public static func peripheralManagerIsReadyToSend() {
        guard
            let data = dataToSend,
            sendDataIndex < data.count
        else { return }
        BluetoothManager.shared.sendNextChunk()
    }
}
