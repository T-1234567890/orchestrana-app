//
//  MusicController.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import AppKit
import Combine
import MediaPlayer
import SwiftUI
import Foundation

// Backfill MPNowPlaying notifications for macOS SDKs that omit the symbols.
private extension Notification.Name {
    static let MPNowPlayingInfoCenterNowPlayingInfoDidChange = Notification.Name("MPNowPlayingInfoCenterNowPlayingInfoDidChange")
    static let MPNowPlayingInfoCenterPlaybackStateDidChange = Notification.Name("MPNowPlayingInfoCenterPlaybackStateDidChange")
}

enum MusicPlaybackState: String {
    case idle
    case playing
    case paused
}

enum MusicSource {
    case none
    case focusSound
}

enum MediaSource: String {
    case appleMusic = "Apple Music"
    case unknown = "External Audio"

    var displayName: String {
        switch self {
        case .appleMusic:
            return rawValue
        case .unknown:
            return LocalizationManager.shared.text("audio.external_audio")
        }
    }
}

struct ExternalMedia {
    let title: String
    let artist: String
    let album: String?
    let artwork: NSImage?
    let source: MediaSource
}

enum AudioSource {
    case off
    case ambient(type: FocusSoundType)
    case external(ExternalMedia)
}

/// Observable external audio state dedicated to Apple Music detection.
enum ExternalAudioState {
    case none
    case appleMusic(title: String, artist: String, artworkData: Data?)
}

enum FocusSoundType: String, CaseIterable, Identifiable {
    case off
    case white
    case brown
    case rain
    case wind
    // Extendable: previously defined ambient sounds remain available through this list.

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .off:
            return LocalizationManager.shared.text("audio.sound.off")
        case .white:
            return LocalizationManager.shared.text("audio.sound.white")
        case .brown:
            return LocalizationManager.shared.text("audio.sound.brown")
        case .rain:
            return LocalizationManager.shared.text("audio.sound.rain")
        case .wind:
            return LocalizationManager.shared.text("audio.sound.wind")
        }
    }
}

final class MusicController: ObservableObject {
    @Published private(set) var playbackState: MusicPlaybackState
    @Published private(set) var activeSource: MusicSource
    @Published var currentFocusSound: FocusSoundType
    @Published var focusVolume: Float

    private let userDefaults: UserDefaults
    private let ambientNoiseEngine: AmbientNoiseEngine

    init(
        userDefaults: UserDefaults = .standard,
        ambientNoiseEngine: AmbientNoiseEngine
    ) {
        self.userDefaults = userDefaults
        self.ambientNoiseEngine = ambientNoiseEngine
        let storedFocus = FocusSoundType(rawValue: userDefaults.string(forKey: "music.focusSound") ?? "") ?? .off
        let storedPlayback = MusicPlaybackState(rawValue: userDefaults.string(forKey: "music.playbackState") ?? "") ?? .idle
        let storedVolume = userDefaults.object(forKey: "music.focusVolume") as? Float ?? 0.25
        currentFocusSound = storedFocus
        playbackState = storedPlayback
        activeSource = storedFocus == .off ? .none : .focusSound
        focusVolume = max(0, min(storedVolume, 1))
        if storedFocus != .off, storedPlayback == .playing {
            startFocusSound(storedFocus)
        }
        ambientNoiseEngine.setVolume(focusVolume)
    }

    func play() {
        guard currentFocusSound != .off else {
            playbackState = .idle
            activeSource = .none
            persistState()
            return
        }
        startFocusSound(currentFocusSound)
    }

    func pause() {
        stopFocusSoundPlayback(keepSelection: true)
        playbackState = activeSource == .focusSound ? .paused : .idle
        persistState()
    }

    func next() {
        stopFocusSoundPlayback(keepSelection: true)
    }

    func previous() {
        stopFocusSoundPlayback(keepSelection: true)
    }

    func startFocusSound(_ type: FocusSoundType) {
        guard type != .off else {
            stopFocusSound()
            return
        }
        if currentFocusSound == type, playbackState == .playing, activeSource == .focusSound {
            ambientNoiseEngine.setVolume(focusVolume)
            return
        }
        currentFocusSound = type
        ambientNoiseEngine.setVolume(focusVolume)
        ambientNoiseEngine.play(type: type.ambientNoiseType)
        playbackState = .playing
        activeSource = .focusSound
        persistState()
    }

    func stopFocusSound() {
        stopFocusSoundPlayback(keepSelection: false)
        currentFocusSound = .off
        activeSource = .none
        playbackState = .idle
        persistState()
    }

    private func stopFocusSoundPlayback(keepSelection: Bool) {
        ambientNoiseEngine.stop()
        if !keepSelection {
            currentFocusSound = .off
        }
        if activeSource == .focusSound {
            activeSource = keepSelection ? .focusSound : .none
        }
    }

    private func persistState() {
        userDefaults.set(currentFocusSound.rawValue, forKey: "music.focusSound")
        userDefaults.set(playbackState.rawValue, forKey: "music.playbackState")
        userDefaults.set(focusVolume, forKey: "music.focusVolume")
    }

    func setFocusVolume(_ volume: Float) {
        let clamped = max(0, min(volume, 1))
        focusVolume = clamped
        ambientNoiseEngine.setVolume(clamped)
        persistState()
    }
}

/// Detects Apple Music playback via AppleScript polling (no private APIs).
/// Publishes current ExternalMedia and a detection flag in real time (~0.5s polling).
@MainActor
final class ExternalAudioMonitor: ObservableObject {
    @Published private(set) var media: ExternalMedia?
    @Published private(set) var playbackState: MPNowPlayingPlaybackState = .unknown
    @Published private(set) var externalMediaDetected: Bool = false
    @Published private(set) var externalState: ExternalAudioState = .none

