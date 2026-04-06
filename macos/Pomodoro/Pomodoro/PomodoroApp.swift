//
//  PomodoroApp.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import SwiftUI
import FirebaseCore
import AppKit

@MainActor
@main
struct PomodoroApp: App {
    static let mainWindowID = "main-window"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var musicController: MusicController
    @StateObject private var audioSourceStore: AudioSourceStore
    @StateObject private var onboardingState: OnboardingState
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var languageManager: LanguageManager
    @StateObject private var appTypography: AppTypography
    @StateObject private var fullscreenFocusBackdropStore: FullscreenFocusBackdropStore
    @StateObject private var flowWindowManager: FlowWindowManager

    init() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        SubscriptionStore.shared.start()

        let appState = AppState()
        let musicController = MusicController(ambientNoiseEngine: appState.ambientNoiseEngine)
        let externalMonitor = ExternalAudioMonitor()
        let externalController = ExternalPlaybackController()
        _appState = StateObject(wrappedValue: appState)
        _musicController = StateObject(wrappedValue: musicController)
        _audioSourceStore = StateObject(
            wrappedValue: AudioSourceStore(
                musicController: musicController,
                externalMonitor: externalMonitor,
                externalController: externalController
            )
        )
        _onboardingState = StateObject(wrappedValue: OnboardingState())
        _authViewModel = StateObject(wrappedValue: AuthViewModel.shared)
        _languageManager = StateObject(wrappedValue: LanguageManager.shared)
        _appTypography = StateObject(wrappedValue: AppTypography.shared)
        _fullscreenFocusBackdropStore = StateObject(wrappedValue: FullscreenFocusBackdropStore())
        _flowWindowManager = StateObject(wrappedValue: FlowWindowManager())
    }

    var body: some Scene {
        WindowGroup("Orchestrana", id: Self.mainWindowID) {
            rootContentView
        }
        .commands {
            CommandMenu("Timer") {
                Button("Start Session") {
                    startSession()
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Pause Session") {
                    pauseSession()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button("Reset Session") {
                    appState.resetPomodoro()
                }
                .keyboardShortcut("r", modifiers: [])

                Divider()

                Button("Skip Break") {
                    appState.skipBreak()
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
            }

            CommandMenu("Tasks") {
                Button("New Task") {
                    openNewTaskComposer()
                }
                .keyboardShortcut("n", modifiers: [.command])

                Button("Open Task List") {
                    navigateTo(.navigateToTasks)
                }
                .keyboardShortcut("0", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Task Done") {
                    NotificationCenter.default.post(name: .taskToggleSelectedCompletion, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command])

                Button("Delete Task") {
                    NotificationCenter.default.post(name: .taskDeleteSelection, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }

            CommandMenu("Calendar") {
                Button("Open Calendar") {
                    navigateTo(.navigateToCalendar)
                }
                .keyboardShortcut("4", modifiers: [.command, .shift])

                Button("Today View") {
                    openCalendarToday()
                }
                .keyboardShortcut("t", modifiers: [.command, .option])
            }

            CommandMenu("Audio") {
                Button("White Noise") {
                    audioSourceStore.selectAmbient(.white)
                }
                Button("Brown Noise") {
                    audioSourceStore.selectAmbient(.brown)
                }
                Button("Rain") {
                    audioSourceStore.selectAmbient(.rain)
                }
                Button("Wind") {
                    audioSourceStore.selectAmbient(.wind)
                }
                Menu("Volume") {
                    Button("Mute") { audioSourceStore.setVolume(0.0) }
                    Button("25%") { audioSourceStore.setVolume(0.25) }
                    Button("50%") { audioSourceStore.setVolume(0.5) }
                    Button("75%") { audioSourceStore.setVolume(0.75) }
                    Button("100%") { audioSourceStore.setVolume(1.0) }
                }
            }

            CommandGroup(after: .newItem) {
                Button("New Task") {
                    openNewTaskComposer()
                }
            }

            CommandGroup(after: .toolbar) {
                Divider()
                Button("Show Pomodoro") {
                    navigateTo(.navigateToPomodoro)
                }
                .keyboardShortcut("1", modifiers: [.command, .option])

                Button("Show Flow Mode") {
                    navigateTo(.navigateToFlow)
                }
                .keyboardShortcut("2", modifiers: [.command, .option])

                Button("Show Countdown Mode") {
                    navigateTo(.navigateToCountdown)
                }
                .keyboardShortcut("3", modifiers: [.command, .option])
            }
        }
    }

    @ViewBuilder
    private var rootContentView: some View {
        let content = ContentView()
            .environmentObject(appState)
            .environmentObject(musicController)
            .environmentObject(audioSourceStore)
            .environmentObject(onboardingState)
            .environmentObject(authViewModel)
            .environmentObject(languageManager)
            .environmentObject(appTypography)
            .environmentObject(fullscreenFocusBackdropStore)
            .environmentObject(flowWindowManager)
            .background(MainWindowSceneOpenerBridge(onRegister: { action in
                appDelegate.registerMainWindowSceneOpener(action)
            }))
            .id(languageManager.currentLanguage.rawValue)
            .task(id: ObjectIdentifier(appState)) {
                appDelegate.appState = appState
                appDelegate.musicController = musicController
                appDelegate.audioSourceStore = audioSourceStore
                appDelegate.onboardingState = onboardingState
                appDelegate.authViewModel = authViewModel
                flowWindowManager.configure(
                    appState: appState,
                    musicController: musicController,
                    audioSourceStore: audioSourceStore,
                    onboardingState: onboardingState,
                    authViewModel: authViewModel,
                    languageManager: languageManager,
                    fullscreenFocusBackdropStore: fullscreenFocusBackdropStore
                )
            }
            .onAppear {
                enforceWindowedMainWindow()
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: NSApplication.willUpdateNotification
                )
            ) { _ in
                enforceWindowedMainWindow()
            }

        content.environment(\.locale, languageManager.effectiveLocale)
    }

    private struct MainWindowSceneOpenerBridge: View {
        @Environment(\.openWindow) private var openWindow
        let onRegister: (@escaping () -> Void) -> Void

        var body: some View {
            Color.clear
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .onAppear {
                    onRegister {
                        openWindow(id: PomodoroApp.mainWindowID)
                    }
                }
        }
    }

    private func startSession() {
        // Spacebar should be inert while in Flow Mode to keep the focus surface passive.
        guard !appState.isInFlowMode else { return }
        switch appState.pomodoro.state {
        case .idle:
            appState.startPomodoro()
        case .paused, .breakPaused:
            appState.togglePomodoroPause()
        case .running, .breakRunning:
            break
        }
    }

    private func pauseSession() {
        switch appState.pomodoro.state {
        case .running, .breakRunning:
            appState.togglePomodoroPause()
        case .idle, .paused, .breakPaused:
            break
        }
    }

    private func openNewTaskComposer() {
        navigateTo(.navigateToTasks)
        NotificationCenter.default.post(name: .openNewTaskComposer, object: nil)
    }

    private func openCalendarToday() {
        navigateTo(.navigateToCalendar)
        NotificationCenter.default.post(name: .calendarGoToToday, object: nil)
    }

    private func navigateTo(_ notification: Notification.Name) {
        appDelegate.openMainWindow()
        NotificationCenter.default.post(name: notification, object: nil)
    }

    private func enforceWindowedMainWindow() {
        for window in NSApplication.shared.windows {
            if window.identifier == .pomodoroMainWindow {
                let chromeStyle: PomodoroWindowChromeStyle = onboardingState.isPresented ? .onboarding : .main
                window.applyPomodoroWindowChrome(chromeStyle)
            }
        }
    }
}
