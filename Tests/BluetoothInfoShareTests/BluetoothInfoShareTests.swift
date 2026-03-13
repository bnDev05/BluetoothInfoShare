import XCTest
import CryptoKit
@testable import BluetoothInfoShare

// MARK: - Existing plaintext tests (unchanged)

final class AdvertisementInfoTests: XCTestCase {

    func test_encoded_concatenatesFieldsInOrder() {
        let info = AdvertisementInfo(
            lastFourCardNumber: "1234",
            objectID: "dscd34",
            userID: "hskad7",
            userName: "UserABCDEF"
        )
        XCTAssertEqual(info.encoded(), "1234dscd34hskad7UserABCDEF")
    }

    func test_decode_roundTrip() throws {
        let original = AdvertisementInfo(
            lastFourCardNumber: "9876",
            objectID: "abc123",
            userID: "xyz789",
            userName: "UserTestDevice"
        )
        let parsed = try AdvertisementInfo(encoded: original.encoded())

        XCTAssertEqual(parsed.lastFourCardNumber, original.lastFourCardNumber)
        XCTAssertEqual(parsed.objectID,           original.objectID)
        XCTAssertEqual(parsed.userID,             original.userID)
        XCTAssertEqual(parsed.userName,           original.userName)
    }

    func test_decode_singleCharUserName() throws {
        let wire = "1234dscd34hskad7X"
        let info = try AdvertisementInfo(encoded: wire)
        XCTAssertEqual(info.userName, "X")
    }

    func test_decode_longUserName() throws {
        let wire = "1234dscd34hskad7" + "This Is A Very Long User Name 🎉"
        let info = try AdvertisementInfo(encoded: wire)
        XCTAssertEqual(info.userName, "This Is A Very Long User Name 🎉")
    }

    func test_decode_throwsOnStringTooShort() {
        let wire = "1234dscd34hskad"
        XCTAssertThrowsError(try AdvertisementInfo(encoded: wire)) { error in
            guard case AdvertisementInfoError.stringTooShort = error else {
                XCTFail("Expected stringTooShort, got \(error)")
                return
            }
        }
    }

    func test_decode_throwsOnEmptyString() {
        XCTAssertThrowsError(try AdvertisementInfo(encoded: ""))
    }

    func test_minimumTotal_isCorrect() {
        XCTAssertEqual(AdvertisementFieldLength.minimumTotal, 17)
    }
}

final class CellInfoModelTests: XCTestCase {

    func test_shortString_failsToParse() {
        XCTAssertThrowsError(try AdvertisementInfo(encoded: "short"))
    }

    func test_validWireString_parsesAllFields() throws {
        let info = try AdvertisementInfo(encoded: "1234dscd34hskad7UserDevice")
        XCTAssertEqual(info.lastFourCardNumber, "1234")
        XCTAssertEqual(info.objectID,           "dscd34")
        XCTAssertEqual(info.userID,             "hskad7")
        XCTAssertEqual(info.userName,           "UserDevice")
    }
}

// MARK: - New: AdvertisementCrypto tests

final class AdvertisementCryptoTests: XCTestCase {

    // A fixed 32-byte key for deterministic tests.
    private var validKey: Data { Data(repeating: 0xAB, count: 32) }

    // MARK: Round-trip

