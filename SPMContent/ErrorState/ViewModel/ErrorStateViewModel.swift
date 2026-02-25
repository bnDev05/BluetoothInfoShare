//
//  ErrorStateViewModel.swift
//  ExampleProject
//
//  Created by Behruz on 04/02/26.
//

import Foundation
import Combine
import CoreBluetooth
import UIKit

final class ErrorStateViewModel: ObservableObject {
    let errorState: CBManagerState
    
    init(errorState: CBManagerState) {
        self.errorState = errorState
    }
    
    func isButtonNeeded() -> Bool {
        switch errorState {
        case .unknown, .resetting, .unsupported, .poweredOn:
            return false
        case .unauthorized, .poweredOff:
            return true

        @unknown default:
            return false
        }
    }
    
    func openBluetoothSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        
        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL)
        }
    }

}
