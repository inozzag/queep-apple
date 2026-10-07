import Foundation

/// Copy for the live search screen. The API message and the pending notice are shown as written.
public enum SearchPresentation {
    public static let pending = "Algumas referências ainda aguardam análise ou precisam de uma nova tentativa."
    public static let analyzedCandidates = "Nenhuma correspondência entre os candidatos analisados. Tente descrever de outro jeito."
    public static let filteredOut = "Nenhuma referência deste tipo nos resultados. Remova o filtro para ver o que a busca encontrou."
    public static let archived = "Nenhum arquivado tem esse título ou endereço."

    public static func failureMessage(_ apiError: String) -> String {
        let trimmed = apiError.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Não foi possível buscar" }
        return trimmed
    }

    /// `localFilterHidMatches` is true when the API returned hits and the on-device type filter removed all of them.
    public static func emptyDescription(archived: Bool, localFilterHidMatches: Bool) -> String {
        if localFilterHidMatches { return filteredOut }
        if archived { return Self.archived }
        return analyzedCandidates
    }

    public static func showsPending(hasPending: Bool, showingSearch: Bool) -> Bool {
        hasPending && showingSearch
    }
}
