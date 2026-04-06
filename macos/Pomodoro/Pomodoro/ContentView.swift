//
//  ContentView.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import SwiftUI
import Foundation

@MainActor
struct ContentView: View {
    @EnvironmentObject private var onboardingState: OnboardingState
    @EnvironmentObject private var flowWindowManager: FlowWindowManager

    var body: some View {
        ZStack {
            if onboardingState.isPresented {
                OnboardingFlowView()
                    .transition(.opacity)
            } else {
                MainWindowView()
                    .transition(.opacity)
            }
        }
        .background(
            WindowBackgroundConfigurator(
                chromeStyle: onboardingState.isPresented ? .onboarding : .main,
                onResolveWindow: { window in
                    flowWindowManager.registerMainWindow(window)
                }
            )
        )
        .animation(.easeInOut(duration: 0.22), value: onboardingState.isPresented)
    }
}

struct PremiumButton: View {
    let title: String
    let action: () -> Void

    @EnvironmentObject private var authViewModel: AuthViewModel
    @State private var showLoginSheet = false
    @State private var pendingAction = false

    var body: some View {
        Button(title) {
            if authViewModel.isLoggedIn {
                action()
            } else {
                pendingAction = true
                showLoginSheet = true
            }
        }
        .sheet(isPresented: $showLoginSheet) {
            LoginSheetView()
                .environmentObject(authViewModel)
        }
        .onChange(of: authViewModel.isLoggedIn) { _, isLoggedIn in
            if isLoggedIn, pendingAction {
                pendingAction = false
                showLoginSheet = false
                action()
            }
        }
    }
}

#if DEBUG && PREVIEWS_ENABLED
#Preview {
    MainActor.assumeIsolated {
        let appState = AppState()
        let musicController = MusicController(ambientNoiseEngine: appState.ambientNoiseEngine)
        let externalMonitor = ExternalAudioMonitor()
        let externalController = ExternalPlaybackController()
        let audioSourceStore = AudioSourceStore(
            musicController: musicController,
            externalMonitor: externalMonitor,
            externalController: externalController
        )
        return ContentView()
            .environmentObject(appState)
            .environmentObject(musicController)
            .environmentObject(audioSourceStore)
            .environmentObject(OnboardingState())
            .environmentObject(AuthViewModel.shared)
            .environmentObject(AppTypography.shared)
    }
}
#endif