    func test_encryptDecrypt_roundTrip() throws {
        let plaintext = "Hello, BLE!".data(using: .utf8)!
        let encrypted = try AdvertisementCrypto.encrypt(plaintext: plaintext, keyData: validKey)
        let decrypted = try AdvertisementCrypto.decrypt(encoded: encrypted, keyData: validKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    func test_encryptDecrypt_roundTrip_emptyPlaintext() throws {
        let plaintext = Data()
        let encrypted = try AdvertisementCrypto.encrypt(plaintext: plaintext, keyData: validKey)
        let decrypted = try AdvertisementCrypto.decrypt(encoded: encrypted, keyData: validKey)
        XCTAssertEqual(decrypted, plaintext)
    }

    // MARK: Ciphertext is non-deterministic (fresh nonce each call)

    func test_encrypt_producesDifferentCiphertextEachCall() throws {
        let plaintext = "same payload".data(using: .utf8)!
        let first  = try AdvertisementCrypto.encrypt(plaintext: plaintext, keyData: validKey)
        let second = try AdvertisementCrypto.encrypt(plaintext: plaintext, keyData: validKey)
        // Same plaintext + key must yield different ciphertext (different nonces).
        XCTAssertNotEqual(first, second, "Encryption must use a fresh nonce every time.")
    }

    // MARK: Wrong key is rejected

    func test_decrypt_wrongKey_throws() throws {
        let plaintext = "secret".data(using: .utf8)!
        let encrypted = try AdvertisementCrypto.encrypt(plaintext: plaintext, keyData: validKey)

        let wrongKey = Data(repeating: 0x00, count: 32)
        XCTAssertThrowsError(try AdvertisementCrypto.decrypt(encoded: encrypted, keyData: wrongKey)) { error in
            guard case AdvertisementCrypto.CryptoError.decryptionFailed = error else {
                XCTFail("Expected decryptionFailed, got \(error)")
                return
            }
        }
    }

    // MARK: Tampered ciphertext is rejected (AES-GCM integrity)

    func test_decrypt_tamperedCiphertext_throws() throws {
        let plaintext = "sensitive data".data(using: .utf8)!
        var encrypted = try AdvertisementCrypto.encrypt(plaintext: plaintext, keyData: validKey)

        // Flip the last character of the base64url string to simulate tampering.
        encrypted = String(encrypted.dropLast()) + (encrypted.hasSuffix("A") ? "B" : "A")

        XCTAssertThrowsError(try AdvertisementCrypto.decrypt(encoded: encrypted, keyData: validKey))
    }

    // MARK: Invalid key lengths

    func test_encrypt_shortKey_throws() {
        let shortKey = Data(repeating: 0x01, count: 16)   // 128-bit — invalid for this API
        XCTAssertThrowsError(
            try AdvertisementCrypto.encrypt(plaintext: Data(), keyData: shortKey)
        ) { error in
            guard case AdvertisementCrypto.CryptoError.invalidKeyLength(16) = error else {
                XCTFail("Expected invalidKeyLength(16), got \(error)")
                return
            }
        }
    }

    func test_decrypt_shortKey_throws() {
        let shortKey = Data(repeating: 0x01, count: 16)
        XCTAssertThrowsError(
            try AdvertisementCrypto.decrypt(encoded: "anything", keyData: shortKey)
        ) { error in
            guard case AdvertisementCrypto.CryptoError.invalidKeyLength(16) = error else {
                XCTFail("Expected invalidKeyLength(16), got \(error)")
                return
            }
        }
    }

    // MARK: Malformed base64

    func test_decrypt_invalidBase64_throws() {
        XCTAssertThrowsError(
            try AdvertisementCrypto.decrypt(encoded: "!!!not-base64!!!", keyData: validKey)
        ) { error in
            guard case AdvertisementCrypto.CryptoError.base64DecodingFailed = error else {
                XCTFail("Expected base64DecodingFailed, got \(error)")
                return
            }
        }
    }

    // MARK: Payload too short (nonce + tag not present)

    func test_decrypt_tooShortPayload_throws() throws {
        // A valid base64url string that decodes to fewer than 28 bytes (nonce 12 + tag 16).
        let tooShort = Data(repeating: 0xFF, count: 10)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        XCTAssertThrowsError(
            try AdvertisementCrypto.decrypt(encoded: tooShort, keyData: validKey)
        ) { error in
            guard case AdvertisementCrypto.CryptoError.payloadTooShort = error else {
                XCTFail("Expected payloadTooShort, got \(error)")
                return
            }
        }
    }
}

// MARK: - New: Encrypted AdvertisementInfo round-trip

final class AdvertisementInfoEncryptedTests: XCTestCase {

    private var key: Data { Data(repeating: 0xCD, count: 32) }

    func test_encryptedEncoding_roundTrip() throws {
        let original = AdvertisementInfo(
            lastFourCardNumber: "5678",
            objectID: "obj999",
            userID: "usr123",
            userName: "AliceDevice"
        )

        let wire   = try original.encoded(encryptedWith: key)
        let parsed = try AdvertisementInfo(encoded: wire, decryptingWith: key)

        XCTAssertEqual(parsed.lastFourCardNumber, original.lastFourCardNumber)
        XCTAssertEqual(parsed.objectID,           original.objectID)
        XCTAssertEqual(parsed.userID,             original.userID)
        XCTAssertEqual(parsed.userName,           original.userName)
    }

    func test_encryptedPayload_isOpaque_toPlaintextDecoder() throws {
        let info = AdvertisementInfo(
            lastFourCardNumber: "1111",
            objectID: "aaaaaa",
            userID: "bbbbbb",
            userName: "BobDevice"
        )
        let wire = try info.encoded(encryptedWith: key)

        // The encrypted wire string must not be parseable as plaintext.
        // (If it were, private fields would be visible without the key.)
        XCTAssertThrowsError(try AdvertisementInfo(encoded: wire),
            "Encrypted payload must not be decodable via the plaintext path.")
    }

    func test_decryptWithWrongKey_throws() throws {
        let info = AdvertisementInfo(
            lastFourCardNumber: "2222",
            objectID: "cccccc",
            userID: "dddddd",
            userName: "CharlieDevice"
        )
        let wire     = try info.encoded(encryptedWith: key)
        let wrongKey = Data(repeating: 0x00, count: 32)

        XCTAssertThrowsError(try AdvertisementInfo(encoded: wire, decryptingWith: wrongKey))
    }

    func test_encryptedPayload_doesNotContainPlaintextFields() throws {
        let info = AdvertisementInfo(
            lastFourCardNumber: "9999",
            objectID: "secret",
            userID: "priv88",
            userName: "SensitiveUser"
        )
        let wire = try info.encoded(encryptedWith: key)

        // None of the sensitive fields should appear literally in the wire string.
        XCTAssertFalse(wire.contains("9999"),         "Card digits must not appear in plaintext.")
        XCTAssertFalse(wire.contains("secret"),       "objectID must not appear in plaintext.")
        XCTAssertFalse(wire.contains("priv88"),       "userID must not appear in plaintext.")
        XCTAssertFalse(wire.contains("SensitiveUser"),"userName must not appear in plaintext.")
    }
}
