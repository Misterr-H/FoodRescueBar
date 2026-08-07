import Foundation
import UserNotifications
import AppKit

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    private(set) var isAuthorized = false

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
        } catch {
            isAuthorized = false
        }
    }

    func sendFoodRescueAlert(playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Food Rescue nearby!"
        content.body = "A cancelled order is available. Open Zomato now to claim it."
        content.sound = playSound ? .default : nil
        content.categoryIdentifier = "FOOD_RESCUE"
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: "fr-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)

        if playSound {
            NSSound(named: "Glass")?.play()
        }

        // Bounce dock / attention if possible (LSUIElement = true so no dock, but still ok)
        NSApp.requestUserAttention(.criticalRequest)
    }

    // Show banner even when app is focused / menu open
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await MainActor.run {
            Self.openZomato()
        }
    }

    static func openZomato() {
        // Prefer installed Zomato / browser
        let candidates = [
            "zomato://",
            "https://www.zomato.com/order"
        ]
        for c in candidates {
            if let url = URL(string: c), NSWorkspace.shared.open(url) {
                return
            }
        }
    }
}
