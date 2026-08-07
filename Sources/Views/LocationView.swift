import SwiftUI

struct LocationView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderBar(
                title: "Choose area",
                subtitle: "Food Rescue is scoped to a saved address",
                backAction: state.selectedLocation != nil ? { state.screen = .home } : nil
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
                    .buttonStyle(SecondaryButtonStyle())
                }
                .frCard()
            } else {
                VStack(spacing: 8) {
                    ForEach(state.locations.prefix(6)) { location in
                        locationRow(location)
                    }
                    if state.locations.count > 6 {
                        Text("Showing first 6 of \(state.locations.count)")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity)
                    }
                }

                Button {
                    Task { await state.loadLocations() }
                } label: {
                    Label("Refresh addresses", systemImage: "arrow.clockwise")
                }
                .buttonStyle(SecondaryButtonStyle())
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

    private func locationRow(_ location: UserLocation) -> some View {
        Button {
            state.selectLocation(location)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(FRTheme.brand)
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

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        state.selectedLocation?.addressId == location.addressId
                            ? FRTheme.brand.opacity(0.45)
                            : Color.primary.opacity(0.06),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
