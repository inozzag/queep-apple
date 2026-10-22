import QueepCore
import SwiftUI

// MARK: - Icons and brand

/// A Remix icon from the asset catalog (`ri-*`), tinted unless it carries its own colours.
struct QueepIcon: View {
    let asset: String
    var size: CGFloat = 24
    var color: Color = Theme.ink
    var original = false

    init(_ asset: String, size: CGFloat = 24, color: Color = Theme.ink, original: Bool = false) {
        self.asset = asset
        self.size = size
        self.color = color
        self.original = original
    }

    var body: some View {
        Group {
            if original {
                Image(asset).resizable().renderingMode(.original)
            } else {
                Image(asset).resizable().renderingMode(.template).foregroundStyle(color)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Earlier name for an icon from the asset catalog. New code uses `QueepIcon`.
struct HomeGlyph: View {
    let asset: String
    var size: CGFloat = 20
    var original = false
    var color: Color = Theme.inkSoft

    var body: some View {
        QueepIcon(asset, size: size, color: color, original: original)
    }
}

/// The V2 mark: one ink shape with the eyes cut out.
struct QueepMark: View {
    /// Width; the mark is a hair wider than tall.
    var size: CGFloat = 36.5
    var color: Color = Theme.ink

    var body: some View {
        Image("QueepMark")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(color)
            .aspectRatio(36.5163 / 35.473, contentMode: .fit)
            .frame(width: size, height: size * 35.473 / 36.5163)
            .accessibilityHidden(true)
    }
}

/// Earlier name for the mark, kept for the screens that still call it.
struct QueepLogo: View {
    var size: CGFloat = 72
    var color: Color = Theme.ink

    var body: some View { QueepMark(size: size, color: color) }
}

/// Mark and wordmark as in the header: 36.5pt mark, 27pt bold "Queep", 9pt apart.
struct QueepLockup: View {
    var scale: CGFloat = 1
    var color: Color = Theme.ink

    var body: some View {
        HStack(spacing: 9 * scale) {
            QueepMark(size: 36.5 * scale, color: color)
            Text("Queep")
                .font(.system(size: 27 * scale, weight: .bold))
                .tracking(-0.75 * scale)
                .foregroundStyle(color)
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Queep")
    }
}

/// Header brand, as in the gallery.
struct HomeBrand: View {
    var body: some View {
        QueepLockup()
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Labels and badges

/// The plan in a pill: green wash for Pro and Max, gray for Free.
struct PlanBadge: View {
    enum Size { case small, medium, large }

    let plan: SubscriptionPlan
    var size: Size = .small

    private var text: String { plan == .free ? "FREE" : plan.title.uppercased() }
    private var font: CGFloat { switch size { case .small: 13; case .medium: 11.5; case .large: 26 } }
    private var height: CGFloat { switch size { case .small: 18; case .medium: 16; case .large: 36 } }
    private var tracking: CGFloat { switch size { case .small: -0.6; case .medium: -0.6; case .large: -1.6 } }
    private var horizontal: CGFloat { switch size { case .small: 8; case .medium: 7; case .large: 19 } }

    var body: some View {
        Text(text)
            .font(.system(size: font, weight: .bold))
            .tracking(tracking)
            .foregroundStyle(plan == .free ? Color(hex: 0xBFBFBF) : Theme.forest)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, horizontal)
            .frame(height: height)
            .background {
                ZStack {
                    Capsule().fill(Color.white)
                    Capsule().fill(plan == .free ? Theme.grayWash
                                   : Theme.limeWash(strength: size == .medium ? 0.7 : 0.4))
                }
            }
            .accessibilityLabel("Plano \(plan.title)")
    }
}

/// A count next to a tab title.
struct CountBadge: View {
    let value: Int
    var selected = false

    var body: some View {
        Text(value > 999 ? "999+" : "\(value)")
            .font(.system(size: 13))
            .monospacedDigit()
            .foregroundStyle(Theme.inkSoft)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(selected ? Theme.surface : Theme.fill,
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(Theme.fill, lineWidth: 1)
            }
    }
}

/// Small lime tag beside a choice, as in "30% off".
struct OfferTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.forest)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(Theme.lime.opacity(0.3), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

/// A 46pt gray well holding an 18pt icon, as in the paywall's benefits and the settings rows.
struct IconTile: View {
    let asset: String
    var size: CGFloat = 46
    var icon: CGFloat = 18
    var fill: Color = Theme.fill
    var color: Color = Theme.ink

    var body: some View {
        QueepIcon(asset, size: icon, color: color)
            .frame(width: size, height: size)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }
}

/// A square 60pt chrome button face with a 24pt icon, as in "more" on the opened item.
struct ChromeIcon: View {
    let asset: String
    var size: CGFloat = Theme.chrome
    var icon: CGFloat = 24
    var style: SurfaceStyle = .fill
    var color: Color = Theme.ink

    var body: some View {
        QueepIcon(asset, size: icon, color: color)
            .frame(width: size, height: size)
            .surface(style, radius: size >= Theme.chrome ? Theme.radius : Theme.controlRadius)
            .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
    }
}

/// Capsule from the opened item: gray, or dark for the main action. Icons are Remix names.
struct GalleryPill: View {
    var title: String?
    var leading: String?
    var trailing: String?
    var dark = false
    var height: CGFloat = Theme.pill
    var stretches = false

    var body: some View {
        let tint = dark ? Theme.onAction : Theme.ink
        HStack(spacing: 6) {
            if let leading { QueepIcon(leading, size: 22, color: tint) }
            if let title {
                Text(title).font(.system(size: 16)).foregroundStyle(tint).lineLimit(1)
            }
            if let trailing { QueepIcon(trailing, size: 22, color: tint) }
        }
        .padding(.leading, title == nil ? 0 : (leading == nil ? 18 : 12))
        .padding(.trailing, title == nil ? 0 : (trailing == nil ? 18 : 12))
        .frame(width: title == nil ? height : nil, height: height)
        .frame(maxWidth: stretches ? .infinity : nil)
        .background(dark ? Theme.action : Theme.fill, in: Capsule())
        .contentShape(Capsule())
    }
}

/// Filter and topic chip. Selected chips take the lime tint used by the tabs on the paywall.
struct GalleryChip: View {
    let title: String
    var symbol: String?
    var selected = false

    var body: some View {
        HStack(spacing: 6) {
            if let symbol { QueepIcon(symbol, size: 14, color: selected ? Theme.ink : Theme.inkSoft) }
            Text(title).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(selected ? Theme.ink : Theme.inkSoft)
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(selected ? Theme.lime.opacity(0.5) : Theme.fill,
                    in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .contentShape(Rectangle())
        .fixedSize()
    }
}

// MARK: - Segmented tabs

/// Grouped choice from the gallery header ("Gallery 2 · Spaces 1") and the paywall ("Mensal · Anual").
struct QueepSegment<Value: Hashable>: View {
    struct Item {
        let title: String
        let value: Value
        var count: Int? = nil
        var tag: String? = nil
        var identifier: String
    }

    enum Accent { case neutral, lime }

    let items: [Item]
    @Binding var selection: Value
    var accent: Accent = .neutral
    var stretches = false
    @Environment(\.chromeMetrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.bare ? 2 : 8) {
            ForEach(items, id: \.identifier) { item in
                let selected = item.value == selection
                Button { selection = item.value } label: {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.system(size: metrics.text))
                            .foregroundStyle(Theme.ink)
                            .lineLimit(1)
                            .fixedSize()
                        if let count = item.count { CountBadge(value: count, selected: selected) }
                        if let tag = item.tag { OfferTag(text: tag) }
                    }
                    .padding(.horizontal, metrics.padding)
                    .frame(height: metrics.control)
                    .frame(maxWidth: stretches ? .infinity : nil)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: metrics.controlRadius, style: .continuous)
                                .fill(accent == .lime ? Theme.lime.opacity(0.5) : Theme.fill)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: metrics.controlRadius, style: .continuous))
                    .barHover(radius: metrics.bare ? metrics.controlRadius : 0)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.tag.map { "\(item.title), \($0)" } ?? item.title)
                .accessibilityValue(item.count.map { "\($0)" } ?? "")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier(item.identifier)
            }
        }
        .animation(.spring(duration: 0.25, bounce: 0), value: selection)
        .modifier(SegmentChrome(bare: metrics.bare))
    }
}

private struct SegmentChrome: ViewModifier {
    let bare: Bool

    func body(content: Content) -> some View {
        if bare { content } else { content.chrome(.outline) }
    }
}

// MARK: - Fields

/// Small label over a field, as in the sign-in form.
struct FieldLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityHidden(true)
    }
}

