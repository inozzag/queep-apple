import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Queep V2 tokens, taken from the "Queep V2" Figma file (`i4zmG8DjKzkHgq6mkLT8Hh`).
/// One warm gray ink on white, a pale fill for every surface, lime for the main action and a
/// dark stage for promotional art. Type stays on the system font.
enum Theme {
    // MARK: Palette

    /// Text, icons and the logo. `#484848`.
    static let ink = Color(hex: 0x484848)
    /// Secondary text and counters. `#696969`.
    static let inkSoft = Color(hex: 0x696969)
    /// Placeholders and quiet captions: the ink at half strength.
    static let inkFaint = Color(hex: 0x484848, opacity: 0.5)
    /// Pages, sheets and cards.
    static let surface = Color.white
    /// Tiles, chrome and icon wells. `#F5F5F5`.
    static let fill = Color(hex: 0xF5F5F5)
    /// Fill under the pointer or a press.
    static let fillPressed = Color(hex: 0xEDEDED)
    /// Search field. `#FCFCFC`.
    static let field = Color(hex: 0xFCFCFC)
    /// Hairline around grouped controls. `#F5F5F5`.
    static let line = Color(hex: 0xF5F5F5)
    /// Outlined buttons and the sign-in card edge. `#E7E5E3`.
    static let lineStrong = Color(hex: 0xE7E5E3)
    /// Main action. `#DFE6B2`.
    static let lime = Color(hex: 0xDFE6B2)
    /// Middle green of the logo washes. `#ACBE95`.
    static let sage = Color(hex: 0xACBE95)
    /// Plan labels, checks and text on lime washes. `#3D6855`.
    static let forest = Color(hex: 0x3D6855)
    /// Text on a lime button. `#333333`.
    static let onLime = Color(hex: 0x333333)
    /// Dark action, as in "Ver original". `#211F12`.
    static let action = Color(hex: 0x211F12)
    /// Text and icons on `action` and on the dark stage. `#F5F5F5`.
    static let onAction = Color(hex: 0xF5F5F5)
    /// Promotional stage, top to bottom: `#13110C` to `#0A0807`.
    static let night = Color(hex: 0x13110C)
    static let nightDeep = Color(hex: 0x0A0807)
    /// Sign-in art panel. `#1E1E1E`.
    static let panel = Color(hex: 0x1E1E1E)
    static let danger = Color(red: 0.70, green: 0.16, blue: 0.14)

    // MARK: Shape and size

    /// Containers, tiles and cards.
    static let radius: CGFloat = 22
    /// Controls that sit inside a container.
    static let controlRadius: CGFloat = 16.4
    /// A chrome container: 6pt inset around a 46pt control.
    static let chrome: CGFloat = 60
    static let control: CGFloat = 46
    static let chromeInset: CGFloat = 6
    /// Capsule pills on the opened item (Esc, Anterior, Próximo).
    static let pill: CGFloat = 39
    /// Full-width actions and text fields.
    #if os(iOS)
    static let button: CGFloat = 52
    #else
    static let button: CGFloat = 48
    #endif
    /// Space between gallery tiles.
    static let gap: CGFloat = 18
    /// Inset of badges and marks inside a tile.
    static let tileInset: CGFloat = 12
    #if os(iOS)
    static let badge: CGFloat = 26
    static let tileTitle: CGFloat = 15
    #else
    static let badge: CGFloat = 28
    static let tileTitle: CGFloat = 17
    #endif

    /// Side margin of a page: 97pt on a 1440pt window, never under 20.
    static func pageMargin(for width: CGFloat) -> CGFloat {
        #if os(iOS)
        return 16
        #else
        return min(97, max(20, (width * 0.0674).rounded()))
        #endif
    }

    // MARK: iPhone floating chrome

    static let nav: CGFloat = 60
    static let navGap: CGFloat = 8
    static let navInset: CGFloat = 16
    static let navBottom: CGFloat = 16

    // MARK: Washes

    /// Logo greens over white, as on the PRO label and the paywall action.
    /// `strength` is the gradient's alpha (0.4 on labels, 0.7 on the action); `angle` is CSS degrees.
    static func limeWash(strength: Double = 0.4, angle: Double = 32.1) -> LinearGradient {
        cssGradient(angle: angle, stops: [
            .init(color: Color.white.opacity(strength), location: 0.080),
            .init(color: sage.opacity(strength), location: 0.080),
            .init(color: lime.opacity(strength), location: 0.552),
            .init(color: forest.opacity(strength), location: 1.0),
        ])
    }

