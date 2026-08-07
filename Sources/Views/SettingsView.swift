import SwiftUI
import AppKit

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

                Toggle(isOn: $state.launchAtLoginPref) {
                    labelRow(
                        title: "Launch at login",
                        subtitle: "Start quietly when you sign in to your Mac",
                        systemImage: "power"
                    )
                }
                .toggleStyle(.switch)

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
                Text("Listens to Food Rescue MQTT only — never auto-claims (avoids burning the in-app pitch). Open Zomato when you get an alert.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Not affiliated with Zomato. Personal research use only.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frCard()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit FoodRescueBar", systemImage: "xmark.circle")
            }
            .buttonStyle(SecondaryButtonStyle())
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
