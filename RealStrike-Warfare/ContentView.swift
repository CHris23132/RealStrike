import SwiftUI
import AVFoundation
import Vision
import MultipeerConnectivity
import CoreLocation
import MediaPlayer

struct ContentView: View {
    @StateObject private var gameManager = GameManager()
    @State private var showingModePicker = false
    
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
                        
                        Button("Mode") {
                            showingModePicker = true
                        }
                        .padding(8)
                        .background(Color.green.opacity(0.8))
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
                
                // Respawn overlay
                if gameManager.isRespawning {
                    Color.red.opacity(0.4)
                        .edgesIgnoringSafeArea(.all)

                    if gameManager.currentMode == .freeForAll {
                        // Free-for-All: show countdown
                        VStack {
                            Text("Respawning in")
                                .font(.largeTitle)
                                .foregroundColor(.white)
                            Text("\(gameManager.respawnTimeRemaining)")
                                .font(.system(size: 80, weight: .bold))
                                .foregroundColor(.white)
                        }
                    } else {
                        // Team modes: show QR codes
                        VStack(spacing: 20) {
                            QRCodeDisplayView(mode: gameManager.currentMode,
                                              team: gameManager.localTeam)
                                .frame(width: 250, height: 300)
                        }
                        .padding()
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
                GroupPairingView(gameManager: gameManager,
                                 isPresented: $gameManager.isShowingPairing)
            }
            .sheet(isPresented: $showingModePicker) {
                GameModePicker(selected: $gameManager.currentMode)
            }
        }
    }
}

struct GameModePicker: View {
    @Binding var selected: GameMode

    var body: some View {
        NavigationView {
            Form {
                Picker("Game Mode", selection: $selected) {
                    Text("Free-for-All").tag(GameMode.freeForAll)
                    Text("Team Match").tag(GameMode.teamMatch)
                    Text("Capture the Flag").tag(GameMode.captureTheFlag)
                }
                .pickerStyle(.segmented)
            }
            .navigationTitle("Select Mode")
            .padding()
        }
    }
}
