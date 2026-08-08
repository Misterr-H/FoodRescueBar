import SwiftUI
import AppKit

@main
struct FoodRescueBarApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarRootView()
                .environmentObject(appState)
        } label: {
            Label {
                Text("Food Rescue")
            } icon: {
                Image(systemName: appState.menuBarSystemImage)
                    .symbolRenderingMode(.hierarchical)
            }
            .help(menuBarHelp)
        }
        .menuBarExtraStyle(.window)

        Settings {
            VStack(alignment: .leading, spacing: 12) {
                Text("FoodRescueBar")
                    .font(.title2.bold())
                Text("Use the menu bar icon (top-right) to control monitoring.")
                    .foregroundStyle(.secondary)
                Button("Quit") { NSApp.terminate(nil) }
            }
            .padding(24)
            .frame(width: 360)
        }
    }

    private var menuBarHelp: String {
        if !appState.isLoggedIn { return "FoodRescueBar — Sign in" }
        if appState.isMonitoring {
            return "FoodRescueBar — \(appState.monitorState.label) · \(appState.selectionSummary)"
        }
        return "FoodRescueBar — \(appState.selectionSummary)"
    }
}
