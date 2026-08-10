import SwiftUI
import AppKit

/// Menu bar agent — always shows a visible "FoodRescue" status item.
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
        log("applicationDidFinishLaunching")
        NSApp.setActivationPolicy(.accessory)
        installStatusItem()

        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.ensureStatusItem()
            }
        }

        // Always open panel so user knows the app launched (even if status item is crowded out)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showMainPanel(force: true)
            self?.log("opened panel after launch")
        }
    }

    // MARK: - Logging

    private func log(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        let path = NSHomeDirectory() + "/Library/Logs/FoodRescueBar.log"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: path),
               let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? data.write(to: URL(fileURLWithPath: path))
            }
        }
        NSLog("FoodRescueBar: \(msg)")
    }

    // MARK: - Status item

    private func ensureStatusItem() {
        if statusItem?.button == nil {
            log("status item missing — recreating")
            installStatusItem()
        } else {
            refreshStatusItemAppearance()
        }
    }

    private func installStatusItem() {
        if let old = statusItem {
            NSStatusBar.system.removeStatusItem(old)
            statusItem = nil
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else {
            log("ERROR: statusItem.button is nil")
            showMainPanel(force: true)
            return
        }

        // Highly visible: always show text (icons alone can vanish in crowded bars)
        button.title = " FoodRescue "
        button.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        if let image = NSImage(systemSymbolName: "leaf.fill", accessibilityDescription: "Food Rescue") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
        }
        button.toolTip = "FoodRescueBar"
        button.isEnabled = true
        button.appearsDisabled = false

        item.menu = buildStatusMenu()
        statusItem = item
        log("status item installed title='\(button.title)' hasImage=\(button.image != nil)")
    }

    private func refreshStatusItemAppearance() {
        guard let button = statusItem?.button else {
            installStatusItem()
            return
        }
        if button.title.trimmingCharacters(in: .whitespaces).isEmpty {
            button.title = " FoodRescue "
        }
        let symbol = appState.isMonitoring ? "leaf.fill" : "leaf"
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Food Rescue") {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            button.image = image.withSymbolConfiguration(config)
            button.image?.isTemplate = true
            button.imagePosition = .imageLeft
        }
        if appState.isMonitoring {
            button.title = " FoodRescue• "
        } else {
            button.title = " FoodRescue "
        }
        statusItem?.menu = buildStatusMenu()
    }

    private func buildStatusMenu() -> NSMenu {
        let menu = NSMenu()

        let open = NSMenuItem(title: "Open Food Rescue panel", action: #selector(showMainWindowAction), keyEquivalent: "")
        open.target = self
        menu.addItem(open)
        menu.addItem(.separator())

        if appState.isLoggedIn {
            let status = NSMenuItem(title: "Status: \(appState.monitorState.label)", action: nil, keyEquivalent: "")
            status.isEnabled = false
            menu.addItem(status)

            let areas = NSMenuItem(
                title: appState.selectionSummary.isEmpty ? "No areas selected" : "Areas: \(appState.selectionSummary)",
                action: nil,
                keyEquivalent: ""
            )
            areas.isEnabled = false
            menu.addItem(areas)
            menu.addItem(.separator())

            let listen = NSMenuItem(
                title: appState.isMonitoring ? "Stop listening" : "Start listening",
                action: #selector(toggleListening),
                keyEquivalent: ""
            )
            listen.target = self
            if appState.selectedLocations.isEmpty && !appState.isMonitoring {
                listen.isEnabled = false
            }
            menu.addItem(listen)

            let z = NSMenuItem(title: "Open Zomato", action: #selector(openZomato), keyEquivalent: "")
            z.target = self
            menu.addItem(z)
            menu.addItem(.separator())

            let test = NSMenuItem(title: "Test alarm…", action: #selector(testAlarm), keyEquivalent: "")
            test.target = self
            menu.addItem(test)
        } else {
            let signIn = NSMenuItem(title: "Sign in…", action: #selector(showMainWindowAction), keyEquivalent: "")
            signIn.target = self
            menu.addItem(signIn)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit FoodRescueBar", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    // MARK: - Panel

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
                styleMask: [.titled, .closable, .nonactivatingPanel],
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

        if let screen = NSScreen.main {
            let f = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - f.width / 2,
                y: screen.visibleFrame.midY - f.height / 2
            ))
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        log("panel ordered front")
    }

    // MARK: - Actions

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
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        NSApp.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showMainPanel(force: true)
        ensureStatusItem()
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}
