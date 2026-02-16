//
//  lidarApp.swift
//  lidar
//
//  Created by Jaime Pareja Arco on 9/2/26.
//

import SwiftUI

@main
struct lidarApp: App {
    @State private var showOnboarding = !UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                
                if showOnboarding {
                    OnboardingView(isPresented: $showOnboarding)
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: showOnboarding)
        }
    }
}
