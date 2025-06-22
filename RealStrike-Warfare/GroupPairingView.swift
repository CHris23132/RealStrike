import SwiftUI
import MultipeerConnectivity

struct GroupPairingView: View {
    @ObservedObject var gameManager: GameManager
    @Binding var isPresented: Bool
    let maxCount: Int = 8           // allow up to 8 players
    let minCount: Int = 2           // need at least 2 to start

    // MARK: – Derived helpers
    private var allPeers: [MCPeerID] {
        // host first, then everyone we can see
        [gameManager.connectivityManager.myPeerID] + gameManager.connectivityManager.availablePeers
    }

    private var readyCount: Int { allPeers.count }
    private var canStart: Bool { readyCount >= minCount && readyCount <= maxCount }

    // MARK: – Actions
    private func startGame() {
        // 1️⃣  Invite everyone visible
        gameManager.connectivityManager.invitePeers(gameManager.connectivityManager.availablePeers)

        // 2️⃣  Build auto-assignment map
        var map: [String:Team] = [:]
        for (index, peer) in allPeers.enumerated() {
            map[peer.displayName] = (index % 2 == 0) ? .red : .blue
        }

        // 3️⃣  Store + broadcast
        gameManager.playerTeamAssignments = map
        gameManager.connectivityManager.sendTeamAssignments(map)

        isPresented = false            // dismiss lobby
    }

    // MARK: – UI
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // live list
                List(allPeers, id: \.self) { peer in
                    Text(peer == gameManager.connectivityManager.myPeerID ? "You" : peer.displayName)
                }

                Text("Found \(readyCount) device\(readyCount == 1 ? "" : "s")")
                    .font(.headline)
                Text("Need at least \(minCount), up to \(maxCount)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button("Start Game", action: startGame)
                    .frame(maxWidth:.infinity)
                    .padding()
                    .background(canStart ? Color.green : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(!canStart)
                    .padding(.horizontal)
            }
            .navigationTitle("Pair Devices")
            .navigationBarItems(trailing: Button("Close") { isPresented = false })
        }
    }
}
