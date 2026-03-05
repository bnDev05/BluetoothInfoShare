//
//  AdvertisementInfo.swift
//  BluetoothInfoShare
//
//  Created by Behruz Norov on 04/03/26.
//

//  Defines the structured payload that is encoded into the BLE advertisement
//  local-name string and decoded back into a `CellInfoModel` on the scanning side.
//
//  ## Wire Format
//  The advertisement local-name is a plain concatenated string:
//
//      [lastFourCardNumber (4)][objectID (6)][userID (6)][userName (variable)]
//
//  Field lengths are fixed for the first three segments so that parsing is
//  unambiguous without delimiters.  `userName` occupies everything that follows.
//

import Foundation

// MARK: - Field Length Constants

/// Fixed byte-lengths for each segment of the advertisement string.
public enum AdvertisementFieldLength {
    /// Length of `lastFourCardNumber` segment in the advertisement string.
    public static let lastFourCardNumber: Int = 4
    /// Length of `objectID` segment in the advertisement string.
    public static let objectID: Int = 6
    /// Length of `userID` segment in the advertisement string.
    public static let userID: Int = 6

    /// Minimum total length required to attempt parsing.
    public static var minimumTotal: Int {
        lastFourCardNumber + objectID + userID + 1  // at least 1 char for userName
    }
}

// MARK: - AdvertisementInfo

/// Structured representation of the data embedded in a BLE advertisement local-name.
///
/// Use ``encoded()`` to produce the advertisement string and ``init(encoded:)``
/// to parse one back.
///
/// ```swift
/// let info = AdvertisementInfo(
///     lastFourCardNumber: "1234",
///     objectID: "dscd34",
///     userID: "hskad7",
///     userName: "UserABCDEF"
/// )
/// let wire = info.encoded()          // "1234dscd34hskad7UserABCDEF"
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

    /// Creates an `AdvertisementInfo` with the given field values.
    ///
    /// - Parameters:
    ///   - lastFourCardNumber: Exactly 4 characters.
    ///   - objectID: Exactly 6 characters.
    ///   - userID: Exactly 6 characters.
    ///   - userName: At least 1 character.
    public init(
        lastFourCardNumber: String,
        objectID: String,
        userID: String,
        userName: String
    ) {
        self.lastFourCardNumber = lastFourCardNumber
        self.objectID = objectID
        self.userID = userID
        self.userName = userName
    }

    // MARK: Encoding

    /// Returns the concatenated advertisement string suitable for use as
    /// `CBAdvertisementDataLocalNameKey`.
    public func encoded() -> String {
        "\(lastFourCardNumber)\(objectID)\(userID)\(userName)"
    }

    // MARK: Decoding

    /// Parses an `AdvertisementInfo` from a raw advertisement local-name string.
    ///
    /// - Parameter encoded: The raw string from `CBAdvertisementDataLocalNameKey`.
    /// - Throws: ``AdvertisementInfoError`` if the string is too short or fields
    ///   cannot be extracted.
    public init(encoded: String) throws {
        guard encoded.count >= AdvertisementFieldLength.minimumTotal else {
            throw AdvertisementInfoError.stringTooShort(
                expected: AdvertisementFieldLength.minimumTotal,
                actual: encoded.count
            )
        }

        var cursor = encoded.startIndex

        // lastFourCardNumber
        let lastFourEnd = encoded.index(cursor, offsetBy: AdvertisementFieldLength.lastFourCardNumber)
        lastFourCardNumber = String(encoded[cursor..<lastFourEnd])
        cursor = lastFourEnd

        // objectID
        let objectIDEnd = encoded.index(cursor, offsetBy: AdvertisementFieldLength.objectID)
        objectID = String(encoded[cursor..<objectIDEnd])
        cursor = objectIDEnd

        // userID
        let userIDEnd = encoded.index(cursor, offsetBy: AdvertisementFieldLength.userID)
        userID = String(encoded[cursor..<userIDEnd])
        cursor = userIDEnd

        // userName — everything that remains
        let remaining = String(encoded[cursor...])
        guard !remaining.isEmpty else {
            throw AdvertisementInfoError.missingUserName
        }
        userName = remaining
    }
}

// MARK: - AdvertisementInfoError

/// Errors thrown when parsing an advertisement string fails.
public enum AdvertisementInfoError: LocalizedError {
    /// The raw string is shorter than the minimum required length.
    case stringTooShort(expected: Int, actual: Int)
    /// The `userName` portion of the string is empty.
    case missingUserName

    public var errorDescription: String? {
        switch self {
        case let .stringTooShort(expected, actual):
            return "Advertisement string too short: expected ≥\(expected) characters, got \(actual)."
        case .missingUserName:
            return "Advertisement string contains no userName after the fixed-length fields."
        }
    }
}
