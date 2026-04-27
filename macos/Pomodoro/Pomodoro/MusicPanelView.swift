//
//  MusicPanelView.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import SwiftUI

@MainActor
struct MusicPanelView: View {
    @EnvironmentObject private var localMusicPlayer: LocalMusicPlayer
    @EnvironmentObject private var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if localMusicPlayer.hasFiles {
                HStack(spacing: 12) {
                    Button(action: { localMusicPlayer.previous() }) {
                        Image(systemName: "backward.fill")
                    }
                    .orchestranaButton(.subtle)

                    Button(action: togglePlayback) {
                        Image(systemName: localMusicPlayer.isPlaying ? "pause.fill" : "play.fill")
                    }
                    .orchestranaButton(.subtle)

                    Button(action: { localMusicPlayer.next() }) {
                        Image(systemName: "forward.fill")
                    }
                    .orchestranaButton(.subtle)
                }
                .font(.system(size: 18, weight: .semibold))

                Text(localMusicPlayer.currentTrackName ?? localizationManager.text("audio.unknown_track"))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(.secondary)
            } else {
                Button(localizationManager.text("audio.choose_music")) {
                    localMusicPlayer.loadFiles()
                }
                .orchestranaButton(.primary)
            }
        }
        .padding(20)
        .frame(minWidth: 280)
    }

    private func togglePlayback() {
        if localMusicPlayer.isPlaying {
            localMusicPlayer.pause()
        } else {
            localMusicPlayer.play()
        }
    }
}

#if DEBUG && PREVIEWS_ENABLED
#Preview {
    MainActor.assumeIsolated {
        MusicPanelView()
            .environmentObject(LocalMusicPlayer())
    }
}
#endif
