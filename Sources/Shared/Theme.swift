import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Shared visual language: quiet canvas, soft cards, one restrained gradient reserved for AI.
/// Everything stays on the system font; only sizes, weights, spacing and surfaces change.
enum Theme {
    static let cardRadius: CGFloat = 16
    static let homeRadius: CGFloat = 16.4
    static let homeGap: CGFloat = 24
    static let homeColumn: CGFloat = 250
    static let homeChrome: CGFloat = 46
    /// Floating iOS chips: 64pt matches the previous visual weight; add stays a 16.4 card.
    static let homeNav: CGFloat = 64
    static let homeNavGap: CGFloat = 8
    static let homeNavInset: CGFloat = 16
    static let homeNavBottom: CGFloat = 16
    static let homeNavMenuRadius: CGFloat = 22
    static let homeInk = Color(red: 23 / 255, green: 23 / 255, blue: 29 / 255)
    static let homePreview = Color(red: 102 / 255, green: 102 / 255, blue: 113 / 255)
    static let homeLine = Color(red: 238 / 255, green: 238 / 255, blue: 238 / 255)
    static let homeAccent = Color(red: 60 / 255, green: 107 / 255, blue: 157 / 255)
    static let homeFill = Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
    static let homeShadow = Color(red: 60 / 255, green: 60 / 255, blue: 60 / 255).opacity(0.05)
    static let aiColors = [Color(red: 0.45, green: 0.38, blue: 0.96), Color(red: 0.24, green: 0.60, blue: 0.98),
                           Color(red: 0.22, green: 0.79, blue: 0.70)]
    static var aiGradient: LinearGradient {
        LinearGradient(colors: aiColors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var addWash: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Color.white.opacity(0.4), location: 0.066),
                .init(color: Color(red: 207 / 255, green: 228 / 255, blue: 251 / 255).opacity(0.4), location: 0.170),
                .init(color: Color(red: 247 / 255, green: 251 / 255, blue: 254 / 255).opacity(0.4), location: 0.606),
                .init(color: Color(red: 245 / 255, green: 249 / 255, blue: 254 / 255).opacity(0.4), location: 0.853),
                .init(color: Color(red: 165 / 255, green: 205 / 255, blue: 248 / 255).opacity(0.4), location: 1)
            ],
            startPoint: UnitPoint(x: 0.02, y: 0.72),
            endPoint: UnitPoint(x: 0.98, y: 0.18)
        )
    }
}

extension Color {
    /// Page background behind cards; on the Mac it mirrors the grouped iOS palette so cards read
    /// as raised surfaces in both appearances.
    static var canvas: Color {
        #if os(macOS)
        Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0.11, green: 0.11, blue: 0.118, alpha: 1) : .white
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

    func homeSurface(highlighted: Bool = false) -> some View {
        modifier(HomeSurface(highlighted: highlighted))
    }

    /// A small uppercase-free section label, Craft style: light, quiet, aligned with content.
    func sectionLabel() -> some View {
        self.font(.footnote.weight(.medium)).foregroundStyle(Color.muted)
    }
}

private struct HomeSurface: ViewModifier {
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous)
                    .fill(Color.white)
                if highlighted {
                    RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous)
                        .fill(Theme.addWash)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous)
                    .strokeBorder(Theme.homeLine)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
            .shadow(color: Theme.homeShadow, radius: 6, y: 3)
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
            // No ProgressView here: inside a styled Button on macOS it would take over the
            // accessibility role of the whole card.
            HStack(spacing: 6) {
                PulseDot()
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

/// Small native pasteboard helpers shared by menus.
enum Clipboard {
    static func copy(_ text: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #else
        UIPasteboard.general.string = text
        #endif
    }

    static func copy(imageData: Data) {
        #if os(macOS)
        guard let image = NSImage(data: imageData) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
        #else
        UIPasteboard.general.image = UIImage(data: imageData)
        #endif
    }
}

/// A SwiftUI image built from encoded bytes, for sharing and previews.
func platformImage(_ data: Data) -> Image? {
    #if os(macOS)
    NSImage(data: data).map { Image(nsImage: $0) }
    #else
    UIImage(data: data).map { Image(uiImage: $0) }
    #endif
}

/// A quiet breathing dot for work in progress.
struct PulseDot: View {
    var body: some View {
        Circle().fill(Theme.aiGradient).frame(width: 7, height: 7)
            .phaseAnimator([0.35, 1.0]) { view, phase in view.opacity(phase).scaleEffect(0.8 + phase * 0.2) }
                animation: { _ in .easeInOut(duration: 0.9) }
            .accessibilityHidden(true)
    }
}

/// Mac sheets show only cancel and confirm in their bar, so other document actions live in a
/// small header row on the Mac and in the toolbar on iPhone.
struct DocumentActions<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        #if os(macOS)
        HStack(spacing: 8) { Spacer(); content }.controlSize(.small)
        #else
        EmptyView()
        #endif
    }
}
