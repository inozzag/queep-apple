import SwiftUI
import QueepCore

/// How the Mac library lays out references. The choice is remembered.
enum LibraryLayout: String, CaseIterable, Identifiable {
    /// The bento plane you drag in any direction.
    case infinite
    /// The masonry gallery, in sections by when each reference was saved.
    case grouped
    /// One row per reference, with columns.
    case list

    var id: String { rawValue }

    var title: String {
        switch self {
        case .infinite: "Galeria infinita"
        case .grouped: "Por data"
        case .list: "Lista"
        }
    }

    var icon: String {
        switch self {
        case .infinite: "layout-infinite"
        case .grouped: "ri-layout-masonry-line"
        case .list: "layout-list"
        }
    }
}

/// Three icons under the bar, at the right: the plane, the dated gallery, the list.
struct LibraryLayoutSwitch: View {
    @Binding var layout: LibraryLayout

    private static let control: CGFloat = 32
    private static let inset: CGFloat = 4
    private static let radius: CGFloat = 10

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LibraryLayout.allCases) { option in
                let selected = option == layout
                Button { layout = option } label: {
                    QueepIcon(option.icon, size: 17, color: selected ? Theme.ink : Theme.inkSoft)
                        .frame(width: Self.control + 4, height: Self.control)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: Self.radius, style: .continuous).fill(Theme.fill)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .barHover(radius: Self.radius)
                .help(option.title)
                .accessibilityLabel(option.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("library.layout.\(option.rawValue)")
            }
        }
        .animation(.spring(duration: 0.22, bounce: 0), value: layout)
        .padding(Self.inset)
        .floatingSurface(radius: Self.radius + Self.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Visualização")
    }
}

// MARK: - Dated gallery

/// Saved-date sections, newest first: Hoje, Ontem, Últimos 7 dias, Últimos 30 dias, then one per month.
struct LibraryDateSection: Identifiable {
    let id: String
    let title: String
    let items: [Reference]

    static func sections(_ items: [Reference], now: Date = .now, calendar: Calendar = .current) -> [LibraryDateSection] {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let week = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let month = calendar.date(byAdding: .day, value: -29, to: today) ?? today
        let monthTitle = Date.FormatStyle(locale: Locale(identifier: "pt_BR")).month(.wide).year()

        var order: [String] = []
        var titles: [String: String] = [:]
        var grouped: [String: [Reference]] = [:]
        for item in items.sorted(by: { $0.createdAt > $1.createdAt }) {
            let date = item.createdAt
            let key: String
            let title: String
            if date >= today {
                (key, title) = ("today", "Hoje")
            } else if date >= yesterday {
                (key, title) = ("yesterday", "Ontem")
            } else if date >= week {
                (key, title) = ("week", "Últimos 7 dias")
            } else if date >= month {
                (key, title) = ("month", "Últimos 30 dias")
            } else {
                let parts = calendar.dateComponents([.year, .month], from: date)
                key = "\(parts.year ?? 0)-\(parts.month ?? 0)"
                let name = date.formatted(monthTitle)
                title = name.prefix(1).uppercased() + name.dropFirst()
            }
            if grouped[key] == nil {
                order.append(key)
                titles[key] = title
            }
            grouped[key, default: []].append(item)
        }
        return order.map { LibraryDateSection(id: $0, title: titles[$0] ?? $0, items: grouped[$0] ?? []) }
    }
}

/// The masonry gallery in dated sections. The next page loads when the end of the list comes into view.
struct DateGroupedGallery<MenuContent: View, Leading: View>: View {
    let items: [Reference]
    let more: Bool
    let loading: Bool
    let selecting: Bool
    let selectedIDs: Set<String>
    let open: (Reference) -> Void
    var toggle: ((Reference) -> Void)?
    let loadMore: () -> Void
    @ViewBuilder var menu: (Reference) -> MenuContent
    /// First tile of the first section, such as the PRO tile on a free account.
    @ViewBuilder var leading: () -> Leading

    /// Loopable cards on screen, in gallery order. Changes only when one enters or leaves.
    @State private var onScreen: [String] = []

    var body: some View {
        let sections = LibraryDateSection.sections(items)
        let playing = Set(onScreen.prefix(InlineLoop.playerCap))
        VStack(alignment: .leading, spacing: 36) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(section.title)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text("\(section.items.count)")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                    }
                    MasonryLayout(spacing: Theme.gap) {
                        if section.id == sections.first?.id { leading() }
                        ForEach(section.items) { reference in
                            LibraryCardCell(reference: reference, playsLoop: playing.contains(reference.id),
                                            selectable: toggle != nil,
                                            selecting: selecting, selected: selectedIDs.contains(reference.id),
                                            open: { open(reference) },
                                            toggleSelection: { toggle?(reference) }) {
                                menu(reference)
                            }
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .modifier(LoopVisibility(enabled: reference.playsInlineLoop) { visible in
                                track(reference.id, visible: visible, order: items)
                            })
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            if more {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        // The next page loads once the end is within a screen of the window's bottom.
                        GeometryReader { proxy in
                            let near = proxy.frame(in: .global).minY < (NSScreen.main?.frame.height ?? 1_000) * 2
                            Color.clear
                                .onChange(of: near && !loading, initial: true) { _, ready in
                                    if ready { loadMore() }
                                }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        // The page restores its scroll position by card id; the cards must be scroll targets.
        .scrollTargetLayout()
    }
}

extension DateGroupedGallery {
    private func track(_ id: String, visible: Bool, order: [Reference]) {
        let present = onScreen.contains(id)
        guard visible != present else { return }
        if visible {
            let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1.id, $0) })
            onScreen = (onScreen + [id]).sorted { (rank[$0] ?? 0) < (rank[$1] ?? 0) }
        } else {
            onScreen.removeAll { $0 == id }
        }
    }
}

