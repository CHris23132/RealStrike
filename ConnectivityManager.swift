import Foundation
import MultipeerConnectivity
import SwiftUI
import CoreLocation

struct PlayerData: Identifiable {
    let id: String
    let location: CLLocation
    let heading: Double  // in degrees
    let lastUpdate: Date
}

protocol ConnectivityDelegate: AnyObject {
    func didReceiveHit(fromPeer peerID: MCPeerID, targetId: String)
    func didReceivePlayerData(_ player: PlayerData)
}

class ConnectivityManager: NSObject, ObservableObject {
    let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private(set) var session: MCSession!
    
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    private let serviceType = "ar-laser-tag"
    
    // List of discovered peers available for pairing.
    @Published var availablePeers: [MCPeerID] = []
    
    weak var delegate: ConnectivityDelegate?
    
    // Used to flash a hit overlay when a hit is received.
    @Published var showHitOverlay: Bool = false
    
    override init() {
        super.init()
        
        session = MCSession(peer: myPeerID,
                            securityIdentity: nil,
                            encryptionPreference: .required)
        session.delegate = self
        
        // Start advertising
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                                 discoveryInfo: nil,
                                                 serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        // Start browsing for nearby peers.
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }
    
    // Call this method from the pairing UI when the host taps “Start Game”.
    func invitePeers(_ peers: [MCPeerID]) {
        for peer in peers {
            // Only invite if the peer isn’t already connected.
            if !session.connectedPeers.contains(peer) {
                browser.invitePeer(peer, to: session, withContext: nil, timeout: 30)
            }
        }
    }
    
    func stop() {
        advertiser.stopAdvertisingPeer()
        browser.stopBrowsingForPeers()
        session.disconnect()
    }
    
    func sendHit(to targetId: String) {
        let dict: [String: Any] = [
            "action": "hit",
            "targetId": targetId
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            print("Error encoding hit JSON.")
            return
        }
        if !session.connectedPeers.isEmpty {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                print("Hit message sent.")
            } catch {
                print("Error sending hit: \(error.localizedDescription)")
            }
        }
    }
    
    func sendPlayerUpdate(player: PlayerData) {
        let dict: [String: Any] = [
            "action": "update",
            "id": player.id,
            "latitude": player.location.coordinate.latitude,
            "longitude": player.location.coordinate.longitude,
            "heading": player.heading,
            "timestamp": player.lastUpdate.timeIntervalSince1970
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []) else {
            print("Error encoding update JSON.")
            return
        }
        if !session.connectedPeers.isEmpty {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                print("Error sending update: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate
extension ConnectivityManager: MCNearbyServiceAdvertiserDelegate {
    // Auto-accept incoming invitations without any UI prompt.
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Auto-accept invitation from \(peerID.displayName)")
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("Failed to advertise: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowserDelegate
extension ConnectivityManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        if peerID == myPeerID { return }
        if !availablePeers.contains(peerID) && !session.connectedPeers.contains(peerID) {
            DispatchQueue.main.async {
                self.availablePeers.append(peerID)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        DispatchQueue.main.async {
            self.availablePeers.removeAll { $0 == peerID }
        }
    }
}

// MARK: - MCSessionDelegate
extension ConnectivityManager: MCSessionDelegate {
    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        print("Peer \(peerID.displayName) state changed to \(state.rawValue)")
        DispatchQueue.main.async {
            if state == .connected {
                // Remove connected peers from the available peers list.
                self.availablePeers.removeAll { $0 == peerID }
            }
        }
    }
    
    func session(_ session: MCSession,
                 didReceive data: Data,
                 fromPeer peerID: MCPeerID) {
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let action = dict["action"] as? String else { return }
        if action == "hit", let targetId = dict["targetId"] as? String {
            DispatchQueue.main.async {
                self.delegate?.didReceiveHit(fromPeer: peerID, targetId: targetId)
            }
        } else if action == "update" {
            guard let id = dict["id"] as? String,
                  let lat = dict["latitude"] as? CLLocationDegrees,
                  let lon = dict["longitude"] as? CLLocationDegrees,
                  let heading = dict["heading"] as? Double,
                  let timestamp = dict["timestamp"] as? TimeInterval else { return }
            let location = CLLocation(latitude: lat, longitude: lon)
            let playerData = PlayerData(id: id,
                                        location: location,
                                        heading: heading,
                                        lastUpdate: Date(timeIntervalSince1970: timestamp))
            DispatchQueue.main.async {
                self.delegate?.didReceivePlayerData(playerData)
            }
        }
    }
    
    func session(_ session: MCSession,
                 didReceive stream: InputStream,
                 withName streamName: String,
                 fromPeer peerID: MCPeerID) { }
    
    func session(_ session: MCSession,
                 didStartReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 with progress: Progress) { }
    
    func session(_ session: MCSession,
                 didFinishReceivingResourceWithName resourceName: String,
                 fromPeer peerID: MCPeerID,
                 at localURL: URL?,
                 withError error: Error?) { }
}
