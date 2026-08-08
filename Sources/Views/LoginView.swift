import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HeaderBar(
                title: "Food Rescue Bar",
                subtitle: "Sign in with your Zomato account"
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("Phone number")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                PhoneField(text: $state.phoneDigits)

                Text("OTP via")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                HStack(spacing: 8) {
                    ForEach(OTPChannel.allCases) { channel in
                        Button {
                            state.otpChannel = channel
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: channel.systemImage)
                                Text(channel.title)
                            }
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(state.otpChannel == channel ? FRTheme.brand : Color.primary.opacity(0.06))
                            )
                            .foregroundStyle(state.otpChannel == channel ? .white : .primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if state.otpSent {
                    Text("One-time password")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                    OTPField(text: $state.otpCode)
                }
            }
            .frCard()

            if state.otpSent {
                Button {
                    Task { await state.verifyOTP() }
                } label: {
                    HStack {
                        if state.isBusy { ProgressView().controlSize(.small).tint(.white) }
                        Text(state.isBusy ? "Verifying…" : "Verify & continue")
                    }
                }
                #if os(macOS)
                .buttonStyle(.borderedProminent)
                .tint(FRTheme.brand)
                .controlSize(.large)
                #else
                .buttonStyle(PrimaryButtonStyle(enabled: !state.isBusy && state.otpCode.count >= 4))
                #endif
                .disabled(state.isBusy || state.otpCode.count < 4)

                Button("Use a different number") {
                    state.otpSent = false
                    state.otpCode = ""
                }
                #if os(macOS)
                .buttonStyle(.bordered)
                .controlSize(.large)
                #else
                .buttonStyle(SecondaryButtonStyle())
                #endif
            } else {
                Button {
                    Task { await state.sendOTP() }
                } label: {
                    HStack {
                        if state.isBusy {
                            #if os(macOS)
                            ProgressView().controlSize(.small)
                            #else
                            ProgressView().controlSize(.small).tint(.white)
                            #endif
                        }
                        Text(state.isBusy ? "Sending…" : "Send OTP")
                    }
                    .frame(maxWidth: .infinity)
                }
                #if os(macOS)
                .buttonStyle(.borderedProminent)
                .tint(FRTheme.brand)
                .controlSize(.large)
                #else
                .buttonStyle(PrimaryButtonStyle(enabled: !state.isBusy && state.phoneDigits.filter(\.isNumber).count >= 10))
                #endif
                .disabled(state.isBusy || state.phoneDigits.filter(\.isNumber).count < 10)
            }

            disclaimer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disclaimer: some View {
        Text("Unofficial personal tool. Uses private APIs; not affiliated with Zomato. May violate ToS — use at your own risk.")
            .font(.system(size: 10))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
