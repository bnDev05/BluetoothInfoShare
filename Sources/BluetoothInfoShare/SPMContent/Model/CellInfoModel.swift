//
//  CellInfoModel.swift
//  BluetoothInfoShare
//

import Foundation
import CoreBluetooth

/// An immutable snapshot of the data broadcast by a remote peripheral.
///
/// ### Secure usage (recommended)
/// ```swift
/// // sessionKey: Data — 32 bytes shared with the peripheral out-of-band
/// if let cell = CellInfoModel.makeInfo(
///     advertisementLocalName: localName,
///     peripheral: peripheral,
///     isConnected: false,
///     decryptingWith: sessionKey
/// ) {
///     print(cell.userName)
/// }
/// ```
///
/// ### Legacy plaintext usage (debugging / migration only)
/// ```swift
/// if let cell = CellInfoModel.makeInfo(
///     advertisementLocalName: "1234dscd34hskad7UserABCDEF",
///     peripheral: peripheral,
///     isConnected: false
/// ) { ... }
/// ```
public struct CellInfoModel: Identifiable, Equatable {

    // MARK: - Properties

    public let id:                 UUID
    public let name:               String
    public let lastFourCardNumber: String
    public let objectID:           String
    public let userID:             String
    public let peripheral:         CBPeripheral
    public var isConnected:        Bool

    // MARK: - Init

    public init(info: AdvertisementInfo, peripheral: CBPeripheral, isConnected: Bool) {
        self.id                 = UUID()
        self.name               = info.userName
        self.lastFourCardNumber = info.lastFourCardNumber
        self.objectID           = info.objectID
        self.userID             = info.userID
        self.peripheral         = peripheral
        self.isConnected        = isConnected
    }

    // MARK: - Factory (encrypted — recommended)

    /// Decrypts and parses the advertisement local-name, returning a model on success.
    ///
    /// - Parameters:
    ///   - advertisementLocalName: Raw value of `CBAdvertisementDataLocalNameKey`.
    ///   - peripheral:             The originating peripheral.
    ///   - isConnected:            Current connection state.
    ///   - key:                    The 32-byte AES-GCM key shared with the advertiser.
    /// - Returns: A populated `CellInfoModel`, or `nil` if the name is absent,
    ///   the key is wrong, or the ciphertext has been tampered with.
    public static func makeInfo(
        advertisementLocalName: String,
        peripheral: CBPeripheral,
        isConnected: Bool,
        decryptingWith key: Data
    ) -> CellInfoModel? {
        do {
            let info = try AdvertisementInfo(encoded: advertisementLocalName, decryptingWith: key)
            return CellInfoModel(info: info, peripheral: peripheral, isConnected: isConnected)
        } catch {
            // Decryption failure can mean: wrong key, tampered payload, or a
            // peripheral that isn't part of this system — all are non-fatal.
            print("[BluetoothInfoShare] CellInfoModel decryption/parse failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Factory (plaintext — legacy / debug only)

    /// Parses a **plaintext** advertisement local-name.
    ///
    /// - Warning: Do not use in production; the local-name is visible to all
    ///   nearby BLE scanners.  Use ``makeInfo(advertisementLocalName:peripheral:isConnected:decryptingWith:)`` instead.
    public static func makeInfo(
        advertisementLocalName: String,
        peripheral: CBPeripheral,
        isConnected: Bool
    ) -> CellInfoModel? {
        do {
            let info = try AdvertisementInfo(encoded: advertisementLocalName)
            return CellInfoModel(info: info, peripheral: peripheral, isConnected: isConnected)
        } catch {
            print("[BluetoothInfoShare] CellInfoModel parse failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Equatable

    public static func == (lhs: CellInfoModel, rhs: CellInfoModel) -> Bool {
        lhs.peripheral.identifier == rhs.peripheral.identifier
    }
}
