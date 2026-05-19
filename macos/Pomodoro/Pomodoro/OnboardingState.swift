//
//  OnboardingState.swift
//  Pomodoro
//
//  Created by OpenAI on 2025-02-01.
//

import Foundation
import Combine

@MainActor
final class OnboardingState: ObservableObject {
    @Published var isPresented: Bool
    @Published var needsSystemPermissions: Bool
    @Published var needsMenuBarTip: Bool
    @Published var eventKitRequestCalled: Bool

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        let completed = userDefaults.bool(forKey: DefaultsKey.onboardingCompleted)
        let permissionsPrompted = userDefaults.bool(forKey: DefaultsKey.calendarPermissionsPrompted)
        let menuTipSeen = userDefaults.bool(forKey: DefaultsKey.menuBarTipSeen)
        let requestCalled = userDefaults.bool(forKey: DefaultsKey.eventKitRequestCalled)

        let needsSystemPermissions = !permissionsPrompted
        let needsMenuBarTip = !menuTipSeen

        self.needsSystemPermissions = needsSystemPermissions
        self.needsMenuBarTip = needsMenuBarTip
        self.eventKitRequestCalled = requestCalled
        self.isPresented = !completed || needsSystemPermissions || needsMenuBarTip || !requestCalled
    }

    func markCompleted() {
        guard isPresented || needsSystemPermissions || needsMenuBarTip || !eventKitRequestCalled else { return }
        isPresented = false
        needsSystemPermissions = false
        needsMenuBarTip = false
        eventKitRequestCalled = true
        userDefaults.set(true, forKey: DefaultsKey.onboardingCompleted)
        userDefaults.set(true, forKey: DefaultsKey.calendarPermissionsPrompted)
        userDefaults.set(true, forKey: DefaultsKey.menuBarTipSeen)
        userDefaults.set(true, forKey: DefaultsKey.eventKitRequestCalled)
    }

    func reopen() {
        isPresented = true
    }

    func markPermissionsPrompted() {
        needsSystemPermissions = false
        userDefaults.set(true, forKey: DefaultsKey.calendarPermissionsPrompted)
    }

    func markMenuBarTipSeen() {
        needsMenuBarTip = false
        userDefaults.set(true, forKey: DefaultsKey.menuBarTipSeen)
    }

    func markEventKitRequestCalled() {
        eventKitRequestCalled = true
        userDefaults.set(true, forKey: DefaultsKey.eventKitRequestCalled)
    }

    private enum DefaultsKey {
        static let onboardingCompleted = "onboarding.completed"
        static let calendarPermissionsPrompted = "onboarding.calendarPermissionsPrompted"
        static let menuBarTipSeen = "onboarding.menuBarTipSeen"
        static let eventKitRequestCalled = "onboarding.eventKitRequestCalled"
    }
}
