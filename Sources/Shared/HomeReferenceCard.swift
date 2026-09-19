import SwiftUI
import QueepCore

/// Library card from Queep Design V2: post header, swipeable media, AI title, and a dedicated
/// analyzing state that replaces the preview until the item is ready.
struct HomeReferenceCard: View {
    let reference: Reference

    private var excerpt: String {
        Markdown.plainText(reference.source?.text.isEmpty == false ? reference.source?.text ?? "" : reference.text)
    }
    private var host: String? { reference.url.flatMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") } }
    private var isAnalyzing: Bool { reference.status == "queued" || reference.status == "processing" }

    var body: some View {
        Group {
            if isAnalyzing {
                analyzingCard
            } else {
                switch layout {
                case .photo: photoCard
                case .note: noteCard.homeSurface()
                case .post: postCard.homeSurface()
                case .profile: profileCard.homeSurface()
                case .website: websiteCard.homeSurface()
                case .site: siteCard.homeSurface()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .overlay(alignment: .topTrailing) { status }
    }

    private enum Layout { case photo, note, post, profile, website, site }

    private var layout: Layout {
        if reference.isSocialProfile { return .profile }
        if reference.isSocialPost { return .post }
        if reference.isWebsite { return .website }
        if !reference.gallery.isEmpty || reference.kind == "video" { return .photo }
        if reference.kind == "note" || reference.kind == "audio" { return .note }
        if reference.kind == "link" { return .site }
        return .note
    }

    @ViewBuilder private var status: some View {
        if !isAnalyzing, reference.status == "error" {
            StatusPill(status: reference.status, partial: false).padding(10)
        }
    }

    private var analyzingCard: some View {
        HStack(spacing: 12) {
            Text("Enviando novos itens...")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.homePreview)
                .lineLimit(1)
            Spacer(minLength: 8)
            HomeSpinningLoader()
        }
        .padding(.horizontal, 16.4)
        .padding(.vertical, 14.76)
        .frame(maxWidth: .infinity, alignment: .leading)
        .homeSurface(highlighted: true)
        .accessibilityIdentifier("library.analyzing")
    }

    private var photoCard: some View {
        ZStack(alignment: .bottom) {
            Color.clear
                .aspectRatio(photoRatio, contentMode: .fit)
                .frame(maxHeight: 434)
                .overlay {
                    ZStack {
                        RemoteImage(reference: reference, thumbnail: true, fill: true)
                        if reference.kind == "video" {
                            Image(systemName: "play.circle.fill").font(.system(size: 40)).foregroundStyle(.white).shadow(radius: 6)
                        }
                    }
                }
                .clipped()
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 11.48))
                    .foregroundStyle(Theme.homePreview)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(12)
            }
        }
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous)
                .strokeBorder(Theme.homeLine)
        }
        .shadow(color: Theme.homeShadow, radius: 6, y: 3)
        .accessibilityHidden(true)
    }

    private var photoRatio: CGFloat {
        guard let image = reference.gallery.first, image.width > 0 else { return 0.72 }
        return min(1.75, max(0.55, CGFloat(image.height) / CGFloat(image.width)))
    }

    private var caption: String { reference.title }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            brandTile {
                Image("HomeStickyNote").resizable().renderingMode(.original).frame(width: 32, height: 32)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(reference.displayTitle).font(.system(size: 13.94, weight: .semibold)).foregroundStyle(Theme.homeInk)
                    .lineLimit(2)
                if !excerpt.isEmpty, excerpt != reference.displayTitle {
                    Text(excerpt).font(.system(size: 11.48)).foregroundStyle(Theme.homePreview)
                        .lineLimit(8).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16.4).padding(.vertical, 14.76)
        .frame(maxWidth: .infinity, maxHeight: 205, alignment: .top)
        .clipped()
        .overlay(alignment: .bottom) { fade }
    }

    private var postCard: some View {
        let copy = postCopy
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 9) {
                HStack(alignment: .bottom, spacing: 0) {
                    PostBrandMark(surface: reference.linkSurface, size: 32, radius: 6)
                        .padding(.trailing, -11)
                    PostAvatar(reference: reference, initials: copy.initials, size: 24)
                }
                HStack(spacing: 10) {
                    if !copy.author.isEmpty {
                        Text(copy.author)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.homeInk)
                            .lineLimit(1)
                    }
                    if !copy.handle.isEmpty {
                        Text(copy.handle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Theme.homeInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 16) {
                if !reference.gallery.isEmpty {
                    Color.clear
                        .aspectRatio(mediaRatio, contentMode: .fit)
                        .overlay {
                            RemoteImageCarousel(
                                reference: reference,
                                thumbnail: true,
                                fill: true,
                                height: nil,
                                showsChrome: false
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                if !copy.title.isEmpty {
                    Text(copy.title)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.homePreview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !copy.body.isEmpty {
                    Text(copy.body)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(Theme.homePreview)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(10)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16.4).padding(.vertical, 14.76)
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { fade }
    }

    private var profileCard: some View {
        let copy = postCopy
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 9) {
                HStack(alignment: .bottom, spacing: 0) {
                    PostBrandMark(surface: reference.linkSurface, size: 32, radius: 6)
                        .padding(.trailing, -11)
                    PostAvatar(reference: reference, initials: copy.initials, size: 24)
                }
                HStack(spacing: 10) {
                    if !copy.author.isEmpty {
                        Text(copy.author)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.homeInk)
                            .lineLimit(1)
                    }
                    if !copy.handle.isEmpty {
                        Text(copy.handle)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Theme.homeInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if !copy.body.isEmpty {
                Text(copy.body)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(Theme.homePreview)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(10)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16.4).padding(.vertical, 14.76)
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { fade }
    }

    private var mediaRatio: CGFloat {
        guard let image = reference.gallery.first, image.height > 0 else { return 2048 / 1529 }
        return CGFloat(image.width) / CGFloat(image.height)
    }

    private var websiteCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom, spacing: 9) {
                HStack(alignment: .bottom, spacing: 0) {
                    PostBrandMark(surface: .website, size: 32, radius: 6)
                        .padding(.trailing, -11)
                    SiteFavicon(reference: reference, size: 24)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(productName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.homeInk)
                        .lineLimit(1)
                    if let host {
                        Text(host)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundStyle(Theme.homePreview)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            if !reference.gallery.isEmpty {
                Color.clear
                    .aspectRatio(mediaRatio, contentMode: .fit)
                    .frame(maxHeight: 220)
                    .overlay {
                        RemoteImage(reference: reference, thumbnail: true, fill: true)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if !functionalTitle.isEmpty {
                Text(functionalTitle)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.homePreview)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16.4).padding(.vertical, 14.76)
        .frame(maxWidth: .infinity, alignment: .top)
        .overlay(alignment: .bottom) { fade }
    }

    private var productName: String {
        if let name = reference.source?.title, !name.isEmpty { return name }
        return host ?? "Site"
    }

    private var functionalTitle: String {
        let value = reference.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "" }
        if value.caseInsensitiveCompare(productName) == .orderedSame { return "" }
        return value
    }

    private var siteCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            PostBrandMark(surface: reference.linkSurface, size: reference.linkSurface == .medium ? 64 : 48)
            VStack(alignment: .leading, spacing: 10) {
                Text(siteTitle).font(.system(size: 13.94, weight: .semibold)).foregroundStyle(Theme.homeInk).lineLimit(2)
                if let host {
                    Text(host).font(.system(size: 11.48)).foregroundStyle(Theme.homePreview).lineLimit(1)
                } else if !excerpt.isEmpty {
                    Text(excerpt).font(.system(size: 11.48)).foregroundStyle(Theme.homePreview).lineLimit(3)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16.4).padding(.vertical, 14.76)
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .top)
    }

    private var siteTitle: String {
        if let surface = reference.linkSurface, reference.title.isEmpty,
           reference.displayTitle == host || reference.source?.title.isEmpty != false {
            return surface.brandName
        }
        return reference.displayTitle
    }

    private var fade: some View {
        LinearGradient(colors: [.clear, .white], startPoint: .top, endPoint: .bottom)
            .frame(height: 36).allowsHitTesting(false)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: Theme.homeRadius, bottomTrailingRadius: Theme.homeRadius, style: .continuous))
    }

    private func brandTile<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .frame(width: 48, height: 48)
            .background(Color(red: 0.929, green: 0.929, blue: 0.929), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var postCopy: PostIdentity { PostIdentity(reference) }
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
        .overlay { Circle().strokeBorder(Color.white, lineWidth: 1) }
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
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.white, lineWidth: 1)
        }
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

/// Tap opens the item; horizontal pans stay with the media carousel.
struct LibraryCardCell<MenuContent: View>: View {
    let reference: Reference
    let open: () -> Void
    @ViewBuilder var menu: () -> MenuContent
    @State private var hovered = false

    private var isAnalyzing: Bool { reference.status == "queued" || reference.status == "processing" }

    var body: some View {
        HomeReferenceCard(reference: reference)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .scaleEffect(hovered ? 1.008 : 1)
            .shadow(color: .black.opacity(hovered ? 0.08 : 0), radius: 16, y: 6)
            .animation(.easeOut(duration: 0.18), value: hovered)
            .onHover { hovered = $0 }
            .contentShape(RoundedRectangle(cornerRadius: Theme.homeRadius, style: .continuous))
            .simultaneousGesture(TapGesture().onEnded(open))
            .contextMenu { menu() }
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(isAnalyzing ? "Enviando novos itens" : reference.displayTitle)
            .accessibilityValue("\(reference.kindLabel), \(reference.statusLabel)")
            .accessibilityHint("Abrir \(reference.kindLabel.lowercased())")
            .accessibilityAction(named: "Abrir", open)
    }
}

private struct HomeSpinningLoader: View {
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
