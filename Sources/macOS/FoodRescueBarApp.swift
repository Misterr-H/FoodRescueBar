import SwiftUI
import AppKit

/// Pure AppKit entry — menu bar agent (no Dock).
@main
enum FoodRescueBarMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = MacAppDelegate()
        app.delegate = delegate
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
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()

        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusItemAppearance()
            }
        }

        // Open panel once if not signed in, so first-run isn't "invisible"
        if !appState.isLoggedIn {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
                self?.showMainPanel(force: true)
            }
        }
    }

    // MARK: - Status item (always visible)

    private func installStatusItem() {
        // Remove old item if re-installing
        if let old = statusItem {
            NSStatusBar.system.removeStatusItem(old)
            statusItem = nil
        }

        // Use variable length so "FR" text + icon both fit
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            NSLog("FoodRescueBar: failed to create status item button")
            return
        }

        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.toolTip = "Food Rescue — left click: panel · right click: menu"

        statusItem = item
        applyStatusItemAppearance(to: button)
        // Permanent menu as fallback so the item always does something useful
        // (left-click still handled via action when menu is nil; we use hybrid below)
        rebuildAndAttachMenu()
    }

    private func applyStatusItemAppearance(to button: NSStatusBarButton) {
        let symbolName = appState.menuBarSystemImage
        // Always show "FR" text so the item is never invisible in a crowded menu bar
        // (system symbol alone can fail to render for accessory apps).
        button.title = " FR"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Food Rescue") {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
        } else {
            button.image = nil
            button.title = " FR"
        }
    }

    private func refreshStatusItemAppearance() {
        guard let button = statusItem?.button else {
            // Status item lost (can happen if menu bar restarts) — recreate
            installStatusItem()
            return
        }
        applyStatusItemAppearance(to: button)
        rebuildAndAttachMenu()
    }

    private func rebuildAndAttachMenu() {
        let menu = buildStatusMenu()
        statusItem?.menu = menu
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = true

        let open = NSMenuItem(title: "Open Food Rescue", action: #selector(showMainWindowAction), keyEquivalent: "o")
        menu.addItem(open)
        menu.addItem(NSMenuItem.separator())

        if appState.isLoggedIn {
            let status = NSMenuItem(
                title: "● \(appState.monitorState.label)",
                action: nil,
                keyEquivalent: ""
            )
            status.isEnabled = false
            menu.addItem(status)

            let areas = NSMenuItem(
                title: appState.selectionSummary.isEmpty ? "No areas selected" : appState.selectionSummary,
                action: nil,
                keyEquivalent: ""
            )
            areas.isEnabled = false
            menu.addItem(areas)
            menu.addItem(NSMenuItem.separator())

            let listenTitle = appState.isMonitoring ? "Stop listening" : "Start listening"
            let listen = NSMenuItem(title: listenTitle, action: #selector(toggleListening), keyEquivalent: "l")
            if appState.selectedLocations.isEmpty && !appState.isMonitoring {
                listen.isEnabled = false
            }
            menu.addItem(listen)

            menu.addItem(NSMenuItem(title: "Open Zomato", action: #selector(openZomato), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Test alarm…", action: #selector(testAlarm), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "Sign in…", action: #selector(showMainWindowAction), keyEquivalent: ""))
        }

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FoodRescueBar", action: #selector(quitApp), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        return menu
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        // With an attached menu, AppKit usually shows the menu on click.
        // Also open the panel on left-click for quicker access.
        let event = NSApp.currentEvent
        if event?.type == .leftMouseUp {
            // Slight delay so menu and panel don't fight
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.showMainPanel(force: true)
            }
        }
        rebuildAndAttachMenu()
    }

    @objc private func showMainWindowAction() {
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

        if let button = statusItem?.button, let buttonWindow = button.window {
            let buttonRect = button.convert(button.bounds, to: nil)
            let screenRect = buttonWindow.convertToScreen(buttonRect)
            var origin = NSPoint(
                x: screenRect.midX - panel.frame.width / 2,
                y: screenRect.minY - panel.frame.height - 6
            )
            if let screen = buttonWindow.screen ?? NSScreen.main {
                origin.x = min(
                    max(origin.x, screen.visibleFrame.minX + 8),
                    screen.visibleFrame.maxX - panel.frame.width - 8
                )
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
            refreshStatusItemAppearance()
        }
    }

    @objc private func openZomato() {
        appState.openZomato()
    }

    @objc private func testAlarm() {
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
        showMainPanel(force: true)
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
