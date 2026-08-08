import SwiftUI
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

enum FRTheme {
    static let brand = Color(red: 0.886, green: 0.216, blue: 0.267)
    static let brandSoft = Color(red: 0.886, green: 0.216, blue: 0.267).opacity(0.12)
    static let success = Color(red: 0.18, green: 0.72, blue: 0.45)
    static let warning = Color(red: 0.95, green: 0.62, blue: 0.18)

    #if os(macOS)
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let card = Color(nsColor: .controlBackgroundColor)
    #else
    static let surface = Color(uiColor: .systemBackground)
    static let card = Color(uiColor: .secondarySystemBackground)
    #endif

    static let secondaryText = Color.secondary

    /// Fixed popover width on macOS MenuBarExtra.
    static let popoverWidth: CGFloat = 360
    static let corner: CGFloat = 12
    static let contentPadding: CGFloat = 14
}

struct CardBackground: ViewModifier {
    var padding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: FRTheme.corner, style: .continuous)
                    .fill(FRTheme.card.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: FRTheme.corner, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func frCard(padding: CGFloat = 12) -> some View {
        modifier(CardBackground(padding: padding))
    }

    /// Size the menu-bar panel to its content (macOS).
    func frPopoverPanel() -> some View {
        self
            .frame(width: FRTheme.popoverWidth, alignment: .topLeading)
            .fixedSize(horizontal: true, vertical: true)
    }
}

struct StatusDot: View {
    let color: Color
    var pulse: Bool = false
    @State private var animating = false

    var body: some View {
        ZStack {
            if pulse {
                Circle()
                    .fill(color.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(animating ? 1.45 : 1)
                    .opacity(animating ? 0.35 : 0.7)
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .frame(width: 14, height: 14)
        .onAppear {
            guard pulse else { return }
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                animating = true
            }
        }
        .onChange(of: pulse) { _, isPulsing in
            if isPulsing {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                    animating = true
                }
            } else {
                animating = false
            }
        }
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var enabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(enabled ? FRTheme.brand : Color.gray.opacity(0.4))
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
            )
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Rectangle())
    }
}
