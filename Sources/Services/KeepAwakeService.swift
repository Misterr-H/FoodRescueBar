import Foundation

#if os(macOS)
import IOKit.pwr_mgt
import AppKit
#endif

/// Prevents idle sleep while Food Rescue monitoring is active (macOS).
///
/// Note: closing a MacBook lid often still forces sleep (especially on battery).
/// Keep-awake helps with idle display sleep and some clamshell/AC setups.
@MainActor
final class KeepAwakeService {
    static let shared = KeepAwakeService()

    #if os(macOS)
    private var assertionID: IOPMAssertionID = 0
    private var hasAssertion = false
    private var activity: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

    var onSystemDidWake: (() -> Void)?
    var onSystemWillSleep: (() -> Void)?
    #endif

    private init() {
        #if os(macOS)
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onSystemWillSleep?()
            }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onSystemDidWake?()
            }
        }
        #endif
    }

    deinit {
        #if os(macOS)
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        #endif
    }

    func start(reason: String = "FoodRescueBar is listening for Food Rescue deals") {
        #if os(macOS)
        stop()

        // Stronger assertion: try to prevent system idle sleep
        let type = kIOPMAssertionTypePreventUserIdleSystemSleep as CFString
        let result = IOPMAssertionCreateWithName(
            type,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )
        hasAssertion = (result == kIOReturnSuccess)

        // Also mark process as user-initiated so App Nap is less aggressive
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: reason
        )
        #endif
    }

    func stop() {
        #if os(macOS)
        if hasAssertion {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
            hasAssertion = false
        }
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        #endif
    }

    var isActive: Bool {
        #if os(macOS)
        return hasAssertion || activity != nil
        #else
        return false
        #endif
    }
}
