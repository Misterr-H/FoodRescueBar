import Foundation
import UserNotifications
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import AudioToolbox
#endif

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private(set) var isAuthorized = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        registerCategories()
    }

    private func registerCategories() {
        let open = UNNotificationAction(
            identifier: "OPEN_ZOMATO",
            title: "Open Zomato",
            options: [.foreground]
        )
        let ack = UNNotificationAction(
            identifier: "ACKNOWLEDGE",
            title: "Acknowledge",
            options: []
        )
        let alarm = UNNotificationCategory(
            identifier: "FOOD_RESCUE_ALARM",
            actions: [open, ack],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let normal = UNNotificationCategory(
            identifier: "FOOD_RESCUE",
            actions: [open],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([alarm, normal])
    }

    func requestAuthorization() async {
        do {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                isAuthorized = granted
            } else {
                isAuthorized = settings.authorizationStatus == .authorized
                    || settings.authorizationStatus == .provisional
            }
            #if os(iOS)
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            #endif
        } catch {
            isAuthorized = false
        }
    }

    /// Ensure we have alert permission; returns false if denied.
    func ensureAuthorized() async -> Bool {
        await requestAuthorization()
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        #if os(macOS)
        if settings.authorizationStatus == .denied {
            // Help user enable notifications for a menu-bar app
            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
        }
        #endif
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Legacy soft alert path (used for non-cancel events if needed).
    func sendFoodRescueAlert(for event: RescueEvent, playSound: Bool) {
        if event.type == .orderCancelled {
            // Sticky alarm is the primary path for cancels
            AlarmCenter.shared.raiseAlarm(for: event, playSound: playSound)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Food Rescue claimed"
        content.body = "Near \(event.locationName)" + (event.restaurantName.map { " · \($0)" } ?? "")
        content.sound = playSound ? .default : nil
        content.categoryIdentifier = "FOOD_RESCUE"
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: "fr-\(event.id)-\(UUID().uuidString.prefix(6))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            switch response.actionIdentifier {
            case "ACKNOWLEDGE":
                AlarmCenter.shared.acknowledge()
            case "OPEN_ZOMATO", UNNotificationDefaultActionIdentifier:
                if AlarmCenter.shared.isAlarming {
                    AlarmCenter.shared.acknowledgeAndOpenZomato()
                } else {
                    Self.openZomato()
                }
            default:
                break
            }
        }
    }

    static func openZomato() {
        let candidates = [
            "zomato://",
            "https://www.zomato.com/order"
        ]
        for c in candidates {
            guard let url = URL(string: c) else { continue }
            #if os(macOS)
            if NSWorkspace.shared.open(url) { return }
            #elseif os(iOS)
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
            #endif
        }
        #if os(iOS)
        if let url = URL(string: "https://www.zomato.com") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
