//
//  BluetoothCellViewModel.swift
//  ExampleProject
//
//  Created by Behruz on 03/02/26.
//

import Foundation
import CoreBluetooth

class BluetoothCellViewModel: ObservableObject {
    @Published var didTapTransfer: Bool = false
    let item: CellInfoModel
    let bluetoothManager: BluetoothManager
    var isConnected: Bool = true
    var isLoading: Bool = false
    
    public init(item: CellInfoModel, bluetoothManager: BluetoothManager) {
        self.item = item
        self.bluetoothManager = bluetoothManager
        self.isConnected = item.isConnected
    }
}
