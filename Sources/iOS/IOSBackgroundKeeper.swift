import Foundation
import UIKit
import BackgroundTasks

/// Best-effort keep-alive for MQTT while the app is backgrounded.
/// True always-on push requires a server + APNs; this extends runtime briefly
/// and schedules refresh attempts.
@MainActor
final class IOSBackgroundKeeper {
    static let shared = IOSBackgroundKeeper()

    static let refreshTaskId = "com.foodrescuebar.ios.refresh"

    private var bgTask: UIBackgroundTaskIdentifier = .invalid

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskId,
            using: nil
        ) { task in
            Self.handleRefresh(task: task as! BGAppRefreshTask)
        }
    }

    func beginBackgroundListening() {
        endBackgroundTask()
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "FoodRescueMQTT") { [weak self] in
            Task { @MainActor in
                self?.endBackgroundTask()
            }
        }
        scheduleRefresh()
    }

    func endBackgroundTask() {
        guard bgTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(bgTask)
        bgTask = .invalid
    }

    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleRefresh(task: BGAppRefreshTask) {
        scheduleFromBackground()
        // Soft ping — actual MQTT lives in AppState when process is alive
        task.setTaskCompleted(success: true)
    }

    private static func scheduleFromBackground() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
