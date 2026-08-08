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

    #if os(macOS)
    private var panelController: MacAlarmPanelController?
    private var soundTimer: Timer?
    #elseif os(iOS)
    private var soundTimer: Timer?
    #endif

    private init() {}

    /// Raise (or refresh) a blocking alarm for a claimable cancel.
    func raiseAlarm(for event: RescueEvent, playSound: Bool) {
        guard event.type == .orderCancelled else { return }

        activeAlarm = event
        isAlarming = true

        postSystemNotification(for: event)

        #if os(macOS)
        if panelController == nil {
            panelController = MacAlarmPanelController(
                onAcknowledge: { [weak self] in self?.acknowledge() },
                onOpenZomato: { [weak self] in self?.acknowledgeAndOpenZomato() }
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
    }

    func acknowledgeAndOpenZomato() {
        acknowledge()
        NotificationManager.openZomato()
    }

    // MARK: - System notification (backup banner)

    private func postSystemNotification(for event: RescueEvent) {
        let content = UNMutableNotificationContent()
        content.title = "🚨 FOOD RESCUE — ACKNOWLEDGE"
        content.subtitle = event.restaurantName ?? "Cancelled order nearby"
        content.body = [
            "Near \(event.locationName)",
            event.priceText,
            "Use the alarm window to acknowledge"
        ].compactMap { $0 }.joined(separator: " · ")
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

    private lazy var panel: NSPanel = {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 360),
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

    init(onAcknowledge: @escaping () -> Void, onOpenZomato: @escaping () -> Void) {
        self.onAcknowledge = onAcknowledge
        self.onOpenZomato = onOpenZomato
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

        let openBtn = NSButton(title: "Open Zomato & stop alarm", target: self, action: #selector(tapOpen))
        openBtn.bezelStyle = .rounded
        openBtn.isBordered = true
        openBtn.contentTintColor = .white
        openBtn.wantsLayer = true
        openBtn.layer?.backgroundColor = NSColor(red: 0.886, green: 0.216, blue: 0.267, alpha: 1).cgColor
        openBtn.layer?.cornerRadius = 8
        openBtn.font = NSFont.systemFont(ofSize: 14, weight: .bold)
        openBtn.translatesAutoresizingMaskIntoConstraints = false
        // Use prominent control
        if #available(macOS 11.0, *) {
            openBtn.controlSize = .large
            openBtn.hasDestructiveAction = false
        }

        let ackBtn = NSButton(title: "Acknowledge — stop alarm", target: self, action: #selector(tapAck))
        ackBtn.bezelStyle = .rounded
        ackBtn.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        ackBtn.translatesAutoresizingMaskIntoConstraints = false
        if #available(macOS 11.0, *) {
            ackBtn.controlSize = .large
        }

        hintLabel.stringValue = "Alarm keeps ringing until you acknowledge."

        let stack = NSStackView(views: [titleLabel, areaLabel, priceLabel, metaLabel, hintLabel, openBtn, ackBtn])
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
            ackBtn.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40)
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
        // Don't force key window via SwiftUI path; nonactivating panel + orderFront is safer
    }

    func update(event: RescueEvent) {
        titleLabel.stringValue = event.restaurantName ?? "Cancelled order — claimable"
        areaLabel.stringValue = "📍 \(event.subscribedAreaText)"
        priceLabel.stringValue = event.priceText ?? ""
        priceLabel.isHidden = event.priceText == nil

        var meta: [String] = []
        if let v = event.viewersCount, v > 0 { meta.append("\(v) watching") }
        if let o = event.orderId { meta.append("Order \(o)") }
        meta.append(event.timestamp.formatted(date: .omitted, time: .shortened))
        if event.isEnriching { meta.append("Loading details…") }
        if event.enrichmentFailed { meta.append("Details unavailable") }
        metaLabel.stringValue = meta.joined(separator: " · ")
    }

    func hide() {
        panel.orderOut(nil)
    }

    @objc private func tapAck() {
        onAcknowledge()
    }

    @objc private func tapOpen() {
        onOpenZomato()
    }
}
#endif

// MARK: - Shared SwiftUI alarm view (iOS fullScreenCover)

struct AlarmPanelView: View {
    let event: RescueEvent
    let onAcknowledge: () -> Void
    let onOpenZomato: () -> Void

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
                Text(event.restaurantName ?? "Cancelled order — claimable")
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

                Text("Alarm keeps ringing until you acknowledge.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FRTheme.brand)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                Button(action: onOpenZomato) {
                    Text("Open Zomato & stop alarm")
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
