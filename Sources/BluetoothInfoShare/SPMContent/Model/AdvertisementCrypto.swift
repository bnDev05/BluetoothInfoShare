//
//  AdvertisementCrypto.swift
//  BluetoothInfoShare
//
//  AES-GCM encryption / decryption for BLE advertisement payloads.
//
//  ## Why AES-GCM?
//  BLE local-name bytes are broadcast to every nearby device unencrypted.
//  AES-GCM provides:
//    • Confidentiality  – no passive observer can read the fields.
//    • Integrity        – tampered ciphertext is rejected on decryption.
//    • Freshness        – a random 12-byte nonce is prepended so the same
//                         plaintext never produces the same ciphertext twice,
//                         defeating replay attacks.
//
//  ## Key management (your responsibility)
//  This file only handles the symmetric encryption layer.  The 256-bit key
//  must be established through a secure channel *before* advertising begins —
//  for example, derived from a server-issued session token, exchanged via a
//  QR-code pairing flow, or negotiated with ECDH over an authenticated
//  connection.  Never hard-code a key in source.
//
//  ## Wire format
//
//      [ nonce (12 bytes) ][ AES-GCM ciphertext + 16-byte tag ]
//
//  The combined blob is base64url-encoded (no padding) before it is placed
//  into CBAdvertisementDataLocalNameKey, keeping it printable and compact.
//
//  ## BLE advertisement name length limit
//  The BLE spec allows up to 248 bytes for the Complete Local Name AD type,
//  but iOS/macOS CoreBluetooth typically honours only the first 26–29 bytes
//  visible to passive scanners (the rest is available after a scan-response
//  or connection).  An encrypted 16-byte plaintext (4+6+6 fixed fields with
//  minimal userName) expands to 12 (nonce) + 16 (tag) + 16 (cipher) = 44 raw
//  bytes → ~59 base64 chars.  If you hit the limit, reduce the userName
//  length or move large payloads to the GATT characteristic after connection.
//

import Foundation
import CryptoKit

// MARK: - AdvertisementCrypto

public enum AdvertisementCrypto {

    // MARK: - Errors

    public enum CryptoError: LocalizedError {
        case invalidKeyLength(Int)
        case base64DecodingFailed
        case payloadTooShort(got: Int, minimum: Int)
        case decryptionFailed(underlying: Error)

        public var errorDescription: String? {
            switch self {
            case .invalidKeyLength(let len):
                return "Key must be 32 bytes (256 bits); got \(len)."
            case .base64DecodingFailed:
                return "Advertisement payload is not valid base64url."
            case .payloadTooShort(let got, let min):
                return "Decoded payload is \(got) bytes; minimum is \(min) (nonce + tag)."
            case .decryptionFailed(let err):
                return "AES-GCM decryption failed: \(err.localizedDescription)"
            }
        }
    }

    // MARK: - Constants

    /// AES-GCM nonce size in bytes.
    private static let nonceSize = 12
    /// AES-GCM authentication tag size in bytes.
    private static let tagSize   = 16
    /// Minimum decoded payload: nonce + tag (zero-length plaintext is valid).
    private static let minimumPayloadSize = nonceSize + tagSize

    // MARK: - Encrypt

    /// Encrypts `plaintext` with a 256-bit AES-GCM key and returns a
    /// base64url-encoded string suitable for `CBAdvertisementDataLocalNameKey`.
    ///
    /// - Parameters:
    ///   - plaintext: The raw bytes to protect (e.g. encoded `AdvertisementInfo`).
    ///   - keyData:   A 32-byte symmetric key shared with the scanning peer.
    /// - Returns: `nonce ‖ ciphertext+tag` encoded as base64url (no padding).
    /// - Throws: ``CryptoError`` if the key length is wrong; `CryptoKit` errors
    ///   on encryption failure (extremely rare with valid inputs).
    public static func encrypt(plaintext: Data, keyData: Data) throws -> String {
        guard keyData.count == 32 else {
            throw CryptoError.invalidKeyLength(keyData.count)
        }

        let key   = SymmetricKey(data: keyData)
        let nonce = try AES.GCM.Nonce()                     // cryptographically random 12 bytes
        let box   = try AES.GCM.seal(plaintext, using: key, nonce: nonce)

        // Combine: nonce (12) ‖ ciphertext ‖ tag (16)
        var combined = Data(nonce)
        combined.append(box.ciphertext)
        combined.append(box.tag)

        return base64urlEncode(combined)
    }

    // MARK: - Decrypt

    /// Decrypts a base64url-encoded advertisement payload produced by ``encrypt(plaintext:keyData:)``.
    ///
    /// - Parameters:
    ///   - encoded:  The raw value of `CBAdvertisementDataLocalNameKey`.
    ///   - keyData:  The same 32-byte key used during encryption.
    /// - Returns: The original plaintext bytes.
    /// - Throws: ``CryptoError`` on malformed input or authentication failure.
    public static func decrypt(encoded: String, keyData: Data) throws -> Data {
        guard keyData.count == 32 else {
            throw CryptoError.invalidKeyLength(keyData.count)
        }

        guard let raw = base64urlDecode(encoded) else {
            throw CryptoError.base64DecodingFailed
        }
        guard raw.count >= minimumPayloadSize else {
            throw CryptoError.payloadTooShort(got: raw.count, minimum: minimumPayloadSize)
        }

        let nonceBytes      = raw[..<nonceSize]
        let ciphertextBytes = raw[nonceSize ..< raw.count - tagSize]
        let tagBytes        = raw[(raw.count - tagSize)...]

        do {
            let nonce      = try AES.GCM.Nonce(data: nonceBytes)
            let sealedBox  = try AES.GCM.SealedBox(
                nonce:      nonce,
                ciphertext: ciphertextBytes,
                tag:        tagBytes
            )
            let key = SymmetricKey(data: keyData)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            throw CryptoError.decryptionFailed(underlying: error)
        }
    }

    // MARK: - Base64url helpers (RFC 4648 §5, no padding)

    private static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64urlDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        // Re-add padding
        let remainder = s.count % 4
        if remainder != 0 { s += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: s)
    }
}
