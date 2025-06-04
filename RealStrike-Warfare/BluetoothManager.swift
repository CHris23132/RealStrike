// BluetoothManager.swift

import Foundation
import CoreBluetooth

/// These must match exactly what your ESP32 is advertising:
private let kServiceUUID     = CBUUID(string: "12345678-1234-1234-1234-1234567890AB")
private let kTxCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-1234567890AC")
// (We only need to subscribe to TX from the gamepad → phone.)
// If you ever need to write back to the ESP32, you would also define RX here:
// private let kRxCharacteristicUUID = CBUUID(string: "12345678-1234-1234-1234-1234567890AD")

/// Delegate or callback‐style manager that scans for & connects to the Real_Strike_Gamepad
/// and invokes `onShotFired` whenever the peripheral sends back “Shot_Fired” over the notify characteristic.
class BluetoothManager: NSObject {
    
    /// Called whenever we receive the exact string "Shot_Fired" from the peripheral.
    /// (You can set this closure from GameManager.swift to call handleFireAction().)
    var onShotFired: (() -> Void)?
    
    private var centralManager: CBCentralManager!
    private var gamepadPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?
    // (If you wanted to write something back, you'd keep a reference to rxCharacteristic as well.)
    
    override init() {
        super.init()
        // Create central manager. We’ll wait for .poweredOn before scanning.
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }
    
    /// Call this to start scanning. If the BLE radio is already powered on, scanning will begin immediately.
    /// Otherwise, scanning will kick off as soon as centralManagerDidUpdateState(_: ) reports .poweredOn.
    func startScanning() {
        guard centralManager.state == .poweredOn else {
            // Once the state changes to .poweredOn, we will scan in centralManagerDidUpdateState(_:).
            return
        }
        
        // Scan only for peripherals advertising our SERVICE_UUID
        centralManager.scanForPeripherals(withServices: [kServiceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        print("BluetoothManager: Scanning for peripherals advertising service \(kServiceUUID.uuidString)...")
    }
    
    /// If you wish to stop scanning or disconnect:
    func stop() {
        if let p = gamepadPeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        centralManager.stopScan()
    }
}


// MARK: - CBCentralManagerDelegate

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .unknown:
            print("BluetoothManager: state is .unknown")
        case .resetting:
            print("BluetoothManager: state is .resetting")
        case .unsupported:
            print("BluetoothManager: state is .unsupported")
        case .unauthorized:
            print("BluetoothManager: state is .unauthorized")
        case .poweredOff:
            print("BluetoothManager: Bluetooth is powered off. Please turn it on.")
        case .poweredOn:
            print("BluetoothManager: Bluetooth powered on – start scanning.")
            // Now that BLE is powered on, begin scanning
            startScanning()
        @unknown default:
            print("BluetoothManager: A new state was added that we do not handle.")
        }
    }
    
    // Found a peripheral that advertises our SERVICE_UUID
    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        print("BluetoothManager: Discovered peripheral \(peripheral.name ?? "Unnamed") – attempting to connect.")
        
        // Retain the reference and connect
        self.gamepadPeripheral = peripheral
        self.gamepadPeripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral, options: nil)
    }
    
    // Connected successfully
    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("BluetoothManager: Connected to \(peripheral.name ?? "Unnamed"). Discovering services...")
        peripheral.discoverServices([kServiceUUID])
    }
    
    // Failed to connect
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        print("BluetoothManager: Failed to connect to \(peripheral.name ?? "Unnamed"). Error: \(error?.localizedDescription ?? "unknown"). Restarting scan.")
        self.gamepadPeripheral = nil
        startScanning()
    }
    
    // Disconnected
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        print("BluetoothManager: Disconnected from peripheral. Error: \(error?.localizedDescription ?? "none"). Will restart scanning.")
        self.gamepadPeripheral = nil
        startScanning()
    }
}


// MARK: - CBPeripheralDelegate

extension BluetoothManager: CBPeripheralDelegate {
    
    // When services are discovered, look for our service
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let e = error {
            print("BluetoothManager: Error discovering services: \(e.localizedDescription)")
            return
        }
        guard let services = peripheral.services else { return }
        
        for service in services {
            if service.uuid == kServiceUUID {
                print("BluetoothManager: Found service \(service.uuid.uuidString). Discovering characteristics...")
                peripheral.discoverCharacteristics([kTxCharacteristicUUID], for: service)
                return
            }
        }
    }
    
    // When characteristics are discovered, subscribe to the TX characteristic
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        if let e = error {
            print("BluetoothManager: Error discovering characteristics: \(e.localizedDescription)")
            return
        }
        guard let chars = service.characteristics else { return }
        
        for char in chars {
            if char.uuid == kTxCharacteristicUUID {
                print("BluetoothManager: Found TX characteristic \(char.uuid.uuidString). Subscribing to notifications.")
                txCharacteristic = char
                peripheral.setNotifyValue(true, for: txCharacteristic!)
                return
            }
        }
    }
    
    // Called whenever the peripheral sends us an updated value on TX
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let e = error {
            print("BluetoothManager: Error receiving notification: \(e.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        
        // Attempt to parse the incoming data as a UTF8 string
        if let stringValue = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            print("BluetoothManager: Received string: '\(stringValue)'.")
            if stringValue == "Shot_Fired" {
                DispatchQueue.main.async { [weak self] in
                    self?.onShotFired?()
                }
            }
        }
    }
    
    // Optional: called when notifications state changes
    func peripheral(_ peripheral: CBPeripheral,
                    didUpdateNotificationStateFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let e = error {
            print("BluetoothManager: Notification state error: \(e.localizedDescription)")
            return
        }
        let isNotifying = characteristic.isNotifying
        print("BluetoothManager: Characteristic \(characteristic.uuid.uuidString) isNotifying = \(isNotifying)")
    }
}
