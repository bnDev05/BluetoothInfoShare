// swift-tools-version: 5.9
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
