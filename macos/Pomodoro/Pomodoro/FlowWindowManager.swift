import AppKit
import Combine
import SwiftUI

@MainActor
final class FlowWindowManager: ObservableObject {
    private static let flowWindowIdentifier = NSUserInterfaceItemIdentifier("PomodoroFlowWindow")

    enum PremiumFeature: String, Identifiable {
        case fullscreen
        case customBackground

        var id: String { rawValue }
    }

    @Published private(set) var isFullscreenPresentation = false
    @Published private(set) var activePremiumPreview: PremiumFeature?

    private weak var flowWindow: NSWindow?
    private var closeAfterFullscreenExit = false
    private var fullscreenExitObserver: NSObjectProtocol?
    private var fullscreenEnterObserver: NSObjectProtocol?
    private var flowWindowCloseObserver: NSObjectProtocol?
    private var premiumPreviewTask: Task<Void, Never>?

    private var appState: AppState?
    private var musicController: MusicController?
    private var audioSourceStore: AudioSourceStore?
    private var onboardingState: OnboardingState?
    private var authViewModel: AuthViewModel?
    private var languageManager: LanguageManager?
    private var fullscreenFocusBackdropStore: FullscreenFocusBackdropStore?

    deinit {
        premiumPreviewTask?.cancel()
        if let fullscreenExitObserver {
            NotificationCenter.default.removeObserver(fullscreenExitObserver)
        }
        if let fullscreenEnterObserver {
            NotificationCenter.default.removeObserver(fullscreenEnterObserver)
        }
        if let flowWindowCloseObserver {
            NotificationCenter.default.removeObserver(flowWindowCloseObserver)
        }
    }

    func configure(
        appState: AppState,
        musicController: MusicController,
        audioSourceStore: AudioSourceStore,
        onboardingState: OnboardingState,
        authViewModel: AuthViewModel,
        languageManager: LanguageManager,
        fullscreenFocusBackdropStore: FullscreenFocusBackdropStore
    ) {
        self.appState = appState
        self.musicController = musicController
        self.audioSourceStore = audioSourceStore
        self.onboardingState = onboardingState
        self.authViewModel = authViewModel
        self.languageManager = languageManager
        self.fullscreenFocusBackdropStore = fullscreenFocusBackdropStore
        refreshFlowWindowContentIfNeeded()
    }

