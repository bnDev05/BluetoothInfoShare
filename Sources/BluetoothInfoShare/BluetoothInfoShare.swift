/// BluetoothInfoShare
///
/// A Swift Package for advertising and discovering structured payment info
/// over Bluetooth Low Energy (BLE) between iOS devices.
///
/// ## Quick Start
///
/// ### Advertising (Peripheral side)
/// ```swift
/// let manager = BluetoothManager.shared
///
/// let info = AdvertisementInfo(
///     lastFourCardNumber: "1234",
///     objectID: "dscd34",
///     userID: "hskad7",
///     userName: "UserABC123"
/// )
///
/// let handler = PeripheralManagerDelegateHandler(bluetoothManager: manager)
/// manager.setupPeripheralManager(delegate: handler)
/// manager.setAdvertisementInfo(info)
/// // Advertising starts automatically once Bluetooth powers on.
/// ```
///
/// ### Scanning (Central side)
/// ```swift
/// manager.startScan(serviceUUIDs: [BluetoothManager.dataSharingServiceUUID])
///
/// manager.discoveryPublisher
///     .sink { peripheral in
///         // Use peripheral.name or advertisementData to parse CellInfoModel
///     }
///     .store(in: &cancellables)
/// ```
///
/// ### Sending Data
/// ```swift
/// let payload = try JSONEncoder().encode(yourModel)
/// manager.sendData(payload)
/// ```
///
/// ### Receiving Data
/// ```swift
/// BluetoothManager.dataReceivedPublisher
///     .sink { data in
///         let decoded = try? JSONDecoder().decode(YourModel.self, from: data)
///     }
///     .store(in: &cancellables)
/// ```
public enum BluetoothInfoShare {}