    /// Gray version of the label wash, for the free plan.
    static var grayWash: LinearGradient {
        cssGradient(angle: 32.1, stops: [
            .init(color: Color.white.opacity(0.4), location: 0.080),
            .init(color: Color(hex: 0xBCBCBC, opacity: 0.4), location: 0.080),
            .init(color: Color(hex: 0xE6E6E2, opacity: 0.4), location: 0.552),
            .init(color: Color(hex: 0x4A4C4B, opacity: 0.4), location: 1.0),
        ])
    }

    /// Soft green for anything the AI layer produced.
    static var aiGradient: LinearGradient {
        LinearGradient(colors: [sage, forest], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// CSS `linear-gradient(<angle>deg, …)`: 0° points up, angles turn clockwise.
    static func cssGradient(angle: Double, stops: [Gradient.Stop]) -> LinearGradient {
        let radians = angle * .pi / 180
        let dx = sin(radians) / 2
        let dy = -cos(radians) / 2
        return LinearGradient(stops: stops,
                              startPoint: UnitPoint(x: 0.5 - dx, y: 0.5 - dy),
                              endPoint: UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }

    /// Page background. Queep stays on a white page in every appearance.
    static var canvas: Color { Theme.surface }
    /// Raised surface for documents and editors.
    static var card: Color { Theme.surface }
    /// Secondary text that still passes contrast audits.
    static var muted: Color { Theme.inkSoft }
}

// MARK: - Surfaces

/// How a container or control is painted.
enum SurfaceStyle {
    /// `#F5F5F5`, no edge: tiles, chrome, icon wells.
    case fill
    /// White with a 1pt `#F5F5F5` edge: grouped controls such as the tabs or the plan list.
    case outline
    /// `#FCFCFC` with an edge: the search field.
    case field
    /// White with a 1pt `#E7E5E3` edge: secondary buttons and the sign-in card.
    case outlineStrong
    /// White, no edge.
    case plain
}

private struct Surface: ViewModifier {
    var style: SurfaceStyle
    var radius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                switch style {
                case .fill: shape.fill(Theme.fill)
                case .field: shape.fill(Theme.field)
                case .outline, .outlineStrong, .plain: shape.fill(Theme.surface)
                }
            }
            .overlay {
                switch style {
                case .outline, .field: shape.strokeBorder(Theme.line, lineWidth: 1)
                case .outlineStrong: shape.strokeBorder(Theme.lineStrong, lineWidth: 1)
                case .fill, .plain: EmptyView()
                }
            }
    }
}

extension View {
    /// Paints a V2 surface behind the view. Containers use `Theme.radius`; controls `Theme.controlRadius`.
    func surface(_ style: SurfaceStyle = .fill, radius: CGFloat = Theme.radius) -> some View {
        modifier(Surface(style: style, radius: radius))
    }

    /// A 60pt chrome container: the 6pt inset around 46pt controls, as in the gallery header.
    func chrome(_ style: SurfaceStyle = .fill) -> some View {
        padding(Theme.chromeInset)
            .frame(minHeight: Theme.chrome)
            .surface(style, radius: Theme.radius)
    }

    /// Clips to a gallery tile.
    func galleryTile() -> some View {
        clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }

    /// Raised document surface. Kept for editors that still float a card.
    func card(radius: CGFloat = Theme.radius, padding: CGFloat? = nil, elevated: Bool = true) -> some View {
        self.padding(.all, padding ?? 0)
            .surface(.outline, radius: radius)
            .shadow(color: .black.opacity(elevated ? 0.04 : 0), radius: 12, y: 4)
    }

    /// A quiet label above a group: 13pt, soft ink.
    func sectionLabel() -> some View {
        font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.inkSoft)
    }
}

// MARK: - Buttons

/// Every V2 button. `primary` is the lime action; `promo` adds the logo wash; `neutral` is the
/// gray chrome; `dark` is "Ver original"; `outline` is "Criar conta".
struct QueepButtonStyle: ButtonStyle {
    enum Kind {
        case primary, promo, neutral, dark, outline, destructive, quiet
    }

