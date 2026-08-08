import SwiftUI
import AppKit

@main
struct FoodRescueBarApp: App {
    @StateObject private var appState = AppState()
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate

    var body: some Scene {
        // Stable path: real Window for UI (avoids MenuBarExtra+SwiftUI button crash on macOS 26)
        Window("Food Rescue", id: "main") {
            MenuBarRootView()
                .environmentObject(appState)
                .frame(minWidth: 360, idealWidth: 360, maxWidth: 400)
                .frame(minHeight: 420)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 360, height: 560)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        // Menu bar: native menu only (no SwiftUI gesture host)
        MenuBarExtra {
            MacMenuBarMenu()
                .environmentObject(appState)
        } label: {
            Label("Food Rescue", systemImage: appState.menuBarSystemImage)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Native-style menu actions for the menu bar icon.
struct MacMenuBarMenu: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Show Food Rescue") {
            openMainWindow()
        }

        Divider()

        if state.isLoggedIn {
            Text(state.monitorState.label)
            if !state.selectionSummary.isEmpty {
                Text(state.selectionSummary)
            }

            Divider()

            Button(state.isMonitoring ? "Stop listening" : "Start listening") {
                Task { await state.toggleMonitoring() }
            }
            .disabled(state.selectedLocations.isEmpty && !state.isMonitoring)

            Button("Open Zomato") {
                state.openZomato()
            }

            Divider()

            Button("Test alarm…") {
                openMainWindow()
                Task {
                    await NotificationManager.shared.ensureAuthorized()
                    let sample = RescueEvent(
                        id: "test-\(UUID().uuidString)",
                        type: .orderCancelled,
                        timestamp: Date(),
                        rawPreview: "",
                        addressId: state.selectedLocations.first?.addressId ?? 0,
                        locationName: state.selectedLocations.first?.name ?? "Home",
                        locationAddress: state.selectedLocations.first?.fullAddress ?? "Test address",
                        orderId: "TEST123",
                        restaurantId: nil,
                        restaurantName: "Test Kitchen (alarm demo)",
                        restaurantLat: nil,
                        restaurantLng: nil,
                        cartFinalCost: 199,
                        catalogTotalCost: 399,
                        viewersCount: 12,
                        cartExpiry: Date().addingTimeInterval(180),
                        isEnriching: false,
                        enrichmentFailed: false
                    )
                    // Defer slightly so menu dismisses cleanly first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        AlarmCenter.shared.raiseAlarm(for: sample, playSound: state.playSound)
                    }
                }
            }
        } else {
            Button("Sign in…") {
                openMainWindow()
            }
        }

        Divider()

        Button("Quit FoodRescueBar") {
            NSApp.terminate(nil)
        }
    }

    private func openMainWindow() {
        // Ensure app can show windows even as menu-bar style accessory
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
        // Bring any existing window forward
        DispatchQueue.main.async {
            for window in NSApp.windows where window.identifier?.rawValue.contains("main") == true
                || window.title == "Food Rescue" {
                window.makeKeyAndOrderFront(nil)
            }
            // Fallback: any visible non-panel window
            NSApp.windows.first(where: { $0.isVisible && !($0 is NSPanel) })?.makeKeyAndOrderFront(nil)
        }
    }
}

final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Stay out of Dock; menu bar + windows still work
        NSApp.setActivationPolicy(.accessory)
        // Soft-open main window on first launch so user isn't stuck with only a menu
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            for window in NSApp.windows where window.title == "Food Rescue" {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in NSApp.windows where window.title == "Food Rescue" {
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
    }
}
