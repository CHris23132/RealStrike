import SwiftUI
import MultipeerConnectivity

struct GroupPairingView: View {
    @ObservedObject var gameManager: GameManager
    @Binding var isPresented: Bool
    @State private var assignments: [MCPeerID: Team] = [:]

    private func isPeer(_ peer: MCPeerID, in team: Team) -> Bool {
        assignments[peer] == team
    }

    private func bgColor(for peer: MCPeerID, team: Team) -> Color {
        isPeer(peer, in: team)
            ? Color.green.opacity(0.7)
            : Color.gray.opacity(0.3)
    }

    private func startGame() {
        let peersToInvite = Array(assignments.keys)
        gameManager.connectivityManager.invitePeers(peersToInvite)
        // Convert MCPeerID keys to player ID strings
        let stringAssignments = assignments.reduce(into: [String: Team]()) { result, entry in
            result[entry.key.displayName] = entry.value
        }
        gameManager.playerTeamAssignments = stringAssignments
        gameManager.connectivityManager.sendTeamAssignments(stringAssignments)
        isPresented = false
    }

    private var canStart: Bool {
        // Ensure each team has at least one assigned peer
        Team.allCases.allSatisfy { team in
            assignments.values.contains(team)
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                ForEach(Team.allCases, id: \.self) { team in
                    Text("\(team.rawValue.capitalized) Team")
                        .font(.headline)
                        .padding(.top)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            // Include the local device first
                            let allPeers = [gameManager.connectivityManager.myPeerID] + gameManager.connectivityManager.availablePeers
                            ForEach(allPeers, id: \.self) { peer in
                                let name = (peer == gameManager.connectivityManager.myPeerID) ? "You" : peer.displayName
                                
                                Text(name)
                                    .padding(8)
                                    .background(bgColor(for: peer, team: team))
                                    .cornerRadius(8)
                                    .onTapGesture {
                                        if isPeer(peer, in: team) {
                                            assignments[peer] = nil
                                        } else {
                                            assignments[peer] = team
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal)
                    }
                }

                Spacer()

                Button("Start Game", action: startGame)
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canStart ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                    .disabled(!canStart)
                    .padding()
            }
            .navigationTitle("Assign Teams")
            .navigationBarItems(trailing: Button("Cancel") {
                isPresented = false
            })
        }
    }
}
