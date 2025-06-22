//
//  SettingsView.swift
//  RealStrike-Warfare
//
//  Created by Chris on 2025-06-22.
//

import Foundation
import SwiftUI

struct SettingsView: View {
    @Binding var selectedTeam: Team

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Your Team")) {
                    Picker("Team", selection: $selectedTeam) {
                        Text("🔴 Red").tag(Team.red)
                        Text("🔵 Blue").tag(Team.blue)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
