// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BluetoothInfoShare",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "BluetoothInfoShare",
            targets: ["BluetoothInfoShare"]
        ),
    ],
    targets: [
        .target(
            name: "BluetoothInfoShare"
        ),
        .testTarget(
            name: "BluetoothInfoShareTests",
            dependencies: ["BluetoothInfoShare"]
        ),
    ]
)
