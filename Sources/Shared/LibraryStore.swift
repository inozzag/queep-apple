import Observation
import QueepCore
import Foundation

enum LibrarySurface: String, CaseIterable {
    case home, spaces, archived

    var showsArchived: Bool { self == .archived }
}

struct ArchiveUndo: Identifiable {
    let id = UUID()
    let references: [Reference]
}

enum LibraryPresentation: Identifiable {
    case account
    case usage
    case help
    case deleteAccount
    case subscription
    case capture(UUID)
    case reference(Reference)
    case newSpace

    var id: String {
        switch self {
        case .account: "account"
        case .usage: "usage"
        case .help: "help"
        case .deleteAccount: "delete-account"
        case .subscription: "subscription"
        case .capture(let id): "capture-\(id)"
        case .reference(let reference): "reference-\(reference.id)"
        case .newSpace: "new-space"
        }
    }
}

@MainActor
enum LibraryAnalytics {
    static var searchSubmitted: ((Bool) -> Void)?
    static var spaceCreated: (() -> Void)?
}

@MainActor @Observable
final class LibraryStore {
    var items: [Reference] = []
    var spaces: [Space] = []
    var selectedSpaceID: String?
    var spaceError: String?
    var spaceMutating = false
    var scrollAnchors: [String: String] = [:]
    private var cachedPages: [String: LibraryPage] = [:]
    private var knownReferences: [String: Reference] = [:]
    /// Folder open on the Spaces tab. Home always shows the whole library.
    var scopedSpaceID: String? { surface == .spaces ? selectedSpaceID : nil }
    var filterKey: String {
        if surface.showsArchived { return "archived" }
        return scopedSpaceID ?? "all"
    }
    var selectedSpace: Space? { spaces.first { $0.id == selectedSpaceID } }
    var nextCursor: String?
    var error: String?
    /// True only for the first load of an empty library. A refresh that already has rows stays quiet.
    var loading = false
    /// True while a later page is in flight. Independent from a background refresh.
    var loadingMore = false
    /// True during a non-blocking refresh. Existing rows stay on screen.
    var refreshing = false
    var hasLoaded = false
    var captureKind = "note"
    var captureIntent = "note"
    /// iPhone Galeria presents the system photo library without the capture card.
    var openPhotoLibrary = false
    var kindFilter: String?
    var presentation: LibraryPresentation?
    var surface: LibrarySurface = .home
    var query = "" {
        didSet {
            if query != oldValue, searchChips.isEmpty { clearSearch() }
        }
    }
    var searchChips: [String] = []
    var searchItems: [Reference]?
    var searchError: String?
    var searching = false
    var hasPending = false
    var archiveUndo: ArchiveUndo?
    var hasArchivedItems = false
    var hasActiveCollection: Bool { !searchChips.isEmpty || kindFilter != nil }
    private var searchGeneration = 0
    private var accountID: String?
    private var generation = 0
    private var refreshToken: UUID?
    private var moreToken: UUID?
    /// Set when the last page failed so a visible tail cannot retry on its own.
    private var moreFailed = false
    private var fetchedAt: [String: Date] = [:]
    /// Cursor that belongs to the cached first page, not to a later page the user scrolled into.
    private var diskCursors: [String: String] = [:]
    private var firstPageItems: [String: [Reference]] = [:]
    private var paginatedFilters: Set<String> = []
    private static let staleInterval: TimeInterval = 60
    static let cachedPageLimit = 18
    private static let cachedFilterLimit = 8

    var hasPendingAnalysis: Bool {
        items.contains { $0.status == "queued" || $0.status == "processing" }
    }

    private func isStale(_ key: String) -> Bool {
        guard let at = fetchedAt[key] else { return true }
        return Date().timeIntervalSince(at) >= Self.staleInterval
    }

    /// Drops in-flight library requests so a cancelled or superseded fetch cannot leave the spinner up.
    private func invalidateRequests() {
        generation += 1
        refreshToken = nil
        moreToken = nil
        loading = false
        loadingMore = false
        refreshing = false
        moreFailed = false
    }

