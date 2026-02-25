//
//  ErrorStateView.swift
//  ExampleProject
//
//  Created by Behruz on 04/02/26.
//

import SwiftUI
import CoreBluetooth

private extension ErrorStateView {
    private enum Constants {
        static let errorIcon: Image = Image(systemName: "xmark.circle.fill")
        static let iconSize: CGFloat = 60.0
        static let defaultErrorMessage: String = "An unknown error occurred"
        static let bottomPadding: CGFloat = 20
        static let textHorizontalPadding: CGFloat = 30
        static let goToSettings: String = "Go to Settings"
    }
}

public struct ErrorStateView: View {
    let errorMessage: String?
    let errorStatus: CBManagerState
    @StateObject private var viewModel: ErrorStateViewModel
    
    init(errorMessage: String?, errorStatus: CBManagerState) {
        self.errorMessage = errorMessage
        self.errorStatus = errorStatus
        _viewModel = StateObject(wrappedValue: ErrorStateViewModel(errorState: errorStatus))
    }
    
    public var body: some View {
        ZStack {
            VStack(spacing: 18) {
                Constants.errorIcon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize, height: Constants.iconSize, alignment: .center)
                
                Text(errorMessage ?? Constants.defaultErrorMessage)
                    .font(.system(size: 18, weight: .regular))
                
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, Constants.textHorizontalPadding)
            
            
            buttonContent
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(maxHeight: .infinity, alignment: .center)
    }
    
    private var buttonContent: some View {
        ZStack {
            if viewModel.isButtonNeeded() {
                Button {
                    viewModel.openBluetoothSettings()
                } label: {
                    Text(Constants.goToSettings)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical)
                }
                .background(Color.accentColor)
                .clipShape(Capsule())
                .padding(.horizontal)
                .padding(.bottom, Constants.bottomPadding)
            }
        }
    }
}

#Preview {
    ErrorStateView(errorMessage: "An unknown error occurred", errorStatus: .poweredOff)
}
