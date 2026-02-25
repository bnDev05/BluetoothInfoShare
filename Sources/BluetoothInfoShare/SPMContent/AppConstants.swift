//
//  AppConstants.swift
//  ExampleProject
//
//  Created by Behruz on 24/02/26.
//

import UIKit

enum AppConstants {
    static let lastFourCardNumber: String = "1234"
    static let objectID: String = "dscd34"
    static let userID: String = "hskad7"
    
    static let userName: String = {
        let rawID = UIDevice.current.identifierForVendor?.uuidString
            .replacingOccurrences(of: "-", with: "")
        
        let suffix = String(rawID?.prefix(6) ?? UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .prefix(6))
        
        return "User\(suffix)"
    }()
}