    func exitFlowMode() {
        guard let window = flowWindow else {
            appState?.isInFlowMode = false
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        if window.styleMask.contains(.fullScreen) {
            closeAfterFullscreenExit = true
            window.toggleFullScreen(nil)
        } else {
            closeFlowWindow()
        }
    }

    func toggleFlowFullscreen() {
        if isFullscreenPresentation {
            leaveFullscreen()
        } else {
            Task { @MainActor [weak self] in
                await self?.requestPremiumFeature(.fullscreen) {
                    self?.enterFullscreen()
                }
            }
        }
    }

    func requestCustomBackgroundImage() {
        Task { @MainActor [weak self] in
            await self?.requestCustomBackgroundAccess {
                self?.fullscreenFocusBackdropStore?.chooseImage()
            }
        }
    }

    func requestCustomBackgroundFolder() {
        Task { @MainActor [weak self] in
            await self?.requestCustomBackgroundAccess {
                self?.fullscreenFocusBackdropStore?.chooseFolder()
            }
        }
    }

    func setBackgroundAutoRotateEnabled(_ enabled: Bool) {
        Task { @MainActor [weak self] in
            await self?.requestCustomBackgroundAccess {
                self?.fullscreenFocusBackdropStore?.autoRotateEnabled = enabled
            }
        }
    }

    func dismissPremiumPreview() {
        let preview = activePremiumPreview
        clearPremiumPreview()
        if preview == .fullscreen {
            leaveFullscreen()
        }
    }

    func completePremiumPreviewIfUnlocked() {
        guard let activePremiumPreview, hasAccess(to: activePremiumPreview) else { return }
        clearPremiumPreview()
    }

    private func makeFlowWindowIfNeeded() -> NSWindow? {
        if let flowWindow {
            refreshFlowWindowContentIfNeeded()
            return flowWindow
        }

        guard let rootView = makeFlowRootView() else { return nil }

        let hostingController = NSHostingController(rootView: rootView)
        let window = FlowWindow(contentViewController: hostingController)
        window.identifier = Self.flowWindowIdentifier
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.fullScreenPrimary]
        window.animationBehavior = .documentWindow
        window.backgroundColor = .black
        window.isOpaque = true
        window.level = .normal
        window.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 1180, height: 760))
        window.center()
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        flowWindow = window
        observeFlowWindow(window)
        return window
    }

    private func makeFlowRootView() -> AnyView? {
        guard let appState,
              let musicController,
              let audioSourceStore,
              let onboardingState,
              let authViewModel,
              let languageManager,
              let fullscreenFocusBackdropStore else {
            return nil
        }

        return AnyView(
            FlowModeView(
                showsBackgroundLayer: true,
                isFullscreenPresentation: false,
                exitAction: { [weak self] in
                    self?.exitFlowMode()
                }
            )
            .environmentObject(appState)
            .environmentObject(musicController)
            .environmentObject(audioSourceStore)
            .environmentObject(onboardingState)
            .environmentObject(authViewModel)
            .environmentObject(languageManager)
            .environmentObject(fullscreenFocusBackdropStore)
            .environmentObject(self)
        )
    }

    private func refreshFlowWindowContentIfNeeded() {
        guard let flowWindow,
              let hostingController = flowWindow.contentViewController as? NSHostingController<AnyView>,
              let rootView = makeFlowRootView() else {
            return
        }

        hostingController.rootView = rootView
    }

    private func observeFlowWindow(_ window: NSWindow) {
        if let fullscreenExitObserver {
            NotificationCenter.default.removeObserver(fullscreenExitObserver)
        }
        if let fullscreenEnterObserver {
            NotificationCenter.default.removeObserver(fullscreenEnterObserver)
        }
        if let flowWindowCloseObserver {
            NotificationCenter.default.removeObserver(flowWindowCloseObserver)
        }

        fullscreenEnterObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didEnterFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isFullscreenPresentation = true
            }
        }

        fullscreenExitObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didExitFullScreenNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isFullscreenPresentation = false
                if self.closeAfterFullscreenExit {
                    self.closeAfterFullscreenExit = false
                    self.closeFlowWindow()
                } else {
                    self.clearPremiumPreview()
                    self.focus(window)
                }
            }
        }

        flowWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.closeFlowWindow()
            }
        }
    }

    private func closeFlowWindow() {
        premiumPreviewTask?.cancel()
        premiumPreviewTask = nil
        activePremiumPreview = nil
        isFullscreenPresentation = false
        closeAfterFullscreenExit = false

        if let fullscreenExitObserver {
            NotificationCenter.default.removeObserver(fullscreenExitObserver)
            self.fullscreenExitObserver = nil
        }
        if let fullscreenEnterObserver {
            NotificationCenter.default.removeObserver(fullscreenEnterObserver)
            self.fullscreenEnterObserver = nil
        }
        if let flowWindowCloseObserver {
            NotificationCenter.default.removeObserver(flowWindowCloseObserver)
            self.flowWindowCloseObserver = nil
        }

        let window = flowWindow
        flowWindow = nil
        window?.orderOut(nil)
        if window?.isVisible == true {
            window?.close()
        }
        appState?.isInFlowMode = false
        NSApp.activate(ignoringOtherApps: true)
    }

    private func focus(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
    }

    private func enterFullscreen() {
        guard let window = makeFlowWindowIfNeeded() else { return }
        closeAfterFullscreenExit = false
        focus(window)
        guard !window.styleMask.contains(.fullScreen) else {
            isFullscreenPresentation = true
            return
        }
        let flowWindow = window as? FlowWindow
        flowWindow?.allowsProgrammaticFullscreenToggle = true
        window.toggleFullScreen(nil)
        flowWindow?.allowsProgrammaticFullscreenToggle = false
    }

    private func leaveFullscreen() {
        guard let window = flowWindow, window.styleMask.contains(.fullScreen) else {
            isFullscreenPresentation = false
            return
        }
        closeAfterFullscreenExit = false
        window.toggleFullScreen(nil)
    }

    private func requestPremiumFeature(
        _ feature: PremiumFeature,
        onAuthorized: @escaping @MainActor () -> Void
    ) async {
        guard let authViewModel else { return }

        guard authViewModel.isAuthenticated else {
            authViewModel.isPurchaseLoginPromptPresented = true
            return
        }

        await authViewModel.preparePurchaseReadiness()
        await FeatureGate.shared.refreshTier()

        if hasAccess(to: feature) {
            clearPremiumPreview()
            onAuthorized()
            return
        }

        startPremiumPreview(for: feature)
    }

    private func requestCustomBackgroundAccess(
        onAuthorized: @escaping @MainActor () -> Void
    ) async {
        guard isFullscreenPresentation else {
            activePremiumPreview = .customBackground
            return
        }
        guard let authViewModel else { return }
        guard authViewModel.isAuthenticated else {
            authViewModel.isPurchaseLoginPromptPresented = true
            return
        }

        await authViewModel.preparePurchaseReadiness()
        await FeatureGate.shared.refreshTier()

        if hasAccess(to: .customBackground) {
            clearPremiumPreview()
            onAuthorized()
            return
        }

        activePremiumPreview = .customBackground
    }

    private func hasAccess(to feature: PremiumFeature) -> Bool {
        switch feature {
        case .fullscreen:
            return FeatureGate.shared.canUseFullscreenFlow
        case .customBackground:
            return FeatureGate.shared.canUseCustomFlowBackgrounds
        }
    }

    private func startPremiumPreview(for feature: PremiumFeature) {
        premiumPreviewTask?.cancel()
        activePremiumPreview = nil

        premiumPreviewTask = Task { @MainActor [weak self] in
            if feature == .fullscreen {
                self?.enterFullscreen()
            }
            try? await Task.sleep(for: .milliseconds(700))
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard !self.hasAccess(to: feature) else { return }
            self.activePremiumPreview = feature
        }
    }

    private func clearPremiumPreview() {
        premiumPreviewTask?.cancel()
        premiumPreviewTask = nil
        activePremiumPreview = nil
    }

    private final class FlowWindow: NSWindow {
        var allowsProgrammaticFullscreenToggle = false

        override func toggleFullScreen(_ sender: Any?) {
            guard allowsProgrammaticFullscreenToggle || styleMask.contains(.fullScreen) else {
                return
            }
            super.toggleFullScreen(sender)
        }
    }
}
