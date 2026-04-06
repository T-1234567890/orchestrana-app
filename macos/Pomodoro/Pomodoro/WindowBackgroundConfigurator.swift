//
//  WindowBackgroundConfigurator.swift
//  Pomodoro
//
//  Configures the NSWindow to support wallpaper blur across main app and onboarding chrome styles.
//

import AppKit
import SwiftUI

enum PomodoroWindowChromeStyle {
    case main
    case onboarding
}

/// Configures the NSWindow to support wallpaper blur and the active chrome style.
///
/// Responsibilities:
/// - Enables true wallpaper blur by making the window non-opaque with a clear background
/// - Switches between normal app chrome and onboarding chrome
/// - Preserves window dragging by allowing the full background to act as a drag region
struct WindowBackgroundConfigurator: NSViewRepresentable {
    let chromeStyle: PomodoroWindowChromeStyle
    let onResolveWindow: ((NSWindow) -> Void)?

    init(
        chromeStyle: PomodoroWindowChromeStyle,
        onResolveWindow: ((NSWindow) -> Void)? = nil
    ) {
        self.chromeStyle = chromeStyle
        self.onResolveWindow = onResolveWindow
    }

    final class HostingView: NSView {
        var chromeStyle: PomodoroWindowChromeStyle = .main
        var onResolveWindow: ((NSWindow) -> Void)?

        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            applyWindowStyling()
        }

        func applyWindowStyling() {
            guard let window else { return }
            window.identifier = .pomodoroMainWindow
            window.applyPomodoroWindowChrome(chromeStyle)
            onResolveWindow?(window)
        }
    }

    func makeNSView(context: Context) -> HostingView {
        let view = HostingView()
        view.chromeStyle = chromeStyle
        view.onResolveWindow = onResolveWindow
        return view
    }

    func updateNSView(_ nsView: HostingView, context: Context) {
        nsView.chromeStyle = chromeStyle
        nsView.onResolveWindow = onResolveWindow
        nsView.applyWindowStyling()
    }
}

extension NSWindow {
    private static let sidebarToggleButtonTag = 2_113_001

    /// Applies the shared wallpaper-blur window settings plus the requested chrome mode.
    func applyPomodoroWindowChrome(_ style: PomodoroWindowChromeStyle = .main) {
        guard level == .normal else { return }

        styleMask.insert(.titled)
        styleMask.insert(.closable)
        styleMask.insert(.miniaturizable)
        styleMask.insert(.resizable)
        collectionBehavior.remove(.fullScreenPrimary)
        collectionBehavior.remove(.fullScreenAuxiliary)
        collectionBehavior.remove(.fullScreenAllowsTiling)

        switch style {
        case .main:
            styleMask.insert(.fullSizeContentView)
            isOpaque = false
            backgroundColor = .clear
            title = ""
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            titlebarSeparatorStyle = .none
            toolbarStyle = .unified
            isMovableByWindowBackground = true
            toolbar = nil
            applyTrafficLights(hidden: false)
            configureSidebarToggleButton(hidden: true)
        case .onboarding:
            styleMask.insert(.fullSizeContentView)
            isOpaque = false
            backgroundColor = .clear
            title = ""
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            titlebarSeparatorStyle = .none
            toolbarStyle = .unified
            isMovableByWindowBackground = true
            toolbar = nil
            applyTrafficLights(hidden: true)
            configureSidebarToggleButton(hidden: true)
        }
    }

    private func applyTrafficLights(hidden: Bool) {
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for buttonType in buttons {
            guard let button = standardWindowButton(buttonType) else { continue }
            button.isHidden = hidden
            button.isEnabled = !hidden
        }
    }

    private func configureSidebarToggleButton(hidden: Bool) {
        guard let titlebarContainer = standardWindowButton(.closeButton)?.superview else { return }

        if hidden {
            titlebarContainer.subviews
                .first(where: { $0.tag == Self.sidebarToggleButtonTag })?
                .removeFromSuperview()
            return
        }

        let button: NSButton
        if let existing = titlebarContainer.subviews.first(where: { $0.tag == Self.sidebarToggleButtonTag }) as? NSButton {
            button = existing
        } else {
            let image = NSImage(
                systemSymbolName: "sidebar.left",
                accessibilityDescription: "Toggle Sidebar"
            ) ?? NSImage()
            let created = NSButton(image: image, target: nil, action: #selector(NSSplitViewController.toggleSidebar(_:)))
            created.tag = Self.sidebarToggleButtonTag
            created.bezelStyle = .texturedRounded
            created.isBordered = true
            created.imagePosition = .imageOnly
            created.setButtonType(.momentaryPushIn)
            created.translatesAutoresizingMaskIntoConstraints = true
            created.autoresizingMask = [.minXMargin, .minYMargin]
            created.toolTip = "Toggle Sidebar"
            titlebarContainer.addSubview(created)
            button = created
        }

        guard let zoomButton = standardWindowButton(.zoomButton) else { return }
        let controlFrame = zoomButton.frame
        let buttonSize = NSSize(width: 28, height: 22)
        let origin = NSPoint(
            x: controlFrame.maxX + 10,
            y: controlFrame.midY - (buttonSize.height / 2)
        )
        button.frame = NSRect(origin: origin, size: buttonSize)
    }
}

extension NSUserInterfaceItemIdentifier {
    static let pomodoroMainWindow = NSUserInterfaceItemIdentifier("PomodoroMainWindow")
    static let pomodoroFlowWindow = NSUserInterfaceItemIdentifier("PomodoroFlowWindow")
}
