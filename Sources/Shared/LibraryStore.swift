import Observation
import QueepCore
import Foundation

enum LibraryPresentation: Identifiable {
    case subscription
    case capture(UUID)
    case reference(Reference)

    var id: String {
        switch self {
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
    var presentation: LibraryPresentation?
    var query = "" {
        didSet { if query != oldValue { clearSearch() } }
    }
    var searchItems: [Reference]?
    var searchError: String?
    var searching = false
    var hasPending = false
    private var searchGeneration = 0
    private var accountID: String?
    private var generation = 0

    func reset(for account: String?) {
        // Reopening a window must not cancel the capture that opened it.
        guard account != accountID else { return }
        generation += 1
        accountID = account
        items = []
        nextCursor = nil
        error = nil
        loading = false
        presentation = nil
        query = ""
        clearSearch()
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
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
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
