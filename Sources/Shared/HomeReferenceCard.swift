import SwiftUI
import QueepCore

/// Palette and metrics taken from saved.design, shared by the gallery and the opened item.
enum GalleryStyle {
    static let ink = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let onInk = Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
    static let secondary = Color(red: 105 / 255, green: 105 / 255, blue: 105 / 255)
    static let tertiary = Color(red: 161 / 255, green: 161 / 255, blue: 161 / 255)
    static let fill = Color(red: 245 / 255, green: 245 / 255, blue: 245 / 255)
    static let ring = Color(red: 237 / 255, green: 237 / 255, blue: 237 / 255)
    static let dot = Color(red: 212 / 255, green: 212 / 255, blue: 212 / 255)
    static let radius: CGFloat = 16
    static let gap: CGFloat = 14
    static let inset: CGFloat = 12
    #if os(iOS)
    static let badge: CGFloat = 26
    static let tileTitle: CGFloat = 15
    #else
    static let badge: CGFloat = 28
    static let tileTitle: CGFloat = 17
    #endif
}

extension View {
    func galleryTile() -> some View {
        clipShape(RoundedRectangle(cornerRadius: GalleryStyle.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GalleryStyle.radius, style: .continuous)
                    .strokeBorder(GalleryStyle.ring, lineWidth: 1)
            }
    }
}

/// Gallery tile: the picture is the card, with the source on the bottom left.
/// References without a picture become text tiles of the same family.
struct HomeReferenceCard: View {
    let reference: Reference
    /// The gallery turns this on for a visible cell that won one of the four loop slots.
    var playsLoop = false

