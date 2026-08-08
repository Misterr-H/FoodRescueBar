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
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            #if os(iOS)
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            #endif
        } catch {
            isAuthorized = false
        }
    }

    func sendFoodRescueAlert(for event: RescueEvent, playSound: Bool) {
        let content = UNMutableNotificationContent()

        if event.type == .orderCancelled {
            content.title = event.restaurantName.map { "Food Rescue · \($0)" } ?? "Food Rescue nearby!"
            var lines: [String] = []
            lines.append("Near your \(event.locationName)")
            if !event.locationAddress.isEmpty {
                lines.append(event.locationAddress)
            }
            if let price = event.priceText {
                lines.append(price)
            }
            if let viewers = event.viewersCount, viewers > 0 {
                lines.append("\(viewers) watching")
            }
            if let orderId = event.orderId {
                lines.append("Order #\(orderId)")
            }
            lines.append("Open Zomato now to claim.")
            content.body = lines.joined(separator: " · ")
        } else {
            content.title = "Food Rescue claimed"
            content.body = "Near \(event.locationName)" + (event.restaurantName.map { " · \($0)" } ?? "")
        }

        content.sound = playSound ? .default : nil
        content.categoryIdentifier = "FOOD_RESCUE"
        content.interruptionLevel = .timeSensitive
        content.userInfo = [
            "addressId": event.addressId,
            "locationName": event.locationName,
            "orderId": event.orderId ?? "",
            "restaurantName": event.restaurantName ?? ""
        ]

        let request = UNNotificationRequest(
            identifier: "fr-\(event.id)-\(UUID().uuidString.prefix(6))",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)

        if playSound {
            #if os(macOS)
            NSSound(named: "Glass")?.play()
            #elseif os(iOS)
            AudioServicesPlaySystemSound(1007)
            #endif
        }

        #if os(macOS)
        NSApp.requestUserAttention(.criticalRequest)
        #endif
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
            Self.openZomato()
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
