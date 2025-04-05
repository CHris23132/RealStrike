import Foundation
import AVFoundation
import CoreLocation
import MultipeerConnectivity
import MediaPlayer
import SwiftUI

class GameManager: NSObject, ObservableObject {
    @Published var cameraViewModel = CameraViewModel()
    @Published var connectivityManager = ConnectivityManager()
    private let locationManager = LocationManager()
    
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
    
    override init() {
        super.init()
        setupVolumeButtonHandler()
        connectivityManager.delegate = self
        locationManager.delegate = self
    }
    
    func startGameSession() {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        cameraViewModel.checkPermissions()
        cameraViewModel.startSession()
        // Removed connectivityManager.startHosting() because advertising starts in init.
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
    }
    
    private func setupVolumeButtonHandler() {
        // Optional: Retain volume button handling if desired.
        let volumeView = MPVolumeView(frame: .zero)
        if let window = UIApplication.shared.windows.first {
            window.addSubview(volumeView)
        }
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(true)
        try? session.setCategory(.playback, options: [.mixWithOthers])
        
        NotificationCenter.default.addObserver(forName: .volumeDidChange,
                                               object: nil,
                                               queue: .main) { [weak self] _ in
            self?.handleFireAction()
        }
    }
    
    // This method sends local player updates every 2 seconds.
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
    
    /// Called when the Fire button is pressed.
    func fireButtonPressed() {
        handleFireAction()
    }
    
    /// Core logic: if a person is detected, determine the best target based on relative bearing.
    private func handleFireAction() {
        guard cameraViewModel.personDetected else {
            print("No person detected, cannot fire.")
            return
        }
        let shooterLocation = locationManager.currentLocation
        guard let shooterHeading = locationManager.currentHeading?.trueHeading else { return }
        
        var bestCandidate: PlayerData?
        var smallestAngleDiff = 360.0
        
        for player in otherPlayers.values {
            if player.id == localPlayerId { continue }
            let bearing = computeBearing(from: shooterLocation, to: player.location)
            let diff = angleDifference(shooterHeading, bearing)
            if diff < smallestAngleDiff && diff < 15.0 { // 15° tolerance
                smallestAngleDiff = diff
                bestCandidate = player
            }
        }
        
        if let target = bestCandidate {
            strikesGiven += 1
            connectivityManager.sendHit(to: target.id)
            print("Fired at \(target.id) with angle diff \(smallestAngleDiff)°")
            if let detection = cameraViewModel.currentDetection {
                cameraViewModel.hitBoundingBox = detection
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.cameraViewModel.hitBoundingBox = nil
                }
            }
        } else if let fallbackPeer = connectivityManager.session.connectedPeers.first {
            // Fallback: if no target fits our criteria, use the first connected peer.
            strikesGiven += 1
            connectivityManager.sendHit(to: fallbackPeer.displayName)
            print("Fired at \(fallbackPeer.displayName) by fallback.")
            if let detection = cameraViewModel.currentDetection {
                cameraViewModel.hitBoundingBox = detection
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    self.cameraViewModel.hitBoundingBox = nil
                }
            }
        } else {
            print("No target available")
        }
    }
    
    /// Compute bearing (in degrees) from one CLLocation to another.
    private func computeBearing(from start: CLLocation, to end: CLLocation) -> Double {
        let lat1 = start.coordinate.latitude * .pi / 180.0
        let lon1 = start.coordinate.longitude * .pi / 180.0
        let lat2 = end.coordinate.latitude * .pi / 180.0
        let lon2 = end.coordinate.longitude * .pi / 180.0
        
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180.0 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
    
    /// Compute the smallest difference between two angles (in degrees).
    private func angleDifference(_ angle1: Double, _ angle2: Double) -> Double {
        let diff = abs(angle1 - angle2).truncatingRemainder(dividingBy: 360)
        return diff > 180 ? 360 - diff : diff
    }
}

extension GameManager: ConnectivityDelegate {
    func didReceiveHit(fromPeer peerID: MCPeerID, targetId: String) {
        if targetId == localPlayerId {
            hitsReceived += 1
            print("Hit received from: \(peerID.displayName)")
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