private struct QueepFieldStyle: ViewModifier {
    var focused: Bool

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: Theme.button)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    .strokeBorder(focused ? Theme.sage : Theme.line, lineWidth: focused ? 1.5 : 1)
            }
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

extension View {
    /// V2 text field: white, hairline edge, sage edge while focused. Apply it to the field itself.
    func queepField(focused: Bool = false) -> some View {
        modifier(QueepFieldStyle(focused: focused))
    }
}

/// Square check used by forms ("Lembrar") and pickers.
struct QueepCheckbox: View {
    let checked: Bool
    var size: CGFloat = 18

    var body: some View {
        QueepIcon(checked ? "ri-checkbox-fill" : "ri-checkbox-blank-line", size: size,
                  color: checked ? Theme.forest : Theme.inkFaint)
    }
}

// MARK: - Selection

/// Round mark on a gallery tile: shown on hover on the Mac, and on every tile while selecting.
struct SelectionMark: View {
    let selected: Bool
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            Circle()
                .fill(selected ? Theme.ink : Color.white.opacity(0.92))
            Circle()
                .strokeBorder(selected ? Theme.ink : Theme.ink.opacity(0.18), lineWidth: 1.5)
            if selected {
                QueepIcon("ri-check-line", size: size * 0.64, color: .white)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(selected ? 0 : 0.12), radius: 6, y: 2)
        .animation(.spring(duration: 0.2, bounce: 0.2), value: selected)
    }
}

