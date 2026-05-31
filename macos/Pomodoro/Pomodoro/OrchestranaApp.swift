//
//  OrchestranaApp.swift
//  Orchestrana
//
//  Created by Zhengyang Hu on 1/15/26.
//

import SwiftUI
import AppKit
import FirebaseCore

enum ClientLog {
    static func debug(_ message: @autoclosure () -> String) {
#if DEBUG
        print(message())
#endif
    }

    static func debugError(_ prefix: String, _ error: Error) {
#if DEBUG
        let nsError = error as NSError
        print("\(prefix): [\(nsError.domain):\(nsError.code)]")
#endif
    }
}

enum FirebaseBootstrap {
    @discardableResult
    static func configureIfPossible() -> Bool {
        if FirebaseApp.app() != nil {
            return true
        }

        guard let resourceURL = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") else {
            ClientLog.debug("[Firebase] Skipping configure: GoogleService-Info.plist is missing.")
            return false
        }

        guard
            let configuration = NSDictionary(contentsOf: resourceURL) as? [String: Any]
        else {
            ClientLog.debug("[Firebase] Skipping configure: GoogleService-Info.plist could not be decoded.")
            return false
        }

        let googleAppID = (configuration["GOOGLE_APP_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let clientID = (configuration["CLIENT_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bundleID = (configuration["BUNDLE_ID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let runtimeBundleID = Bundle.main.bundleIdentifier ?? ""

        guard !googleAppID.isEmpty, !clientID.isEmpty else {
            ClientLog.debug("[Firebase] Skipping configure: plist is missing required app fields.")
            return false
        }

        if !bundleID.isEmpty, !runtimeBundleID.isEmpty, bundleID != runtimeBundleID {
            ClientLog.debug("[Firebase] Skipping configure: plist bundle ID does not match runtime bundle ID.")
            return false
        }

        FirebaseApp.configure()
        ClientLog.debug("[Firebase] configureIfPossible succeeded.")
        return FirebaseApp.app() != nil
    }
}

@MainActor
@main
struct OrchestranaApp: App {
    static let mainWindowID = "main-window"

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @StateObject private var musicController: MusicController
    @StateObject private var audioSourceStore: AudioSourceStore
    @StateObject private var audioMixerStore: AudioMixerStore
    @StateObject private var onboardingState: OnboardingState
    @StateObject private var authViewModel: AuthViewModel
    @StateObject private var languageManager: LanguageManager
    @StateObject private var appTypography: AppTypography
    @StateObject private var fullscreenFocusBackdropStore: FullscreenFocusBackdropStore
    @StateObject private var flowWindowManager: FlowWindowManager

    init() {
        _ = FirebaseBootstrap.configureIfPossible()

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
        _audioMixerStore = StateObject(wrappedValue: AudioMixerStore())
        _onboardingState = StateObject(wrappedValue: OnboardingState())
        _authViewModel = StateObject(wrappedValue: AuthViewModel.shared)
        _languageManager = StateObject(wrappedValue: LanguageManager.shared)
        _appTypography = StateObject(wrappedValue: AppTypography.shared)
        _fullscreenFocusBackdropStore = StateObject(wrappedValue: FullscreenFocusBackdropStore())
        _flowWindowManager = StateObject(wrappedValue: FlowWindowManager())
    }

    var body: some Scene {
        Window("Orchestrana", id: Self.mainWindowID) {
            rootContentView
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            AppInfoCommands()

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
            .environmentObject(audioMixerStore)
            .environmentObject(onboardingState)
            .environmentObject(authViewModel)
            .environmentObject(languageManager)
            .environmentObject(appTypography)
            .environmentObject(fullscreenFocusBackdropStore)
            .environmentObject(flowWindowManager)
            .background(MainWindowSceneOpenerBridge(onRegister: { action in
                appDelegate.registerMainWindowSceneOpener(action)
            }))
            .background(MainWindowFullscreenGuard())
            .task(id: ObjectIdentifier(appState)) {
                appDelegate.appState = appState
                appDelegate.musicController = musicController
                appDelegate.audioSourceStore = audioSourceStore
                appDelegate.audioMixerStore = audioMixerStore
                flowWindowManager.configure(
                    appState: appState,
                    musicController: musicController,
                    audioSourceStore: audioSourceStore,
                    audioMixerStore: audioMixerStore,
                    onboardingState: onboardingState,
                    authViewModel: authViewModel,
                    languageManager: languageManager,
                    fullscreenFocusBackdropStore: fullscreenFocusBackdropStore
                )
            }

        content
    }

    private struct AppInfoCommands: Commands {
        var body: some Commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Orchestrana") {
                    AboutWindowPresenter.open()
                }
            }
        }
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
                        openWindow(id: OrchestranaApp.mainWindowID)
                    }
                }
        }
    }

    private struct MainWindowFullscreenGuard: NSViewRepresentable {
        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            configureWindow(for: view, context: context)
            return view
        }

        func updateNSView(_ nsView: NSView, context: Context) {
            configureWindow(for: nsView, context: context)
        }

        private func configureWindow(for view: NSView, context: Context) {
            DispatchQueue.main.async {
                guard let window = view.window else { return }
                context.coordinator.configure(window)
            }
        }

        final class Coordinator: NSObject, NSWindowDelegate {
            weak var configuredWindow: NSWindow?
            weak var zoomOnlyButton: ZoomOnlyTrafficLightButton?

            func configure(_ window: NSWindow) {
                if configuredWindow !== window {
                    zoomOnlyButton?.removeFromSuperview()
                    zoomOnlyButton = nil
                    configuredWindow = window
                    window.delegate = self
                }
                window.identifier = NSUserInterfaceItemIdentifier(OrchestranaApp.mainWindowID)
                window.collectionBehavior = [.fullScreenNone]
                if let zoomButton = window.standardWindowButton(.zoomButton) {
                    installZoomOnlyButton(over: zoomButton)
                }
            }

            private func installZoomOnlyButton(over zoomButton: NSButton) {
                guard let container = zoomButton.superview else { return }

                zoomButton.isHidden = true
                let replacement = zoomOnlyButton ?? ZoomOnlyTrafficLightButton(frame: zoomButton.frame)
                replacement.frame = zoomButton.frame
                replacement.autoresizingMask = zoomButton.autoresizingMask
                replacement.target = self
                replacement.action = #selector(performMainWindowZoom(_:))

                if replacement.superview !== container {
                    replacement.removeFromSuperview()
                    container.addSubview(replacement, positioned: .above, relativeTo: zoomButton)
                }
                zoomOnlyButton = replacement
            }

            @objc private func performMainWindowZoom(_ sender: Any?) {
                configuredWindow?.performZoom(sender)
            }
        }

        final class ZoomOnlyTrafficLightButton: NSButton {
            private var isHovered = false

            override init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                isBordered = false
                imagePosition = .noImage
                title = ""
                toolTip = "Maximize"
                setButtonType(.momentaryPushIn)
                setAccessibilityLabel("Maximize")
            }

            required init?(coder: NSCoder) {
                super.init(coder: coder)
                isBordered = false
                imagePosition = .noImage
                title = ""
                toolTip = "Maximize"
                setButtonType(.momentaryPushIn)
                setAccessibilityLabel("Maximize")
            }

            override func updateTrackingAreas() {
                super.updateTrackingAreas()
                trackingAreas.forEach(removeTrackingArea)
                addTrackingArea(NSTrackingArea(
                    rect: bounds,
                    options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                    owner: self,
                    userInfo: nil
                ))
            }

            override func mouseEntered(with event: NSEvent) {
                isHovered = true
                needsDisplay = true
            }

            override func mouseExited(with event: NSEvent) {
                isHovered = false
                needsDisplay = true
            }

            override func draw(_ dirtyRect: NSRect) {
                let diameter = min(bounds.width, bounds.height, 13)
                let circleRect = NSRect(
                    x: bounds.midX - diameter / 2,
                    y: bounds.midY - diameter / 2,
                    width: diameter,
                    height: diameter
                )
                NSColor(calibratedRed: 0.16, green: 0.78, blue: 0.25, alpha: isEnabled ? 1 : 0.45).setFill()
                NSBezierPath(ovalIn: circleRect).fill()

                guard isHovered || isHighlighted else { return }
                let plusPath = NSBezierPath()
                plusPath.lineWidth = 1.6
                plusPath.lineCapStyle = .round
                let inset = diameter * 0.31
                plusPath.move(to: NSPoint(x: circleRect.minX + inset, y: circleRect.midY))
                plusPath.line(to: NSPoint(x: circleRect.maxX - inset, y: circleRect.midY))
                plusPath.move(to: NSPoint(x: circleRect.midX, y: circleRect.minY + inset))
                plusPath.line(to: NSPoint(x: circleRect.midX, y: circleRect.maxY - inset))
                NSColor(calibratedWhite: 0, alpha: 0.55).setStroke()
                plusPath.stroke()
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
}
