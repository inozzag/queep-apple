import Testing
@testable import QueepCore

@Test func searchFailureShowsTheServerMessage() {
    let message = "Escreva uma busca de 2 a 500 caracteres."
    #expect(SearchPresentation.failureMessage(message) == message)
    #expect(!SearchPresentation.failureMessage(message).contains("Não foi possível buscar"))
    #expect(SearchPresentation.failureMessage("  ") == "Não foi possível buscar")
}

@Test func typeFilterEmptyCopyDoesNotBlameAnalyzedCandidates() {
    let filtered = SearchPresentation.emptyDescription(archived: false, localFilterHidMatches: true)
    #expect(filtered == SearchPresentation.filteredOut)
    #expect(!filtered.contains("candidatos analisados"))
    let missed = SearchPresentation.emptyDescription(archived: false, localFilterHidMatches: false)
    #expect(missed.contains("candidatos analisados"))
    let archived = SearchPresentation.emptyDescription(archived: true, localFilterHidMatches: false)
    #expect(archived == SearchPresentation.archived)
}

@Test func pendingAnalysisNoticeIsShownWithLiveResults() {
    #expect(SearchPresentation.showsPending(hasPending: true, showingSearch: true))
    #expect(!SearchPresentation.showsPending(hasPending: true, showingSearch: false))
    #expect(!SearchPresentation.showsPending(hasPending: false, showingSearch: true))
    #expect(SearchPresentation.pending.contains("aguardam análise"))
}
