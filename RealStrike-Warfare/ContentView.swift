import SwiftUI
import AVFoundation
import Vision
import MultipeerConnectivity
import CoreLocation
import MediaPlayer

struct ContentView: View {
    @StateObject private var gameManager = GameManager()
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Camera preview
                CameraView(cameraViewModel: gameManager.cameraViewModel)
                    .edgesIgnoringSafeArea(.all)
                
                // Top overlay: Pair button (top left) and Scoreboard (top right)
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
                                .font(.headline)
                            Text("Hits: \(gameManager.hitsReceived)")
                                .font(.headline)
                        }
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .padding()
                    
                    Spacer()
                }
                
                // Bottom overlay: Person detection indicator (bottom left) and Fire button (bottom right)
                VStack {
                    Spacer()
                    HStack {
                        // Person detection indicator
                        if gameManager.cameraViewModel.personDetected {
                            Image("Person-Is-Detected-icon")
                                .resizable()
                                .frame(width: 50, height: 50)
                        } else {
                            Image("Person-Not-Detected-icon")
                                .resizable()
                                .frame(width: 50, height: 50)
                        }
                        Spacer()
                        // Fire button
                        Button(action: { gameManager.fireButtonPressed() }) {
                            Image("Fire-Button")
                                .resizable()
                                .frame(width: 70, height: 70)
                        }
                        .disabled(gameManager.isRespawning)
                    }
                    .padding()
                }
                
                // Strike marker overlay – displays the Strike-Marker image over the detected person area.
                if let hitBox = gameManager.cameraViewModel.hitBoundingBox {
                    GeometryReader { geo in
                        let frame = CGRect(x: hitBox.minX * geo.size.width,
                                           y: (1 - hitBox.maxY) * geo.size.height,
                                           width: hitBox.width * geo.size.width,
                                           height: hitBox.height * geo.size.height)
                        Image("Strike-Marker")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: frame.width, height: frame.height)
                            .position(x: frame.midX, y: frame.midY)
                    }
                }
                
                // Respawn overlay: tinted overlay with an 8-second countdown.
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
                
                // Optionally, show a hit overlay when triggered.
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
            // Present the new group pairing interface.
            .sheet(isPresented: $gameManager.isShowingPairing) {
                GroupPairingView(connectivityManager: gameManager.connectivityManager,
                                 isPresented: $gameManager.isShowingPairing,
                                 requiredPlayerCount: 2) // Adjust as needed.
            }
        }
    }
}
