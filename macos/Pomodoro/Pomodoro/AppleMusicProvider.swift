//
//  AppleMusicProvider.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import AppKit
import Foundation

final class AppleMusicProvider: NowPlayingProvider {
    let sourceName = "Apple Music"

    func fetchState() async -> NowPlayingProviderState {
        let script = """
        set isRunning to (application "Music" is running)
        if not isRunning then
            return {false, false, "", "", missing value}
        end if
        tell application "Music"
            set playerState to player state
            if playerState is not playing then
                return {true, false, "", "", missing value}
            end if
            set trackName to name of current track
            set artistName to artist of current track
            set artworkData to data of artwork 1 of current track
            return {true, true, trackName, artistName, artworkData}
        end tell
        """

        guard let result = await AppleScriptRunner.run(script) else {
            return NowPlayingProviderState(isRunning: false, isPlaying: false, title: "", artist: "", artwork: nil)
        }

        let isRunning = result.boolean(at: 1) ?? false
        let isPlaying = result.boolean(at: 2) ?? false
        let title = result.string(at: 3) ?? ""
        let artist = result.string(at: 4) ?? ""
        let artworkData = result.data(at: 5)
        let artwork = artworkData.flatMap { NSImage(data: $0) }

        return NowPlayingProviderState(
            isRunning: isRunning,
            isPlaying: isPlaying,
            title: title,
            artist: artist,
            artwork: artwork
        )
    }

    func playPause() async {
        let script = """
        if application "Music" is running then
            tell application "Music" to playpause
        end if
        """
        _ = await AppleScriptRunner.run(script)
    }

    func nextTrack() async {
        let script = """
        if application "Music" is running then
            tell application "Music" to next track
        end if
        """
        _ = await AppleScriptRunner.run(script)
    }

    func previousTrack() async {
        let script = """
        if application "Music" is running then
            tell application "Music" to previous track
        end if
        """
        _ = await AppleScriptRunner.run(script)
    }
}
