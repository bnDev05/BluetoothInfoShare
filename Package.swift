// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BluetoothInfoShare",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
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
