import AVFoundation
import Combine
import Foundation

struct LofiAudioTrack: Identifiable, Hashable {
    let id: String
    let packID: String
    let packName: String
    let title: String
    let relativePath: String
    let symbolName: String
}

struct LofiAudioPack: Identifiable, Hashable {
    let id: String
    let name: String
    let mood: String
    let symbolName: String
    let tracks: [LofiAudioTrack]
}

@MainActor
final class AudioMixerStore: ObservableObject {
    static let packs: [LofiAudioPack] = [
        LofiAudioPack(
            id: "coffee-shop",
            name: "Coffee Shop",
            mood: "Cafe focus",
            symbolName: "cup.and.saucer.fill",
            tracks: [
                LofiAudioTrack(id: "coffee-shop-room", packID: "coffee-shop", packName: "Coffee Shop", title: "Cafe Room", relativePath: "Coffee Shop/403066__awenaudio__ms-stereo-coffee-shop-6-people-low-chatter-refrigerator-barista-making-milk-shake-customers-entering-3.m4a", symbolName: "person.2.wave.2.fill"),
                LofiAudioTrack(id: "coffee-shop-chatter", packID: "coffee-shop", packName: "Coffee Shop", title: "Low Chatter", relativePath: "Coffee Shop/457895__bvsowle__coffee-shop-chatter.m4a", symbolName: "bubble.left.and.bubble.right.fill"),
                LofiAudioTrack(id: "coffee-shop-lofi", packID: "coffee-shop", packName: "Coffee Shop", title: "B Minor Lofi", relativePath: "Coffee Shop/591327__seth_makes_sounds__basic-lofi-loop-b-minor-90-bpm.wav", symbolName: "music.note")
            ]
        ),
        LofiAudioPack(
            id: "forest",
            name: "Forest",
            mood: "Cabin calm",
            symbolName: "tree.fill",
            tracks: [
                LofiAudioTrack(id: "forest-jungle", packID: "forest", packName: "Forest", title: "Forest Room", relativePath: "Forest/123087__itsmrjack__jungle_1.m4a", symbolName: "leaf.fill"),
                LofiAudioTrack(id: "forest-pad", packID: "forest", packName: "Forest", title: "Jungle Pad", relativePath: "Forest/449909__analogist__jungle-pad.m4a", symbolName: "waveform"),
                LofiAudioTrack(id: "forest-fireplace", packID: "forest", packName: "Forest", title: "Fireplace", relativePath: "Forest/81801__silencyo__silencyo_cc_fire-in-fireplace_close-up_reverberant2.m4a", symbolName: "flame.fill")
            ]
        ),
        LofiAudioPack(
            id: "rain-desk",
            name: "Rain Desk",
            mood: "Deep work",
            symbolName: "cloud.rain.fill",
            tracks: [
                LofiAudioTrack(id: "rain-desk-keyboard", packID: "rain-desk", packName: "Rain Desk", title: "Keyboard", relativePath: "Rain Desk/450282__stu556__mechanical-keyboard-typing-treble-version.m4a", symbolName: "keyboard.fill"),
                LofiAudioTrack(id: "rain-desk-room", packID: "rain-desk", packName: "Rain Desk", title: "Room Hail", relativePath: "Rain Desk/503282__khenshom__room-tone-with-hail-falling-outside.m4a", symbolName: "house.fill"),
                LofiAudioTrack(id: "rain-desk-rain", packID: "rain-desk", packName: "Rain Desk", title: "Soft Rain", relativePath: "Rain Desk/757276__garuda1982__gentle-rain-on-leaves-with-soft-wind-and-suburban-ambience.m4a", symbolName: "cloud.rain.fill")
            ]
        )
    ]

    @Published private(set) var selectedTrackIDs: Set<String> = []
    @Published private(set) var activePackID: String?
    @Published private(set) var isPlaying = false
    @Published var trackVolumes: [String: Double] = [:] {
        didSet { applyVolumes() }
    }

    private var players: [String: AVAudioPlayer] = [:]
    private let defaultVolume: Double = 0.45

    var selectedTracks: [LofiAudioTrack] {
        Self.packs.flatMap(\.tracks).filter { selectedTrackIDs.contains($0.id) }
    }

    var nowPlayingTitle: String {
        if let activePackID,
           let pack = Self.packs.first(where: { $0.id == activePackID }),
           selectedTracks.allSatisfy({ $0.packID == activePackID }) {
            return pack.name
        }
        return "Custom Mix"
    }

    var nowPlayingSubtitle: String {
        "\(selectedTracks.count) audio layer\(selectedTracks.count == 1 ? "" : "s")"
    }

    func selectPack(_ pack: LofiAudioPack) {
        activePackID = pack.id
        selectedTrackIDs = Set(pack.tracks.map(\.id))
        for track in pack.tracks where trackVolumes[track.id] == nil {
            trackVolumes[track.id] = defaultVolume
        }
        rebuildPlayers()
        if isPlaying {
            playSelectedTracks()
        }
    }

    func toggleTrack(_ track: LofiAudioTrack) {
        if selectedTrackIDs.contains(track.id) {
            selectedTrackIDs.remove(track.id)
            players[track.id]?.stop()
            players.removeValue(forKey: track.id)
        } else {
            selectedTrackIDs.insert(track.id)
            trackVolumes[track.id] = trackVolumes[track.id] ?? defaultVolume
            _ = preparePlayer(for: track)
            if isPlaying {
                players[track.id]?.play()
            }
        }
        updateActivePackFromSelection()
    }

    func setVolume(_ value: Double, for track: LofiAudioTrack) {
        trackVolumes[track.id] = max(0, min(value, 1))
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard !selectedTrackIDs.isEmpty else {
            if let firstPack = Self.packs.first {
                selectPack(firstPack)
            }
            return
        }
        isPlaying = true
        playSelectedTracks()
    }

    func pause() {
        isPlaying = false
        for player in players.values {
            player.pause()
        }
    }

    func stop() {
        isPlaying = false
        for player in players.values {
            player.stop()
            player.currentTime = 0
        }
    }

    private func rebuildPlayers() {
        let selected = Set(selectedTracks.map(\.id))
        for (id, player) in players where !selected.contains(id) {
            player.stop()
            players.removeValue(forKey: id)
        }
        for track in selectedTracks {
            _ = preparePlayer(for: track)
        }
        applyVolumes()
    }

    private func playSelectedTracks() {
        rebuildPlayers()
        for player in players.values {
            if !player.isPlaying {
                player.play()
            }
        }
    }

    private func preparePlayer(for track: LofiAudioTrack) -> AVAudioPlayer? {
        if let player = players[track.id] {
            return player
        }
        guard let url = Bundle.main.url(forResource: track.relativePath, withExtension: nil, subdirectory: "AudioAssets") else {
            return nil
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = Float(trackVolumes[track.id] ?? defaultVolume)
            player.prepareToPlay()
            players[track.id] = player
            return player
        } catch {
            return nil
        }
    }

    private func applyVolumes() {
        for (id, player) in players {
            player.volume = Float(trackVolumes[id] ?? defaultVolume)
        }
    }

    private func updateActivePackFromSelection() {
        for pack in Self.packs {
            let packIDs = Set(pack.tracks.map(\.id))
            if selectedTrackIDs == packIDs {
                activePackID = pack.id
                return
            }
        }
        activePackID = nil
    }
}
