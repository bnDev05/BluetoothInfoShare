//
//  AdvertisementInfo.swift
//  BluetoothInfoShare
//
//  ## Why the design changed
//
//  BLE advertisement packets are limited to ~26 bytes for the local-name AD
//  type as seen by a passive iOS scanner.  AES-GCM adds 12 bytes (nonce) +
//  16 bytes (tag) of overhead before base64 encoding, which expands every
//  payload by ~2.3x.  Even the minimum plaintext (4+6+6+1 = 17 bytes)
//  produces a 68-character base64url string — far exceeding the iOS passive-
//  scan truncation limit.  The result: the scanner always received a truncated
//  ciphertext, decryption always failed, and no devices ever appeared.
//
//  ## New design
//
//  The advertisement carries ONLY the userName (a display name, not a
//  credential).  Sensitive fields (lastFourCardNumber, objectID, userID) are
//  exchanged encrypted over the GATT characteristic AFTER connection, using
//  the existing chunked send/receive infrastructure.
//
//  ## Wire format (advertisement local name)
//      [userName — plain UTF-8, variable, <= 20 chars recommended]
//
//  ## Wire format (GATT payload)
//      JSON: { "lastFour": "1234", "objectID": "dscd34", "userID": "hskad7" }
//      Encrypted with AES-GCM before being passed to sendData(_:).
//

import Foundation

// MARK: - AdvertisementInfo

/// Represents the data a device broadcasts and shares over BLE.
///
/// ### Advertisement (passive scan)
/// Only `userName` is broadcast — it is a display name, not a credential.
///
/// ### Sensitive payload (post-connection, over GATT)
/// `lastFourCardNumber`, `objectID`, and `userID` travel as encrypted JSON
/// sent via ``BluetoothManager/sendData(_:)`` after connection.
public struct AdvertisementInfo: Equatable, Sendable {

    // MARK: - Properties

    /// Last four digits of the payment card — GATT only, never advertised.
    public let lastFourCardNumber: String
    /// Opaque object identifier — GATT only, never advertised.
    public let objectID: String
    /// Opaque user identifier — GATT only, never advertised.
    public let userID: String
    /// Human-readable display name — the ONLY field placed in the BLE advertisement.
    public let userName: String

    // MARK: - Init

    public init(
        lastFourCardNumber: String,
        objectID: String,
        userID: String,
        userName: String
    ) {
        self.lastFourCardNumber = lastFourCardNumber
        self.objectID           = objectID
        self.userID             = userID
        self.userName           = userName
    }

    // MARK: - Advertisement encoding (safe — userName only)

    /// The string to place in `CBAdvertisementDataLocalNameKey`.
    /// Keep userName <= 20 UTF-8 characters to stay within the iOS
    /// passive-scan local-name truncation limit (~26 bytes).
    public func advertisementLocalName() -> String {
        userName
    }

    // MARK: - Sensitive payload (for encrypted GATT transfer)

    /// Compact JSON containing the three sensitive fields.
    /// Encrypt this before passing to ``BluetoothManager/sendData(_:)``.
    public func sensitivePayload() throws -> Data {
        let dict: [String: String] = [
            "lastFour": lastFourCardNumber,
            "objectID": objectID,
            "userID":   userID
        ]
        return try JSONSerialization.data(withJSONObject: dict)
    }

    // MARK: - Reconstruct from advertisement + decrypted GATT payload

    /// Rebuilds a complete `AdvertisementInfo` from a scanned userName and
    /// a decrypted GATT payload produced by ``sensitivePayload()``.
    public init(userName: String, sensitivePayloadData payloadData: Data) throws {
        guard
            let dict     = try JSONSerialization.jsonObject(with: payloadData) as? [String: String],
            let lastFour = dict["lastFour"],
            let objectID = dict["objectID"],
            let userID   = dict["userID"]
        else {
            throw AdvertisementInfoError.malformedSensitivePayload
        }
        self.userName           = userName
        self.lastFourCardNumber = lastFour
        self.objectID           = objectID
        self.userID             = userID
    }
}

// MARK: - AdvertisementInfoError

public enum AdvertisementInfoError: LocalizedError {
    case malformedSensitivePayload

    public var errorDescription: String? {
        "Sensitive GATT payload is missing required keys (lastFour / objectID / userID)."
    }
}
