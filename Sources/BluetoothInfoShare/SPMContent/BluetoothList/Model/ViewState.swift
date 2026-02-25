//
//  ViewState.swift
//  ExampleProject
//
//  Created by Behruz on 13/02/26.
//

import Foundation
import CoreBluetooth

public enum ViewState {
    case loading
    case scanning
    case loaded
    case error(String, CBManagerState)
    
    public var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}
