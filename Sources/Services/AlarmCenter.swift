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
    private var panel: NSPanel?
    private var soundTimer: Timer?
    private var host: NSHostingView<AlarmPanelView>?
    #elseif os(iOS)
    private var soundTimer: Timer?
    private var audioPlayer: AVAudioPlayer?
    #endif

    private init() {}

    /// Raise (or refresh) a blocking alarm for a claimable cancel.
    func raiseAlarm(for event: RescueEvent, playSound: Bool) {
        guard event.type == .orderCancelled else { return }

        activeAlarm = event
        isAlarming = true

        // System banner (auto-dismisses) — backup only
        postSystemNotification(for: event, playSound: false)

        #if os(macOS)
        presentMacPanel(event: event)
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
        guard isAlarming, activeAlarm?.id == event.id || activeAlarm != nil else { return }
        activeAlarm = event
        #if os(macOS)
        refreshMacPanelContent()
        #endif
    }

    func acknowledge() {
        stopSound()
        #if os(macOS)
        dismissMacPanel()
        #endif
        activeAlarm = nil
        isAlarming = false
    }

    func acknowledgeAndOpenZomato() {
        acknowledge()
        NotificationManager.openZomato()
    }

    // MARK: - System notification (non-blocking backup)

    private func postSystemNotification(for event: RescueEvent, playSound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "🚨 FOOD RESCUE — ACKNOWLEDGE"
        content.subtitle = event.restaurantName ?? "Cancelled order nearby"
        content.body = [
            "Near \(event.locationName)",
            event.priceText,
            "Tap Acknowledge in the alarm window"
        ].compactMap { $0 }.joined(separator: " · ")
        content.sound = playSound ? UNNotificationSound.default : nil
        content.categoryIdentifier = "FOOD_RESCUE_ALARM"
        content.interruptionLevel = .timeSensitive
        #if os(macOS)
        if #available(macOS 12.0, *) {
            content.relevanceScore = 1.0
        }
        #endif

        let req = UNNotificationRequest(
            identifier: "fr-alarm-\(event.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(req)
    }

    // MARK: - macOS panel + sound

    #if os(macOS)
    private func presentMacPanel(event: RescueEvent) {
        if panel == nil {
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                styleMask: [.titled, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = "Food Rescue Alarm"
            panel.isFloatingPanel = true
            panel.level = .statusBar // above most windows
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .moveToActiveSpace]
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = NSColor.windowBackgroundColor
            panel.worksWhenModal = true
            self.panel = panel
        }

        refreshMacPanelContent()

        guard let panel else { return }
        panel.center()
        // Nudge to active screen center
        if let screen = NSScreen.main {
            let f = panel.frame
            let sx = screen.visibleFrame.midX - f.width / 2
            let sy = screen.visibleFrame.midY - f.height / 2 + 40
            panel.setFrameOrigin(NSPoint(x: sx, y: sy))
        }
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    private func refreshMacPanelContent() {
        guard let panel, let event = activeAlarm else { return }
        let view = AlarmPanelView(
            event: event,
            onAcknowledge: { [weak self] in self?.acknowledge() },
            onOpenZomato: { [weak self] in self?.acknowledgeAndOpenZomato() }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 440, height: 380)
        panel.contentView = host
        self.host = host
        panel.setContentSize(NSSize(width: 440, height: 380))
    }

    private func dismissMacPanel() {
        panel?.orderOut(nil)
    }

    private func startMacSoundLoop() {
        stopSound()
        playMacAlarmSound()
        // Repeat until acknowledged
        let timer = Timer(timeInterval: 1.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.playMacAlarmSound()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        soundTimer = timer
    }

    private func playMacAlarmSound() {
        // Loud built-in system sounds (cycle a few)
        let names = ["Sosumi", "Hero", "Submarine", "Ping", "Funk"]
        let name = names[Int(Date().timeIntervalSince1970) % names.count]
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.volume = 1.0
            sound.play()
        } else {
            NSSound.beep()
        }
        // Second beep for urgency
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSSound.beep()
        }
    }
    #endif

    // MARK: - iOS sound

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
        AudioServicesPlaySystemSound(1005) // alert
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
    }
    #endif

    private func stopSound() {
        #if os(macOS)
        soundTimer?.invalidate()
        soundTimer = nil
        #elseif os(iOS)
        soundTimer?.invalidate()
        soundTimer = nil
        audioPlayer?.stop()
        audioPlayer = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

// MARK: - Alarm UI

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

                Label(event.subscribedAreaText, systemImage: "mappin.and.ellipse")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let price = event.priceText {
                    Text(price)
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(FRTheme.brand)
                }

                HStack(spacing: 12) {
                    if let viewers = event.viewersCount, viewers > 0 {
                        chip("\(viewers) watching")
                    }
                    if let orderId = event.orderId {
                        chip("Order \(orderId)")
                    }
                    chip(event.timestamp.formatted(date: .omitted, time: .shortened))
                }

                if event.isEnriching {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Loading restaurant details…")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Alarm keeps ringing until you acknowledge.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(FRTheme.brand)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)

            VStack(spacing: 10) {
                Button(action: onOpenZomato) {
                    Label("Open Zomato & stop alarm", systemImage: "arrow.up.right.square.fill")
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
        }
        .frame(width: 440)
        .background(FRTheme.surface)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
    }
}
