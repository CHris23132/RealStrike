import SwiftUI
import MultipeerConnectivity

struct GroupPairingView: View {
    @ObservedObject var connectivityManager: ConnectivityManager
    @Binding var isPresented: Bool
    var requiredPlayerCount: Int = 2   // Modify this as needed.
    
    var body: some View {
        NavigationView {
            VStack {
                Text("Available Devices")
                    .font(.headline)
                    .padding()
                
                List(connectivityManager.availablePeers, id: \.self) { peer in
                    Text(peer.displayName)
                }
                
                Spacer()
                
                Button(action: {
                    // Invite all available peers to join the session.
                    connectivityManager.invitePeers(connectivityManager.availablePeers)
                }) {
                    Text("Start Game")
                        .font(.title)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding()
                // Require at least (requiredPlayerCount - host) connected peers.
                .disabled(connectivityManager.availablePeers.count < requiredPlayerCount - 1)
            }
            .navigationTitle("Pairing")
            .navigationBarItems(trailing: Button("Cancel") {
                isPresented = false
            })
        }
    }
}
