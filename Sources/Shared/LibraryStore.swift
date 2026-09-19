import Observation
import QueepCore
import Foundation

enum LibrarySurface: String, CaseIterable {
    case home, spaces
}

enum LibraryPresentation: Identifiable {
    case account
    case usage
    case help
    case deleteAccount
    case subscription
    case capture(UUID)
    case reference(Reference)

    var id: String {
        switch self {
        case .account: "account"
        case .usage: "usage"
        case .help: "help"
        case .deleteAccount: "delete-account"
        case .subscription: "subscription"
        case .capture(let id): "capture-\(id)"
        case .reference(let reference): "reference-\(reference.id)"
        }
    }
}

@MainActor @Observable
final class LibraryStore {
    var items: [Reference] = []
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
        generation += 1
        accountID = account
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
        clearSearch()
    }

    func showHome() {
        surface = .home
        searchChips = []
        query = ""
        kindFilter = nil
        clearSearch()
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
        defer { if operation == searchGeneration { searching = false } }
        do {
            let result = try await client.search(term)
            guard operation == searchGeneration, account == accountID else { return }
            searchItems = result.items
            hasPending = result.hasPending
        } catch is CancellationError { }
        catch { if operation == searchGeneration { searchError = error.localizedDescription } }
    }

    func refresh(_ client: APIClient, account: String, more: Bool = false) async {
        guard account == accountID, !loading else { return }
        let operation = generation
        loading = true
        defer { if operation == generation { loading = false } }
        do {
            let page = try await client.list(cursor: more ? nextCursor : nil)
            guard operation == generation, account == accountID else { return }
            if more {
                let known = Set(items.map(\.id))
                items += page.items.filter { !known.contains($0.id) }
            } else { items = page.items }
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
        } catch is CancellationError { }
        catch { if operation == generation { self.error = error.localizedDescription } }
    }
}
