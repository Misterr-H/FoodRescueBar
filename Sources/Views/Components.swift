import SwiftUI

struct HeaderBar: View {
    let title: String
    var subtitle: String? = nil
    var backAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            if let backAction {
                Button(action: backAction) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "leaf.fill")
                .foregroundStyle(FRTheme.brand)
                .font(.system(size: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct BannerToast: View {
    let message: String
    let isError: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isError ? FRTheme.brand : FRTheme.success)
                .font(.system(size: 12))
            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isError ? FRTheme.brand.opacity(0.12) : FRTheme.success.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder((isError ? FRTheme.brand : FRTheme.success).opacity(0.25), lineWidth: 1)
        )
        .transition(.opacity)
    }
}

struct PhoneField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text("+91")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))

            TextField("10-digit mobile", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .onChange(of: text) { _, new in
                    let digits = new.filter(\.isNumber)
                    if digits != new { text = digits }
                    if text.count > 12 { text = String(text.prefix(12)) }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

struct OTPField: View {
    @Binding var text: String

    var body: some View {
        TextField("Enter OTP", text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 18, weight: .semibold, design: .rounded))
            .multilineTextAlignment(.center)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .onChange(of: text) { _, new in
                let digits = new.filter(\.isNumber)
                if digits != new { text = digits }
                if text.count > 8 { text = String(text.prefix(8)) }
            }
    }
}

struct EmptyEventsView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.primary.opacity(0.06)))

            VStack(alignment: .leading, spacing: 2) {
                Text("No rescues yet")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Cancels show restaurant, price, and which of your areas fired.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EventRow: View {
    let event: RescueEvent
    var expanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: event.type == .orderCancelled ? "bolt.fill" : "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(event.type == .orderCancelled ? FRTheme.brand : FRTheme.success)
                    .frame(width: 22, height: 22)
                    .background(
                        Circle().fill((event.type == .orderCancelled ? FRTheme.brand : FRTheme.success).opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(event.titleText)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(expanded ? 3 : 1)
                        if event.isEnriching {
                            ProgressView().controlSize(.mini)
                        }
                    }

                    // Subscribed area — always visible for multi-location
                    Label {
                        Text(event.subscribedAreaText)
                            .lineLimit(expanded ? 3 : 1)
                    } icon: {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(FRTheme.brand)
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)

                    HStack(spacing: 6) {
                        if let price = event.priceText {
                            Text(price)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(FRTheme.brand)
                        }
                        if let viewers = event.viewersCount, viewers > 0 {
                            Text("· \(viewers) watching")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(event.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }

                    if expanded {
                        expandedMeta
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var expandedMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let orderId = event.orderId {
                metaLine(icon: "number", text: "Order \(orderId)")
            }
            if let resId = event.restaurantId {
                metaLine(icon: "storefront", text: "Res ID \(resId)")
            }
            if let lat = event.restaurantLat, let lng = event.restaurantLng {
                metaLine(icon: "map", text: String(format: "Restaurant · %.4f, %.4f", lat, lng))
            }
            if let expiry = event.cartExpiry {
                metaLine(icon: "timer", text: "Expires \(expiry.formatted(date: .omitted, time: .shortened))")
            }
            if event.enrichmentFailed {
                metaLine(icon: "exclamationmark.triangle", text: "Couldn’t load deal details (pitch may already be used)")
            }
            if !event.isEnriching && event.restaurantName == nil && event.type == .orderCancelled && !event.enrichmentFailed {
                metaLine(icon: "info.circle", text: "Enable “Fetch deal details” in Settings for restaurant & price")
            }
        }
        .padding(.top, 2)
    }

    private func metaLine(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)
            .lineLimit(2)
    }
}
