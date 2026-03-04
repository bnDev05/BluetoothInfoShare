//
//  CellInfoModel.swift
//  ExampleProject
//
//  Created by Behruz on 03/02/26.
//

import Foundation
import CoreBluetooth

public struct CellInfoModel: Identifiable {
    public let id: UUID
    public let name: String
    public let lastFourCardNumber: String
    public let objectID: String
    public let userID: String
    public let peripheral: CBPeripheral
    public var isConnected: Bool
    
    
    public static func makeInfo(
        fullString: String,
        peripheral: CBPeripheral,
        isConnected: Bool
    ) -> CellInfoModel? {
        
        guard fullString.count >= 18 else { return nil }
        
        let lastFour = String(fullString.prefix(4))
        
        let objectStart = fullString.index(fullString.startIndex, offsetBy: AppConstants.lastFourCardNumber.count)
        let objectEnd = fullString.index(objectStart, offsetBy: AppConstants.objectID.count)
        let objectID = String(fullString[objectStart..<objectEnd])
        
        let userStart = objectEnd
        let userEnd = fullString.index(userStart, offsetBy: AppConstants.userID.count)
        let userID = String(fullString[userStart..<userEnd])
        
        let name = String(fullString[userEnd...])
        
        return CellInfoModel(
            id: UUID(),
            name: name,
            lastFourCardNumber: lastFour,
            objectID: objectID,
            userID: userID,
            peripheral: peripheral,
            isConnected: isConnected
        )
    }
}
