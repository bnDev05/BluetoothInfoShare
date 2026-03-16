//
//  CellInfoModel.swift
//  BluetoothInfoShare
//

import Foundation
import CoreBluetooth

/// An immutable snapshot of the data broadcast by a remote peripheral.
///
/// ## Two-phase population
///
/// **Phase 1 — passive scan** (no connection needed):
/// `makeInfo(advertisementLocalName:peripheral:isConnected:)` creates a model
/// with `userName` filled in and sensitive fields set to empty strings.
/// This is enough to display the device in a list.
///
/// **Phase 2 — post-connection** (after GATT exchange):
/// `applying(sensitivePayloadData:encryptionKey:)` returns a new model with
/// `lastFourCardNumber`, `objectID`, and `userID` populated from the
/// decrypted GATT payload.
public struct CellInfoModel: Identifiable, Equatable {

    // MARK: - Properties

    public let id:                 UUID
    public let name:               String
    /// Empty until the encrypted GATT payload is received and decrypted.
    public let lastFourCardNumber: String
    /// Empty until the encrypted GATT payload is received and decrypted.
    public let objectID:           String
    /// Empty until the encrypted GATT payload is received and decrypted.
    public let userID:             String
    public let peripheral:         CBPeripheral
    public var isConnected:        Bool

    // MARK: - Phase 1: build from advertisement (userName only)

    /// Creates a display-ready model from a raw advertisement local-name.
    ///
    /// Sensitive fields are empty — they arrive over GATT after connection.
    ///
    /// - Parameters:
    ///   - advertisementLocalName: The raw value of `CBAdvertisementDataLocalNameKey`
    ///                             (now just the userName).
    ///   - peripheral:             The originating peripheral.
    ///   - isConnected:            Current connection state.
    /// - Returns: A model with `name` set and sensitive fields empty,
    ///   or `nil` if `advertisementLocalName` is blank.
    public static func makeInfo(
        advertisementLocalName: String,
        peripheral: CBPeripheral,
        isConnected: Bool
    ) -> CellInfoModel? {
        let userName = advertisementLocalName.trimmingCharacters(in: .whitespaces)
        guard !userName.isEmpty else {
            print("[BluetoothInfoShare] CellInfoModel: empty local name, skipping.")
            return nil
        }
        return CellInfoModel(
            id:                 UUID(),
            name:               userName,
            lastFourCardNumber: "",   // populated in phase 2
            objectID:           "",
            userID:             "",
            peripheral:         peripheral,
            isConnected:        isConnected
        )
    }

    // MARK: - Phase 2: merge decrypted GATT payload

    /// Returns a new model with sensitive fields populated from a decrypted
    /// GATT payload produced by ``AdvertisementInfo/sensitivePayload()``.
    ///
    /// Call this inside your `dataReceivedPublisher` handler after decrypting:
    /// ```swift
    /// BluetoothManager.dataReceivedPublisher
    ///     .sink { data in
    ///         let cipher  = String(data: data, encoding: .utf8)!
    ///         let json    = try AdvertisementCrypto.decrypt(encoded: cipher, keyData: key)
    ///         let updated = cell.applying(sensitivePayloadData: json)
    ///     }
    /// ```
    ///
    /// - Parameter payloadData: Decrypted JSON from the GATT characteristic.
    /// - Returns: Updated model, or `self` if parsing fails.
    public func applying(sensitivePayloadData payloadData: Data) -> CellInfoModel {
        guard
            let dict     = try? JSONSerialization.jsonObject(with: payloadData) as? [String: String],
            let lastFour = dict["lastFour"],
            let objectID = dict["objectID"],
            let userID   = dict["userID"]
        else {
            print("[BluetoothInfoShare] CellInfoModel: failed to parse sensitive payload.")
            return self
        }
        return CellInfoModel(
            id:                 self.id,
            name:               self.name,
            lastFourCardNumber: lastFour,
            objectID:           objectID,
            userID:             userID,
            peripheral:         self.peripheral,
            isConnected:        self.isConnected
        )
    }

    /// Returns a new model with sensitive fields replaced.
    /// Use this to restore cached fields when a device reappears after a list clear.
    public func withSensitiveFields(lastFour: String, objectID: String, userID: String) -> CellInfoModel {
        CellInfoModel(
            id:                 self.id,
            name:               self.name,
            lastFourCardNumber: lastFour,
            objectID:           objectID,
            userID:             userID,
            peripheral:         self.peripheral,
            isConnected:        self.isConnected
        )
    }

    // MARK: - Internal memberwise init

    private init(
        id: UUID,
        name: String,
        lastFourCardNumber: String,
        objectID: String,
        userID: String,
        peripheral: CBPeripheral,
        isConnected: Bool
    ) {
        self.id                 = id
        self.name               = name
        self.lastFourCardNumber = lastFourCardNumber
        self.objectID           = objectID
        self.userID             = userID
        self.peripheral         = peripheral
        self.isConnected        = isConnected
    }

    // MARK: - Equatable

    public static func == (lhs: CellInfoModel, rhs: CellInfoModel) -> Bool {
        lhs.peripheral.identifier == rhs.peripheral.identifier
    }
}
