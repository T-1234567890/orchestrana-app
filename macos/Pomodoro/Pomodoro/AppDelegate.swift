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
        if !flag {
            openMainWindow()
        }
        return true
    }

    func openMainWindow() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        openMainWindowScene?()
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
            print("[Firebase] Firebase is unavailable. Cloud auth and subscription-backed features will stay disabled.")
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
