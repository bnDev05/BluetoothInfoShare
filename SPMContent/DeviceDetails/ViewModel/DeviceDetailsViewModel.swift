//
//  DeviceDetailsViewModel.swift
//  ExampleProject
//
//  Created by Behruz on 04/02/26.
//

import SwiftUI
import Combine
import CoreBluetooth

final class DeviceDetailsViewModel: ObservableObject {
    @Published var deviceName: String
    @Published var deviceIdentifier: String
    @Published var isConnected: Bool
    @Published var rssi: Int?
    @Published var services: [CBService] = []
    @Published var characteristics: [CBService: [CBCharacteristic]] = [:]
    @Published var characteristicValues: [CBUUID: String] = [:]
    @Published var isDiscoveringServices = false
    @Published var errorMessage: String?
    
    let item: CellInfoModel
    let bluetoothManager: BluetoothManager
    private var cancellables = Set<AnyCancellable>()
    
    var peripheralState: String {
        switch item.peripheral.state {
        case .connected: return "Connected"
        case .connecting: return "Connecting"
        case .disconnected: return "Disconnected"
        case .disconnecting: return "Disconnecting"
        @unknown default: return "Unknown"
        }
    }
    
    var canRead: Bool {
        item.peripheral.state == .connected
    }
    
    init(item: CellInfoModel, bluetoothManager: BluetoothManager) {
        self.item = item
        self.bluetoothManager = bluetoothManager
        self.deviceName = item.name
        self.deviceIdentifier = item.id.uuidString
        self.isConnected = item.isConnected
        
        setupBindings()
        loadPeripheralData()
    }
    
    private func setupBindings() {
        Timer.publish(every: 0.5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.updateConnectionState()
            }
            .store(in: &cancellables)
    }
    
    private func updateConnectionState() {
        let newState = item.peripheral.state == .connected
        if isConnected != newState {
            isConnected = newState
            if newState {
                loadPeripheralData()
            }
        }
    }
    
    func loadPeripheralData() {
        guard item.peripheral.state == .connected else {
            return
        }
        
        isDiscoveringServices = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.isDiscoveringServices = false
            self?.updateServicesAndCharacteristics(from: self!.item.peripheral)
            if let itemRssi = self?.item.peripheral.rssi {
                self?.rssi = Int(truncating: itemRssi)
            }
        }
    }
    
    private func updateServicesAndCharacteristics(from peripheral: CBPeripheral) {
        guard let services = peripheral.services else { return }
        
        self.services = services
        
        for service in services {
            if let characteristics = service.characteristics {
                self.characteristics[service] = characteristics
            } else {
                peripheral.discoverCharacteristics(nil, for: service)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let self = self, let services = peripheral.services else { return }
            for service in services {
                if let characteristics = service.characteristics {
                    self.characteristics[service] = characteristics
                }
            }
        }
    }
    
    func connect() {
        Task {
            do {
                let _ = try await bluetoothManager.connect(item.peripheral)
                print("Connected successfully")
            } catch {
                print("Connection failed:", error)
            }
        }
    }

    func disconnect() {
        Task {
            let _ = await bluetoothManager.disconnect(item.peripheral)
            print("Disconnected")
        }
    }

    
    func readRSSI() {
        guard item.peripheral.state == .connected else {
            errorMessage = "Device must be connected to read RSSI"
            return
        }
        item.peripheral.readRSSI()
        if let itemRssi = item.peripheral.rssi {
            rssi = Int(truncating: itemRssi)
        }
    }
    
    func readCharacteristic(_ characteristic: CBCharacteristic, for service: CBService) {
        item.peripheral.readValue(for: characteristic)
    }
    
    func writeCharacteristic(_ characteristic: CBCharacteristic, value: Data, for service: CBService) {
        item.peripheral.writeValue(value, for: characteristic, type: .withoutResponse)
    }
    
    func toggleNotifications(for characteristic: CBCharacteristic) {
        item.peripheral.setNotifyValue(!characteristic.isNotifying, for: characteristic)
    }
    
    func characteristicPropertiesDescription(_ properties: CBCharacteristicProperties) -> [String] {
        var descriptions: [String] = []
        
        if properties.contains(.read) { descriptions.append("Read") }
        if properties.contains(.write) { descriptions.append("Write") }
        if properties.contains(.writeWithoutResponse) { descriptions.append("Write w/o Response") }
        if properties.contains(.notify) { descriptions.append("Notify") }
        if properties.contains(.indicate) { descriptions.append("Indicate") }
        if properties.contains(.broadcast) { descriptions.append("Broadcast") }
        if properties.contains(.authenticatedSignedWrites) { descriptions.append("Signed Write") }
        if properties.contains(.extendedProperties) { descriptions.append("Extended") }
        
        return descriptions
    }
    
    func formatCharacteristicValue(_ data: Data?) -> String {
        guard let data = data, !data.isEmpty else { return "No data" }
        
        if let string = String(data: data, encoding: .utf8), !string.isEmpty {
            return string
        }
        
        return data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
