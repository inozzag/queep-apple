import Testing
@testable import QueepCore

@Test func apiDiagnosticsReportsOnlyServerAndTransportFailures() {
    #expect(APIDiagnostics.shouldReport(status: nil))
    #expect(APIDiagnostics.shouldReport(status: 500))
    #expect(APIDiagnostics.shouldReport(status: 503))
    #expect(APIDiagnostics.shouldReport(status: 599))
    #expect(!APIDiagnostics.shouldReport(status: 401))
    #expect(!APIDiagnostics.shouldReport(status: 402))
    #expect(!APIDiagnostics.shouldReport(status: 403))
    #expect(!APIDiagnostics.shouldReport(status: 404))
    #expect(!APIDiagnostics.shouldReport(status: 409))
    #expect(!APIDiagnostics.shouldReport(status: 422))
    #expect(!APIDiagnostics.shouldReport(status: 429))
}

@Test func apiDiagnosticsRouteDropsQueryAndReferenceID() {
    let route = APIDiagnostics.route(
        "v1/references/550e8400-e29b-41d4-a716-446655440000?q=nota+secreta"
    )
    #expect(route == "v1/references/:id")
    #expect(!route.contains("nota"))
    #expect(!route.contains("550e8400"))
}

@Test func apiDiagnosticsKeepsTransportCodeWithoutTheRouteQuery() async {
    final class Seen: @unchecked Sendable {
        var items: [APIDiagnostics.Failure] = []
    }
    let seen = Seen()
    await DiagnosticsIsolation.shared.perform {
        APIDiagnostics.record = { seen.items.append($0) }
        defer { APIDiagnostics.record = nil }
        APIDiagnostics.report(method: "GET", path: "v1/account?token=secret", status: nil,
                              transportCode: URLError.timedOut.rawValue)
    }
    #expect(seen.items.count == 1)
    #expect(seen.items[0].status == nil)
    #expect(seen.items[0].transportCode == URLError.timedOut.rawValue)
    #expect(seen.items[0].path == "v1/account")
    #expect(!seen.items[0].path.contains("secret"))
}

@Test func apiDiagnosticsIgnoresQuotaEvenIfReported() async {
    final class Seen: @unchecked Sendable {
        var items: [APIDiagnostics.Failure] = []
    }
    let seen = Seen()
    await DiagnosticsIsolation.shared.perform {
        APIDiagnostics.record = { seen.items.append($0) }
        defer { APIDiagnostics.record = nil }
        APIDiagnostics.report(method: "POST", path: "v1/references?url=https://secret.example", status: 402)
        APIDiagnostics.report(method: "GET", path: "v1/search?q=crm", status: nil)
    }
    #expect(seen.items.count == 1)
    #expect(seen.items[0].status == nil)
    #expect(seen.items[0].path == "v1/search")
    #expect(!seen.items[0].path.contains("crm"))
}

@Test func diagnosticScrubberRemovesNoteURLAndSecrets() {
    let payload: [String: Any] = [
        "platform": "ios",
        "note": "texto da nota",
        "url": "https://example.com/private",
        "query": "busca secreta",
        "filename": "contrato.pdf",
        "token": "abc",
        "email": "person@example.com",
        "password": "secret",
        "detail": "saved https://example.com/a and person@example.com"
    ]
    let clean = DiagnosticScrubber.scrub(payload)
    #expect(clean["platform"] as? String == "ios")
    #expect(clean["note"] == nil)
    #expect(clean["url"] == nil)
    #expect(clean["query"] == nil)
    #expect(clean["filename"] == nil)
    #expect(clean["token"] == nil)
    #expect(clean["email"] == nil)
    #expect(clean["password"] == nil)
    let detail = clean["detail"] as? String ?? ""
    #expect(detail.contains("[redacted]"))
    #expect(!detail.contains("https://"))
    #expect(!detail.contains("person@example.com"))
}
