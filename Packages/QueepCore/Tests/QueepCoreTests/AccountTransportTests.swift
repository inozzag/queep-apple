import Foundation
import Testing
@testable import QueepCore

private final class ScriptedTransport: URLProtocol, @unchecked Sendable {
    final class Script: @unchecked Sendable {
        let steps: [Step]
        private let lock = NSLock()
        private var served = 0

        init(steps: [Step]) { self.steps = steps }

        var count: Int {
            lock.lock()
            defer { lock.unlock() }
            return served
        }

        func next() -> Step {
            lock.lock()
            defer { lock.unlock() }
            let step = steps[min(served, steps.count - 1)]
            served += 1
            return step
        }
    }

    enum Step {
        case fail(URLError.Code)
        case http(Int, Data)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var scripts: [String: Script] = [:]

    static func register(host: String, steps: [Step]) -> Script {
        let script = Script(steps: steps)
        lock.lock()
        scripts[host] = script
        lock.unlock()
        return script
    }

    static func remove(host: String) {
        lock.lock()
        scripts[host] = nil
        lock.unlock()
    }

    private static func script(for host: String) -> Script? {
        lock.lock()
        defer { lock.unlock() }
        return scripts[host]
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return script(for: host) != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let host = request.url?.host, let script = Self.script(for: host), let client else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        switch script.next() {
        case .fail(let code):
            client.urlProtocol(self, didFailWithError: URLError(code))
        case .http(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client.urlProtocol(self, didLoad: body)
            client.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private func scriptedClient(host: String) -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ScriptedTransport.self]
    configuration.waitsForConnectivity = false
    configuration.timeoutIntervalForResource = 8
    return APIClient(baseURL: URL(string: "https://\(host)")!,
                     session: URLSession(configuration: configuration),
                     retryDelay: { _ in .milliseconds(1) },
                     token: { "test" })
}

private let activeAccount = Data(#"{"status":"active","version":1,"can_restore":false}"#.utf8)

@Test func transientTransportClassificationMatchesTimeoutAndConnectivity() {
    #expect(APIClient.isTransientTransport(URLError(.timedOut)))
    #expect(APIClient.isTransientTransport(URLError(.networkConnectionLost)))
    #expect(APIClient.isTransientTransport(URLError(.notConnectedToInternet)))
    #expect(APIClient.isTransientTransport(URLError(.cannotConnectToHost)))
    #expect(APIClient.isTransientTransport(URLError(.dnsLookupFailed)))
    let bridged = NSError(domain: NSURLErrorDomain, code: URLError.timedOut.rawValue)
    #expect(APIClient.isTransientTransport(bridged))
    #expect(!APIClient.isTransientTransport(URLError(.cancelled)))
    #expect(!APIClient.isTransientTransport(URLError(.badURL)))
    #expect(!APIClient.isTransientTransport(NSError(domain: NSURLErrorDomain, code: URLError.cancelled.rawValue)))
    #expect(APIClient.retriesTransientFailures(method: "GET", timeout: 12, enabled: true))
    #expect(APIClient.retriesTransientFailures(method: "GET", timeout: 20, enabled: true))
    #expect(!APIClient.retriesTransientFailures(method: "GET", timeout: 12, enabled: false))
    #expect(!APIClient.retriesTransientFailures(method: "GET", timeout: 60, enabled: true))
    #expect(!APIClient.retriesTransientFailures(method: "POST", timeout: 12, enabled: true))
    #expect(!APIClient.retriesTransientFailures(method: "DELETE", timeout: 12, enabled: true))
    #expect(APIClient.defaultRetryDelay(0) == .milliseconds(400))
    #expect(APIClient.defaultRetryDelay(1) == .milliseconds(1200))
}

@Test func accountStatusRetriesTransportThenReadsTheAccount() async throws {
    let host = "account-retry-\(UUID().uuidString.lowercased()).test"
    let script = ScriptedTransport.register(host: host, steps: [
        .fail(.timedOut), .fail(.networkConnectionLost), .http(200, activeAccount)
    ])
    defer { ScriptedTransport.remove(host: host) }
    let seen = FailureLog()
    let status = try await DiagnosticsIsolation.shared.perform {
        APIDiagnostics.record = { seen.append($0) }
        defer { APIDiagnostics.record = nil }
        return try await scriptedClient(host: host).accountStatus()
    }
    #expect(status.isActive)
    #expect(script.count == 3)
    #expect(seen.items.isEmpty)
}

@Test func accountStatusReportsTransportOnceAfterRetriesAreExhausted() async {
    let host = "account-fail-\(UUID().uuidString.lowercased()).test"
    let script = ScriptedTransport.register(host: host, steps: [
        .fail(.timedOut), .fail(.timedOut), .fail(.notConnectedToInternet)
    ])
    defer { ScriptedTransport.remove(host: host) }
    let seen = FailureLog()
    let failure = await DiagnosticsIsolation.shared.perform { () -> String in
        APIDiagnostics.record = { seen.append($0) }
        defer { APIDiagnostics.record = nil }
        do {
            _ = try await scriptedClient(host: host).accountStatus()
            return "loaded"
        } catch QueepError.unavailable {
            return ""
        } catch {
            return String(describing: error)
        }
    }
    #expect(failure.isEmpty)
    #expect(script.count == 3)
    #expect(seen.items.count == 1)
    #expect(seen.items.first?.method == "GET")
    #expect(seen.items.first?.path == "v1/account")
    #expect(seen.items.first?.status == nil)
    #expect(seen.items.first?.transportCode == URLError.notConnectedToInternet.rawValue)
}

@Test func accountStatusDoesNotRetryUnauthorized() async {
    let host = "account-auth-\(UUID().uuidString.lowercased()).test"
    let script = ScriptedTransport.register(host: host, steps: [
        .http(401, Data(#"{"detail":"unauthorized"}"#.utf8)),
        .http(200, activeAccount)
    ])
    defer { ScriptedTransport.remove(host: host) }
    let seen = FailureLog()
    let failure = await DiagnosticsIsolation.shared.perform { () -> String in
        APIDiagnostics.record = { seen.append($0) }
        defer { APIDiagnostics.record = nil }
        do {
            _ = try await scriptedClient(host: host).accountStatus()
            return "loaded"
        } catch QueepError.unauthorized {
            return ""
        } catch {
            return String(describing: error)
        }
    }
    #expect(failure.isEmpty)
    #expect(script.count == 1)
    #expect(seen.items.isEmpty)
}

@Test func serverFailureIsNotRetried() async {
    let host = "account-server-\(UUID().uuidString.lowercased()).test"
    let script = ScriptedTransport.register(host: host, steps: [
        .http(503, Data(#"{"detail":"down"}"#.utf8)),
        .http(200, activeAccount)
    ])
    defer { ScriptedTransport.remove(host: host) }
    let seen = FailureLog()
    let message = await DiagnosticsIsolation.shared.perform { () -> String in
        APIDiagnostics.record = { seen.append($0) }
        defer { APIDiagnostics.record = nil }
        do {
            _ = try await scriptedClient(host: host).accountStatus()
            return "503 should not be retried into success"
        } catch let error as QueepError {
            return error.localizedDescription
        } catch {
            return "Unexpected error \(error)"
        }
    }
    #expect(message == "down")
    #expect(script.count == 1)
    #expect(seen.items.count == 1)
    #expect(seen.items.first?.status == 503)
    #expect(seen.items.first?.transportCode == nil)
}

@Test func postTransportFailureStaysSingleAttempt() async {
    let host = "search-transport-\(UUID().uuidString.lowercased()).test"
    let script = ScriptedTransport.register(host: host, steps: [
        .fail(.timedOut), .http(200, Data(#"{"items":[],"has_pending":false}"#.utf8))
    ])
    defer { ScriptedTransport.remove(host: host) }
    let message = await DiagnosticsIsolation.shared.perform { () -> String in
        do {
            _ = try await scriptedClient(host: host).search("queep")
            return "POST should not retry a timeout"
        } catch QueepError.unavailable {
            return ""
        } catch {
            return "Unexpected error \(error)"
        }
    }
    #expect(message.isEmpty)
    #expect(script.count == 1)
}

private final class FailureLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [APIDiagnostics.Failure] = []
    var items: [APIDiagnostics.Failure] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }
    func append(_ failure: APIDiagnostics.Failure) {
        lock.lock()
        stored.append(failure)
        lock.unlock()
    }
}
