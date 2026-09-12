import Foundation
import XCTest

/// Disposable emulator identities only; never reuses the preview or cloud account.
struct DeletionFixture {
    let email: String
    let token: String
    let title: String
    let password = "queep-delete-only-123"

    static func make(seed: Bool = true) async throws -> DeletionFixture {
        let unique = UUID().uuidString.lowercased()
        let email = "delete-\(unique)@example.test"
        let (data, status) = try await send(
            "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=local",
            method: "POST", body: ["email": email, "password": "queep-delete-only-123", "returnSecureToken": true])
        XCTAssertEqual(status, 200)
        let result = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let token = try XCTUnwrap(result["idToken"] as? String)
        let fixture = DeletionFixture(email: email, token: token, title: "Excluir fixture \(unique)")
        if !seed { return fixture }
        let (_, saved) = try await send("http://127.0.0.1:8000/v1/references/\(unique)",
                                       method: "PUT", token: token,
                                       body: ["kind": "note", "title": fixture.title, "text": "Synthetic account deletion test."])
        XCTAssertEqual(saved, 200)
        return fixture
    }

    func delete(immediate: Bool = true) async throws -> Int {
        let (data, status) = try await Self.send("http://127.0.0.1:8000/v1/account", method: "GET", token: token)
        guard status == 200 else { return status }
        let account = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        return try await Self.send("http://127.0.0.1:8000/v1/account/deletion", method: "POST", token: token,
            body: ["version": account["version"]!, "operation_id": UUID().uuidString.lowercased(),
                   "immediate": immediate]).1
    }

    func libraryStatus() async throws -> Int {
        try await Self.send("http://127.0.0.1:8000/v1/references", method: "GET", token: token).1
    }

    func containsSavedNote(text: String) async throws -> Bool {
        let (data, status) = try await Self.send("http://127.0.0.1:8000/v1/references", method: "GET", token: token)
        guard status == 200 else { return false }
        let page = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let items = page?["items"] as? [[String: Any]] ?? []
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?["title"] as? String, title)
        XCTAssertEqual(items.first?["text"] as? String, text)
        return items.contains { $0["title"] as? String == title && $0["text"] as? String == text }
    }

    static func send(_ url: String, method: String, token: String? = nil,
                     body: [String: Any]? = nil) async throws -> (Data, Int) {
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body) }
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as! HTTPURLResponse).statusCode)
    }
}