    func startCapture(kind: String = "note", intent: String? = nil) {
        captureKind = kind
        captureIntent = intent ?? kind
        presentation = .capture(UUID())
    }

    func reset(for account: String?) {
        // Reopening a window must not cancel the capture that opened it.
        guard account != accountID else { return }
        if let previous = cacheURL { try? FileManager.default.removeItem(at: previous) }
        invalidateRequests()
        accountID = account
        spaces = []
        selectedSpaceID = nil
        spaceError = nil
        spaceMutating = false
        cachedPages = [:]
        knownReferences = [:]
        scrollAnchors = [:]
        fetchedAt = [:]
        diskCursors = [:]
        firstPageItems = [:]
        paginatedFilters = []
        items = []
        nextCursor = nil
        error = nil
        hasLoaded = false
        presentation = nil
        openPhotoLibrary = false
        query = ""
        kindFilter = nil
        searchChips = []
        surface = .home
        captureIntent = "note"
        archiveUndo = nil
        hasArchivedItems = false
        clearSearch()
        restoreCache()
    }

    func showHome() {
        searchChips = []
        query = ""
        kindFilter = nil
        clearSearch()
        if surface != .home { show(.home) }
    }

    func show(_ destination: LibrarySurface) {
        guard destination != surface else { return }
        rememberPage()
        invalidateRequests()
        surface = destination
        let cached = cachedPages[filterKey]
        items = cached?.items ?? []
        nextCursor = cached?.nextCursor
        hasLoaded = cached != nil
        error = nil
        searchChips = []
        query = ""
        kindFilter = nil
        clearSearch()
    }

    /// Opens or closes a folder on the Spaces tab. Does not filter Home or switch to it.
    func selectSpace(_ id: String?) {
        guard id != selectedSpaceID || surface != .spaces else { return }
        rememberPage()
        invalidateRequests()
        selectedSpaceID = id
        if id != nil { surface = .spaces }
        let cached = cachedPages[filterKey]
        items = cached?.items ?? []
        nextCursor = cached?.nextCursor
        hasLoaded = cached != nil
        error = nil
        clearSearch()
        persistCache()
    }

    func removeSearchChip(_ term: String) {
        searchChips.removeAll { $0 == term }
        if searchChips.isEmpty { clearSearch() }
    }

    func clearSearch() {
        searchGeneration += 1
        searchItems = nil
        searchError = nil
        searching = false
        hasPending = false
    }

    func discardSearchReference(_ id: String) {
        searchItems?.removeAll { $0.id == id }
    }