    private var isAnalyzing: Bool { reference.status == "queued" || reference.status == "processing" }
    private var hasVisual: Bool { reference.kind == "video" || !reference.gallery.isEmpty }
    private var host: String? { reference.url.flatMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") } }
    private var isSocial: Bool { reference.isSocialPost || reference.isSocialProfile }

    var body: some View {
        Group {
            if isAnalyzing && !hasVisual {
                analyzingTile
            } else if hasVisual {
                visualTile
            } else {
                textTile
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .topLeading) {
            if !isAnalyzing, reference.status == "error" {
                StatusPill(status: reference.status, partial: false).padding(10)
            }
        }
    }

    private var analyzingTile: some View {
        HStack(spacing: 12) {
            Text(LibrarySync.analyzingTile(reference.status) ?? "Analisando…")
                .font(.system(size: 13, weight: .medium))
                .tracking(-0.2)
                .foregroundStyle(GalleryStyle.secondary)
                .lineLimit(1)
            Spacer(minLength: 8)
            HomeSpinningLoader()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .background(GalleryStyle.fill)
        .galleryTile()
        .accessibilityIdentifier("library.analyzing")
    }

    private var visualTile: some View {
        GalleryStyle.fill
            .aspectRatio(tileAspect, contentMode: .fit)
            .overlay(alignment: .top) {
                ZStack {
                    RemoteImage(reference: reference, thumbnail: true, fill: true)
                    if playsLoop, reference.playsInlineLoop {
                        MotionLoop(reference: reference, active: true)
                    }
                }
            }
            .galleryTile()
            .overlay(alignment: .bottomLeading) {
                SourceBadge(reference: reference).padding(GalleryStyle.inset)
            }
            .overlay(alignment: .topLeading) {
                if isAnalyzing { HomeSpinningLoader().padding(GalleryStyle.inset) }
            }
            .accessibilityHidden(true)
    }

    private var tileAspect: CGFloat {
        let size: (Int, Int)? = {
            if let image = reference.gallery.first, image.width > 0, image.height > 0 {
                return (image.width, image.height)
            }
            if let media = reference.media, let width = media.width, let height = media.height, width > 0, height > 0 {
                return (width, height)
            }
            return nil
        }()
        guard let size else { return 0.8 }
        return min(1.8, max(0.62, CGFloat(size.0) / CGFloat(size.1)))
    }

    private var textTile: some View {
        GalleryStyle.fill
            .aspectRatio(reference.kind == "link" && !isSocial ? 1.25 : 0.95, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(textTitle)
                        .font(.system(size: GalleryStyle.tileTitle, weight: .medium))
                        .tracking(-0.4)
                        .foregroundStyle(GalleryStyle.ink)
                        .lineLimit(4)
                        .layoutPriority(1)
                    if !textBody.isEmpty {
                        Text(textBody)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(GalleryStyle.secondary)
                            .lineSpacing(3)
                    }
                    Spacer(minLength: 10)
                    HStack(spacing: 8) {
                        SourceBadge(reference: reference, size: 22)
                        if let footnote {
                            Text(footnote)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(GalleryStyle.secondary)
                                .lineLimit(1)
                        }
                    }
                    .layoutPriority(1)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .galleryTile()
            .accessibilityHidden(true)
    }

    private var identity: PostIdentity { PostIdentity(reference) }

    private var siteName: String {
        if let name = reference.source?.title, !name.isEmpty,
           name.caseInsensitiveCompare("Post") != .orderedSame { return name }
        if let host { return host }
        return reference.linkSurface?.brandName ?? "Site"
    }

    private var textTitle: String {
        if isSocial {
            let copy = identity
            return [copy.title, copy.author, reference.linkSurface?.brandName ?? ""]
                .first { !$0.isEmpty } ?? reference.displayTitle
        }
        if reference.kind == "link" { return siteName }
        return reference.displayTitle
    }

    private var textBody: String {
        if isSocial { return identity.body }
        if reference.kind == "link" {
            let title = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, title.caseInsensitiveCompare(siteName) != .orderedSame { return title }
            return reference.analysis?.summary ?? ""
        }
        if reference.kind == "audio" { return reference.analysis?.summary ?? "" }
        let text = Markdown.plainText(reference.text).trimmingCharacters(in: .whitespacesAndNewlines)
        let title = reference.displayTitle
        if text == title { return "" }
        if text.hasPrefix(title) {
            return String(text.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private var footnote: String? {
        if isSocial {
            let copy = identity
            if !copy.handle.isEmpty { return copy.handle }
            return copy.title.isEmpty || copy.author.isEmpty ? nil : copy.author
        }
        if reference.kind == "link" { return host }
        if let media = reference.media { return "\(reference.kindLabel) · \(media.durationLabel)" }
        return reference.kindLabel
    }
}

/// Where the reference came from: the network mark with the author's avatar, or the site's icon.
struct SourceBadge: View {
    let reference: Reference
    var size: CGFloat = GalleryStyle.badge

    var body: some View {
        if reference.isSocialPost || reference.isSocialProfile {
            let identity = PostIdentity(reference)
            HStack(spacing: -size * 0.3) {
                PostBrandMark(surface: reference.linkSurface, size: size, radius: size * 0.3)
                if reference.authorImage != nil || !identity.initials.isEmpty {
                    PostAvatar(reference: reference, initials: identity.initials, size: size)
                }
            }
        } else if reference.kind == "link" {
            if reference.authorImage != nil {
                SiteFavicon(reference: reference, size: size)
            } else if let surface = reference.linkSurface, surface != .website {
                PostBrandMark(surface: surface, size: size, radius: size * 0.3)
            }
        }
    }
}

struct PostIdentity {
    let author: String
    let handle: String
    let title: String
    let body: String
    let initials: String

    init(_ reference: Reference) {
        let excerpt = Markdown.plainText(
            reference.source?.text.isEmpty == false ? reference.source?.text ?? "" : reference.text)
        let body: String = {
            if let source = reference.source, source.state == "read", !source.text.isEmpty {
                return source.text
            }
            return excerpt
        }()
        var author = ""
        if let name = reference.source?.authorName, !name.isEmpty {
            author = name
        } else if let source = reference.source?.title, !source.isEmpty {
            var value = source
            for marker in [" on Instagram", " on X", " on Twitter", " no Instagram"] {
                if let range = value.range(of: marker) {
                    value = String(value[..<range.lowerBound])
                    break
                }
            }
            author = value
        }
        var handle = ""
        if let stored = reference.source?.authorHandle, !stored.isEmpty {
            handle = stored.hasPrefix("@") ? stored : "@\(stored)"
        } else if let twitter = LinkSurface.twitterHandle(url: reference.url) {
            handle = "@\(twitter)"
        } else if let profile = LinkSurface.twitterProfileHandle(url: reference.url) {
            handle = "@\(profile)"
        } else if author.hasPrefix("@") {
            handle = author
            author = ""
        }
        if author.hasPrefix("@") {
            if handle.isEmpty { handle = author }
            author = ""
        }
        if author.caseInsensitiveCompare("Post") == .orderedSame
            || author.caseInsensitiveCompare("Link") == .orderedSame {
            author = ""
        }
        if !handle.isEmpty {
            let bare = String(handle.drop(while: { $0 == "@" }))
            if author.caseInsensitiveCompare(bare) == .orderedSame {
                author = handle
                handle = ""
            }
        }
        if author.isEmpty, !handle.isEmpty {
            author = handle
            handle = ""
        }
        let title = Self.cardTitle(reference)
        let letters = author.split { $0 == " " || $0 == "@" }.prefix(2)
            .compactMap { $0.first.map(String.init) }.joined()
        self.author = author
        self.handle = handle
        self.title = title
        self.body = body == title ? "" : body
        self.initials = letters.uppercased()
    }

    private static func cardTitle(_ reference: Reference) -> String {
        let candidates = [
            reference.title,
            reference.analysis?.headline ?? "",
            reference.analysis?.summary ?? "",
            reference.analysis?.appearance.first ?? "",
        ]
        for raw in candidates {
            let words = raw.split { $0.isWhitespace || $0.isNewline }.prefix(6)
            let value = words.joined(separator: " ")
            let lowered = value.lowercased()
            if value.isEmpty || lowered == "post" || lowered == "link" { continue }
            if lowered.hasPrefix("http://") || lowered.hasPrefix("https://") { continue }
            return String(value.prefix(80))
        }
        return ""
    }
}

struct PostAvatar: View {
    let reference: Reference
    let initials: String
    var size: CGFloat = 24

    var body: some View {
        Group {
            if reference.authorImage != nil {
                RemoteImage(reference: reference, thumbnail: true, fill: true, author: true)
            } else if initials.isEmpty {
                Theme.homeAccent
            } else {
                Text(initials)
                    .font(.system(size: max(8, size * 0.33), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.homeAccent)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

struct SiteFavicon: View {
    let reference: Reference
    var size: CGFloat = 24

    var body: some View {
        Group {
            if reference.authorImage != nil {
                RemoteImage(reference: reference, thumbnail: true, fill: true, author: true)
            } else {
                Color(red: 0.929, green: 0.929, blue: 0.929)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }
}

struct PostBrandMark: View {
    let surface: LinkSurface?
    var size: CGFloat = 32
    var radius: CGFloat?
    var kind: String = "link"

    var body: some View {
        let corner = radius ?? (size > 50 ? 16 : 12)
        Group {
            switch surface {
            case .twitter: Image("BrandTwitter").resizable()
            case .instagram: Image("BrandInstagram").resizable()
            case .dribbble: Image("BrandDribbble").resizable()
            case .pinterest: Image("BrandPinterest").resizable()
            case .medium: Image("BrandMedium").resizable()
            case .behance:
                Text("Be").font(.system(size: size * 0.32, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.09, green: 0.41, blue: 1))
            case .website, .none:
                Image(systemName: kind == "audio" ? "waveform" : "globe")
                    .font(.system(size: size * 0.38, weight: .semibold))
                    .foregroundStyle(Theme.homePreview)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.929, green: 0.929, blue: 0.929))
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A plain button opens the item and leaves the library pan with the scroll view.
struct LibraryCardCell<MenuContent: View>: View {
    let reference: Reference
    var playsLoop = false
    let open: () -> Void
    @ViewBuilder var menu: () -> MenuContent
    @State private var hovered = false

    var body: some View {
        Button(action: open) {
            HomeReferenceCard(reference: reference, playsLoop: playsLoop)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .opacity(hovered ? 0.92 : 1)
                .animation(.easeOut(duration: 0.15), value: hovered)
                .contentShape(RoundedRectangle(cornerRadius: GalleryStyle.radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .contextMenu { menu() }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(LibrarySync.analyzingTile(reference.status) ?? reference.displayTitle)
        .accessibilityIdentifier("reference.\(reference.id)")
        .accessibilityValue("\(reference.kindLabel), \(reference.statusLabel)")
        .accessibilityHint("Abrir \(reference.kindLabel.lowercased())")
        .accessibilityAction(named: "Abrir", open)
    }
}

struct HomeSpinningLoader: View {
    @State private var spinning = false

    var body: some View {
        Image("HomeLoader")
            .resizable()
            .renderingMode(.template)
            .foregroundStyle(Color(red: 86 / 255, green: 150 / 255, blue: 218 / 255))
            .frame(width: 20, height: 20)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
            .accessibilityHidden(true)
    }
}