    private var cancellables: Set<AnyCancellable> = []
    private var pollTask: Task<Void, Never>?
    private let appleMusicProvider = AppleMusicProvider()

    init() {
        startAppleMusicPolling()
    }

    deinit {
        pollTask?.cancel()
    }

    private func startAppleMusicPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refreshFromAppleMusic()
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
            }
        }
    }

    private func refreshFromAppleMusic() async {
        let state = await appleMusicProvider.fetchState()
        apply(appleMusicState: state)
    }

    private func apply(appleMusicState state: NowPlayingProviderState) {
        playbackState = state.isPlaying ? .playing : .paused

        guard state.isPlaying, !state.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            media = nil
            externalMediaDetected = false
            externalState = .none
            return
        }

        let external = ExternalMedia(
            title: state.title,
            artist: state.artist.isEmpty ? LocalizationManager.shared.text("audio.unknown_artist") : state.artist,
            album: nil,
            artwork: state.artwork,
            source: .appleMusic
        )
        media = external
        externalMediaDetected = true
        externalState = .appleMusic(
            title: state.title,
            artist: state.artist,
            artworkData: state.artwork?.tiffRepresentation
        )
    }
}

/// Lightweight controller to send play/pause to the detected external source.
@MainActor
final class ExternalPlaybackController {
    private let appleProvider = AppleMusicProvider()

    func togglePlayPause(for source: MediaSource) {
        switch source {
        case .appleMusic:
            Task { await appleProvider.playPause() }
        case .unknown:
            break
        }
    }
}

@MainActor
final class AudioSourceStore: ObservableObject {
    @Published private(set) var audioSource: AudioSource = .off
    @Published private(set) var externalMediaDetected: Bool = false
    @Published private(set) var externalMediaMetadata: ExternalMedia?

    private let musicController: MusicController
    private let externalMonitor: ExternalAudioMonitor
    private let externalController: ExternalPlaybackController
    private var cancellables: Set<AnyCancellable> = []
    private var pendingSyncTask: Task<Void, Never>?

    init(
        musicController: MusicController,
        externalMonitor: ExternalAudioMonitor,
        externalController: ExternalPlaybackController
    ) {
        self.musicController = musicController
        self.externalMonitor = externalMonitor
        self.externalController = externalController

        musicController.$playbackState
            .combineLatest(musicController.$currentFocusSound)
            .sink { [weak self] _, _ in
                self?.scheduleStateSync()
            }
            .store(in: &cancellables)

        externalMonitor.$media
            .sink { [weak self] _ in
                self?.scheduleStateSync()
            }
            .store(in: &cancellables)

        externalMonitor.$playbackState
            .sink { [weak self] _ in
                self?.scheduleStateSync()
            }
            .store(in: &cancellables)

        scheduleStateSync()
    }

    // MARK: - Public controls

    func togglePlayPause() {
        switch audioSource {
        case .external(let media):
            externalController.togglePlayPause(for: media.source)
        case .ambient:
            if musicController.playbackState == .playing {
                musicController.pause()
            } else {
                musicController.play()
            }
        case .off:
            break
        }
    }

    func selectAmbient(_ type: FocusSoundType) {
        // External source is read-only; do not override while external is active.
        guard externalMonitor.playbackState != .playing else { return }
        if type == .off {
            musicController.stopFocusSound()
            audioSource = .off
        } else {
            musicController.startFocusSound(type)
            audioSource = .ambient(type: type)
        }
    }

    func setVolume(_ value: Float) {
        switch audioSource {
        case .ambient:
            musicController.setFocusVolume(value)
        case .external, .off:
            break
        }
    }

    private func scheduleStateSync() {
        pendingSyncTask?.cancel()
        pendingSyncTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.syncStateFromSources()
        }
    }

    private func syncStateFromSources() {
        let nextExternalDetected = externalMonitor.externalMediaDetected
        let nextExternalMedia = externalMonitor.media

        let nextSource: AudioSource
        if externalMonitor.playbackState == .playing, let media = externalMonitor.media {
            if musicController.playbackState == .playing {
                Task { @MainActor [weak self] in
                    await Task.yield()
                    self?.musicController.pause()
                }
            }
            nextSource = .external(media)
        } else if musicController.currentFocusSound != .off {
            nextSource = .ambient(type: musicController.currentFocusSound)
        } else {
            nextSource = .off
        }

        if externalMediaDetected != nextExternalDetected {
            externalMediaDetected = nextExternalDetected
        }

        if !mediaEquals(externalMediaMetadata, nextExternalMedia) {
            externalMediaMetadata = nextExternalMedia
        }

        if !audioSourceEquals(audioSource, nextSource) {
            audioSource = nextSource
        }
    }

    deinit {
        pendingSyncTask?.cancel()
    }

    private func mediaEquals(_ lhs: ExternalMedia?, _ rhs: ExternalMedia?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (left?, right?):
            return left.title == right.title
                && left.artist == right.artist
                && left.album == right.album
                && left.source == right.source
        default:
            return false
        }
    }

    private func audioSourceEquals(_ lhs: AudioSource, _ rhs: AudioSource) -> Bool {
        switch (lhs, rhs) {
        case (.off, .off):
            return true
        case let (.ambient(leftType), .ambient(rightType)):
            return leftType == rightType
        case let (.external(leftMedia), .external(rightMedia)):
            return mediaEquals(leftMedia, rightMedia)
        default:
            return false
        }
    }
}

private extension FocusSoundType {
    var ambientNoiseType: AmbientNoiseEngine.NoiseType {
        switch self {
        case .off:
            return .off
        case .white:
            return .white
        case .brown:
            return .brown
        case .rain:
            return .rain
        case .wind:
            return .wind
        }
    }
}