    func search(_ client: APIClient, account: String) async {
        guard account == accountID, !searching else { return }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            if !searchChips.contains(where: { $0.caseInsensitiveCompare(typed) == .orderedSame }) {
                searchChips.append(typed)
            }
            query = ""
        }
        let term = searchChips.joined(separator: ", ")
        guard !term.isEmpty else { clearSearch(); return }
        searchGeneration += 1
        let operation = searchGeneration
        searching = true
        searchError = nil
        searchItems = nil
        if surface.showsArchived {
            let needle = term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            searchItems = items.filter { reference in
                [reference.title, reference.displayTitle, reference.url ?? ""]
                    .contains { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                        .contains(needle) }
            }
            hasPending = false
            searching = false
            return
        }
        defer { if operation == searchGeneration { searching = false } }
        do {
            let result = try await client.search(term, spaceID: scopedSpaceID)
            guard operation == searchGeneration, account == accountID else { return }
            searchItems = result.items
            for ref in result.items { knownReferences[ref.id] = ref }
            hasPending = result.hasPending
            LibraryAnalytics.searchSubmitted?(!result.items.isEmpty)
        } catch is CancellationError { }
        catch { if operation == searchGeneration { searchError = error.localizedDescription } }
    }

    /// Reloads the current filter. `more` appends the next page. `force` bypasses the freshness window
    /// (pull to refresh, retry, and edits). A fresh cache paints immediately and skips the network.
    func refresh(_ client: APIClient, account: String, more: Bool = false, force: Bool = false) async {
        guard account == accountID, !spaceMutating else { return }
        if more {
            await loadMore(client, account: account)
            return
        }
        if !force, hasLoaded, !isStale(filterKey) { return }
        guard refreshToken == nil, moreToken == nil else { return }
        let token = UUID()
        refreshToken = token
        let operation = generation
        let blocking = items.isEmpty && !hasLoaded
        if blocking { loading = true } else { refreshing = true }
        defer {
            if refreshToken == token {
                refreshToken = nil
                loading = false
                refreshing = false
            }
        }
        do {
            let page = try await client.list(cursor: nil,
                                             archived: surface.showsArchived,
                                             spaceID: surface.showsArchived ? nil : scopedSpaceID)
            guard operation == generation, account == accountID, !spaceMutating, refreshToken == token else { return }
            applyFirstPage(page)
            if let matches = searchItems {
                let fresh = Dictionary(uniqueKeysWithValues: page.items.map { ($0.id, $0) })
                searchItems = matches.compactMap { previous in
                    guard let current = fresh[previous.id] else { return previous }
                    return current.revision == previous.revision && current.status == "ready" ? current : nil
                }
            }
            if surface == .home, items.isEmpty {
                let archived = try await client.list(archived: true)
                guard operation == generation, account == accountID, refreshToken == token else { return }
                hasArchivedItems = !archived.items.isEmpty
            } else if surface == .archived, !items.isEmpty {
                hasArchivedItems = true
            }
            await refreshSpaces(client, account: account)
        } catch is CancellationError { }
        catch { if operation == generation, refreshToken == token { self.error = error.localizedDescription } }
    }

    /// Next page. One pagination at a time. A first-page refresh does not count as that request.
    private func loadMore(_ client: APIClient, account: String) async {
        guard account == accountID, !spaceMutating else { return }
        guard let cursor = nextCursor, !cursor.isEmpty else { return }
        guard hasLoaded, !moreFailed, error == nil else { return }
        // A first-page refresh in flight, including the 60-second freshness skip, must not block this.
        guard moreToken == nil, !loadingMore else { return }
        let token = UUID()
        moreToken = token
        loadingMore = true
        let operation = generation
        let previousCount = items.count
        defer {
            if moreToken == token {
                moreToken = nil
                loadingMore = false
            }
        }
        do {
            let page = try await client.list(cursor: cursor,
                                             archived: surface.showsArchived,
                                             spaceID: surface.showsArchived ? nil : scopedSpaceID)
            guard operation == generation, account == accountID, !spaceMutating, moreToken == token else { return }
            let known = Set(items.map(\.id))
            let fresh = page.items.filter { !known.contains($0.id) }
            if !fresh.isEmpty {
                items += fresh
                paginatedFilters.insert(filterKey)
            }
            // A cursor that does not move, or a page with nothing new, must not be requested again.
            if fresh.isEmpty || page.nextCursor == nil || page.nextCursor == cursor || items.count == previousCount {
                nextCursor = nil
            } else {
                nextCursor = page.nextCursor
            }
            for ref in page.items { knownReferences[ref.id] = ref }
            error = nil
            moreFailed = false
            hasLoaded = true
            rememberPage()
            persistCache()
        } catch is CancellationError { }
        catch {
            if operation == generation, moreToken == token {
                moreFailed = true
                self.error = error.localizedDescription
            }
        }
    }

    /// Installs a first page without blanking rows that are already on screen.
    private func applyFirstPage(_ page: LibraryPage) {
        let incoming = Array(page.items.prefix(Self.cachedPageLimit))
        let keepTail = paginatedFilters.contains(filterKey) && items.count > page.items.count
        if keepTail {
            let incomingIDs = Set(page.items.map(\.id))
            items = page.items + items.filter { !incomingIDs.contains($0.id) }
        } else {
            items = page.items
            nextCursor = page.nextCursor
            paginatedFilters.remove(filterKey)
        }
        for ref in page.items { knownReferences[ref.id] = ref }
        firstPageItems[filterKey] = incoming
        if let cursor = page.nextCursor { diskCursors[filterKey] = cursor }
        else { diskCursors.removeValue(forKey: filterKey) }
        fetchedAt[filterKey] = Date()
        hasLoaded = true
        error = nil
        moreFailed = false
        rememberPage()
        persistCache()
    }

    func refreshSpaces(_ client: APIClient, account: String) async {
        guard account == accountID, !spaceMutating else { return }
        let operation = generation
        do {
            let fresh = try await client.spaces()
            guard account == accountID, operation == generation, !spaceMutating else { return }
            spaces = fresh
            spaceError = nil
            if let selectedSpaceID, !spaces.contains(where: { $0.id == selectedSpaceID }) {
                selectSpace(nil)
            }
            persistCache()
        } catch {
            if account == accountID { spaceError = error.localizedDescription }
        }
    }

    func saveSpace(_ client: APIClient, account: String, space: Space? = nil,
                   name: String? = nil, sortIndex: Int? = nil) async -> Bool {
        guard account == accountID, !spaceMutating else { return false }
        let previous = spaces
        var optimistic = space ?? Space(name: name ?? "", sortIndex: spaces.count)
        if let name { optimistic.name = name.trimmingCharacters(in: .whitespacesAndNewlines) }
        spaces.removeAll { $0.id == optimistic.id }
        spaces.insert(optimistic, at: min(sortIndex ?? optimistic.sortIndex, spaces.count))
        for i in spaces.indices { spaces[i].sortIndex = i }
        invalidateRequests()
        spaceMutating = true
        spaceError = nil
        defer { if account == accountID { spaceMutating = false } }
        do {
            let saved = try await client.saveSpace(id: space?.id, name: name, sortIndex: sortIndex)
            guard account == accountID else { return false }
            if let index = spaces.firstIndex(where: { $0.id == optimistic.id }) { spaces[index] = saved }
            if space == nil { LibraryAnalytics.spaceCreated?() }
            persistCache()
            return true
        } catch {
            guard account == accountID else { return false }
            spaces = previous
            spaceError = error.localizedDescription
            return false
        }
    }

    func deleteSpace(_ space: Space, client: APIClient, account: String) async {
        guard account == accountID, !spaceMutating else { return }
        invalidateRequests()
        spaceMutating = true
        spaceError = nil
        defer { if account == accountID { spaceMutating = false } }
        do {
            try await client.deleteSpace(id: space.id)
            guard account == accountID else { return }
            spaces.removeAll { $0.id == space.id }
            cachedPages.removeValue(forKey: space.id)
            firstPageItems.removeValue(forKey: space.id)
            diskCursors.removeValue(forKey: space.id)
            fetchedAt.removeValue(forKey: space.id)
            paginatedFilters.remove(space.id)
            let saved = items + cachedPages.values.flatMap(\.items) + Array(knownReferences.values)
            let all = Array(Dictionary(saved.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }).values)
            for var ref in all {
                ref.spaceIds = ref.membershipIDs.filter { $0 != space.id }
                mergeSpaceReference(ref)
            }
            if selectedSpaceID == space.id { selectSpace(nil) }
            persistCache()
        } catch { if account == accountID { spaceError = error.localizedDescription } }
    }

    func reference(_ id: String) -> Reference? {
        items.first { $0.id == id } ?? knownReferences[id] ?? cachedPages.values.lazy.flatMap(\.items).first { $0.id == id }
    }

    /// Newest gallery or media references already in memory for a space, used on the board mosaic.
    func spaceThumbnails(_ spaceID: String, limit: Int = 3) -> [Reference] {
        var byID: [String: Reference] = [:]
        func consider(_ ref: Reference, forcedMember: Bool) {
            guard !ref.isArchived else { return }
            guard forcedMember || ref.membershipIDs.contains(spaceID) else { return }
            guard !ref.gallery.isEmpty || ref.media != nil else { return }
            if let current = byID[ref.id], current.revision > ref.revision { return }
            byID[ref.id] = ref
        }
        let viewingSpace = scopedSpaceID == spaceID
        for ref in items { consider(ref, forcedMember: viewingSpace) }
        for ref in knownReferences.values { consider(ref, forcedMember: false) }
        for (key, page) in cachedPages {
            for ref in page.items { consider(ref, forcedMember: key == spaceID) }
        }
        return byID.values.sorted { lhs, rhs in
            if lhs.createdAt != rhs.createdAt { return lhs.createdAt > rhs.createdAt }
            return lhs.id > rhs.id
        }.prefix(limit).map { $0 }
    }

    func assignSpace(_ space: Space, references: [Reference], adding: Bool,
                     client: APIClient, account: String) async {
        guard account == accountID, !spaceMutating else { return }
        invalidateRequests()
        spaceMutating = true
        spaceError = nil
        defer { if account == accountID { spaceMutating = false; persistCache() } }
        let originals = references.map { reference($0.id) ?? $0 }
        for ref in originals { knownReferences[ref.id] = ref }
        for var ref in originals {
            var ids = Set(ref.membershipIDs)
            if adding { ids.insert(space.id) } else { ids.remove(space.id) }
            ref.spaceIds = ids.sorted()
            mergeSpaceReference(ref)
        }
        var failures = 0
        for original in originals {
            do {
                let saved = try await client.assignSpaces(referenceID: original.id,
                    add: adding ? [space.id] : [], remove: adding ? [] : [space.id])
                guard account == accountID else { return }
                mergeSpaceReference(saved)
            } catch {
                guard account == accountID else { return }
                // Roll back only this membership; preserve independent archive/content edits.
                var rollback = reference(original.id) ?? original
                var ids = Set(rollback.membershipIDs)
                if original.membershipIDs.contains(space.id) { ids.insert(space.id) }
                else { ids.remove(space.id) }
                rollback.spaceIds = ids.sorted()
                mergeSpaceReference(rollback)
                failures += 1
                spaceError = error.localizedDescription
            }
        }
        if failures > 1 { spaceError = "\(failures) referências não foram alteradas. Tente novamente." }
    }

    private func mergeSpaceReference(_ ref: Reference) {
        let old = reference(ref.id)
        if let old {
            for index in spaces.indices {
                let id = spaces[index].id
                let delta = (!ref.isArchived && ref.membershipIDs.contains(id) ? 1 : 0) - (!old.isArchived && old.membershipIDs.contains(id) ? 1 : 0)
                spaces[index].referenceCount = max(0, spaces[index].referenceCount + delta)
            }
        }
        knownReferences[ref.id] = ref
        for key in Array(cachedPages.keys) {
            guard let page = cachedPages[key] else { continue }
            var values = page.items.filter { $0.id != ref.id }
            let belongs = key == "archived" ? ref.isArchived : !ref.isArchived && (key == "all" || ref.membershipIDs.contains(key))
            if belongs { values.append(ref) }
            values.sort { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
            cachedPages[key] = LibraryPage(items: values, nextCursor: page.nextCursor)
            if var saved = firstPageItems[key] {
                let wasCached = saved.contains { $0.id == ref.id }
                saved.removeAll { $0.id == ref.id }
                if belongs && wasCached { saved.append(ref) }
                saved.sort { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
                firstPageItems[key] = Array(saved.prefix(Self.cachedPageLimit))
            }
        }
        items.removeAll { $0.id == ref.id }
        let inScope = scopedSpaceID.map { ref.membershipIDs.contains($0) } ?? true
        let belongs = surface.showsArchived ? ref.isArchived : !ref.isArchived && inScope
        if belongs { items.append(ref) }
        items.sort { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
        if let index = searchItems?.firstIndex(where: { $0.id == ref.id }) {
            if belongs { searchItems?[index] = ref } else { searchItems?.remove(at: index) }
        }
        rememberPage()
    }

    private struct StoredPage: Codable {
        var items: [Reference]
        var nextCursor: String?
        var fetchedAt: Date?
    }

    private struct Cache: Codable {
        var spaces: [Space]
        var selectedSpaceID: String?
        var pages: [String: StoredPage]
        var anchors: [String: String]
    }

    private var cacheURL: URL? {
        guard let accountID else { return nil }
        let name = Data(accountID.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("QueepLibrary", isDirectory: true).appendingPathComponent(name + ".json")
    }

    private func rememberPage() {
        guard hasLoaded else { return }
        cachedPages[filterKey] = LibraryPage(items: items, nextCursor: nextCursor)
        guard !paginatedFilters.contains(filterKey) else { return }
        firstPageItems[filterKey] = Array(items.prefix(Self.cachedPageLimit))
        if let nextCursor { diskCursors[filterKey] = nextCursor }
        else { diskCursors.removeValue(forKey: filterKey) }
    }

    private func persistCache() {
        guard let url = cacheURL else { return }
        let ranked = cachedPages.keys.sorted { lhs, rhs in
            let left = fetchedAt[lhs] ?? .distantPast
            let right = fetchedAt[rhs] ?? .distantPast
            if left != right { return left > right }
            return lhs < rhs
        }
        var pages: [String: StoredPage] = [:]
        for key in ranked.prefix(Self.cachedFilterLimit) {
            guard let page = cachedPages[key] else { continue }
            let items = Array((firstPageItems[key] ?? page.items).prefix(Self.cachedPageLimit))
            let cursor = diskCursors[key] ?? (paginatedFilters.contains(key) ? nil : page.nextCursor)
            pages[key] = StoredPage(items: items, nextCursor: cursor, fetchedAt: fetchedAt[key])
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let cache = Cache(spaces: spaces, selectedSpaceID: selectedSpaceID, pages: pages, anchors: scrollAnchors)
            try JSONEncoder().encode(cache).write(to: url, options: .atomic)
            var directory = url.deletingLastPathComponent()
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
        } catch { /* A cache failure must not turn a confirmed save into an error. */ }
    }

    private func restoreCache() {
        guard let url = cacheURL, let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        spaces = cache.spaces
        selectedSpaceID = cache.selectedSpaceID
        scrollAnchors = cache.anchors
        cachedPages = [:]
        for (key, page) in cache.pages {
            let items = Array(page.items.prefix(Self.cachedPageLimit))
            cachedPages[key] = LibraryPage(items: items, nextCursor: page.nextCursor)
            firstPageItems[key] = items
            if let cursor = page.nextCursor { diskCursors[key] = cursor }
            if let at = page.fetchedAt { fetchedAt[key] = at }
        }
        if let page = cachedPages[filterKey] {
            items = page.items
            nextCursor = page.nextCursor
            hasLoaded = true
        }
    }

    func setArchived(_ references: [Reference], archived: Bool,
                     client: APIClient, account: String) {
        guard account == accountID, !references.isEmpty else { return }
        let originals = references.map { reference($0.id) ?? $0 }
        invalidateRequests()
        let ids = Set(references.map(\.id))
        let optimistic = references.map { reference in
            var copy = reference
            copy.archivedAt = archived ? Date() : nil
            return copy
        }
        mergeArchiveResults(optimistic)
        persistCache()
        if case .reference(let open) = presentation, ids.contains(open.id) {
            presentation = nil
        }
        Task {
            do {
                let changed: [Reference]
                if references.count == 1, let reference = references.first {
                    changed = [try await client.setArchived(archived, reference: reference)]
                } else {
                    changed = try await client.setArchived(archived, ids: references.map(\.id))
                }
                guard account == accountID else { return }
                mergeArchiveResults(changed)
                if archived {
                    hasArchivedItems = true
                    archiveUndo = ArchiveUndo(references: changed)
                } else if surface == .archived, items.isEmpty, nextCursor == nil {
                    hasArchivedItems = false
                }
                error = nil
            } catch is CancellationError { }
            catch {
                guard account == accountID else { return }
                mergeArchiveResults(originals)
                self.error = error.localizedDescription
            }
        }
    }

    func undoArchive(_ undo: ArchiveUndo, client: APIClient, account: String) {
        guard archiveUndo?.id == undo.id else { return }
        archiveUndo = nil
        setArchived(undo.references, archived: false, client: client, account: account)
    }

    private func mergeArchiveResults(_ references: [Reference]) {
        for ref in references { mergeSpaceReference(ref) }
        if surface.showsArchived {
            items.sort { ($0.archivedAt ?? .distantPast) > ($1.archivedAt ?? .distantPast) }
        }
        rememberPage()
        persistCache()
    }
}

/// Whether the tail of the loaded list is close enough to the visible bottom to request another page.
enum LibraryEndTrigger {
    static let threshold: CGFloat = 160

    /// Points of loaded content still below the visible bottom. Zero means the end is on screen.
    /// A content size that has not been laid out must not look like the end.
    static func distanceToEnd(contentHeight: CGFloat, contentOffsetY: CGFloat, containerHeight: CGFloat) -> CGFloat {
        guard contentHeight > 1, containerHeight > 1,
              contentHeight.isFinite, contentOffsetY.isFinite, containerHeight.isFinite else {
            return .greatestFiniteMagnitude
        }
        return contentHeight - contentOffsetY - containerHeight
    }

    /// Distance still below the visible bottom, using whichever scroll signal has actually moved.
    /// A visible rect that is the entire tall content (not the viewport) is ignored so a stale
    /// full-content frame cannot look like the end while the reader is still in the middle.
    static func resolvedDistance(contentHeight: CGFloat,
                                 contentOffsetY: CGFloat,
                                 containerHeight: CGFloat,
                                 visibleMaxY: CGFloat,
                                 visibleHeight: CGFloat) -> CGFloat {
        guard contentHeight > 1, containerHeight > 1,
              contentHeight.isFinite, containerHeight.isFinite else {
            return .greatestFiniteMagnitude
        }
        let byOffset = distanceToEnd(contentHeight: contentHeight,
                                     contentOffsetY: contentOffsetY,
                                     containerHeight: containerHeight)
        let contentFits = contentHeight <= containerHeight + 1
        let visibleIsViewport = visibleHeight > 1 && visibleHeight <= containerHeight * 1.25
        guard (visibleIsViewport || contentFits), visibleMaxY.isFinite else { return byOffset }
        let byVisible = contentHeight - visibleMaxY
        guard byVisible.isFinite else { return byOffset }
        guard byOffset.isFinite else { return byVisible }
        return min(byOffset, byVisible)
    }

    /// True when the tail is already on screen or within one viewport of the visible bottom.
    /// Farther than that — the middle of a longer list — must not request a page.
    static func shouldPage(distanceToEnd: CGFloat, containerHeight: CGFloat) -> Bool {
        guard distanceToEnd.isFinite, containerHeight > 1, containerHeight.isFinite else { return false }
        return distanceToEnd <= containerHeight
    }

    /// Request another page only near the end, with a cursor, and while no page is already in flight.
    /// A background refresh is not in flight for this decision.
    static func shouldRequestNextPage(distanceToEnd: CGFloat,
                                      containerHeight: CGFloat,
                                      hasCursor: Bool,
                                      inFlight: Bool) -> Bool {
        guard hasCursor, !inFlight else { return false }
        return shouldPage(distanceToEnd: distanceToEnd, containerHeight: containerHeight)
    }

    /// How many loaded rows to show after the list count changes.
    /// When every loaded row was already on screen, an appended page is shown immediately.
    /// A longer list the reader has not reached yet stays on the local batch.
    static func nextShownCount(shown: Int, previousCount: Int, newCount: Int) -> Int {
        if newCount < shown || shown >= previousCount { return max(0, newCount) }
        return shown
    }

    static func isNearEnd(tailMinY: CGFloat, viewport: CGRect) -> Bool {
        guard viewport.width > 1, viewport.height > 1, tailMinY.isFinite else { return false }
        if tailMinY > viewport.maxY + threshold { return false }
        if tailMinY < viewport.minY - threshold { return false }
        return true
    }
}
