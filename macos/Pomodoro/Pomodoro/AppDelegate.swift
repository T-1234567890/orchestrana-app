//
//  AppDelegate.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import AppKit
import FirebaseCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
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
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.shutdown()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureFirebase()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        AuthManager.shared.handleOpenURLs(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !hasVisibleMainWindow {
            openMainWindow()
        }
        return true
    }

    func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        if focusExistingMainWindow() {
            return
        }

        openMainWindowScene?()
        DispatchQueue.main.async { [weak self] in
            _ = self?.focusExistingMainWindow()
        }
    }

    private func quitApp() {
        NSApplication.shared.terminate(nil)
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
        _ = FirebaseBootstrap.configureIfPossible()

        guard FirebaseApp.app() != nil else {
            ClientLog.debug("[Firebase] Firebase is unavailable. Cloud features disabled.")
            return
        }

        AuthManager.shared.logAuthConfiguration()
        AuthViewModel.shared.startListeningIfNeeded()
    }

    func registerMainWindowSceneOpener(_ opener: @escaping () -> Void) {
        openMainWindowScene = opener
    }

    private var hasVisibleMainWindow: Bool {
        NSApplication.shared.windows.contains { window in
            window.identifier?.rawValue == OrchestranaApp.mainWindowID &&
            window.isVisible &&
            !window.isMiniaturized
        }
    }

    @discardableResult
    private func focusExistingMainWindow() -> Bool {
        guard let window = NSApplication.shared.windows.first(where: {
            $0.identifier?.rawValue == OrchestranaApp.mainWindowID
        }) else {
            return false
        }

        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        return true
    }
}
