//
//  CellInfoModel.swift
//  ExampleProject
//
//  Created by Behruz on 03/02/26.
//

import Foundation
import CoreBluetooth

struct CellInfoModel: Identifiable {
    let id: UUID
    let name: String
    let lastFourCardNumber: String
    let objectID: String
    let userID: String
    let peripheral: CBPeripheral
    var isConnected: Bool
    
    
    static func makeInfo(
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
