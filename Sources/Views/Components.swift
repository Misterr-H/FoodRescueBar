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

    private var accent: Color {
        if event.isLikelyNoise || event.enrichmentFailed { return .secondary }
        if event.isVerifiedDeal { return FRTheme.brand }
        if event.type == .orderClaimed { return FRTheme.success }
        return FRTheme.warning
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accent)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(accent.opacity(0.12)))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(event.titleText)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(event.isLikelyNoise ? .secondary : .primary)
                            .lineLimit(3)
                        if event.isEnriching {
                            ProgressView().controlSize(.mini)
                        }
                    }

                    HStack(alignment: .top, spacing: 4) {
                        Image(systemName: "mappin")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(accent)
                            .padding(.top, 1)
                        Text(event.subscribedAreaText)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

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

                    if expanded, event.isVerifiedDeal {
                        expandedMeta
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 4)
        // Not a Button — non-interactive to avoid SwiftUI gesture crashes
        .allowsHitTesting(false)
    }

    private var iconName: String {
        if event.isLikelyNoise || event.enrichmentFailed { return "moon.zzz.fill" }
        if event.isVerifiedDeal { return "bolt.fill" }
        if event.type == .orderClaimed { return "checkmark.seal.fill" }
        if event.isEnriching { return "hourglass" }
        return "bolt.fill"
    }

    @ViewBuilder
    private var expandedMeta: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let orderId = event.orderId {
                Text("Order \(orderId)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let resId = event.restaurantId {
                Text("Restaurant id \(resId)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let lat = event.restaurantLat, let lng = event.restaurantLng {
                Text(String(format: "Map · %.4f, %.4f", lat, lng))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            if let expiry = event.cartExpiry {
                Text("Expires \(expiry.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 2)
    }
}
