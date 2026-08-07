import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderBar(
                title: "Food Rescue",
                subtitle: state.user.map { "Hi, \($0.name)" } ?? "Listening for nearby cancels"
            )

            statusCard
            actions
            eventFeed
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                StatusDot(color: state.statusColor, pulse: state.monitorState.isLive)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.monitorState.label)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(state.lastConnectedDescription)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if state.isMonitoring {
                    Text("LIVE")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(0.6)
                        .foregroundStyle(FRTheme.success)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(FRTheme.success.opacity(0.15)))
                }
            }

            Divider().opacity(0.45)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(FRTheme.brand)
                    .font(.system(size: 14))
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(state.selectedLocation?.name ?? "No address")
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                    Text(state.selectedLocation?.fullAddress ?? "Choose a saved Zomato address")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button("Change") {
                    state.screen = .location
                    Task { await state.loadLocations() }
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(FRTheme.brand)
                .padding(.top, 1)
            }

            HStack(spacing: 8) {
                statPill(title: "Alerts today", value: "\(state.alertCountToday)")
                statPill(
                    title: "Last alert",
                    value: state.lastAlertAt?.formatted(date: .omitted, time: .shortened) ?? "—"
                )
            }
        }
        .frCard()
    }

    private func statPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private var actions: some View {
        VStack(spacing: 8) {
            Button {
                Task { await state.toggleMonitoring() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: state.isMonitoring ? "stop.circle.fill" : "play.circle.fill")
                    Text(state.isMonitoring ? "Stop listening" : "Start listening")
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 8) {
                Button {
                    state.openZomato()
                } label: {
                    Label("Open Zomato", systemImage: "arrow.up.right.square")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(SecondaryButtonStyle())

                Button {
                    state.screen = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
    }

    private var eventFeed: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Recent activity")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if state.events.isEmpty {
                EmptyEventsView()
                    .frCard(padding: 10)
            } else {
                VStack(spacing: 4) {
                    ForEach(state.events.prefix(5)) { event in
                        EventRow(event: event)
                    }
                    if state.events.count > 5 {
                        Text("+\(state.events.count - 5) more")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                    }
                }
                .frCard(padding: 10)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                Task { await state.logout() }
            } label: {
                Text("Sign out")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Text("Claim in official Zomato app")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
        }
        .padding(.top, 2)
    }
}
