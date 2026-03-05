import XCTest
@testable import BluetoothInfoShare

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

