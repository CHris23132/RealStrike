import SwiftUI
import AVFoundation
import Vision
import MultipeerConnectivity
import CoreLocation
import MediaPlayer

// MARK: - Notification Extension for Volume Change
extension Notification.Name {
    static let volumeDidChange = Notification.Name("AVSystemController_SystemVolumeDidChangeNotification")
}

struct ContentView: View {
    @StateObject private var gameManager = GameManager()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview
                CameraView(cameraViewModel: gameManager.cameraViewModel)
                    .edgesIgnoringSafeArea(.all)
                
                // Overlays: Scoreboard, Pair Button, and Fire Button
                VStack {
                    HStack {
                        Button("Pair") {
                            gameManager.isShowingPairing = true
                        }
                        .padding(8)
                        .background(Color.blue.opacity(0.8))
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text("Strikes: \(gameManager.strikesGiven)")
                            Text("Hits: \(gameManager.hitsReceived)")
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                    
                    Spacer()
                    
                    // Fire button
                    Button("Fire") {
                        gameManager.fireButtonPressed()
                    }
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .padding(.bottom, 20)
                    
                    // Status message
                    Text(gameManager.cameraViewModel.personDetected ? "👤 Person Detected" : "No Person")
                        .padding(8)
                        .background(gameManager.cameraViewModel.personDetected ? Color.green : Color.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                }
                
                // Hit marker overlay – shows a red "X" for 1 second.
                if let hitBox = gameManager.cameraViewModel.hitBoundingBox {
                    GeometryReader { geo in
                        let frame = CGRect(x: hitBox.minX * geo.size.width,
                                           y: (1 - hitBox.maxY) * geo.size.height,
                                           width: hitBox.width * geo.size.width,
                                           height: hitBox.height * geo.size.height)
                        Text("X")
                            .font(.system(size: min(frame.width, frame.height) * 2, weight: .bold))
                            .foregroundColor(.red)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .onAppear {
                gameManager.startGameSession()
            }
            .onDisappear {
                gameManager.stopGameSession()
            }
            // Present pairing UI.
            .sheet(isPresented: $gameManager.isShowingPairing) {
                PairingView(connectivityManager: gameManager.connectivityManager)
            }
            // Alert for incoming invitations.
            .alert(item: $gameManager.connectivityManager.invitationRequest) { invitation in
                Alert(title: Text("Invitation"),
                      message: Text("Accept invitation from \(invitation.peerID.displayName)?"),
                      primaryButton: .default(Text("Accept")) {
                        invitation.invitationHandler(true, gameManager.connectivityManager.session)
                        gameManager.connectivityManager.invitationRequest = nil
                      },
                      secondaryButton: .cancel {
                        invitation.invitationHandler(false, nil)
                        gameManager.connectivityManager.invitationRequest = nil
                      })
            }
        }
    }
}
