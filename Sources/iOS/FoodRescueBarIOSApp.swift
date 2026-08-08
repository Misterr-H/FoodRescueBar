import SwiftUI
import UIKit
import UserNotifications

@main
struct FoodRescueBarIOSApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            IOSRootView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    appDelegate.appState = appState
                    Task {
                        await NotificationManager.shared.requestAuthorization()
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        IOSBackgroundKeeper.shared.endBackgroundTask()
                        if appState.isMonitoring {
                            Task { await appState.ensureMonitoringAlive() }
                        }
                    case .background:
                        if appState.isMonitoring {
                            IOSBackgroundKeeper.shared.beginBackgroundListening()
                        }
                    default:
                        break
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    weak var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        Task { @MainActor in
            IOSBackgroundKeeper.shared.register()
        }
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Task { @MainActor in
            if appState?.isMonitoring == true {
                IOSBackgroundKeeper.shared.beginBackgroundListening()
            }
        }
    }
}
