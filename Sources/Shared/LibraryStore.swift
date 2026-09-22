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
    var filterKey: String { surface.showsArchived ? "archived" : selectedSpaceID ?? "all" }
    var selectedSpace: Space? { spaces.first { $0.id == selectedSpaceID } }
    var nextCursor: String?
    var error: String?
    var loading = false
    var hasLoaded = false
    var captureKind = "note"
    var captureIntent = "note"
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

    func startCapture(kind: String = "note", intent: String? = nil) {
        captureKind = kind
        captureIntent = intent ?? kind
        presentation = .capture(UUID())
    }

    func reset(for account: String?) {
        // Reopening a window must not cancel the capture that opened it.
        guard account != accountID else { return }
        if let previous = cacheURL { try? FileManager.default.removeItem(at: previous) }
        generation += 1
        accountID = account
        spaces = []
        selectedSpaceID = nil
        spaceError = nil
        spaceMutating = false
        cachedPages = [:]
        knownReferences = [:]
        scrollAnchors = [:]
        items = []
        nextCursor = nil
        error = nil
        loading = false
        hasLoaded = false
        presentation = nil
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
        selectSpace(nil)
        searchChips = []
        query = ""
        kindFilter = nil
        clearSearch()
    }

    func show(_ destination: LibrarySurface) {
        guard destination != surface else { return }
        rememberPage()
        generation += 1
        surface = destination
        let cached = cachedPages[filterKey]
        items = cached?.items ?? []
        nextCursor = cached?.nextCursor
        hasLoaded = cached != nil
        loading = false
        error = nil
        searchChips = []
        query = ""
        kindFilter = nil
        clearSearch()
    }

    func selectSpace(_ id: String?) {
        guard id != selectedSpaceID || surface != .home else { return }
        rememberPage()
        generation += 1
        selectedSpaceID = id
        surface = .home
        let cached = cachedPages[filterKey]
        items = cached?.items ?? []
        nextCursor = cached?.nextCursor
        hasLoaded = cached != nil
        loading = false
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
            let result = try await client.search(term, spaceID: selectedSpaceID)
            guard operation == searchGeneration, account == accountID else { return }
            searchItems = result.items
            for ref in result.items { knownReferences[ref.id] = ref }
            hasPending = result.hasPending
        } catch is CancellationError { }
        catch { if operation == searchGeneration { searchError = error.localizedDescription } }
    }

    func refresh(_ client: APIClient, account: String, more: Bool = false) async {
        guard account == accountID, !loading, !spaceMutating else { return }
        let operation = generation
        loading = true
        defer { if operation == generation { loading = false } }
        do {
            let page = try await client.list(cursor: more ? nextCursor : nil,
                                             archived: surface.showsArchived,
                                             spaceID: surface.showsArchived ? nil : selectedSpaceID)
            guard operation == generation, account == accountID, !spaceMutating else { return }
            if more {
                let known = Set(items.map(\.id))
                items += page.items.filter { !known.contains($0.id) }
            } else { items = page.items }
            for ref in page.items { knownReferences[ref.id] = ref }
            nextCursor = page.nextCursor
            hasLoaded = true
            if let matches = searchItems {
                let fresh = Dictionary(uniqueKeysWithValues: page.items.map { ($0.id, $0) })
                searchItems = matches.compactMap { previous in
                    guard let current = fresh[previous.id] else { return previous }
                    return current.revision == previous.revision && current.status == "ready" ? current : nil
                }
            }
            error = nil
            rememberPage()
            persistCache()
            if surface == .home, selectedSpaceID == nil, !more, items.isEmpty {
                let archived = try await client.list(archived: true)
                guard operation == generation, account == accountID else { return }
                hasArchivedItems = !archived.items.isEmpty
            } else if surface == .archived, !items.isEmpty {
                hasArchivedItems = true
            }
            if !more { await refreshSpaces(client, account: account) }
        } catch is CancellationError { }
        catch { if operation == generation { self.error = error.localizedDescription } }
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
        generation += 1
        loading = false
        spaceMutating = true
        spaceError = nil
        defer { if account == accountID { spaceMutating = false } }
        do {
            let saved = try await client.saveSpace(id: space?.id, name: name, sortIndex: sortIndex)
            guard account == accountID else { return false }
            if let index = spaces.firstIndex(where: { $0.id == optimistic.id }) { spaces[index] = saved }
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
        generation += 1
        loading = false
        spaceMutating = true
        spaceError = nil
        defer { if account == accountID { spaceMutating = false } }
        do {
            try await client.deleteSpace(id: space.id)
            guard account == accountID else { return }
            spaces.removeAll { $0.id == space.id }
            cachedPages.removeValue(forKey: space.id)
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

    func assignSpace(_ space: Space, references: [Reference], adding: Bool,
                     client: APIClient, account: String) async {
        guard account == accountID, !spaceMutating else { return }
        generation += 1
        loading = false
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
        }
        items.removeAll { $0.id == ref.id }
        let belongs = surface.showsArchived ? ref.isArchived : !ref.isArchived && (selectedSpaceID == nil || ref.membershipIDs.contains(selectedSpaceID!))
        if belongs { items.append(ref) }
        items.sort { $0.createdAt == $1.createdAt ? $0.id > $1.id : $0.createdAt > $1.createdAt }
        if let index = searchItems?.firstIndex(where: { $0.id == ref.id }) {
            if belongs { searchItems?[index] = ref } else { searchItems?.remove(at: index) }
        }
        rememberPage()
    }

    private struct Cache: Codable {
        var spaces: [Space]
        var selectedSpaceID: String?
        var pages: [String: LibraryPage]
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
    }

    private func persistCache() {
        guard let url = cacheURL else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let cache = Cache(spaces: spaces, selectedSpaceID: selectedSpaceID, pages: cachedPages, anchors: scrollAnchors)
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
        cachedPages = cache.pages
        scrollAnchors = cache.anchors
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
        generation += 1
        loading = false
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
