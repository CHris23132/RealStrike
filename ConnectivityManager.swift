import Foundation
import MultipeerConnectivity
import SwiftUI
import CoreLocation

/// Wraps an invitation request for SwiftUI alerts.
struct InvitationRequest: Identifiable {
    let id = UUID()
    let peerID: MCPeerID
    let context: Data?
    let invitationHandler: (Bool, MCSession?) -> Void
}

/// Delegate protocol for connectivity events.
protocol ConnectivityDelegate: AnyObject {
    func didReceiveHit(fromPeer peerID: MCPeerID, targetId: String)
    func didReceivePlayerData(_ player: PlayerData)
}

/// Simple model for player updates (not used in this simplified hit version).
struct PlayerData: Identifiable {
    let id: String
    let location: CLLocation
    let heading: Double  // in degrees
    let lastUpdate: Date
}

class ConnectivityManager: NSObject, ObservableObject {
    let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    private(set) var session: MCSession!
    
    private var advertiser: MCNearbyServiceAdvertiser!
    private let serviceType = "ar-laser-tag"
    
    weak var delegate: ConnectivityDelegate?
    
    @Published var invitationRequest: InvitationRequest? = nil
    
    override init() {
        super.init()
        session = MCSession(peer: myPeerID,
                            securityIdentity: nil,
                            encryptionPreference: .required)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID,
                                                 discoveryInfo: nil,
                                                 serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
    }
    
    /// Returns a standard MCBrowserViewController for pairing.
    func makeBrowserViewController() -> MCBrowserViewController {
        let browserVC = MCBrowserViewController(serviceType: serviceType, session: session)
        browserVC.maximumNumberOfPeers = 8
        return browserVC
    }
    
    /// Stop advertising and disconnect.
    func stop() {
        advertiser.stopAdvertisingPeer()
        session.disconnect()
    }
    
    /// Sends a hit message to all connected peers.
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
    
    /// (Optional) Sends player update data – not used in this simplified version.
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

extension ConnectivityManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?,
                    invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        print("Invitation received from \(peerID.displayName)")
        DispatchQueue.main.async {
            self.invitationRequest = InvitationRequest(peerID: peerID,
                                                       context: context,
                                                       invitationHandler: invitationHandler)
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                    didNotStartAdvertisingPeer error: Error) {
        print("Failed to advertise: \(error.localizedDescription)")
    }
}

extension ConnectivityManager: MCSessionDelegate {
    func session(_ session: MCSession,
                 peer peerID: MCPeerID,
                 didChange state: MCSessionState) {
        print("Peer \(peerID.displayName) state changed to \(state.rawValue)")
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
            // Player update handling – not used in this simplified version.
            guard let id = dict["id"] as? String,
                  let lat = dict["latitude"] as? CLLocationDegrees,
                  let lon = dict["longitude"] as? CLLocationDegrees,
                  let heading = dict["heading"] as? Double,
                  let timestamp = dict["timestamp"] as? TimeInterval else { return }
            let location = CLLocation(latitude: lat, longitude: lon)
            let playerData = PlayerData(id: id, location: location, heading: heading, lastUpdate: Date(timeIntervalSince1970: timestamp))
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
