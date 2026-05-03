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
    let fileURL: URL?

    init(
        id: String,
        packID: String,
        packName: String,
        title: String,
        relativePath: String,
        symbolName: String,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.packID = packID
        self.packName = packName
        self.title = title
        self.relativePath = relativePath
        self.symbolName = symbolName
        self.fileURL = fileURL
    }
}

struct LofiAudioPack: Identifiable, Hashable {
    let id: String
    let name: String
    let mood: String
    let symbolName: String
    let tracks: [LofiAudioTrack]

    var isCustom: Bool {
        id.hasPrefix("custom-")
    }
}

enum AudioMixerFocusMode: String, CaseIterable {
    case workspace
    case flow
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
    @Published private(set) var customPacks: [LofiAudioPack] = []
    @Published private(set) var lastCustomPackImportMessage: String?
    @Published private(set) var isPlaying = false
    @Published var trackVolumes: [String: Double] = [:] {
        didSet { applyVolumes() }
    }

    private struct CustomPackRecord: Codable, Equatable {
        let id: String
        var name: String
        let bookmarkData: Data?
        let fallbackPath: String
    }

    private var players: [String: AVAudioPlayer] = [:]
    private var customPackRecords: [CustomPackRecord] = []
    private var securityScopedFolderURLs: [String: URL] = [:]
    private let userDefaults: UserDefaults
    private let defaultVolume: Double = 0.45
    private let supportedCustomAudioExtensions: Set<String> = ["aac", "aif", "aiff", "caf", "m4a", "mp3", "wav"]
    private let customPackRecordsKey = "audioMixer.customPackRecords.v1"
    private let lastPackByFocusModeKeyPrefix = "audioMixer.lastPack."

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadPersistedCustomPacks()
        restoreLastPack(for: .workspace)
    }

    deinit {
        for url in securityScopedFolderURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    var availablePacks: [LofiAudioPack] {
        Self.packs + customPacks
    }

    var selectedTracks: [LofiAudioTrack] {
        availablePacks.flatMap(\.tracks).filter { selectedTrackIDs.contains($0.id) }
    }

    var nowPlayingTitle: String {
        if let activePackID,
           let pack = availablePacks.first(where: { $0.id == activePackID }),
           selectedTracks.allSatisfy({ $0.packID == activePackID }) {
            return pack.name
        }
        return "Custom Mix"
    }

    var nowPlayingSubtitle: String {
        "\(selectedTracks.count) audio layer\(selectedTracks.count == 1 ? "" : "s")"
    }

    func selectPack(_ pack: LofiAudioPack, for focusMode: AudioMixerFocusMode = .workspace) {
        activePackID = pack.id
        rememberLastPack(pack.id, for: focusMode)
        selectedTrackIDs = []
        for track in pack.tracks where trackVolumes[track.id] == nil {
            trackVolumes[track.id] = defaultVolume
        }
        for track in pack.tracks where preparePlayer(for: track) != nil {
            selectedTrackIDs.insert(track.id)
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
            trackVolumes[track.id] = trackVolumes[track.id] ?? defaultVolume
            guard preparePlayer(for: track) != nil else {
                trackVolumes.removeValue(forKey: track.id)
                return
            }
            selectedTrackIDs.insert(track.id)
            if isPlaying {
                players[track.id]?.play()
            }
        }
        updateActivePackFromSelection()
    }

    func setVolume(_ value: Double, for track: LofiAudioTrack) {
        trackVolumes[track.id] = max(0, min(value, 1))
    }

    func restoreLastPack(for focusMode: AudioMixerFocusMode) {
        guard let packID = userDefaults.string(forKey: lastPackKey(for: focusMode)),
              let pack = availablePacks.first(where: { $0.id == packID }) else {
            return
        }
        selectPack(pack, for: focusMode)
    }

    func loadCustomPack(from folderURL: URL, for focusMode: AudioMixerFocusMode = .workspace) throws {
        let didAccess = folderURL.startAccessingSecurityScopedResource()

        do {
            let scan = try scanCustomAudioFolder(folderURL)

            guard !scan.supportedFileURLs.isEmpty else {
                folderURL.stopAccessingSecurityScopedResource()
                throw AudioMixerError.noSupportedAudio(
                    unsupportedCount: scan.unsupportedCount,
                    supportedExtensions: supportedExtensionsDescription
                )
            }

            let folderName = folderURL.lastPathComponent.isEmpty ? "Your Pack" : folderURL.lastPathComponent
            let packID = "custom-\(folderURL.standardizedFileURL.path)"
            let pack = makeCustomPack(id: packID, name: folderName, fileURLs: scan.supportedFileURLs)

            upsertCustomPack(pack, folderURL: folderURL)
            selectPack(pack, for: focusMode)

            let customTrackIDs = Set(pack.tracks.map(\.id))
            guard !selectedTrackIDs.intersection(customTrackIDs).isEmpty else {
                removeCustomPack(pack)
                throw AudioMixerError.noPlayableAudio(packName: pack.name)
            }

            persistCustomPackRecord(
                id: pack.id,
                name: pack.name,
                folderURL: folderURL
            )
            let ignored = scan.unsupportedCount
            lastCustomPackImportMessage = ignored > 0
                ? "Loaded \(pack.tracks.count) track\(pack.tracks.count == 1 ? "" : "s"). Ignored \(ignored) unsupported file\(ignored == 1 ? "" : "s")."
                : "Loaded \(pack.tracks.count) track\(pack.tracks.count == 1 ? "" : "s")."
        } catch {
            if didAccess {
                folderURL.stopAccessingSecurityScopedResource()
            }
            throw error
        }
    }

    func renameCustomPack(_ pack: LofiAudioPack, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard pack.isCustom, !name.isEmpty else { return }
        guard let index = customPacks.firstIndex(where: { $0.id == pack.id }) else { return }

        let renamedTracks = customPacks[index].tracks.map { track in
            LofiAudioTrack(
                id: track.id,
                packID: track.packID,
                packName: name,
                title: track.title,
                relativePath: track.relativePath,
                symbolName: track.symbolName,
                fileURL: track.fileURL
            )
        }
        customPacks[index] = LofiAudioPack(
            id: pack.id,
            name: name,
            mood: customPacks[index].mood,
            symbolName: customPacks[index].symbolName,
            tracks: renamedTracks
        )
        if let recordIndex = customPackRecords.firstIndex(where: { $0.id == pack.id }) {
            customPackRecords[recordIndex].name = name
            saveCustomPackRecords()
        }
    }

    func removeCustomPack(_ pack: LofiAudioPack) {
        guard pack.isCustom else { return }
        removeCustomPack(id: pack.id)
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
            if let activePackID, let activePack = availablePacks.first(where: { $0.id == activePackID }) {
                selectPack(activePack)
            } else if let firstPack = availablePacks.first {
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
        let removedIDs = players.keys.filter { !selected.contains($0) }
        for id in removedIDs {
            players[id]?.stop()
            players.removeValue(forKey: id)
        }
        for track in selectedTracks {
            if preparePlayer(for: track) == nil {
                selectedTrackIDs.remove(track.id)
                trackVolumes.removeValue(forKey: track.id)
            }
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
        guard let url = track.fileURL ?? Bundle.main.url(forResource: track.relativePath, withExtension: nil, subdirectory: "AudioAssets") else {
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
        for pack in availablePacks {
            let packIDs = Set(pack.tracks.map(\.id))
            if selectedTrackIDs == packIDs {
                activePackID = pack.id
                return
            }
        }
        activePackID = nil
    }

    private func supportedCustomFileURLs(in folderURL: URL) throws -> [URL] {
        try scanCustomAudioFolder(folderURL).supportedFileURLs
    }

    private func scanCustomAudioFolder(_ folderURL: URL) throws -> (supportedFileURLs: [URL], unsupportedCount: Int) {
        let allFileURLs = try FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
        .filter { fileURL in
            (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }

        let supportedFileURLs = allFileURLs
            .filter { supportedCustomAudioExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedStandardCompare(rhs.lastPathComponent) == .orderedAscending
            }

        return (supportedFileURLs, allFileURLs.count - supportedFileURLs.count)
    }

    private func makeCustomPack(id: String, name: String, fileURLs: [URL]) -> LofiAudioPack {
        let tracks = fileURLs.map { fileURL in
            LofiAudioTrack(
                id: "custom-\(fileURL.standardizedFileURL.path)",
                packID: id,
                packName: name,
                title: fileURL.deletingPathExtension().lastPathComponent,
                relativePath: "",
                symbolName: "waveform",
                fileURL: fileURL
            )
        }

        return LofiAudioPack(
            id: id,
            name: name,
            mood: "\(tracks.count) track\(tracks.count == 1 ? "" : "s")",
            symbolName: "folder.fill",
            tracks: tracks
        )
    }

    private func upsertCustomPack(_ pack: LofiAudioPack, folderURL: URL) {
        if let existingIndex = customPacks.firstIndex(where: { $0.id == pack.id }) {
            stopCustomPack(customPacks[existingIndex])
            customPacks[existingIndex] = pack
        } else {
            customPacks.append(pack)
        }
        if let oldURL = securityScopedFolderURLs[pack.id], oldURL != folderURL {
            oldURL.stopAccessingSecurityScopedResource()
        }
        securityScopedFolderURLs[pack.id] = folderURL
    }

    private func removeCustomPack(id: String) {
        guard let pack = customPacks.first(where: { $0.id == id }) else { return }
        stopCustomPack(pack)
        customPacks.removeAll { $0.id == id }
        customPackRecords.removeAll { $0.id == id }
        saveCustomPackRecords()
        if let folderURL = securityScopedFolderURLs.removeValue(forKey: id) {
            folderURL.stopAccessingSecurityScopedResource()
        }
        for mode in AudioMixerFocusMode.allCases where userDefaults.string(forKey: lastPackKey(for: mode)) == id {
            userDefaults.removeObject(forKey: lastPackKey(for: mode))
        }
    }

    private func stopCustomPack(_ customPack: LofiAudioPack) {
        let customTrackIDs = Set(customPack.tracks.map(\.id))
        selectedTrackIDs.subtract(customTrackIDs)
        for id in customTrackIDs {
            players[id]?.stop()
            players.removeValue(forKey: id)
            trackVolumes.removeValue(forKey: id)
        }
        if activePackID == customPack.id {
            activePackID = nil
        }
    }

    private func loadPersistedCustomPacks() {
        guard let data = userDefaults.data(forKey: customPackRecordsKey),
              let records = try? JSONDecoder().decode([CustomPackRecord].self, from: data) else {
            return
        }

        var validRecords: [CustomPackRecord] = []
        for record in records {
            guard let folderURL = resolveFolderURL(for: record) else { continue }
            guard let fileURLs = try? supportedCustomFileURLs(in: folderURL), !fileURLs.isEmpty else { continue }
            let pack = makeCustomPack(id: record.id, name: record.name, fileURLs: fileURLs)
            customPacks.append(pack)
            validRecords.append(record)
            securityScopedFolderURLs[record.id] = folderURL
        }
        customPackRecords = validRecords
        if validRecords != records {
            saveCustomPackRecords()
        }
    }

    private func resolveFolderURL(for record: CustomPackRecord) -> URL? {
        if let bookmarkData = record.bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                _ = url.startAccessingSecurityScopedResource()
                return url
            }
        }

        let url = URL(fileURLWithPath: record.fallbackPath)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    private func persistCustomPackRecord(id: String, name: String, folderURL: URL) {
        let bookmarkData = try? folderURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let record = CustomPackRecord(
            id: id,
            name: name,
            bookmarkData: bookmarkData,
            fallbackPath: folderURL.path
        )
        if let index = customPackRecords.firstIndex(where: { $0.id == id }) {
            customPackRecords[index] = record
        } else {
            customPackRecords.append(record)
        }
        saveCustomPackRecords()
    }

    private func saveCustomPackRecords() {
        guard let data = try? JSONEncoder().encode(customPackRecords) else { return }
        userDefaults.set(data, forKey: customPackRecordsKey)
    }

    private func rememberLastPack(_ packID: String, for focusMode: AudioMixerFocusMode) {
        userDefaults.set(packID, forKey: lastPackKey(for: focusMode))
    }

    private func lastPackKey(for focusMode: AudioMixerFocusMode) -> String {
        "\(lastPackByFocusModeKeyPrefix)\(focusMode.rawValue)"
    }

    private var supportedExtensionsDescription: String {
        supportedCustomAudioExtensions.sorted().joined(separator: ", ")
    }
}

enum AudioMixerError: LocalizedError {
    case noSupportedAudio(unsupportedCount: Int, supportedExtensions: String)
    case noPlayableAudio(packName: String)

    var errorDescription: String? {
        switch self {
        case .noSupportedAudio(let unsupportedCount, let supportedExtensions):
            if unsupportedCount > 0 {
                return "That folder contains \(unsupportedCount) unsupported file\(unsupportedCount == 1 ? "" : "s"). Supported audio formats: \(supportedExtensions)."
            }
            return "No audio files were found. Supported formats: \(supportedExtensions)."
        case .noPlayableAudio(let packName):
            return "\"\(packName)\" was found, but none of its supported audio files could be loaded."
        }
    }
}
