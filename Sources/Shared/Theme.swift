import SwiftUI
#if os(macOS)
import AppKit
#endif

/// Shared visual language: quiet canvas, soft cards, one restrained gradient reserved for AI.
/// Everything stays on the system font; only sizes, weights, spacing and surfaces change.
enum Theme {
    static let cardRadius: CGFloat = 16
    static let aiColors = [Color(red: 0.45, green: 0.38, blue: 0.96), Color(red: 0.24, green: 0.60, blue: 0.98),
                           Color(red: 0.22, green: 0.79, blue: 0.70)]
    static var aiGradient: LinearGradient {
        LinearGradient(colors: aiColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Color {
    /// Page background behind cards; on the Mac it mirrors the grouped iOS palette so cards read
    /// as raised surfaces in both appearances.
    static var canvas: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1) : NSColor(red: 0.95, green: 0.95, blue: 0.965, alpha: 1)
        })
        #else
        Color(uiColor: .systemGroupedBackground)
        #endif
    }
    /// Raised surface for cards and documents.
    static var card: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.173, green: 0.173, blue: 0.18, alpha: 1) : .white
        })
        #else
        Color(uiColor: .secondarySystemGroupedBackground)
        #endif
    }
    /// Secondary text that still passes contrast audits.
    static let muted = Color.primary.opacity(0.72)
}

struct CardStyle: ViewModifier {
    var radius: CGFloat = Theme.cardRadius
    var padding: CGFloat? = nil
    var elevated = true

    func body(content: Content) -> some View {
        content
            .padding(.all, padding ?? 0)
            .background(Color.card, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            .shadow(color: .black.opacity(elevated ? 0.06 : 0), radius: 12, y: 4)
    }
}

extension View {
    func card(radius: CGFloat = Theme.cardRadius, padding: CGFloat? = nil, elevated: Bool = true) -> some View {
        modifier(CardStyle(radius: radius, padding: padding, elevated: elevated))
    }

    /// A small uppercase-free section label, Craft style: light, quiet, aligned with content.
    func sectionLabel() -> some View {
        self.font(.footnote.weight(.medium)).foregroundStyle(Color.muted)
    }
}

/// A rounded tag for topics, kinds and states.
struct Chip: View {
    let text: String
    var symbol: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.caption2.weight(.semibold)) }
            Text(text).font(.caption.weight(.medium)).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundStyle(tint ?? Color.primary.opacity(0.8))
        .background((tint ?? Color.primary).opacity(tint == nil ? 0.07 : 0.12), in: Capsule())
    }
}

/// The sparkle that marks anything produced by the AI layer.
struct Sparkle: View {
    var size: CGFloat = 15
    var body: some View {
        Image(systemName: "sparkles").font(.system(size: size, weight: .semibold))
            .foregroundStyle(Theme.aiGradient)
            .accessibilityHidden(true)
    }
}

/// Analysis state shown only when it adds information; ready items stay quiet.
struct StatusPill: View {
    let status: String
    let partial: Bool

    var body: some View {
        switch status {
        case "queued", "processing":
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text(status == "queued" ? "Na fila para análise" : "Analisando").font(.caption.weight(.medium))
            }.foregroundStyle(Color.muted)
        case "error":
            Chip(text: "Falha na análise", symbol: "exclamationmark.circle", tint: .orange)
        default:
            if partial { Chip(text: "Análise parcial", symbol: "circle.lefthalf.filled") }
        }
    }
}

/// Moving highlight for loading placeholders.
struct Shimmer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .redacted(reason: .placeholder)
            .overlay {
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, Color.card.opacity(0.9), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.6)
                        .phaseAnimator([false, true]) { view, moved in
                            view.offset(x: moved ? geometry.size.width : -geometry.size.width * 0.6)
                        } animation: { _ in .linear(duration: 1.3) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}

/// A squared tile with the kind symbol, used where an item has no picture.
struct KindTile: View {
    let symbol: String
    var size: CGFloat = 40
    var body: some View {
        Image(systemName: symbol).font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Color.primary.opacity(0.7))
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}