// MARK: - Promotional stage

/// The dark stage with the fluffy Queep clouds, from the paywall, the sign-in panel and the PRO
/// tile. Fills its frame, keeps the Figma composition at its aspect, and clips.
struct PromoStage: View {
    enum Style {
        /// Paywall art (`4:652`): night gradient and a soft lime light over everything.
        case paywall
        /// Sign-in panel (`11:46327`): flat `#1E1E1E` and a faint lime rise at the bottom.
        case signIn
    }

    var style: Style = .paywall
    /// Which part of the composition stays in view when the frame is a different shape.
    var anchor: UnitPoint = .center

    private struct Cloud: Identifiable {
        let id: Int
        let x: CGFloat
        let y: CGFloat
        let box: CGFloat
        let side: CGFloat
        let rotation: Double
        let flipped: Bool
    }

    private var reference: CGSize {
        switch style {
        case .paywall: CGSize(width: 364, height: 559)
        case .signIn: CGSize(width: 502, height: 696)
        }
    }

    private var clouds: [Cloud] {
        switch style {
        case .paywall: [
            Cloud(id: 1, x: -90, y: 257.16, box: 291.01, side: 252.41, rotation: 170.39, flipped: true),
            Cloud(id: 2, x: 159.98, y: 344.99, box: 291.01, side: 252.41, rotation: 9.61, flipped: false),
            Cloud(id: 3, x: 163.32, y: -103, box: 270.57, side: 234.69, rotation: 170.39, flipped: true),
            Cloud(id: 4, x: -12.19, y: -1.03, box: 233.25, side: 202.32, rotation: 9.61, flipped: false),
            Cloud(id: 5, x: -45.63, y: 62.49, box: 427.20, side: 387.39, rotation: 6.24, flipped: false),
        ]
        case .signIn: [
            Cloud(id: 1, x: 19.94, y: 470.87, box: 282.28, side: 244.84, rotation: 170.39, flipped: true),
            Cloud(id: 2, x: 262.43, y: 524.05, box: 282.28, side: 244.84, rotation: 9.61, flipped: false),
            Cloud(id: 3, x: 302.47, y: 166.19, box: 262.46, side: 227.65, rotation: 170.39, flipped: true),
            Cloud(id: 4, x: 63.15, y: 264.80, box: 226.26, side: 196.25, rotation: 9.61, flipped: false),
            Cloud(id: 5, x: 97.33, y: 304.56, box: 414.38, side: 375.78, rotation: 6.24, flipped: false),
        ]
        }
    }

