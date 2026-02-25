import SwiftUI
import CoreBluetooth

private extension DeviceDetailsView {
    private enum Constants {
        static let navigationTitle: String = "Details"
        static let deviceNameString: String = "Name"
        static let identifierString: String = "Identifier"
        static let stateString: String = "State"
        static let connectedStateString: String  = "Connected"
        static let yesStatusString: String = "Yes"
        static let noStatusString: String = "No"
        static let signalStrengthString: String = "Signal Strength"
        static let refreshSignalString: String = "Tap refresh to read signal strength"
        static let servicesString: String = "Services & Characteristics"
        static let noServicesFound: String = "No services discovered"
        static let discoverServicesString: String = "Discover Services"
        static let deviceDisconnectedString: String = "Device Disconnected"
        static let connectToServicesString: String = "Connect to view services and characteristics"
        static let disconnectString: String = "Disconnect"
        static let connectString: String = "Connect"
        static let discoverItemsString: String = "Discovering services..."
    }
}

struct DeviceDetailsView: View {
    let dependencies: DependencyContainer
    @StateObject private var viewModel: DeviceDetailsViewModel
    
    init(dependencies: DependencyContainer, item: CellInfoModel) {
        self.dependencies = dependencies
        _viewModel = StateObject(
            wrappedValue: DeviceDetailsViewModel(
                item: item,
                bluetoothManager: dependencies.bluetoothManager
            )
        )
    }
    
    var body: some View {
        ZStack {
            content
            
            if viewModel.isDiscoveringServices {
                loadingOverlay
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle(Constants.navigationTitle)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                connectionButton
            }
        }
    }
    
    private var content: some View {
        ScrollView {
            VStack(spacing: 20) {
                deviceInfoSection
                
                if viewModel.isConnected {
                    rssiSection
                    servicesSection
                } else {
                    disconnectedPrompt
                }
            }
            .padding()
        }
    }
    
    private var deviceInfoSection: some View {
        VStack(spacing: 16) {
            InfoRow(title: Constants.deviceNameString, value: viewModel.deviceName)
            InfoRow(title: Constants.identifierString, value: viewModel.deviceIdentifier)
            InfoRow(title: Constants.stateString, value: viewModel.peripheralState)
            InfoRow(
                title: Constants.connectedStateString,
                value: viewModel.isConnected ? Constants.yesStatusString : Constants.noStatusString,
                valueColor: viewModel.isConnected ? .green : .red
            )
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var rssiSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Constants.signalStrengthString)
                    .font(.headline)
                
                Spacer()
                
                Button(action: viewModel.readRSSI) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                }
            }
            
            if let rssi = viewModel.rssi {
                HStack {
                    Text("\(rssi) dBm")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Spacer()
                    
                    signalStrengthIndicator(rssi: rssi)
                }
            } else {
                Text(Constants.refreshSignalString)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var servicesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(Constants.servicesString)
                .font(.headline)
            
            if viewModel.services.isEmpty {
                emptyServicesView
            } else {
                ForEach(viewModel.services, id: \.uuid) { service in
                    ServiceView(
                        service: service,
                        characteristics: viewModel.characteristics[service] ?? [],
                        viewModel: viewModel
                    )
                }
            }
        }
    }
    
    private var emptyServicesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text(Constants.noServicesFound)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Button(action: viewModel.loadPeripheralData) {
                Text(Constants.discoverServicesString)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var disconnectedPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            
            Text(Constants.deviceDisconnectedString)
                .font(.title3)
                .fontWeight(.semibold)
            
            Text(Constants.connectToServicesString)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
    
    private var connectionButton: some View {
        Button(action: toggleConnection) {
            Text(viewModel.isConnected ? Constants.disconnectString : Constants.connectString)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(viewModel.isConnected ? .red : .green)
        }
    }
    
    private var loadingOverlay: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .foregroundColor(.white)
                
                Text(Constants.discoverItemsString)
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
            .padding(24)
            .background(Color(.systemGray))
            .cornerRadius(12)
        }
    }
    
    private func signalStrengthIndicator(rssi: Int) -> some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(signalColor(rssi: rssi, barIndex: index))
                    .frame(width: 8, height: CGFloat(8 + index * 4))
            }
        }
    }
    
    private func signalColor(rssi: Int, barIndex: Int) -> Color {
        let strength = signalStrength(rssi: rssi)
        return barIndex < strength ? signalStrengthColor(rssi: rssi) : Color(.systemGray4)
    }
    
    private func signalStrength(rssi: Int) -> Int {
        switch rssi {
        case -50...0: return 5
        case -60..<(-50): return 4
        case -70..<(-60): return 3
        case -80..<(-70): return 2
        case -90..<(-80): return 1
        default: return 0
        }
    }
    
    private func signalStrengthColor(rssi: Int) -> Color {
        switch rssi {
        case -50...0: return .green
        case -70..<(-50): return .yellow
        default: return .red
        }
    }
    
    private func toggleConnection() {
        if viewModel.isConnected {
            viewModel.disconnect()
        } else {
            viewModel.connect()
        }
    }
}

//#Preview {
//    NavigationStack {
//        DeviceDetailsView(
//            dependencies: DependencyContainer(),
//            item: CellInfoModel(
//                id: UUID(),
//                name: "Test Device",
//                peripheral: nil,
//                isConnected: false
//            )
//        )
//    }
//}
