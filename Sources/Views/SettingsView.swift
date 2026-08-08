import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderBar(
                title: "Settings",
                subtitle: "Alerts & behavior",
                backAction: { state.screen = .home }
            )

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $state.playSound) {
                    labelRow(
                        title: "Alert sound",
                        subtitle: "Play a sound with each Food Rescue ping",
                        systemImage: "speaker.wave.2.fill"
                    )
                }
                .toggleStyle(.switch)

                Divider().opacity(0.4)

                Toggle(isOn: $state.fetchDealDetails) {
                    labelRow(
                        title: "Fetch deal details",
                        subtitle: "Restaurant, price & viewers via create-cart. May consume the in-app flyer pitch for that deal.",
                        systemImage: "info.circle.fill"
                    )
                }
                .toggleStyle(.switch)

                #if os(macOS)
                Divider().opacity(0.4)

                Toggle(isOn: $state.keepAwakeWhileListening) {
                    labelRow(
                        title: "Keep Mac awake while listening",
                        subtitle: "Blocks idle sleep so MQTT can stay up. Closing the lid often still sleeps the Mac (especially on battery).",
                        systemImage: "cup.and.saucer.fill"
                    )
                }
                .toggleStyle(.switch)
                .onChange(of: state.keepAwakeWhileListening) { _, _ in
                    state.applyKeepAwakeSetting()
                }

                Divider().opacity(0.4)

                Toggle(isOn: $state.launchAtLoginPref) {
                    labelRow(
                        title: "Launch at login",
                        subtitle: "Start quietly when you sign in to your Mac",
                        systemImage: "power"
                    )
                }
                .toggleStyle(.switch)
                #endif

                Divider().opacity(0.4)

                VStack(alignment: .leading, spacing: 8) {
                    labelRow(
                        title: "Alert cooldown",
                        subtitle: "Ignore repeat cancels for a short window",
                        systemImage: "timer"
                    )
                    HStack(spacing: 10) {
                        Slider(value: $state.cooldownSeconds, in: 30...600, step: 30)
                        Text(cooldownLabel)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }
            }
            .frCard()

            VStack(alignment: .leading, spacing: 6) {
                Text("About")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                #if os(iOS)
                Text("On iPhone, leave FoodRescueBar open (or in recent apps with screen awake) for the most reliable real-time alerts. iOS suspends background network; enable notifications when prompted.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #else
                Text("Mac must stay awake for MQTT. Idle sleep is blocked while listening if enabled; lid-close often still sleeps. Prefer lid open, clamshell (power + external display), or a desktop Mac. Open Zomato to claim — we never auto-checkout.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                #endif

                Text("Not affiliated with Zomato. Personal research use only.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frCard()

            #if os(macOS)
            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit FoodRescueBar", systemImage: "xmark.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var cooldownLabel: String {
        let s = Int(state.cooldownSeconds)
        if s < 60 { return "\(s)s" }
        let m = s / 60
        let r = s % 60
        return r == 0 ? "\(m)m" : "\(m)m\(r)s"
    }

    private func labelRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(FRTheme.brand)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
