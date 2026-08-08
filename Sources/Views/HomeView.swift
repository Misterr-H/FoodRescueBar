import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: AppState
    @State private var expandedEventId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderBar(
                title: "Food Rescue",
                subtitle: state.user.map { "Hi, \($0.name)" } ?? "Multi-area listener"
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
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
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

            HStack {
                Text("Areas")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(state.isMonitoring ? "Locked" : "Edit") {
                    guard !state.isMonitoring else { return }
                    state.screen = .location
                    Task { await state.loadLocations() }
                }
                .font(.system(size: 11, weight: .semibold))
                .buttonStyle(.plain)
                .foregroundStyle(state.isMonitoring ? Color.secondary : FRTheme.brand)
            }

            if state.selectedLocations.isEmpty {
                Text("No addresses selected — tap Edit to choose areas.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 6) {
                    ForEach(displayStatuses) { status in
                        locationStatusRow(status)
                    }
                }
            }

            if state.isMonitoring {
                Text("Stop listening to change which areas are watched.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                statPill(title: "Areas", value: "\(state.selectedLocations.count)")
                statPill(title: "Alerts today", value: "\(state.alertCountToday)")
                statPill(
                    title: "Last alert",
                    value: state.lastAlertAt?.formatted(date: .omitted, time: .shortened) ?? "—"
                )
            }
        }
        .frCard()
    }

    private var displayStatuses: [LocationMonitorStatus] {
        if !state.locationStatuses.isEmpty {
            return state.locationStatuses
        }
        return state.selectedLocations.map {
            LocationMonitorStatus(
                addressId: $0.addressId,
                name: $0.name,
                state: .idle,
                detail: $0.fullAddress
            )
        }
    }

    private func locationStatusRow(_ status: LocationMonitorStatus) -> some View {
        HStack(spacing: 8) {
            StatusDot(color: color(for: status.state), pulse: status.state.isLive)
            VStack(alignment: .leading, spacing: 1) {
                Text(status.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(status.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Text(shortLabel(for: status.state))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color(for: status.state))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func color(for state: MonitorState) -> Color {
        switch state {
        case .connected: return FRTheme.success
        case .connecting, .reconnecting: return FRTheme.warning
        case .error: return FRTheme.brand
        case .idle: return .secondary
        }
    }

    private func shortLabel(for state: MonitorState) -> String {
        switch state {
        case .connected: return "Live"
        case .connecting: return "…"
        case .reconnecting: return "Retry"
        case .error: return "Err"
        case .idle: return "Off"
        }
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
        .padding(.horizontal, 8)
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
                .frame(maxWidth: .infinity)
            }
            #if os(macOS)
            .buttonStyle(.borderedProminent)
            .tint(FRTheme.brand)
            .controlSize(.large)
            #else
            .buttonStyle(PrimaryButtonStyle(enabled: !state.selectedLocations.isEmpty || state.isMonitoring))
            #endif
            .disabled(state.selectedLocations.isEmpty && !state.isMonitoring)

            HStack(spacing: 8) {
                Button {
                    state.openZomato()
                } label: {
                    Label("Open Zomato", systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                #if os(macOS)
                .buttonStyle(.bordered)
                .controlSize(.large)
                #else
                .buttonStyle(SecondaryButtonStyle())
                #endif

                Button {
                    state.screen = .settings
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity)
                }
                #if os(macOS)
                .buttonStyle(.bordered)
                .controlSize(.large)
                #else
                .buttonStyle(SecondaryButtonStyle())
                #endif
            }
        }
    }

    private var eventFeed: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent activity")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if state.events.count > 1 {
                    Button("Clean up") {
                        state.pruneDuplicateEvents()
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(FRTheme.brand)
                }
            }

            if state.events.isEmpty {
                EmptyEventsView()
                    .frCard(padding: 10)
            } else {
                VStack(spacing: 8) {
                    ForEach(state.events.prefix(6)) { event in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                expandedEventId = expandedEventId == event.id ? nil : event.id
                            }
                        } label: {
                            EventRow(event: event, expanded: expandedEventId == event.id)
                        }
                        .buttonStyle(.plain)

                        if event.id != state.events.prefix(6).last?.id {
                            Divider().opacity(0.35)
                        }
                    }
                    if state.events.count > 6 {
                        Text("+\(state.events.count - 6) more")
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