    var body: some View {
        GeometryReader { geo in
            let scale = max(geo.size.width / reference.width, geo.size.height / reference.height)
            let dx = (geo.size.width - reference.width * scale) * anchor.x
            let dy = (geo.size.height - reference.height * scale) * anchor.y
            ZStack {
                switch style {
                case .paywall:
                    LinearGradient(colors: [Theme.night, Theme.nightDeep], startPoint: .top, endPoint: .bottom)
                case .signIn:
                    Theme.panel
                }
                ForEach(clouds) { cloud in
                    Image("PromoCloud")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: cloud.side * scale, height: cloud.side * scale)
                        .scaleEffect(x: 1, y: cloud.flipped ? -1 : 1)
                        .rotationEffect(.degrees(cloud.rotation))
                        .position(x: dx + (cloud.x + cloud.box / 2) * scale,
                                  y: dy + (cloud.y + cloud.box / 2) * scale)
                }
                switch style {
                case .paywall:
                    Theme.lime.blendMode(.softLight)
                case .signIn:
                    LinearGradient(colors: [Theme.panel, Theme.lime], startPoint: .top, endPoint: .bottom)
                        .opacity(0.1)
                        .frame(height: 492 * scale)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
            }
            .compositingGroup()
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Page pieces

/// Large page title with an optional quiet line under it, as in a Space or Arquivados.
struct PageTitle: View {
    let text: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text)
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.6)
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Nothing to show yet: an icon well, a title, one line, and an optional action.
struct EmptyState<Actions: View>: View {
    let icon: String
    let title: String
    var message: String? = nil
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 16) {
            IconTile(asset: icon, size: 64, icon: 28)
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            actions.padding(.top, 4)
        }
        .frame(maxWidth: 380)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 64)
        .accessibilityElement(children: .contain)
    }
}

extension EmptyState where Actions == EmptyView {
    init(icon: String, title: String, message: String? = nil) {
        self.init(icon: icon, title: title, message: message, actions: { EmptyView() })
    }
}

/// The PRO tile that opens a free gallery: the cloud stage, the lockup with its plan, a lime action.
struct PromoTile: View {
    static let aspect: CGFloat = 234 / 340
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PromoStage()
                .aspectRatio(Self.aspect, contentMode: .fit)
                .overlay {
                    VStack(spacing: -3) {
                        PlanBadge(plan: .pro, size: .medium)
                        QueepLockup(scale: 0.92, color: .white)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 4)
                }
                .overlay(alignment: .bottom) {
                    Text("Experimente o Queep \(Text("PRO").fontWeight(.bold))")
                        .font(.system(size: 16, weight: .medium))
                        .tracking(-0.6)
                        .foregroundStyle(Color(hex: 0x12100B))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity)
                        .frame(height: Theme.control)
                        .background(Theme.lime, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                                .strokeBorder(Theme.forest.opacity(0.18), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.25), radius: 15)
                        .padding(14)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Experimente o Queep Pro")
        .accessibilityIdentifier("library.promo")
    }
}
