//
//  QRCodeDisplayView.swift
//  RealStrike-Warfare
//
//  Created by Chris on 2025-06-21.
//

import Foundation
import SwiftUI

/// Displays the appropriate QR codes based on the current game mode and team.
struct QRCodeDisplayView: View {
  let mode: GameMode
  let team: Team?

  var body: some View {
    VStack(spacing: 24) {
      // Team-based respawn code
      if (mode == .teamMatch || mode == .captureTheFlag), let team = team {
        Text("Scan to Respawn")
          .font(.headline)
        Image(team == .red ? "qr_red" : "qr_blue")
          .resizable()
          .interpolation(.none)
          .scaledToFit()
          .frame(width: 200, height: 200)
      }

      // Flag capture code (only in CTF)
      if mode == .captureTheFlag {
        Divider()
          .padding(.horizontal)
        Text("Scan to Capture Flag")
          .font(.headline)
        Image("qr_flag")
          .resizable()
          .interpolation(.none)
          .scaledToFit()
          .frame(width: 200, height: 200)
      }
    }
    .padding()
    .background(Color.white.opacity(0.9))
    .cornerRadius(12)
    .shadow(radius: 5)
  }
}
