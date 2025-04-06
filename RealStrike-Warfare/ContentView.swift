import SwiftUI
import AVFoundation
import Vision
import MultipeerConnectivity
import CoreLocation
import MediaPlayer

extension Notification.Name {
    static let volumeDidChange = Notification.Name("AVSystemController_SystemVolumeDidChangeNotification")
}

struct ContentView: View {
    @StateObject private var gameManager = GameManager()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraView(cameraViewModel: gameManager.cameraViewModel)
                    .edgesIgnoringSafeArea(.all)
                
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
                    
                    Button("Fire") {
                        gameManager.fireButtonPressed()
                    }
                    .padding()
                    .background(gameManager.isRespawning ? Color.gray : Color.red)
                    .foregroundColor(.white)
                    .clipShape(Capsule())
                    .disabled(gameManager.isRespawning)
                    .padding(.bottom, 20)
                    
                    Text(gameManager.cameraViewModel.personDetected ? "👤 Person Detected" : "No Person")
                        .padding(8)
                        .background(gameManager.cameraViewModel.personDetected ? Color.green : Color.red)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .padding(.bottom, 40)
                }
                
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
                
                // If respawning, show a tinted overlay with a countdown.
                if gameManager.isRespawning {
                    Color.red.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)
                    VStack {
                        Text("Respawning in")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                        Text("\(gameManager.respawnTimeRemaining)")
                            .font(.system(size: 80, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                
                // Optionally, if showHitOverlay is true, flash a hit overlay.
                if gameManager.connectivityManager.showHitOverlay {
                    Color.red.opacity(0.5)
                        .edgesIgnoringSafeArea(.all)
                }
            }
            .onAppear {
                gameManager.startGameSession()
            }
            .onDisappear {
                gameManager.stopGameSession()
            }
            .sheet(isPresented: $gameManager.isShowingPairing) {
                PairingView(connectivityManager: gameManager.connectivityManager)
            }
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
