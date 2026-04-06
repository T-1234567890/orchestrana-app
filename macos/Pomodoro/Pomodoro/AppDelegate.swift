//
//  AppDelegate.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import AppKit
import FirebaseAuth
import FirebaseCore
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var mainWindow: NSWindow?
    private var appStateConfigured = false
    private var menuBarController: MenuBarController?
    private var openMainWindowScene: (() -> Void)?

    var appState: AppState? {
        didSet {
            configureControllersIfNeeded()
        }
    }

    var musicController: MusicController? {
        didSet {
            configureControllersIfNeeded()
        }
    }
    var audioSourceStore: AudioSourceStore? {
        didSet {
            configureControllersIfNeeded()
        }
    }
    var onboardingState: OnboardingState?
    var authViewModel: AuthViewModel?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureFirebase()
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, let window = self.existingMainWindow() else { return }
            window.applyPomodoroWindowChrome(currentWindowChromeStyle())
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AuthManager.shared.handleOpenURLs(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openMainWindow()
        }
        return true
    }

    func openMainWindow() {
        if let window = mainWindow ?? existingMainWindow() {
            focus(window: window)
            return
        }

        openMainWindowScene?()
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, let openedWindow = self.existingMainWindow() else { return }
            self.focus(window: openedWindow)
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    private func existingMainWindow() -> NSWindow? {
        let windows = NSApplication.shared.windows
        let identifiedWindow = windows.first { window in
            window.identifier == .pomodoroMainWindow
        }
        let window = identifiedWindow ?? windows.first { window in
            window.styleMask.contains(.titled)
                && window.level == .normal
                && window.canBecomeMain
                && !window.isExcludedFromWindowsMenu
        }
        if let window {
            mainWindow = window
        }
        return window
    }

    private func focus(window: NSWindow) {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.applyPomodoroWindowChrome(currentWindowChromeStyle())
        window.makeKeyAndOrderFront(nil)
    }

    private func currentWindowChromeStyle() -> PomodoroWindowChromeStyle {
        onboardingState?.isPresented == true ? .onboarding : .main
    }

    private func configureControllersIfNeeded() {
        guard !appStateConfigured else { return }
        guard let appState, let musicController else { return }
        appStateConfigured = true
        menuBarController = MenuBarController(
            appState: appState,
            musicController: musicController,
            openMainWindow: { [weak self] in
                self?.openMainWindow()
            },
            quitApp: { [weak self] in
                self?.quitApp()
            }
        )
    }

    private func configureFirebase() {
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        guard FirebaseApp.app() != nil else {
            print("[Firebase] ERROR: Firebase failed to initialize. FirebaseApp.app() is nil after configure().")
            return
        }

        print("[Firebase] projectID: \(String(describing: FirebaseApp.app()?.options.projectID))")
        print("[Firebase] googleAppID: \(String(describing: FirebaseApp.app()?.options.googleAppID))")
        AuthManager.shared.logAuthConfiguration()
        AuthViewModel.shared.startListeningIfNeeded()
    }

    func registerMainWindowSceneOpener(_ opener: @escaping () -> Void) {
        openMainWindowScene = opener
    }
}
