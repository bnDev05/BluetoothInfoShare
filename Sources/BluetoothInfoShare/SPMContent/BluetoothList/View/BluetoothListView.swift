//
//  ContentView.swift
//  ExampleProject
//
//  Created by Behruz on 02/02/26.
//

import SwiftUI
import CoreData
import CoreBluetooth

private extension BluetoothListView {
    private enum Constants {
        static let title: String = "Bluetooth Finder"
        static let horizontalPadding: CGFloat = 0
        static let loaderSize: CGFloat = 1.5
    }
}

public struct BluetoothListView: View {
    @Environment(\.managedObjectContext) private var viewContext
//    @Environment(\.dependencies) private var dependencies
    @StateObject private var viewModel: BluetoothListViewModel
//    private let dataSharingManager: DataSharingManager
    
    public init(/*dependencies: DependencyContainer*/) {
//        self.dataSharingManager = dependencies.dataSharingManager
        _viewModel = StateObject(wrappedValue: BluetoothListViewModel(bluetoothManager: BluetoothManager.shared))
    }
    public var body: some View {
        ZStack {
            content
        }
        .navigationTitle(Constants.title)
        .onDisappear {
            viewModel.stopScanning()
        }
//        .toolbar {
//            ToolbarItem(placement: .navigationBarTrailing) {
//                Button {
//                    dependencies.navigationManager.push(
//                        ChatView(dataSharingManager: dataSharingManager, dependencies: dependencies)
//                    )
//                } label: {
//                    Image(systemName: "square.and.arrow.up")
//                }
//            }
//            
//            ToolbarItem(placement: .navigationBarLeading) {
//                Button {
//                    dependencies.navigationManager.push(
//                        QuickShareView()
//                            .environment(\.dependencies, dependencies)
//                    )
//                } label: {
//                    Image(systemName: "antenna.radiowaves.left.and.right.circle")
//                }
//            }
//        }
    }
    
    private var content: some View {
        VStack {
            switch viewModel.viewStatus {
            case .loading, .scanning:
                CustomLoaderView(size: Constants.loaderSize)
                    .frame(maxHeight: .infinity, alignment: .center)
            case .loaded:
                itemsList(items: viewModel.availableDevices)
            case .error(let error, let status):
                ErrorStateView(errorMessage: error, errorStatus: status)
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
    }
    
    @ViewBuilder private func itemsList(items: [CellInfoModel]) -> some View {
        List(viewModel.availableDevices, id: \.id) { device in
            BluetoothItemCell(
                item: device,
                bluetoothManager: BluetoothManager.shared,
                onCellTap: {
//                    dependencies.navigationManager.push(
//                        DeviceDetailsView(dependencies: dependencies, item: device)
//                    )
                }
            )
        }
    }
}


#Preview {
    NavigationView {
        BluetoothListView(/*dependencies: DependencyContainer()*/)
    }
}
