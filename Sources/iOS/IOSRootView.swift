import SwiftUI

/// Full-screen iOS shell reusing the same screens as the macOS popover.
struct IOSRootView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var alarm = AlarmCenter.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    if let banner = state.bannerMessage {
                        BannerToast(message: banner, isError: state.bannerIsError)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                    Group {
                        switch state.screen {
                        case .login:
                            LoginView()
                        case .location:
                            LocationView()
                        case .home:
                            HomeView()
                        case .settings:
                            SettingsView()
                        }
                    }
                    .padding(16)
                }
            }
            .background(FRTheme.surface.ignoresSafeArea())
            .navigationTitle("Food Rescue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if state.isLoggedIn {
                        Image(systemName: state.menuBarSystemImage)
                            .foregroundStyle(state.statusColor)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
            }
            .safeAreaInset(edge: bottomBannerEdge) {
                if state.isMonitoring {
                    listeningBanner
                }
            }
        }
        .animation(.easeInOut(duration: 0.15), value: state.screen)
        .fullScreenCover(item: Binding(
            get: { alarm.activeAlarm.map { AlarmItem(event: $0) } },
            set: { if $0 == nil { alarm.acknowledge() } }
        )) { item in
            AlarmPanelView(
                event: item.event,
                onAcknowledge: { alarm.acknowledge() },
                onOpenZomato: { alarm.acknowledgeAndOpenZomato() }
            )
            .interactiveDismissDisabled(true)
        }
    }

    private struct AlarmItem: Identifiable {
        let event: RescueEvent
        var id: String { event.id }
    }

    private var bottomBannerEdge: VerticalEdge { .bottom }

    private var listeningBanner: some View {
        HStack(spacing: 10) {
            StatusDot(color: state.statusColor, pulse: state.monitorState.isLive)
            VStack(alignment: .leading, spacing: 2) {
                Text(state.monitorState.label)
                    .font(.system(size: 13, weight: .semibold))
                Text(state.lastConnectedDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            if state.monitorState.isLive {
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(FRTheme.success)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(FRTheme.success.opacity(0.15)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}
