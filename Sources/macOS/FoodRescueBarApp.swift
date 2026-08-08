import SwiftUI
import AppKit

/// Pure AppKit entry — avoids SwiftUI `App.main()` + MenuBarExtra MainActor button crashes on macOS 26.
@main
enum FoodRescueBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MacAppDelegate()
        app.delegate = delegate
        // Accessory = menu bar style (no Dock). Windows still work.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    private var hostingController: NSHostingController<AnyView>?
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Status item (AppKit menu — no SwiftUI gestures)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "leaf.circle",
                accessibilityDescription: "Food Rescue"
            )
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        rebuildStatusMenu()

        // Observe state for menu title refresh
        // Lightweight timer to refresh menu labels / icon
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusItem()
            }
        }

        // Show main window on launch
        showMainWindow()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func appDidWake() {
        // no-op; KeepAwakeService already observes wake
    }

    private func refreshStatusItem() {
        let symbol = appState.menuBarSystemImage
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Food Rescue"
        )
        statusItem?.button?.image?.isTemplate = true
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()

        menu.addItem(withTitle: "Show Food Rescue", action: #selector(showMainWindowAction), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())

        if appState.isLoggedIn {
            let status = NSMenuItem(
                title: "Status: \(appState.monitorState.label)",
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)

            let areas = NSMenuItem(
                title: appState.selectionSummary,
                action: nil,
                keyEquivalent: ""
            )
            areas.isEnabled = false
            menu.addItem(areas)
            menu.addItem(NSMenuItem.separator())

            let listenTitle = appState.isMonitoring ? "Stop listening" : "Start listening"
            let listen = NSMenuItem(title: listenTitle, action: #selector(toggleListening), keyEquivalent: "")
            if appState.selectedLocations.isEmpty && !appState.isMonitoring {
                listen.isEnabled = false
            }
            menu.addItem(listen)

            menu.addItem(withTitle: "Open Zomato", action: #selector(openZomato), keyEquivalent: "")
            menu.addItem(NSMenuItem.separator())
            menu.addItem(withTitle: "Test alarm…", action: #selector(testAlarm), keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Sign in…", action: #selector(showMainWindowAction), keyEquivalent: "")
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit FoodRescueBar", action: #selector(quitApp), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }
        statusItem?.menu = menu
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        // Left click: show window. Right click still gets menu via status item menu.
        // With menu assigned, click opens menu — that's fine.
        // Also ensure menu is fresh
        rebuildStatusMenu()
    }

    @objc private func showMainWindowAction() {
        showMainWindow()
    }

    func showMainWindow() {
        if mainWindow == nil {
            let root = MenuBarRootView()
                .environmentObject(appState)
                .frame(width: 360)
                // Prefer system button styles on macOS for stability
                .buttonStyle(.bordered)

            let host = NSHostingController(rootView: AnyView(root))
            hostingController = host

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Food Rescue"
            window.contentViewController = host
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("FoodRescueMain")
            mainWindow = window
        }

        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
        // Keep accessory policy but allow key window
        mainWindow?.level = .normal
    }

    @objc private func toggleListening() {
        Task { @MainActor in
            await appState.toggleMonitoring()
            rebuildStatusMenu()
            refreshStatusItem()
        }
    }

    @objc private func openZomato() {
        appState.openZomato()
    }

    @objc private func testAlarm() {
        showMainWindow()
        Task { @MainActor in
            await NotificationManager.shared.ensureAuthorized()
            let sample = RescueEvent(
                id: "test-\(UUID().uuidString)",
                type: .orderCancelled,
                timestamp: Date(),
                rawPreview: "",
                addressId: appState.selectedLocations.first?.addressId ?? 0,
                locationName: appState.selectedLocations.first?.name ?? "Home",
                locationAddress: appState.selectedLocations.first?.fullAddress ?? "Test address",
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
                enrichmentFailed: false,
                isVerifiedDeal: true,
                isLikelyNoise: false
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                AlarmCenter.shared.raiseAlarm(for: sample, playSound: true)
            }
        }
    }

    @objc private func quitApp() {
        AlarmCenter.shared.acknowledge()
        KeepAwakeService.shared.stop()
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        // Keep app running as menu bar agent when window closes
    }
}
