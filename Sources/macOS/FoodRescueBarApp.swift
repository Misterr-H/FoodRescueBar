import SwiftUI
import AppKit

/// Pure AppKit entry — menu bar agent (no Dock), panel opens only when you click the icon.
@main
enum FoodRescueBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MacAppDelegate()
        app.delegate = delegate
        // No Dock icon — classic menu bar app
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class MacAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var mainPanel: NSPanel?
    private var hostingController: NSHostingController<AnyView>?
    private let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Re-assert accessory in case something tried to promote us to a regular app
        NSApp.setActivationPolicy(.accessory)

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(
                systemSymbolName: "leaf.circle",
                accessibilityDescription: "Food Rescue"
            )
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        // Do NOT assign a permanent menu — that forces “menu app” UX only.
        // Left-click toggles the panel; right-click shows the menu.

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusItem()
            }
        }

        // Stay silent in the menu bar only — no window until user clicks
        // (Settings / sign-in open the panel when needed.)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func appDidWake() {}

    private func refreshStatusItem() {
        let symbol = appState.menuBarSystemImage
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: "Food Rescue"
        )
        statusItem?.button?.image?.isTemplate = true
    }

    // MARK: - Status item click

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showStatusMenu()
            return
        }
        // Left click: toggle panel under menu bar
        toggleMainPanel()
    }

    private func showStatusMenu() {
        let menu = buildStatusMenu()
        // Temporarily attach menu and pop it under the status item
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        // Detach so next left-click toggles panel again
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(withTitle: "Open panel", action: #selector(showMainWindowAction), keyEquivalent: "")
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
        return menu
    }

    @objc private func showMainWindowAction() {
        showMainPanel(force: true)
    }

    private func toggleMainPanel() {
        if let panel = mainPanel, panel.isVisible {
            panel.orderOut(nil)
            return
        }
        showMainPanel(force: true)
    }

    func showMainPanel(force: Bool) {
        NSApp.setActivationPolicy(.accessory)

        if mainPanel == nil {
            let root = MenuBarRootView()
                .environmentObject(appState)
                .frame(width: 360)
                .buttonStyle(.bordered)

            let host = NSHostingController(rootView: AnyView(root))
            hostingController = host

            // Utility panel — not a document-style app window
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 560),
                styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.title = "Food Rescue"
            panel.contentViewController = host
            panel.delegate = self
            panel.isReleasedWhenClosed = false
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.setFrameAutosaveName("FoodRescuePanel")
            mainPanel = panel
        }

        guard let panel = mainPanel else { return }

        // Position under the status item when possible
        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)
            var origin = NSPoint(
                x: screenRect.midX - panel.frame.width / 2,
                y: screenRect.minY - panel.frame.height - 6
            )
            if let screen = buttonWindow.screen ?? NSScreen.main {
                origin.x = min(max(origin.x, screen.visibleFrame.minX + 8),
                               screen.visibleFrame.maxX - panel.frame.width - 8)
                if origin.y < screen.visibleFrame.minY {
                    origin.y = screenRect.maxY + 6
                }
            }
            panel.setFrameOrigin(origin)
        } else if force {
            panel.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleListening() {
        Task { @MainActor in
            await appState.toggleMonitoring()
            refreshStatusItem()
        }
    }

    @objc private func openZomato() {
        appState.openZomato()
    }

    @objc private func testAlarm() {
        // Don't open the big panel for test — just alarm
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
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
        // Dock is hidden; reopen still shows panel if user reopens somehow
        showMainPanel(force: true)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Hide instead of destroy — keep agent running in menu bar
        sender.orderOut(nil)
        return false
    }
}
