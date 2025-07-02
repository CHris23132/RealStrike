import Foundation
import AVFoundation
import CoreLocation
import MultipeerConnectivity
import SwiftUI
import CoreBluetooth

enum GameMode {
    case freeForAll
    case teamMatch
    case captureTheFlag
}

enum Team: String, CaseIterable {
    case red, blue
    var respawnCode: String {
        switch self {
        case .red:   return "QR_TEAM_RED"
        case .blue:  return "QR_TEAM_BLUE"
        }
    }
}

class GameManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var cameraViewModel = CameraViewModel()
    @Published var connectivityManager = ConnectivityManager()
    @Published var currentMode: GameMode = .freeForAll
    @Published var localTeam: Team? = nil
    @Published var teamScores: [Team:Int] = [.red:0, .blue:0]
    @Published var isShowingPairing: Bool = false
    @Published var isShowingGameOver: Bool = false
    @Published var gameOverWinner: Team?
    @Published var strikesGiven: Int = 0
    @Published var hitsReceived: Int = 0
    @Published var otherPlayers: [String: PlayerData] = [:]
    @Published var isRespawning: Bool = false
    @Published var respawnTimeRemaining: Int = 0

    // QR & Teams
    private let flagCaptureCode = "QR_FLAG"
    var playerTeamAssignments: [String: Team] = [:]

    // Computed
    var localPlayerId: String { connectivityManager.myPeerID.displayName }

    // MARK: - Private
    private let locationManager = LocationManager()
    private var updateTimer: Timer?
    private var respawnTimer: Timer?
    private var bluetoothManager: BluetoothManager!
    private var fireSoundPlayer: AVAudioPlayer?
    private var hitHistory = Set<String>()

    // MARK: - Init
    override init() {
        super.init()
        cameraViewModel.onQRCodeScanned = handleScannedCode
        connectivityManager.delegate = self
        locationManager.delegate = self

        // Bluetooth gamepad
        bluetoothManager = BluetoothManager()
        bluetoothManager.onShotFired = { [weak self] in
            self?.handleFireAction()
        }

        // Audio session
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }

        // Load fire-sound effect
        if let url = Bundle.main.url(forResource: "fire-sound-effect", withExtension: "m4a") {
            fireSoundPlayer = try? AVAudioPlayer(contentsOf: url)
            fireSoundPlayer?.prepareToPlay()
        }
    }

    // MARK: - Game Session
    func startGameSession() {
        // Ensure our localTeam is set when pairing happened
        if currentMode != .freeForAll {
            localTeam = playerTeamAssignments[localPlayerId] ?? .red
        }

        bluetoothManager.startScanning()
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        cameraViewModel.checkPermissions()
        cameraViewModel.startSession()
        locationManager.requestPermissions()
        locationManager.startTracking()
        schedulePlayerUpdates()
    }

    func stopGameSession() {
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
        cameraViewModel.stopSession()
        locationManager.stopTracking()
        connectivityManager.stop()
        updateTimer?.invalidate()
        respawnTimer?.invalidate()
    }

    private func schedulePlayerUpdates() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sendLocalPlayerUpdate()
        }
    }

    private func sendLocalPlayerUpdate() {
        guard let heading = locationManager.currentHeading?.trueHeading else { return }
        let data = PlayerData(
            id: localPlayerId,
            location: locationManager.currentLocation,
            heading: heading,
            lastUpdate: Date()
        )
        connectivityManager.sendPlayerUpdate(player: data)
    }

    // MARK: - Fire Action
    func fireButtonPressed() {
        handleFireAction()
    }

    private func handleFireAction() {
        guard !isRespawning, cameraViewModel.personDetected else { return }

        fireSoundPlayer?.play()
        let shooterLoc = locationManager.currentLocation
        let shooterHeading = locationManager.currentHeading?.trueHeading

        // Determine the most likely target using distance, heading, and
        // the age of the last received location update. Older updates get
        // penalized to avoid hitting stale players.
        var best: (player: PlayerData, score: Double)?
        let now = Date()
        for p in otherPlayers.values where p.id != localPlayerId {
            var score = shooterLoc.distance(from: p.location)
            if let heading = shooterHeading {
                let bearing = shooterLoc.bearing(to: p.location)
                let angle = abs(angleDifference(heading, bearing))
                // Players far from the current aim are less likely targets.
                score += angle / 10.0 // each 10° ≈ 1m penalty
            }
            let age = now.timeIntervalSince(p.lastUpdate)
            score += age * 0.5 // stale data penalty
            if best == nil || score < best!.score {
                best = (p, score)
            }
        }

        if best == nil, let peer = connectivityManager.session.connectedPeers.first {
            let dummy = PlayerData(id: peer.displayName,
                                   location: shooterLoc,
                                   heading: 0,
                                   lastUpdate: Date())
            best = (dummy, 0)
        }

        guard let hit = best?.player, !hitHistory.contains(hit.id) else { return }
        strikesGiven += 1
        connectivityManager.sendHit(to: hit.id)
        hitHistory.insert(hit.id)

        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            self.hitHistory.remove(hit.id)
        }

        if let box = cameraViewModel.currentDetection {
            cameraViewModel.hitBoundingBox = box
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.cameraViewModel.hitBoundingBox = nil
            }
        }
    }

    // MARK: - Respawn Logic
    private func triggerRespawn() {
        guard !isRespawning else { return }
        isRespawning = true

        connectivityManager.showHitOverlay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.connectivityManager.showHitOverlay = false
        }

        if currentMode == .freeForAll {
            respawnTimeRemaining = 8
            respawnTimer?.invalidate()
            respawnTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
                guard let s = self else { return }
                if s.respawnTimeRemaining > 0 {
                    s.respawnTimeRemaining -= 1
                } else {
                    s.isRespawning = false
                    t.invalidate()
                }
            }
        }
        // Team modes wait for QR code
    }

    private func handleScannedCode(_ code: String) {
        print("QR scanned: \(code)")          // <-- leave in for debugging
        guard isRespawning else { return }

        switch currentMode {
        case .freeForAll:
            // FFA never uses QR for respawn
            break

        case .teamMatch, .captureTheFlag:
            // --- 1. Respawn codes ---
            if code == Team.red.respawnCode || code == Team.blue.respawnCode {
                // If we already know our team, only accept our own code.
                if let team = localTeam {
                    if code == team.respawnCode { finishRespawn() }
                } else {
                    // We don’t know our team yet – accept either code and infer team.
                    localTeam = (code == Team.red.respawnCode) ? .red : .blue
                    finishRespawn()
                }
            }

            // --- 2. Flag capture (CTF only) ---
            if currentMode == .captureTheFlag && code == flagCaptureCode {
                finishRespawn()
                endGame(winner: localTeam ?? .red)
            }
        }
    }

    private func finishRespawn() {
        respawnTimer?.invalidate()
        isRespawning = false
    }

    // MARK: - Scoring & End Game
    private func recordHit(shooterId: String) {
        guard currentMode != .freeForAll,
              let team = playerTeamAssignments[shooterId] else { return }
        teamScores[team, default: 0] += 1
        if currentMode == .teamMatch, teamScores[team]! >= 25 {
            endGame(winner: team)
        }
    }

    private func endGame(winner: Team) {
        connectivityManager.sendGameOver(winner: winner)
        DispatchQueue.main.async {
            self.gameOverWinner = winner
            self.isShowingGameOver = true
        }
        stopGameSession()
    }
}

// MARK: - ConnectivityDelegate
extension GameManager: ConnectivityDelegate {
    func didReceiveHit(fromPeer peerID: MCPeerID, targetId: String) {
        if targetId == localPlayerId, !isRespawning {
            hitsReceived += 1
            recordHit(shooterId: peerID.displayName)
            triggerRespawn()
        }
    }

    func didReceivePlayerData(_ player: PlayerData) {
        otherPlayers[player.id] = player
    }

    func didReceiveTeamAssignments(_ assignments: [String: Team]) {
        playerTeamAssignments = assignments
        if let t = assignments[localPlayerId] {
            localTeam = t
        }
    }

    func didReceiveGameOver(winner: Team) {
        endGame(winner: winner)
    }
}

// MARK: - LocationManagerDelegate
extension GameManager: LocationManagerDelegate {
    func didUpdateLocation(_ location: CLLocation) {
        print("Location updated: \(location.coordinate)")
    }
    func didUpdateHeading(_ heading: CLHeading) {
        print("Heading updated: \(heading.trueHeading)")
    }
}