/// Reports when a card enters or leaves the window, for cards that can loop. Also reports where
/// it starts, so cards already on screen loop without a scroll.
private struct LoopVisibility: ViewModifier {
    let enabled: Bool
    let changed: (Bool) -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.background {
                GeometryReader { proxy in
                    let frame = proxy.frame(in: .global)
                    let height = NSApp.keyWindow?.contentView?.bounds.height ?? 900
                    Color.clear
                        .onChange(of: frame.maxY > 0 && frame.minY < height, initial: true) { _, visible in
                            changed(visible)
                        }
                }
            }
        } else {
            content
        }
    }
}

// MARK: - List

/// One row per reference, sortable by its columns. A click selects (the selection bar appears);
/// a double click opens; the right click has the same menu as a card.
struct LibraryTable<MenuContent: View>: View {
    let items: [Reference]
    let more: Bool
    let loading: Bool
    @Binding var selection: Set<String>
    let open: (Reference) -> Void
    let loadMore: () -> Void
    @ViewBuilder var menu: (Reference) -> MenuContent

    @State private var sortOrder = [KeyPathComparator(\Reference.createdAt, order: .reverse)]

    private var rows: [Reference] { items.sorted(using: sortOrder) }

    var body: some View {
        let rows = rows
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("") { reference in
                LibraryRowPreview(reference: reference)
                    .onAppear {
                        if more, !loading, reference.id == rows.last?.id { loadMore() }
                    }
            }
            .width(52)
            TableColumn("Título", value: \.displayTitle) { reference in
                VStack(alignment: .leading, spacing: 2) {
                    Text(reference.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if let summary = reference.listSummary {
                        Text(summary)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.inkSoft)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 220, ideal: 320)
            TableColumn("Tipo", value: \.kindLabel) { reference in
                Text(reference.kindLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(Theme.fill, in: Capsule())
            }
            .width(min: 70, ideal: 80, max: 110)
            TableColumn("Origem", value: \.originLabel) { reference in
                HStack(spacing: 8) {
                    if let surface = reference.linkSurface, surface != .website {
                        PostBrandMark(surface: surface, size: 18, radius: 5)
                    }
                    Text(reference.originLabel)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(1)
                }
            }
            .width(min: 100, ideal: 150, max: 220)
            TableColumn("Tags") { reference in
                LibraryRowTags(tags: reference.listTags)
            }
            .width(min: 160, ideal: 300)
            TableColumn("Salvo em", value: \.createdAt) { reference in
                Text(reference.createdAt.formatted(.dateTime.day().month(.abbreviated).year()
                    .locale(Locale(identifier: "pt_BR"))))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
            }
            .width(min: 90, ideal: 110, max: 140)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first, let reference = items.first(where: { $0.id == id }) {
                menu(reference)
            }
        } primaryAction: { ids in
            guard let id = ids.first, let reference = items.first(where: { $0.id == id }) else { return }
            open(reference)
        }
        .accessibilityIdentifier("library.list")
    }
}

/// The card's picture at row size, or the type icon for notes.
private struct LibraryRowPreview: View {
    let reference: Reference

    var body: some View {
        Group {
            if reference.kind == "video" || !reference.gallery.isEmpty {
                Theme.fill.overlay { RemoteImage(reference: reference, thumbnail: true, fill: true) }
            } else {
                Theme.fill.overlay {
                    Image(systemName: reference.kindSymbol)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(.vertical, 4)
        .accessibilityHidden(true)
    }
}

private struct LibraryRowTags: View {
    let tags: [String]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags.prefix(3), id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .frame(height: 20)
                    .background(Theme.lime.opacity(0.45), in: Capsule())
            }
            if tags.count > 3 {
                Text("+\(tags.count - 3)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tags.joined(separator: ", "))
    }
}

private extension Reference {
    /// The network for posts and profiles, the host for sites, the type otherwise.
    var originLabel: String {
        if let surface = linkSurface {
            if surface != .website { return surface.brandName }
            if let host = url.flatMap({ URL(string: $0)?.host }) {
                return host.replacingOccurrences(of: "www.", with: "")
            }
            return surface.brandName
        }
        switch kind {
        case "image": return "Upload"
        case "audio", "video": return "Arquivo"
        default: return "Queep"
        }
    }

    /// The analysis topics, as the list's tags.
    var listTags: [String] { analysis?.topics ?? [] }

    /// A line under the title that adds something: the headline when it differs, else the summary.
    var listSummary: String? {
        let title = displayTitle
        for text in [analysis?.headline, analysis?.summary].compactMap({ $0 }) where !text.isEmpty && text != title {
            return text
        }
        return nil
    }
}
