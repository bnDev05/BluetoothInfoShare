//
//  CellInfoModel.swift
//  ExampleProject
//
//  Created by Behruz on 03/02/26.
//

import Foundation
import CoreBluetooth

/// An immutable snapshot of the data broadcast by a remote peripheral.
///
/// Create instances via ``makeInfo(advertisementLocalName:peripheral:isConnected:)``
/// or directly from an ``AdvertisementInfo`` value.
///
/// ```swift
/// // From raw advertisement string
/// if let cell = CellInfoModel.makeInfo(
///     advertisementLocalName: "1234dscd34hskad7UserABCDEF",
///     peripheral: peripheral,
///     isConnected: false
/// ) {
///     print(cell.userName)  // "UserABCDEF"
/// }
///
/// // From a pre-parsed AdvertisementInfo
/// let info = AdvertisementInfo(lastFourCardNumber: "1234", objectID: "dscd34",
///                              userID: "hskad7", userName: "UserABCDEF")
/// let cell = CellInfoModel(info: info, peripheral: peripheral, isConnected: false)
/// ```
public struct CellInfoModel: Identifiable, Equatable {

    // MARK: - Properties

    /// Stable unique identifier for use in SwiftUI lists.
    public let id: UUID

    /// Human-readable display name extracted from the advertisement.
    public let name: String

    /// Last four digits of the advertiser's payment card.
    public let lastFourCardNumber: String

    /// Opaque object identifier from the advertisement.
    public let objectID: String

    /// Opaque user identifier from the advertisement.
    public let userID: String

    /// The underlying CoreBluetooth peripheral.
    public let peripheral: CBPeripheral

    /// Whether the central is currently connected to this peripheral.
    public var isConnected: Bool

    // MARK: - Init (direct)

    /// Creates a `CellInfoModel` directly from an ``AdvertisementInfo`` value.
    ///
    /// - Parameters:
    ///   - info: Parsed advertisement payload.
    ///   - peripheral: The originating peripheral.
    ///   - isConnected: Current connection state.
    public init(info: AdvertisementInfo, peripheral: CBPeripheral, isConnected: Bool) {
        self.id = UUID()
        self.name = info.userName
        self.lastFourCardNumber = info.lastFourCardNumber
        self.objectID = info.objectID
        self.userID = info.userID
        self.peripheral = peripheral
        self.isConnected = isConnected
    }

    // MARK: - Factory

    /// Attempts to parse the advertisement local-name string and build a model.
    ///
    /// Returns `nil` (and logs a warning) when `advertisementLocalName` is too short
    /// or otherwise malformed.
    ///
    /// - Parameters:
    ///   - advertisementLocalName: The raw value of `CBAdvertisementDataLocalNameKey`.
    ///   - peripheral: The originating `CBPeripheral`.
    ///   - isConnected: Whether the central is already connected.
    /// - Returns: A populated `CellInfoModel`, or `nil` on parse failure.
    public static func makeInfo(
        advertisementLocalName: String,
        peripheral: CBPeripheral,
        isConnected: Bool
    ) -> CellInfoModel? {
        do {
            let info = try AdvertisementInfo(encoded: advertisementLocalName)
            return CellInfoModel(info: info, peripheral: peripheral, isConnected: isConnected)
        } catch {
            // Non-fatal: many peripherals won't carry a matching local name.
            print("[BluetoothInfoShare] CellInfoModel parse failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Equatable

    public static func == (lhs: CellInfoModel, rhs: CellInfoModel) -> Bool {
        lhs.peripheral.identifier == rhs.peripheral.identifier
    }
}
