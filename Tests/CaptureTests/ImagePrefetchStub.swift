import Foundation
import QueepCore

/// Capture tests compile `LibraryStore` without the gallery views.
/// Prefetch only warms posters after a refresh; these tests do not download them.
enum ImagePrefetch {
    static func warm(_ items: [Reference], client: APIClient, account: String) {}
}