    var kind: Kind = .neutral
    var height: CGFloat = Theme.button
    var stretches = true
    var radius: CGFloat = Theme.controlRadius

    func makeBody(configuration: Configuration) -> some View {
        QueepButtonBody(configuration: configuration, kind: kind, height: height,
                        stretches: stretches, radius: radius)
    }
}

extension ButtonStyle where Self == QueepButtonStyle {
    /// Full-width lime action.
    static var queepPrimary: QueepButtonStyle { QueepButtonStyle(kind: .primary) }

    static func queep(_ kind: QueepButtonStyle.Kind, height: CGFloat = Theme.button,
                      stretches: Bool = true, radius: CGFloat = Theme.controlRadius) -> QueepButtonStyle {
        QueepButtonStyle(kind: kind, height: height, stretches: stretches, radius: radius)
    }
}

/// `isEnabled` and the pointer are only readable from a view, not from the style itself.
private struct QueepButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: QueepButtonStyle.Kind
    let height: CGFloat
    let stretches: Bool
    let radius: CGFloat
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        configuration.label
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 20)
            .frame(maxWidth: stretches ? .infinity : nil)
            .frame(height: height)
            .background { fillShape(shape) }
            .overlay {
                if kind == .outline { shape.strokeBorder(Theme.lineStrong, lineWidth: 1) }
            }
            .contentShape(shape)
            .opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.15), value: hovered)
            .onHover { hovered = $0 }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .neutral, .outline: Theme.ink
        case .promo: Theme.onLime
        case .dark: Theme.onAction
        case .destructive: Theme.danger
        case .quiet: Theme.inkSoft
        }
    }

    @ViewBuilder private func fillShape(_ shape: RoundedRectangle) -> some View {
        switch kind {
        case .primary:
            shape.fill(Theme.lime).brightness(hovered ? -0.02 : 0)
        case .promo:
            ZStack {
                shape.fill(Theme.lime)
                shape.fill(Theme.limeWash(strength: 0.7, angle: 15.4))
            }
            .brightness(hovered ? -0.02 : 0)
        case .neutral, .destructive:
            shape.fill(hovered ? Theme.fillPressed : Theme.fill)
        case .dark:
            shape.fill(Theme.action).brightness(hovered ? 0.06 : 0)
        case .outline:
            shape.fill(hovered ? Theme.field : Theme.surface)
        case .quiet:
            shape.fill(hovered ? Theme.fill : Color.clear)
        }
    }
}

/// The primary action under its earlier name. It is the lime button now.
struct MasterButtonStyle: ButtonStyle {
    var height: CGFloat = Theme.button

    func makeBody(configuration: Configuration) -> some View {
        QueepButtonStyle(kind: .primary, height: height).makeBody(configuration: configuration)
    }
}

// MARK: - Small pieces shared by many screens

/// A rounded tag for topics, kinds and states.
struct Chip: View {
    let text: String
    var symbol: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
            Text(text).font(.system(size: 12, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 10).frame(height: 24)
        .foregroundStyle(tint ?? Theme.inkSoft)
        .background((tint ?? Theme.fill).opacity(tint == nil ? 1 : 0.12),
                    in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

/// The mark on anything produced by the AI layer.
struct Sparkle: View {
    var size: CGFloat = 15
    var body: some View {
        QueepIcon("ri-sparkling-2-line", size: size + 2, color: Theme.forest)
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
                Text(status == "queued" ? "Na fila para análise" : "Analisando").font(.system(size: 12, weight: .medium))
            }.foregroundStyle(Theme.inkSoft)
        case "error":
            Chip(text: "Falha na análise", symbol: "exclamationmark.circle", tint: Theme.danger)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
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
                    LinearGradient(colors: [.clear, Color.white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.6)
                        .phaseAnimator([false, true]) { view, moved in
                            view.offset(x: moved ? geometry.size.width : -geometry.size.width * 0.6)
                        } animation: { _ in .linear(duration: 1.3) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
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
        Image(systemName: symbol).font(.system(size: size * 0.4, weight: .medium))
            .foregroundStyle(Theme.ink)
            .frame(width: size, height: size)
            .background(Theme.fill, in: RoundedRectangle(cornerRadius: size * 0.36, style: .continuous))
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
        Circle().fill(Theme.forest).frame(width: 7, height: 7)
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
