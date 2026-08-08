import SwiftUI

struct LocationView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderBar(
                title: "Choose areas",
                subtitle: "Select up to \(AppLimits.maxMonitoredAddresses) addresses to watch",
                backAction: state.selectedLocations.isEmpty ? nil : { state.screen = .home }
            )

            if state.isLoadingLocations {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Loading saved addresses…")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 20)
            } else if state.locations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No addresses found")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Add a delivery address in the official Zomato app, then refresh.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Refresh") {
                        Task { await state.loadLocations() }
                    }
                    #if os(macOS)
                    .buttonStyle(.bordered)
                    #else
                    .buttonStyle(SecondaryButtonStyle())
                    #endif
                }
                .frCard()
            } else {
                HStack {
                    Text("\(state.selectedLocations.count)/\(AppLimits.maxMonitoredAddresses) selected")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !state.selectedLocations.isEmpty {
                        Button("Clear") {
                            state.clearLocationSelection()
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(FRTheme.brand)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(state.locations.prefix(8)) { location in
                        locationRow(location)
                    }
                    if state.locations.count > 8 {
                        Text("Showing first 8 of \(state.locations.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }

                Button {
                    state.confirmLocationSelection()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                        Text(continueLabel)
                    }
                    .frame(maxWidth: .infinity)
                }
                #if os(macOS)
                .buttonStyle(.borderedProminent)
                .tint(FRTheme.brand)
                .controlSize(.large)
                #else
                .buttonStyle(PrimaryButtonStyle(enabled: !state.selectedLocations.isEmpty))
                #endif
                .disabled(state.selectedLocations.isEmpty)

                Button {
                    Task { await state.loadLocations() }
                } label: {
                    Label("Refresh addresses", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                #if os(macOS)
                .buttonStyle(.bordered)
                .controlSize(.large)
                #else
                .buttonStyle(SecondaryButtonStyle())
                #endif
            }

            Button {
                Task { await state.logout() }
            } label: {
                Text("Sign out")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FRTheme.brand)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var continueLabel: String {
        let n = state.selectedLocations.count
        if n == 0 { return "Select addresses" }
        if n == 1 { return "Continue with 1 area" }
        return "Continue with \(n) areas"
    }

    private func locationRow(_ location: UserLocation) -> some View {
        let selected = state.isLocationSelected(location)
        return Button {
            state.toggleLocationSelection(location)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? FRTheme.brand : Color.secondary)
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 3) {
                    Text(location.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(location.fullAddress)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? FRTheme.brand.opacity(0.08) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        selected ? FRTheme.brand.opacity(0.45) : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
