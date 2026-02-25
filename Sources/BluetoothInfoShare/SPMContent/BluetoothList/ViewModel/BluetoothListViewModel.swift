import Foundation
import CoreBluetooth
import Combine

class BluetoothListViewModel: ObservableObject {
    @Published private(set) var viewStatus: ViewState = .loading
    @Published private(set) var availableDevices: [CellInfoModel] = []
        
    private var peripheralMap: [UUID: CBPeripheral] = [:]
    private var cancellables = Set<AnyCancellable>()
    private let manager: BluetoothManager
    
    public init(bluetoothManager: BluetoothManager) {
        self.manager = bluetoothManager
        subscribeToManager()
        startScanning()
    }
    
    func startScanning() {
        guard !manager.isScanning else { return }
        
        viewStatus = manager.state == .poweredOn ? .scanning : .loading
        
        manager.startScan(
            serviceUUIDs: [BluetoothManager.dataSharingServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    func stopScanning() {
        manager.stopScan()
    }
    
    func connect(deviceID: UUID) {
        guard let peripheral = peripheralMap[deviceID] else { return }
        
        Task {
            do {
                _ = try await manager.connect(peripheral)
            } catch {
                await MainActor.run {
                    self.viewStatus = .error("Failed to connect: \(error.localizedDescription)", .unknown)
                }
            }
        }
    }
    
    func disconnect(deviceID: UUID) {
        guard let peripheral = peripheralMap[deviceID] else { return }
        
        Task {
            _ = await manager.disconnect(peripheral)
        }
    }
    
    func reset() {
        stopScanning()
        peripheralMap.removeAll()
        availableDevices.removeAll()
        viewStatus = .loading
    }
        
    private func subscribeToManager() {
        manager.statePublisher
            .sink { [weak self] state in
                self?.handleStateChange(state)
            }
            .store(in: &cancellables)
        
        manager.discoveryPublisher
            .sink { [weak self] peripheral in
                self?.handleDiscovery(peripheral)
            }
            .store(in: &cancellables)
        
        manager.connectedPublisher
            .sink { [weak self] peripheral in
                self?.updateConnectionState(for: peripheral.identifier, connected: true)
            }
            .store(in: &cancellables)
        
        manager.disconnectedPublisher
            .sink { [weak self] peripheral in
                self?.updateConnectionState(for: peripheral.identifier, connected: false)
            }
            .store(in: &cancellables)
    }
        
    private func handleStateChange(_ state: CBManagerState) {
        executeOnMain { [weak self] in
            guard let self else { return }
            
            switch state {
            case .poweredOn:
                self.startScanning()
            case .poweredOff:
                self.viewStatus = .error(Constants.bluetoothOffMessage, .poweredOff)
                self.stopScanning()
            case .unauthorized:
                self.viewStatus = .error(Constants.unauthorizedMessage, .unauthorized)
            case .unsupported:
                self.viewStatus = .error(Constants.unsupportBluetoothMessage, .unsupported)
            case .resetting, .unknown:
                self.viewStatus = .loading
            @unknown default:
                break
            }
        }
    }
    
    private func handleDiscovery(_ peripheral: CBPeripheral) {
        let id = peripheral.identifier
        peripheralMap[id] = peripheral
        
        guard let name = peripheral.name else { return }
        
        executeOnMain { [weak self] in
            guard let self else { return }
            
            if let model = CellInfoModel.makeInfo(fullString: name, peripheral: peripheral, isConnected: peripheral.state == .connected) {
                if self.availableDevices.contains(where: { $0.userID == model.userID }) {
                    print("⚠️ Device with same name already exists: \(model.name)")
                    return
                }
                if let index = self.availableDevices.firstIndex(where: { $0.id == id }) {
                    self.availableDevices[index] = model
                } else {
                    self.availableDevices.append(model)
                }
            }
            
            self.viewStatus = .loaded
        }
    }
    
    private func updateConnectionState(for id: UUID, connected: Bool) {
        executeOnMain { [weak self] in
            guard let self else { return }
            guard let index = self.availableDevices.firstIndex(where: { $0.id == id }) else { return }
            self.availableDevices[index].isConnected = connected
        }
    }
    
    private func executeOnMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread {
            work()
        } else {
            DispatchQueue.main.async(execute: work)
        }
    }
}

private extension BluetoothListViewModel {
    enum Constants {
        static let bluetoothOffMessage = "Bluetooth is turned off"
        static let unauthorizedMessage = "Bluetooth permission denied"
        static let unsupportBluetoothMessage = "Bluetooth not supported on this device"
    }
}
