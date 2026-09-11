import Observation
import QueepCore
import Foundation

enum LibraryPresentation: Identifiable {
    case capture(UUID)
    case reference(Reference)

    var id: String {
        switch self {
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
            error = nil
        } catch is CancellationError { }
        catch { if operation == generation { self.error = error.localizedDescription } }
    }
}
