//
//  BluetoothItemCell.swift
//  ExampleProject
//
//  Created by Behruz on 03/02/26.
//

import SwiftUI
import CoreBluetooth

private extension BluetoothItemCell {
    private enum Constants {
        static let connectedText = "Connected"
        static let notConnectedText = "Not Connected"
        static let transfer: String = "Transfer"
        static let infoIconImage: Image = Image(systemName: "info.circle")
        static let iconSize: CGFloat = 24
        static let horizontalPadding: CGFloat = 15
        static let verticalPadding: CGFloat = 10
    }
}

public struct BluetoothItemCell: View {
    @StateObject private var viewModel: BluetoothCellViewModel
    @Environment(\.presentationMode) private var presentationMode
    let onCellTap: (() -> Void)
    
    public init(item: CellInfoModel, bluetoothManager: BluetoothManager, onCellTap: @escaping (() -> Void)) {
        self.onCellTap = onCellTap
        _viewModel = StateObject(wrappedValue: BluetoothCellViewModel(item: item, bluetoothManager: bluetoothManager))
    }
    
    public var body: some View {
        ZStack {
            Color.clear
            content
        }
        .clipShape(Rectangle())
        .sheet(isPresented: $viewModel.didTapTransfer, content: {
//            QuickShareReceivedView(byTapCell: true, message: ShareableMessage.makeMixed(sender: viewModel.item.name, cardNumber: viewModel.item.lastFourCardNumber), onDismiss: nil)
        })
    }
    
    private var content: some View {
        VStack {
            HStack {
                cellTapContent
//                    .onTapGesture {
//                        onCellTap()
//                    }
                
                sendButton
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        
    }
    
    private var cellTapContent: some View {
        HStack {
            if viewModel.isLoading {
                CustomLoaderView()
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(viewModel.item.name)
                    .font(.system(size: 22, weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("•••• •••• •••• \(viewModel.item.lastFourCardNumber)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
    
    private var sendButton: some View {
        Button {
            print("OBJECT ID: \(viewModel.item.objectID)")
            print("USER ID: \(viewModel.item.userID)")
            viewModel.didTapTransfer = true
            //TODO: -Firebase User Info fetching setup goes right here userID = viewModel.item.userID, objectID = viewModel.item.objectID
        } label: {
            Text(Constants.transfer)
                .foregroundColor(.white)
                .font(.system(size: 13, weight: .regular))
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(
                    LinearGradient(colors: [.green, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .opacity(0.8)
                        .cornerRadius(8.0)
                )
        }
    }
    
    private var connectionStatus: some View {
        Text(viewModel.isConnected ? Constants.connectedText : Constants.notConnectedText)
            .foregroundColor(.green)
            .font(.system(size: 13, weight: .regular))
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

//#Preview {
//    BluetoothItemCell(item: ., bluetoothManager: )
//}
