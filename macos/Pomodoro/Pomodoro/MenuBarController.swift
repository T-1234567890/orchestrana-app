//
//  MenuBarController.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import AppKit
import Combine

@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private static var liveStatusItem: NSStatusItem?

    private enum MenuMode {
        case pomodoro
        case breakTime
        case countdown
        case idle
    }

    private enum MenuActionAvailability {
        case enabled
        case disabled

        var isEnabled: Bool {
            self == .enabled
        }
    }

    private struct PomodoroMenuActionAvailability {
        let start: MenuActionAvailability
        let pauseResume: MenuActionAvailability
        let reset: MenuActionAvailability
        let startBreak: MenuActionAvailability
        let skipBreak: MenuActionAvailability
    }

    private struct CountdownMenuActionAvailability {
        let start: MenuActionAvailability
        let pauseResume: MenuActionAvailability
        let reset: MenuActionAvailability
    }

    private unowned let appState: AppState
    private let musicController: MusicController
    private let audioSourceStore: AudioSourceStore
    private let audioMixerStore: AudioMixerStore
    private let localizationManager = LocalizationManager.shared
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let openMainWindow: () -> Void
    private let quitHandler: () -> Void
    private var titleTimer: Timer?
    private var lastTitleUpdateSecond: Int?
    private var cancellables: Set<AnyCancellable> = []

    init(
        appState: AppState,
        musicController: MusicController,
        audioSourceStore: AudioSourceStore,
        audioMixerStore: AudioMixerStore,
        openMainWindow: @escaping () -> Void,
        quitApp: @escaping () -> Void
    ) {
        self.appState = appState
        self.musicController = musicController
        self.audioSourceStore = audioSourceStore
        self.audioMixerStore = audioMixerStore
        self.openMainWindow = openMainWindow
        self.quitHandler = quitApp
        if let existingItem = Self.liveStatusItem {
            NSStatusBar.system.removeStatusItem(existingItem)
            Self.liveStatusItem = nil
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.liveStatusItem = statusItem
        menu = NSMenu()
        menu.autoenablesItems = false
        super.init()
        configureStatusItem()
        observeStateChanges()
        startTitleTimer()
    }

    deinit {
        titleTimer?.invalidate()
        titleTimer = nil
        cancellables.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = nil
            button.imagePosition = .noImage
            button.attributedTitle = statusTitleAttributedString()
        }
        updateStatusItemLength()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    private func observeStateChanges() {
        appState.pomodoro.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.updateTitleIfNeeded()
            }
            .store(in: &cancellables)

        appState.countdown.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.updateTitleIfNeeded()
            }
            .store(in: &cancellables)

        musicController.$playbackState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        musicController.$currentFocusSound
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        musicController.$activeSource
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        audioSourceStore.$audioSource
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        audioMixerStore.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        audioMixerStore.$selectedTrackIDs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        audioMixerStore.$activePackID
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        audioMixerStore.$customPacks
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
            }
            .store(in: &cancellables)

        localizationManager.$currentLanguage
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.updateStatusItemLength()
                self?.updateTitleIfNeeded()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildMenu()
                self?.updateStatusItemLength()
                self?.updateTitleIfNeeded()
            }
            .store(in: &cancellables)
    }

    private func startTitleTimer() {
        titleTimer?.invalidate()
        titleTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.updateTitleIfNeeded()
            }
        }
        titleTimer?.tolerance = 0.05
    }

    private func updateTitleIfNeeded() {
        let currentSecond = Int(Date().timeIntervalSince1970)
        if lastTitleUpdateSecond == currentSecond {
            return
        }
        lastTitleUpdateSecond = currentSecond
        guard let button = statusItem.button else { return }
        button.image = nil
        button.imagePosition = .noImage
        button.attributedTitle = statusTitleAttributedString()
        button.toolTip = statusTooltip()
    }

    private func statusTitleAttributedString() -> NSAttributedString {
        let title = statusTitle()
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        return NSAttributedString(string: title, attributes: [.font: font])
    }

    private func updateStatusItemLength() {
        let font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        let sampleTitles = [
            "🍅 00:00",
            "☕ 00:00",
            "🌙 00:00",
            "⏱ 00:00",
            "🍅 \(localizationManager.text("menu.status.ready"))"
        ]
        let maxWidth = sampleTitles
            .map { title in
                NSAttributedString(string: title, attributes: [.font: font]).size().width
            }
            .max() ?? 0
        if maxWidth > 0 {
            statusItem.length = ceil(maxWidth) + 6
        }
    }

    private func statusTitle() -> String {
        switch currentMenuMode() {
        case .pomodoro:
            return "🍅 \(formattedTime(appState.pomodoro.remainingSeconds))"
        case .breakTime:
            return "\(breakEmoji()) \(formattedTime(appState.pomodoro.remainingSeconds))"
        case .countdown:
            return "⏱ \(formattedTime(appState.countdown.remainingSeconds))"
        case .idle:
            return "🍅 \(localizationManager.text("menu.status.ready"))"
        }
    }

    private func statusTooltip() -> String {
        switch currentMenuMode() {
        case .pomodoro:
            return localizationManager.text("menu.tooltip.pomodoro_running")
        case .breakTime:
            return breakTooltip()
        case .countdown:
            return localizationManager.text("menu.tooltip.countdown_running")
        case .idle:
            return localizationManager.text("menu.tooltip.idle")
        }
    }

    private func currentMenuMode() -> MenuMode {
        let pomodoroState = appState.pomodoro.state
        let countdownState = appState.countdown.state

        // Countdown has higher display priority than Pomodoro.
        switch countdownState {
        case .running, .paused:
            return .countdown
        case .idle, .breakRunning, .breakPaused:
            break
        }

        switch pomodoroState {
        case .running, .paused:
            return .pomodoro
        case .breakRunning, .breakPaused:
            return .breakTime
        case .idle:
            return .idle
        }
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let pomodoroAvailability = pomodoroMenuActions(for: appState.pomodoro.state)
        menu.addItem(sectionHeader(title: pomodoroSectionTitle()))
        menu.addItem(actionItem(title: localizationManager.text("common.start"), action: #selector(startPomodoro), availability: pomodoroAvailability.start))
        menu.addItem(actionItem(
            title: pomodoroPauseTitle(),
            action: #selector(pausePomodoro),
            availability: pomodoroAvailability.pauseResume
        ))
        menu.addItem(actionItem(title: localizationManager.text("common.reset"), action: #selector(resetPomodoro), availability: pomodoroAvailability.reset))
        menu.addItem(.separator())
        menu.addItem(actionItem(
            title: localizationManager.text("menu.start_break"),
            action: #selector(startBreak),
            availability: pomodoroAvailability.startBreak
        ))
        menu.addItem(actionItem(
            title: localizationManager.text("menu.skip_break"),
            action: #selector(skipBreak),
            availability: pomodoroAvailability.skipBreak
        ))
        menu.addItem(.separator())

        let countdownAvailability = countdownMenuActions(for: appState.countdown.state)
        let countdownMenu = NSMenu()
        countdownMenu.addItem(actionItem(
            title: localizationManager.text("common.start"),
            action: #selector(startCountdown),
            availability: countdownAvailability.start
        ))
        countdownMenu.addItem(actionItem(
            title: countdownPauseTitle(),
            action: #selector(pauseCountdown),
            availability: countdownAvailability.pauseResume
        ))
        countdownMenu.addItem(actionItem(
            title: localizationManager.text("common.reset"),
            action: #selector(resetCountdown),
            availability: countdownAvailability.reset
        ))
        let countdownItem = NSMenuItem(title: localizationManager.text("timer.countdown"), action: nil, keyEquivalent: "")
        countdownItem.submenu = countdownMenu
        menu.addItem(countdownItem)
        menu.addItem(.separator())
        menu.addItem(actionItem(title: localizationManager.text("main.sidebar.flow"), action: #selector(openFlow)))
        menu.addItem(actionItem(title: localizationManager.text("main.sidebar.tasks"), action: #selector(openTasks)))
        menu.addItem(actionItem(title: localizationManager.text("main.sidebar.calendar"), action: #selector(openCalendar)))
        menu.addItem(.separator())
        menu.addItem(musicMenuItem())
        menu.addItem(.separator())
        menu.addItem(actionItem(title: localizationManager.text("menu.open_app"), action: #selector(openApp)))
        menu.addItem(actionItem(title: localizationManager.text("menu.quit"), action: #selector(quitApp)))

        statusItem.menu = menu
    }

    private func sectionHeader(title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func actionItem(
        title: String,
        action: Selector,
        availability: MenuActionAvailability = .enabled
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = availability.isEnabled
        return item
    }

    private func formattedTime(_ seconds: Int) -> String {
        let clampedSeconds = max(0, seconds)
        let minutes = clampedSeconds / 60
        let remaining = clampedSeconds % 60
        return String(format: "%02d:%02d", minutes, remaining)
    }

    private func pomodoroPauseTitle() -> String {
        switch appState.pomodoro.state {
        case .paused, .breakPaused:
            return localizationManager.text("menu.resume_with_icon")
        case .running, .breakRunning, .idle:
            return localizationManager.text("menu.pause_with_icon")
        }
    }

    private func pomodoroSectionTitle() -> String {
        switch appState.pomodoro.state {
        case .running, .paused:
            return localizationManager.text("menu.section.pomodoro_work")
        case .breakRunning, .breakPaused:
            return localizationManager.format("menu.section.pomodoro_break_format", breakMenuTitle())
        case .idle:
            return localizationManager.text("menu.section.pomodoro_timer")
        }
    }

    private func breakMenuTitle() -> String {
        appState.pomodoroMode == .longBreak
            ? localizationManager.text("timer.long_break")
            : localizationManager.text("timer.short_break")
    }

    private func breakTooltip() -> String {
        appState.pomodoroMode == .longBreak
            ? localizationManager.text("menu.tooltip.long_break_running")
            : localizationManager.text("menu.tooltip.break_running")
    }

    private func breakEmoji() -> String {
        appState.pomodoroMode == .longBreak ? "🌙" : "☕"
    }

    private func countdownPauseTitle() -> String {
        switch appState.countdown.state {
        case .paused:
            return localizationManager.text("menu.resume_with_icon")
        case .running, .idle, .breakRunning, .breakPaused:
            return localizationManager.text("menu.pause_with_icon")
        }
    }

    private func musicMenuItem() -> NSMenuItem {
        let musicMenu = NSMenu()
        musicMenu.addItem(actionItem(title: audioPlayPauseTitle(), action: #selector(toggleAudioPlayback)))
        musicMenu.addItem(.separator())

        let packsMenu = NSMenu()
        for pack in audioMixerStore.availablePacks {
            let item = NSMenuItem(title: pack.name, action: #selector(selectLofiPack(_:)), keyEquivalent: "")
            item.target = self
            item.state = pack.id == audioMixerStore.activePackID ? .on : .off
            item.representedObject = pack.id
            packsMenu.addItem(item)
        }
        let packsItem = NSMenuItem(title: localizationManager.text("audio.lofi_packs"), action: nil, keyEquivalent: "")
        packsItem.submenu = packsMenu
        musicMenu.addItem(packsItem)

        let cleanNoiseMenu = NSMenu()
        for sound in cleanNoiseTypes {
            let item = NSMenuItem(title: sound.displayName, action: #selector(selectCleanNoise(_:)), keyEquivalent: "")
            item.target = self
            item.state = currentAmbient == sound ? .on : .off
            item.representedObject = sound
            cleanNoiseMenu.addItem(item)
        }
        let cleanNoiseItem = NSMenuItem(title: localizationManager.text("audio.generated_noise"), action: nil, keyEquivalent: "")
        cleanNoiseItem.submenu = cleanNoiseMenu
        musicMenu.addItem(cleanNoiseItem)

        let musicItem = NSMenuItem(title: localizationManager.text("main.sidebar.audio_music"), action: nil, keyEquivalent: "")
        musicItem.submenu = musicMenu
        return musicItem
    }

    private var cleanNoiseTypes: [FocusSoundType] {
        [.white, .brown]
    }

    private var currentAmbient: FocusSoundType? {
        if case .ambient(let type) = audioSourceStore.audioSource {
            return type
        }
        return nil
    }

    private func audioPlayPauseTitle() -> String {
        if audioMixerStore.isPlaying || musicController.playbackState == .playing {
            return localizationManager.text("menu.pause_with_icon")
        }
        return localizationManager.text("menu.play_with_icon")
    }

    private func pomodoroMenuActions(for state: TimerState) -> PomodoroMenuActionAvailability {
        switch state {
        case .idle:
            return PomodoroMenuActionAvailability(
                start: .enabled,
                pauseResume: .disabled,
                reset: .enabled,
                startBreak: .disabled,
                skipBreak: .disabled
            )
        case .running:
            return PomodoroMenuActionAvailability(
                start: .disabled,
                pauseResume: .enabled,
                reset: .enabled,
                startBreak: .enabled,
                skipBreak: .disabled
            )
        case .paused:
            return PomodoroMenuActionAvailability(
                start: .disabled,
                pauseResume: .enabled,
                reset: .enabled,
                startBreak: .enabled,
                skipBreak: .disabled
            )
        case .breakRunning:
            return PomodoroMenuActionAvailability(
                start: .disabled,
                pauseResume: .enabled,
                reset: .enabled,
                startBreak: .disabled,
                skipBreak: .enabled
            )
        case .breakPaused:
            return PomodoroMenuActionAvailability(
                start: .disabled,
                pauseResume: .enabled,
                reset: .enabled,
                startBreak: .disabled,
                skipBreak: .enabled
            )
        }
    }

    private func countdownMenuActions(for state: TimerState) -> CountdownMenuActionAvailability {
        switch state {
        case .idle:
            return CountdownMenuActionAvailability(start: .enabled, pauseResume: .disabled, reset: .enabled)
        case .running:
            return CountdownMenuActionAvailability(start: .disabled, pauseResume: .enabled, reset: .enabled)
        case .paused:
            return CountdownMenuActionAvailability(start: .disabled, pauseResume: .enabled, reset: .enabled)
        case .breakRunning, .breakPaused:
            return CountdownMenuActionAvailability(start: .disabled, pauseResume: .disabled, reset: .enabled)
        }
    }

    @objc private func startPomodoro() {
        appState.startPomodoro()
    }

    @objc private func pausePomodoro() {
        appState.togglePomodoroPause()
    }

    @objc private func resetPomodoro() {
        appState.resetPomodoro()
    }

    @objc private func startBreak() {
        appState.startBreak()
    }

    @objc private func skipBreak() {
        appState.skipBreak()
    }

    @objc private func startCountdown() {
        appState.startCountdown()
    }

    @objc private func pauseCountdown() {
        appState.toggleCountdownPause()
    }

    @objc private func resetCountdown() {
        appState.resetCountdown()
    }

    @objc private func openApp() {
        openMainWindow()
    }

    // MARK: - Navigation (UI-only; no timer logic changes)
    @objc private func openFlow() {
        openMainWindow()
        NotificationCenter.default.post(name: .navigateToFlow, object: nil)
    }

    @objc private func openTasks() {
        openMainWindow()
        NotificationCenter.default.post(name: .navigateToTasks, object: nil)
    }

    @objc private func openCalendar() {
        openMainWindow()
        NotificationCenter.default.post(name: .navigateToCalendar, object: nil)
    }

    @objc private func toggleAudioPlayback() {
        if audioMixerStore.isPlaying {
            audioMixerStore.pause()
            return
        }

        if musicController.playbackState == .playing {
            audioSourceStore.togglePlayPause()
            return
        }

        if !audioMixerStore.selectedTracks.isEmpty || audioMixerStore.activePackID != nil {
            audioSourceStore.selectAmbient(.off)
            audioMixerStore.play()
            return
        }

        if musicController.currentFocusSound != .off {
            audioSourceStore.togglePlayPause()
        } else {
            audioSourceStore.selectAmbient(.white)
        }
    }

    @objc private func selectLofiPack(_ sender: NSMenuItem) {
        guard let packID = sender.representedObject as? String,
              let pack = audioMixerStore.availablePacks.first(where: { $0.id == packID }) else { return }
        audioSourceStore.selectAmbient(.off)
        audioMixerStore.selectPack(pack)
        audioMixerStore.play()
    }

    @objc private func selectCleanNoise(_ sender: NSMenuItem) {
        guard let sound = sender.representedObject as? FocusSoundType else { return }
        audioMixerStore.pause()
        audioSourceStore.selectAmbient(currentAmbient == sound ? .off : sound)
    }

    @objc private func quitApp() {
        quitHandler()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateTitleIfNeeded()
        rebuildMenu()
    }

    func shutdown() {
        titleTimer?.invalidate()
        titleTimer = nil
        cancellables.removeAll()
        NSStatusBar.system.removeStatusItem(statusItem)
        if let liveItem = Self.liveStatusItem, liveItem === statusItem {
            Self.liveStatusItem = nil
        }
    }
}
