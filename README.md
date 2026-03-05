# BluetoothInfoShare

iOS Swift Package for advertising and exchanging structured payment info over BLE.

Requirements: iOS 14+, Swift 5.9+

---

## Installation

Add via Swift Package Manager in Xcode or `Package.swift`:

.package(url: "https://github.com/your-org/BluetoothInfoShare.git", from: "1.0.0")

Add `NSBluetoothAlwaysUsageDescription` to your `Info.plist`.

---

## Wire Format

The BLE local-name is a fixed-width concatenated string:


[lastFourCardNumber: 4][objectID: 6][userID: 6][userName: variable]
// e.g. "1234dscd34hskad7UserABCDEF"


Use `AdvertisementInfo` to encode and decode this format.

---

## Usage

### Advertising (Peripheral)

#CODE
let manager = BluetoothManager.shared

let info = AdvertisementInfo(
    lastFourCardNumber: "1234",  // exactly 4 chars
    objectID: "dscd34",          // exactly 6 chars
    userID: "hskad7",            // exactly 6 chars
    userName: "UserABCDEF"
)

let handler = PeripheralManagerDelegateHandler(bluetoothManager: manager)
manager.setupPeripheralManager(delegate: handler)
manager.setAdvertisementInfo(info)
// Advertising starts automatically when Bluetooth powers on.

### Scanning (Central)
#CODE
manager.startScan(serviceUUIDs: [BluetoothManager.dataSharingServiceUUID])

manager.discoveryPublisher
    .compactMap { peripheral in
        guard let name = peripheral.name else { return nil }
        return CellInfoModel.makeInfo(
            advertisementLocalName: name,
            peripheral: peripheral,
            isConnected: false
        )
    }
    .sink { cell in print("\(cell.name) — •••• \(cell.lastFourCardNumber)") }
    .store(in: &cancellables)

### Connect & Exchange Data

#CODE
// Connect
let peripheral = try await manager.connect(peripheral)

// Send
let data = try JSONEncoder().encode(myModel)
manager.sendData(data)

// Receive
BluetoothManager.dataReceivedPublisher
    .sink { data in /* decode data */ }
    .store(in: &cancellables)

---

## Key API

| Type / Method | Purpose |
|---|---|
| `AdvertisementInfo(encoded:)` | Parse advertisement local-name |
| `AdvertisementInfo.encoded()` | Produce advertisement local-name |
| `CellInfoModel.makeInfo(advertisementLocalName:peripheral:isConnected:)` | Build view-model from a discovered peripheral |
| `manager.setupPeripheralManager(delegate:)` | One-time peripheral setup |
| `manager.setAdvertisementInfo(_:)` | Set payload before advertising |
| `manager.startAdvertising()` / `stopAdvertising()` | Control advertising |
| `manager.startScan(serviceUUIDs:)` / `stopScan()` | Control scanning |
| `manager.connect(_:)` / `disconnect(_:)` | Async connect/disconnect |
| `manager.sendData(_:)` | Send chunked data (182 B/chunk) |
| `BluetoothManager.dataReceivedPublisher` | Receive reassembled payloads |

---
