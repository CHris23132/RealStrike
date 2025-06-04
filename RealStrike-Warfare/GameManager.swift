import Foundation
import AVFoundation
import CoreLocation
import MultipeerConnectivity
import SwiftUI
import CoreBluetooth

class GameManager: NSObject, ObservableObject {
    @Published var cameraViewModel = CameraViewModel()
    @Published var connectivityManager = ConnectivityManager()
    private let locationManager = LocationManager()
    
    // ----------------------------------------------------------------------------------------------------------------
    // MARK: - Bluetooth Gamepad
    //
    // We’ll read "Shot_Fired" strings from the BLE gamepad. Whenever we see "Shot_Fired",
    // we call handleFireAction() exactly as if the user tapped the on-screen Fire button.
    //
    private var bluetoothManager: BluetoothManager!
    // ----------------------------------------------------------------------------------------------------------------
    
    // Score properties.
    @Published var strikesGiven: Int = 0
    @Published var hitsReceived: Int = 0
    
    // Controls display of the pairing sheet.
    @Published var isShowingPairing: Bool = false
    
    // Dictionary to store updates from other players keyed by their ID.
    @Published var otherPlayers: [String: PlayerData] = [:]
    
    // Local player identifier.
    var localPlayerId: String { connectivityManager.myPeerID.displayName }
    
    // Timer to send periodic player updates.
    private var updateTimer: Timer?
    
    // Respawn properties.
    @Published var isRespawning: Bool = false
    @Published var respawnTimeRemaining: Int = 0
    private var respawnTimer: Timer?
    
    // MARK: - Sound Effects Player
    private var fireSoundPlayer: AVAudioPlayer?
    
    // MARK: - Hit History Tracking
    private var hitHistory = Set<String>()
    
    override init() {
        super.init()
        connectivityManager.delegate = self
        locationManager.delegate = self
        
        // ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
        // Create and configure our BluetoothManager.
        // Whenever the BLE gamepad sends the ASCII string "Shot_Fired", invoke handleFireAction().
        bluetoothManager = BluetoothManager()
        bluetoothManager.onShotFired = { [weak self] in
            guard let self = self else { return }
            self.handleFireAction()
        }
        // Note: BluetoothManager will automatically begin scanning once its central manager is .poweredOn.
        // If you prefer to start scanning explicitly later, you could call:
        //     bluetoothManager.startScanning()
        // For now, we’ll let it auto-scan in init.
        // ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
        
        // Configure the audio session so sound effects play correctly.
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, options: [.mixWithOthers])
            try audioSession.setActive(true)
        } catch {
            print("Audio session setup error: \(error.localizedDescription)")
        }
        
        // Load the fire sound effect.
        if let fireSoundURL = Bundle.main.url(forResource: "fire-sound-effect", withExtension: "m4a") {
            do {
                fireSoundPlayer = try AVAudioPlayer(contentsOf: fireSoundURL)
                fireSoundPlayer?.prepareToPlay()
            } catch {
                print("Error loading fire sound effect: \(error)")
            }
        } else {
            print("fire-sound-effect.m4a not found.")
        }
    }
    
    func startGameSession() {
        // In case we hadn’t started scanning before, ensure BLE scanning is underway:
        bluetoothManager.startScanning()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        cameraViewModel.checkPermissions()
        cameraViewModel.startSession()
        locationManager.requestPermissions()
        locationManager.startTracking()
        startSendingPlayerUpdates()
    }
    
    func stopGameSession() {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        cameraViewModel.stopSession()
        locationManager.stopTracking()
        connectivityManager.stop()
        updateTimer?.invalidate()
        respawnTimer?.invalidate()
    }
    
    private func startSendingPlayerUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sendLocalPlayerUpdate()
        }
    }
    
    private func sendLocalPlayerUpdate() {
        guard let heading = locationManager.currentHeading?.trueHeading else { return }
        let playerUpdate = PlayerData(id: localPlayerId,
                                      location: locationManager.currentLocation,
                                      heading: heading,
                                      lastUpdate: Date())
        connectivityManager.sendPlayerUpdate(player: playerUpdate)
    }
    
    func fireButtonPressed() {
        handleFireAction()
    }
    
    private func handleFireAction() {
        if isRespawning {
            print("Respawning – cannot fire.")
            return
        }
        
        // Play the fire sound effect.
        fireSoundPlayer?.play()
        
        guard cameraViewModel.personDetected else {
            print("No person detected, cannot fire.")
            return
        }
        
        let shooterLocation = locationManager.currentLocation
        var bestCandidate: PlayerData?
        var smallestDistance = Double.greatestFiniteMagnitude
        
        // Find the closest opponent based on location data.
        for player in otherPlayers.values {
            if player.id == localPlayerId { continue }
            let distance = shooterLocation.distance(from: player.location)
            if distance < smallestDistance {
                smallestDistance = distance
                bestCandidate = player
            }
        }
        
        // Fallback: if no candidate is available, use the first connected peer.
        if bestCandidate == nil,
           let fallbackPeer = connectivityManager.session.connectedPeers.first {
            print("No location candidate – falling back to \(fallbackPeer.displayName)")
            bestCandidate = PlayerData(id: fallbackPeer.displayName,
                                       location: shooterLocation,
                                       heading: 0,
                                       lastUpdate: Date())
        }
        
        if let target = bestCandidate {
            if hitHistory.contains(target.id) {
                print("Target \(target.id) was already hit. Ignoring repeated hit.")
                return
            }
            
            strikesGiven += 1
            connectivityManager.sendHit(to: target.id)
            print("Fired at \(target.id) with a distance of \(smallestDistance) meters.")
            
            hitHistory.insert(target.id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
                self.hitHistory.remove(target.id)
                print("Cleared hit record for target \(target.id)")
            }
            
            if let detection = cameraViewModel.currentDetection {
                cameraViewModel.hitBoundingBox = detection
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.cameraViewModel.hitBoundingBox = nil
                }
            }
        } else {
            print("No target available.")
        }
    }
    
    private func triggerRespawn() {
        guard !isRespawning else { return }
        isRespawning = true
        respawnTimeRemaining = 8
        
        DispatchQueue.main.async {
            self.connectivityManager.showHitOverlay = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.connectivityManager.showHitOverlay = false
        }
        
        respawnTimer?.invalidate()
        respawnTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard let self = self else { return }
            if self.respawnTimeRemaining > 0 {
                self.respawnTimeRemaining -= 1
            } else {
                self.isRespawning = false
                timer.invalidate()
            }
        }
    }
}

extension GameManager: ConnectivityDelegate {
    func didReceiveHit(fromPeer peerID: MCPeerID, targetId: String) {
        if targetId == localPlayerId && !isRespawning {
            hitsReceived += 1
            print("Hit received from: \(peerID.displayName)")
            triggerRespawn()
        }
    }
    
    func didReceivePlayerData(_ player: PlayerData) {
        otherPlayers[player.id] = player
    }
}

extension GameManager: LocationManagerDelegate {
    func didUpdateLocation(_ location: CLLocation) {
        print("Location updated: \(location.coordinate)")
    }
    
    func didUpdateHeading(_ heading: CLHeading) {
        print("Heading updated: \(heading.trueHeading)")
    }
}
