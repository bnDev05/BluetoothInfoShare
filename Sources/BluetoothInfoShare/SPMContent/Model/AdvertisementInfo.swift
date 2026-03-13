//
//  AdvertisementInfo.swift
//  BluetoothInfoShare
//
//  Structured payload encoded into the BLE advertisement local-name string.
//
//  ## Wire Format (plaintext, before encryption)
//
//      [lastFourCardNumber (4)][objectID (6)][userID (6)][userName (variable)]
//
//  Field lengths are fixed for the first three segments so that parsing is
//  unambiguous without delimiters.  `userName` occupies everything that follows.
//
//  ## Security
//  Call ``encoded(encryptedWith:)`` / ``init(encoded:decryptingWith:)`` rather
//  than the plain ``encoded()`` / ``init(encoded:)`` overloads.  The encrypted
//  path uses AES-GCM (via ``AdvertisementCrypto``) so that a passive BLE
//  scanner cannot read userID, objectID, or card digits from the advertisement.
//
//  The symmetric key must be established through a secure out-of-band channel
//  (e.g. server-issued session, QR pairing, ECDH over an authenticated link).
//  Never hard-code a key.
//

import Foundation

// MARK: - Field Length Constants

/// Fixed byte-lengths for each segment of the advertisement string.
public enum AdvertisementFieldLength {
    public static let lastFourCardNumber: Int = 4
    public static let objectID:           Int = 6
    public static let userID:             Int = 6

    /// Minimum total length required to attempt plaintext parsing.
    public static var minimumTotal: Int {
        lastFourCardNumber + objectID + userID + 1   // at least 1 char for userName
    }
}

// MARK: - AdvertisementInfo

/// Structured representation of the data embedded in a BLE advertisement local-name.
///
/// ### Secure (recommended)
/// ```swift
/// let info = AdvertisementInfo(
///     lastFourCardNumber: "1234",
///     objectID: "dscd34",
///     userID: "hskad7",
///     userName: "UserABCDEF"
/// )
///
/// // Encrypt before advertising
/// let wire = try info.encoded(encryptedWith: sessionKey)
///
/// // Decrypt on the scanning side
/// let parsed = try AdvertisementInfo(encoded: wire, decryptingWith: sessionKey)
/// ```
///
/// ### Plaintext (legacy / debugging only)
/// ```swift
/// let wire   = info.encoded()                      // "1234dscd34hskad7UserABCDEF"
/// let parsed = try AdvertisementInfo(encoded: wire)
/// ```
public struct AdvertisementInfo: Equatable, Sendable {

    // MARK: Properties

    /// Last four digits of the payment card (exactly 4 characters).
    public let lastFourCardNumber: String

    /// Opaque object identifier (exactly 6 characters).
    public let objectID: String

    /// Opaque user identifier (exactly 6 characters).
    public let userID: String

    /// Human-readable display name (variable length, at least 1 character).
    public let userName: String

    // MARK: Init

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

    // MARK: - Plaintext Encoding (legacy)

    /// Returns the raw concatenated string **without encryption**.
    ///
    /// - Warning: Do **not** pass this string to `CBAdvertisementDataLocalNameKey`
    ///   in production.  Use ``encoded(encryptedWith:)`` instead.
    public func encoded() -> String {
        "\(lastFourCardNumber)\(objectID)\(userID)\(userName)"
    }

    // MARK: - Encrypted Encoding (recommended)

    /// Encrypts the advertisement payload with AES-GCM and returns a
    /// base64url string safe to broadcast as the BLE local name.
    ///
    /// - Parameter key: A 32-byte (256-bit) symmetric key shared with the peer.
    /// - Returns: Encrypted, base64url-encoded advertisement string.
    /// - Throws: ``AdvertisementCrypto/CryptoError`` on invalid key or encryption failure.
    public func encoded(encryptedWith key: Data) throws -> String {
        guard let plaintext = encoded().data(using: .utf8) else {
            throw AdvertisementInfoError.encodingFailed
        }
        return try AdvertisementCrypto.encrypt(plaintext: plaintext, keyData: key)
    }

    // MARK: - Plaintext Decoding (legacy)

    /// Parses an `AdvertisementInfo` from a **plaintext** advertisement local-name string.
    ///
    /// - Warning: Use ``init(encoded:decryptingWith:)`` for data received over the air.
    /// - Throws: ``AdvertisementInfoError`` if the string is too short or malformed.
    public init(encoded: String) throws {
        guard encoded.count >= AdvertisementFieldLength.minimumTotal else {
            throw AdvertisementInfoError.stringTooShort(
                expected: AdvertisementFieldLength.minimumTotal,
                actual: encoded.count
            )
        }

        var cursor = encoded.startIndex

        let lastFourEnd = encoded.index(cursor, offsetBy: AdvertisementFieldLength.lastFourCardNumber)
        lastFourCardNumber = String(encoded[cursor..<lastFourEnd])
        cursor = lastFourEnd

        let objectIDEnd = encoded.index(cursor, offsetBy: AdvertisementFieldLength.objectID)
        objectID = String(encoded[cursor..<objectIDEnd])
        cursor = objectIDEnd

        let userIDEnd = encoded.index(cursor, offsetBy: AdvertisementFieldLength.userID)
        userID = String(encoded[cursor..<userIDEnd])
        cursor = userIDEnd

        let remaining = String(encoded[cursor...])
        guard !remaining.isEmpty else {
            throw AdvertisementInfoError.missingUserName
        }
        userName = remaining
    }

    // MARK: - Encrypted Decoding (recommended)

    /// Decrypts and parses an `AdvertisementInfo` from an encrypted advertisement
    /// local-name string produced by ``encoded(encryptedWith:)``.
    ///
    /// - Parameters:
    ///   - encoded:  The raw value of `CBAdvertisementDataLocalNameKey`.
    ///   - key:      The same 32-byte key used by the advertising peer.
    /// - Throws: ``AdvertisementCrypto/CryptoError`` on decryption failure, or
    ///   ``AdvertisementInfoError`` if the decrypted plaintext is malformed.
    public init(encoded: String, decryptingWith key: Data) throws {
        let plaintext = try AdvertisementCrypto.decrypt(encoded: encoded, keyData: key)
        guard let string = String(data: plaintext, encoding: .utf8) else {
            throw AdvertisementInfoError.decodingFailed
        }
        try self.init(encoded: string)
    }
}

// MARK: - AdvertisementInfoError

/// Errors thrown when encoding or parsing an advertisement string fails.
public enum AdvertisementInfoError: LocalizedError {
    case stringTooShort(expected: Int, actual: Int)
    case missingUserName
    case encodingFailed
    case decodingFailed

    public var errorDescription: String? {
        switch self {
        case let .stringTooShort(expected, actual):
            return "Advertisement string too short: expected ≥\(expected) characters, got \(actual)."
        case .missingUserName:
            return "Advertisement string contains no userName after the fixed-length fields."
        case .encodingFailed:
            return "Failed to encode AdvertisementInfo to UTF-8."
        case .decodingFailed:
            return "Decrypted advertisement payload is not valid UTF-8."
        }
    }
}
