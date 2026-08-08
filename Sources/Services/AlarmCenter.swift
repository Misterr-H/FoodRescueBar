import Foundation
import SwiftUI
import UserNotifications
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
import AudioToolbox
import AVFoundation
#endif

/// Sticky alarm UI + looping sound until the user acknowledges.
@MainActor
final class AlarmCenter: ObservableObject {
    static let shared = AlarmCenter()

    @Published private(set) var activeAlarm: RescueEvent?
    @Published private(set) var isAlarming = false
    /// Optional: load restaurant/price via create-cart (may burn Zomato flyer).
    private var onRequestDetails: (() -> Void)?

    #if os(macOS)
    private var panelController: MacAlarmPanelController?
    private var soundTimer: Timer?
    #elseif os(iOS)
    private var soundTimer: Timer?
    #endif

    private init() {}

    /// Raise (or refresh) a blocking alarm for a claimable cancel.
    /// Does not call create-cart — open official Zomato for the flyer.
    func raiseAlarm(
        for event: RescueEvent,
        playSound: Bool,
        onRequestDetails: (() -> Void)? = nil
    ) {
        guard event.type == .orderCancelled else { return }

        activeAlarm = event
        isAlarming = true
        self.onRequestDetails = onRequestDetails

        postSystemNotification(for: event)

        #if os(macOS)
        if panelController == nil {
            panelController = MacAlarmPanelController(
                onAcknowledge: { [weak self] in self?.acknowledge() },
                onOpenZomato: { [weak self] in self?.acknowledgeAndOpenZomato() },
                onLoadDetails: { [weak self] in self?.requestDetails() }
            )
        }
        panelController?.show(event: event)
        if playSound {
            startMacSoundLoop()
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.requestUserAttention(.criticalRequest)
        #elseif os(iOS)
        if playSound {
            startIOSSoundLoop()
        }
        #endif
    }

    /// Update text on an already-showing alarm (e.g. after deal enrichment).
    func updateAlarm(with event: RescueEvent) {
        guard isAlarming else { return }
        activeAlarm = event
        #if os(macOS)
        panelController?.update(event: event)
        #endif
    }

    func acknowledge() {
        stopSound()
        #if os(macOS)
        panelController?.hide()
        #endif
        activeAlarm = nil
        isAlarming = false
        onRequestDetails = nil
    }

    func acknowledgeAndOpenZomato() {
        acknowledge()
        NotificationManager.openZomato()
    }

    func requestDetails() {
        onRequestDetails?()
    }

    // MARK: - System notification (backup banner)

    private func postSystemNotification(for event: RescueEvent) {
        let content = UNMutableNotificationContent()
        content.title = "🚨 FOOD RESCUE — OPEN ZOMATO"
        content.subtitle = "Near \(event.locationName)"
        content.body = [
            event.restaurantName,
            "Open the Zomato app now for the official popup.",
            "Do not fetch details first — that can hide the flyer."
        ].compactMap { $0 }.joined(separator: " ")
        content.sound = .default
        content.categoryIdentifier = "FOOD_RESCUE_ALARM"
        content.interruptionLevel = .timeSensitive

        let req = UNNotificationRequest(
            identifier: "fr-alarm-\(event.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - Sound

    #if os(macOS)
    private func startMacSoundLoop() {
        stopSound()
        playMacAlarmSound()
        let helper = MacAlarmSoundRepeater { [weak self] in
            Task { @MainActor in
                self?.playMacAlarmSound()
            }
        }
        MacAlarmSoundRepeater.current = helper
        helper.start()
    }

    private func playMacAlarmSound() {
        let names = ["Sosumi", "Hero", "Submarine", "Ping", "Funk"]
        let name = names[Int.random(in: 0..<names.count)]
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.volume = 1.0
            sound.play()
        } else {
            NSSound.beep()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSSound.beep()
        }
    }
    #endif

    #if os(iOS)
    private func startIOSSoundLoop() {
        stopSound()
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        playIOSAlarmSound()
        soundTimer = Timer.scheduledTimer(withTimeInterval: 1.4, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.playIOSAlarmSound()
            }
        }
        if let soundTimer {
            RunLoop.main.add(soundTimer, forMode: .common)
        }
    }

    private func playIOSAlarmSound() {
        AudioServicesPlaySystemSound(1005)
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    #endif

    private func stopSound() {
        #if os(macOS)
        MacAlarmSoundRepeater.current?.stop()
        MacAlarmSoundRepeater.current = nil
        soundTimer?.invalidate()
        soundTimer = nil
        #elseif os(iOS)
        soundTimer?.invalidate()
        soundTimer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

// MARK: - macOS sound repeater (avoids MainActor.assumeIsolated crashes)

#if os(macOS)
private final class MacAlarmSoundRepeater: NSObject {
    static var current: MacAlarmSoundRepeater?
    private var timer: Timer?
    private let tick: () -> Void

    init(tick: @escaping () -> Void) {
        self.tick = tick
        super.init()
    }

    func start() {
        stop()
        let t = Timer(timeInterval: 1.4, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Pure AppKit alarm panel (no SwiftUI hosting — crash-safe)

@MainActor
final class MacAlarmPanelController: NSObject {
    private let onAcknowledge: () -> Void
    private let onOpenZomato: () -> Void
    private let onLoadDetails: () -> Void
    private weak var detailsButton: NSButton?

    private lazy var panel: NSPanel = {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.title = "Food Rescue Alarm"
        p.isFloatingPanel = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.worksWhenModal = true
        return p
    }()

    private let headerLabel = MacAlarmPanelController.makeLabel(size: 20, bold: true, color: .white)
    private let titleLabel = MacAlarmPanelController.makeLabel(size: 18, bold: true)
    private let areaLabel = MacAlarmPanelController.makeLabel(size: 13, bold: false, color: .secondaryLabelColor)
    private let priceLabel = MacAlarmPanelController.makeLabel(size: 26, bold: true, color: NSColor(red: 0.886, green: 0.216, blue: 0.267, alpha: 1))
    private let metaLabel = MacAlarmPanelController.makeLabel(size: 12, bold: false, color: .secondaryLabelColor)
    private let hintLabel = MacAlarmPanelController.makeLabel(size: 12, bold: true, color: NSColor(red: 0.886, green: 0.216, blue: 0.267, alpha: 1))

    init(
        onAcknowledge: @escaping () -> Void,
        onOpenZomato: @escaping () -> Void,
        onLoadDetails: @escaping () -> Void
    ) {
        self.onAcknowledge = onAcknowledge
        self.onOpenZomato = onOpenZomato
        self.onLoadDetails = onLoadDetails
        super.init()
        buildUI()
    }

    private static func makeLabel(size: CGFloat, bold: Bool, color: NSColor = .labelColor) -> NSTextField {
        let t = NSTextField(labelWithString: "")
        t.font = bold
            ? NSFont.systemFont(ofSize: size, weight: .bold)
            : NSFont.systemFont(ofSize: size, weight: .medium)
        t.textColor = color
        t.maximumNumberOfLines = 4
        t.lineBreakMode = .byWordWrapping
        t.isEditable = false
        t.isBordered = false
        t.drawsBackground = false
        t.translatesAutoresizingMaskIntoConstraints = false
        return t
    }

    private func buildUI() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 440, height: 360))
        root.wantsLayer = true

        let header = NSView()
        header.wantsLayer = true
        header.layer?.backgroundColor = NSColor(red: 0.886, green: 0.216, blue: 0.267, alpha: 1).cgColor
        header.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.stringValue = "🚨  FOOD RESCUE"
        headerLabel.alignment = .center
        header.addSubview(headerLabel)

        let openBtn = NSButton(title: "Open Zomato now (keep flyer)", target: self, action: #selector(tapOpen))
        openBtn.bezelStyle = .rounded
        openBtn.isBordered = true
        openBtn.wantsLayer = true
        openBtn.layer?.backgroundColor = NSColor(red: 0.886, green: 0.216, blue: 0.267, alpha: 1).cgColor
        openBtn.layer?.cornerRadius = 8
        openBtn.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        openBtn.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 11.0, *) {
            openBtn.controlSize = .large
        }

        let ackBtn = NSButton(title: "Acknowledge — stop alarm", target: self, action: #selector(tapAck))
        ackBtn.bezelStyle = .rounded
        ackBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        ackBtn.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 11.0, *) {
            ackBtn.controlSize = .large
        }

        let detailsBtn = NSButton(
            title: "Load restaurant details (may hide Zomato flyer)",
            target: self,
            action: #selector(tapDetails)
        )
        detailsBtn.bezelStyle = .rounded
        detailsBtn.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        detailsBtn.translatesAutoresizingMaskIntoConstraints = false
        detailsButton = detailsBtn

        hintLabel.stringValue = "Open Zomato immediately for the official popup. Loading details can consume the flyer pitch."

        let stack = NSStackView(views: [
            titleLabel, areaLabel, priceLabel, metaLabel, hintLabel, openBtn, ackBtn, detailsBtn
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 20, bottom: 16, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(header)
        root.addSubview(stack)
        panel.contentView = root

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 56),

            headerLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            headerLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            headerLabel.leadingAnchor.constraint(greaterThanOrEqualTo: header.leadingAnchor, constant: 12),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: header.trailingAnchor, constant: -12),

            stack.topAnchor.constraint(equalTo: header.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            openBtn.heightAnchor.constraint(equalToConstant: 40),
            openBtn.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            ackBtn.heightAnchor.constraint(equalToConstant: 36),
            ackBtn.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
            detailsBtn.heightAnchor.constraint(equalToConstant: 32),
            detailsBtn.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40)
        ])
    }

    func show(event: RescueEvent) {
        update(event: event)
        panel.center()
        if let screen = NSScreen.main {
            let f = panel.frame
            panel.setFrameOrigin(NSPoint(
                x: screen.visibleFrame.midX - f.width / 2,
                y: screen.visibleFrame.midY - f.height / 2 + 30
            ))
        }
        panel.orderFrontRegardless()
    }

    func update(event: RescueEvent) {
        titleLabel.stringValue = event.restaurantName ?? "Food Rescue nearby — open Zomato now"
        areaLabel.stringValue = "📍 \(event.subscribedAreaText)"
        priceLabel.stringValue = event.priceText ?? ""
        priceLabel.isHidden = event.priceText == nil

        var meta: [String] = []
        if let v = event.viewersCount, v > 0 { meta.append("\(v) watching") }
        if let o = event.orderId { meta.append("Order \(o)") }
        meta.append(event.timestamp.formatted(date: .omitted, time: .shortened))
        if event.isEnriching { meta.append("Loading details…") }
        if event.enrichmentFailed { meta.append("Details unavailable") }
        if event.restaurantName == nil, !event.isEnriching {
            meta.append("MQTT signal only")
        }
        metaLabel.stringValue = meta.joined(separator: " · ")
        detailsButton?.isEnabled = !event.isEnriching && event.restaurantName == nil
    }

    func hide() {
        panel.orderOut(nil)
    }

    @objc private func tapAck() {
        DispatchQueue.main.async { [onAcknowledge] in
            onAcknowledge()
        }
    }

    @objc private func tapOpen() {
        DispatchQueue.main.async { [onOpenZomato] in
            onOpenZomato()
        }
    }

    @objc private func tapDetails() {
        DispatchQueue.main.async { [onLoadDetails] in
            onLoadDetails()
        }
    }
}
#endif

// MARK: - Shared SwiftUI alarm view (iOS fullScreenCover)

struct AlarmPanelView: View {
    let event: RescueEvent
    let onAcknowledge: () -> Void
    let onOpenZomato: () -> Void
    var onLoadDetails: (() -> Void)? = nil

    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .scaleEffect(pulse ? 1.15 : 1.0)
                Text("FOOD RESCUE")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .tracking(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(FRTheme.brand)

            VStack(alignment: .leading, spacing: 10) {
                Text(event.restaurantName ?? "Food Rescue nearby — open Zomato now")
                    .font(.system(size: 20, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text("📍 \(event.subscribedAreaText)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let price = event.priceText {
                    Text(price)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(FRTheme.brand)
                }

                Text([
                    event.viewersCount.map { "\($0) watching" },
                    event.orderId.map { "Order \($0)" },
                    event.timestamp.formatted(date: .omitted, time: .shortened)
                ].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Text("Open Zomato immediately for the official popup. Loading details can hide the flyer.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FRTheme.brand)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                Button(action: onOpenZomato) {
                    Text("Open Zomato now (keep flyer)")
                        .font(.system(size: 15, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundStyle(.white)
                        .background(FRTheme.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onAcknowledge) {
                    Text("Acknowledge — stop alarm")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(.primary)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)

                if let onLoadDetails, event.restaurantName == nil {
                    Button(action: onLoadDetails) {
                        Text("Load restaurant details (may hide flyer)")
                            .font(.system(size: 12, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(event.isEnriching)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(FRTheme.surface)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
