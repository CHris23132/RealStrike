// MultipeerManager.swift
// RealStrike-Warfare
// Created by Chris on 2025-04-05.

import Foundation
import MultipeerConnectivity
import CoreLocation
import simd
import SwiftUI

// Updated protocol includes hit events.
protocol MultipeerDelegate: AnyObject {
    func didReceivePlayerData(_ player: Player, fromPeer peerID: MCPeerID)
    func didReceiveHit(fromPeer peerID: MCPeerID, targetId: String)
}

// Shared Player model
struct Player {
    let id: String
    let location: CLLocation
    let orientation: simd_float3 // [yaw, pitch, roll]
    let lastSeenAt: Date
}

class MultipeerManager: NSObject, ObservableObject {
    // Publish connected peers (not used by the new browser UI but available if needed)
    @Published var connectedPeers: [MCPeerID] = []
    
    weak var delegate: MultipeerDelegate?
    
    let serviceType = "ar-laser-tag"
    // Expose the local peer ID.
    let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    var session: MCSession!
    
    // Using MCAdvertiserAssistant for automatic invitation handling.
    var advertiserAssistant: MCAdvertiserAssistant?
    
    override init() {
        super.init()
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        // Start MCAdvertiserAssistant with discovery info if needed.
        advertiserAssistant = MCAdvertiserAssistant(serviceType: serviceType,
                                                    discoveryInfo: nil,
                                                    session: session)
        advertiserAssistant?.start()
    }
    
    func startHosting() {
        // Additional logic if needed.
    }
    
    func stopHosting() {
        advertiserAssistant?.stop()
        session.disconnect()
    }
    
    // For simplicity, if there is any connected peer and a person is detected, choose the first one as the target.
    func findTarget(from shooterLocation: CLLocation, heading: CLHeading?) -> Player? {
        guard !session.connectedPeers.isEmpty else { return nil }
        let targetPeer = session.connectedPeers.first!
        // Create a dummy Player for the target using current time and shooter’s location.
        return Player(id: targetPeer.displayName, location: shooterLocation, orientation: simd_float3(0,0,0), lastSeenAt: Date())
    }
    
    func sendHit(to target: Player) {
        let hitData: [String: Any] = [
            "action": "hit",
            "targetId": target.id,
            "timestamp": Date().timeIntervalSince1970
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: hitData, options: []) else {
            print("Error encoding hit data")
            return
        }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            print("Hit message sent")
        } catch {
            print("Error sending hit data: \(error.localizedDescription)")
        }
    }
    
    // This helper returns an MCBrowserViewController that can be presented from SwiftUI.
    func getBrowserViewController() -> MCBrowserViewController {
        let browserVC = MCBrowserViewController(serviceType: serviceType, session: session)
        // The delegate will be set in the SwiftUI wrapper.
        return browserVC
    }
}

extension MultipeerManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        print("Peer \(peerID.displayName) changed state: \(state.rawValue)")
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else { return }
        
        if let action = dict["action"] as? String, action == "hit" {
            if let targetId = dict["targetId"] as? String {
                DispatchQueue.main.async {
                    self.delegate?.didReceiveHit(fromPeer: peerID, targetId: targetId)
                }
            }
        } else {
            guard let id = dict["id"] as? String,
                  let latitude = dict["latitude"] as? CLLocationDegrees,
                  let longitude = dict["longitude"] as? CLLocationDegrees,
                  let orientationArray = dict["orientation"] as? [Float],
                  orientationArray.count == 3,
                  let timestamp = dict["lastSeenAt"] as? TimeInterval else { return }
            
            let location = CLLocation(latitude: latitude, longitude: longitude)
            let orientation = simd_float3(orientationArray[0], orientationArray[1], orientationArray[2])
            let player = Player(id: id, location: location, orientation: orientation, lastSeenAt: Date(timeIntervalSince1970: timestamp))
            
            DispatchQueue.main.async {
                self.delegate?.didReceivePlayerData(player, fromPeer: peerID)
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) { }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) { }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) { }
}
