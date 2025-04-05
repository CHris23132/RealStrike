// PairingView.swift
import SwiftUI
import MultipeerConnectivity

struct PairingView: UIViewControllerRepresentable {
    let connectivityManager: ConnectivityManager
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> MCBrowserViewController {
        let browserVC = connectivityManager.makeBrowserViewController()
        browserVC.delegate = context.coordinator
        return browserVC
    }
    
    func updateUIViewController(_ uiViewController: MCBrowserViewController, context: Context) { }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MCBrowserViewControllerDelegate {
        var parent: PairingView
        
        init(_ parent: PairingView) {
            self.parent = parent
        }
        
        func browserViewControllerDidFinish(_ browserViewController: MCBrowserViewController) {
            parent.dismiss()
        }
        
        func browserViewControllerWasCancelled(_ browserViewController: MCBrowserViewController) {
            parent.dismiss()
        }
        
        func browserViewController(_ browserViewController: MCBrowserViewController,
                                   shouldPresentNearbyPeer peerID: MCPeerID,
                                   withDiscoveryInfo info: [String : String]?) -> Bool {
            return true
        }
    }
}
