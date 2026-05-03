//
//  CountdownTimerEngine.swift
//  Pomodoro
//
//  Created by Zhengyang Hu on 1/15/26.
//

import Combine
import Foundation

final class CountdownTimerEngine: ObservableObject {
    @Published private(set) var state: TimerState = .idle
    @Published private(set) var remainingSeconds: Int

    private var durationConfig: DurationConfig
    private let durationProvider: (DurationConfig) -> Int
    private var timer: Timer?

    init(
        durationConfig: DurationConfig = .standard,
        durationProvider: @escaping (DurationConfig) -> Int = { $0.countdownDuration }
    ) {
        self.durationConfig = durationConfig
        self.durationProvider = durationProvider
        let resolvedDuration = durationProvider(durationConfig)
        self.remainingSeconds = resolvedDuration
    }

    func updateConfiguration(durationConfig: DurationConfig) {
        self.durationConfig = durationConfig

        if state == .idle {
            remainingSeconds = duration
        }
    }

    func start() {
        guard state == .idle else { return }
        remainingSeconds = duration
        state = .running
        startTimer()
    }

    func pause() {
        switch state {
        case .running:
            state = .paused
            stopTimer()
        case .idle, .paused, .breakRunning, .breakPaused:
            return
        }
    }

    func resume() {
        switch state {
        case .paused:
            state = .running
            startTimer()
        case .idle, .running, .breakRunning, .breakPaused:
            return
        }
    }

    func reset() {
        stopTimer()
        state = .idle
        remainingSeconds = duration
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard remainingSeconds > 0 else {
            complete()
            return
        }

        remainingSeconds -= 1

        if remainingSeconds == 0 {
            complete()
        }
    }

    private func complete() {
        stopTimer()
        state = .idle
        remainingSeconds = duration
    }

    private var duration: Int {
        durationProvider(durationConfig)
    }
}

final class StopwatchTimerEngine: ObservableObject {
    @Published private(set) var state: TimerState = .idle
    @Published private(set) var elapsedSeconds: Int = 0
    @Published private(set) var laps: [Int] = []

    private var timer: Timer?

    func start() {
        guard state == .idle else { return }
        elapsedSeconds = 0
        laps = []
        state = .running
        startTimer()
    }

    func pause() {
        guard state == .running else { return }
        state = .paused
        stopTimer()
    }

    func resume() {
        guard state == .paused else { return }
        state = .running
        startTimer()
    }

    func reset() {
        stopTimer()
        state = .idle
        elapsedSeconds = 0
        laps = []
    }

    func lap() {
        guard elapsedSeconds > 0 else { return }
        switch state {
        case .running, .paused:
            laps.insert(elapsedSeconds, at: 0)
        case .idle, .breakRunning, .breakPaused:
            return
        }
    }

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.elapsedSeconds += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
