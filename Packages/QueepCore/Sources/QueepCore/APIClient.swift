import Foundation

public struct APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let token: @Sendable () async throws -> String
    private let onUnauthorized: @Sendable () async -> Void

    public init(baseURL: URL, session: URLSession = .shared,
                onUnauthorized: @escaping @Sendable () async -> Void = {},
                token: @escaping @Sendable () async throws -> String) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
        self.onUnauthorized = onUnauthorized
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            let format = ISO8601DateFormatter()
            format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = format.date(from: string) { return date }
            format.formatOptions = [.withInternetDateTime]
            if let date = format.date(from: string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                   debugDescription: "Invalid server date"))
        }
        return decoder
    }

    public func subscriptionAccess(refresh: Bool = false) async throws -> SubscriptionAccess {
        try await decoded(refresh ? "v1/billing/sync" : "v1/billing/access",
                       method: refresh ? "POST" : "GET")
    }

    public func accountStatus() async throws -> AccountStatus {
        try await decoded("v1/account")
    }

    public func usage() async throws -> Usage {
        try await decoded("v1/usage")
    }

    public func changeAccountDeletion(version: Int, operationID: UUID,
                                      immediate: Bool = false, cancel: Bool = false) async throws -> AccountStatus {
        let body: [String: Any] = ["version": version,
                                   "operation_id": operationID.uuidString.lowercased(),
                                   "immediate": immediate]
        return try await decoded(cancel ? "v1/account/deletion/cancel" : "v1/account/deletion",
                                 method: "POST", body: JSONSerialization.data(withJSONObject: body))
    }

    public func list(cursor: String? = nil) async throws -> LibraryPage {
        let query = cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
        return try await decoded("v1/references", query: query)
    }

    public func get(id: String) async throws -> Reference {
        try await decoded("v1/references/\(id)")
    }

    public func search(_ query: String) async throws -> SearchResults {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...500).contains(term.count) else {
            throw QueepError.server("Escreva uma busca de 2 a 500 caracteres.")
        }
        let data = try await request("v1/search", method: "POST",
                                     body: JSONEncoder().encode(["query": term]), timeout: 90)
        return try Self.decoder().decode(SearchResults.self, from: data)
    }

    public func retryAnalysis(_ reference: Reference) async throws -> Reference {
        try await decoded("v1/references/\(reference.id)/retry", method: "POST",
                          body: JSONEncoder().encode(["revision": reference.revision]))
    }

    public func create(id: UUID, capture: Capture) async throws -> Reference {
        guard capture.isValid else { throw QueepError.invalidCapture }
        return try await decoded("v1/references/\(id.uuidString.lowercased())", method: "PUT",
                                 body: JSONEncoder().encode(capture))
    }

    public func edit(_ reference: Reference, capture: Capture, mutationID: UUID) async throws -> Reference {
        guard capture.isValid else { throw QueepError.invalidCapture }
        let data = try JSONEncoder().encode(capture)
        var object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        object["revision"] = reference.revision
        object["mutation_id"] = mutationID.uuidString.lowercased()
        return try await decoded("v1/references/\(reference.id)", method: "PATCH",
                                 body: JSONSerialization.data(withJSONObject: object))
    }

    /// Changes the title and notes of an uploaded image or media file; the file itself stays.
    public func editMetadata(_ reference: Reference, title: String, text: String,
                             mutationID: UUID) async throws -> Reference {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["image", "audio", "video"].contains(reference.kind),
              cleanTitle.count <= 200, text.count <= 30_000 else { throw QueepError.invalidCapture }
        let object: [String: Any] = ["kind": reference.kind, "title": cleanTitle, "text": text,
                                     "revision": reference.revision,
                                     "mutation_id": mutationID.uuidString.lowercased()]
        do {
            return try await decoded("v1/references/\(reference.id)", method: "PATCH",
                                     body: JSONSerialization.data(withJSONObject: object))
        } catch QueepError.invalidCapture {
            throw QueepError.server("Este servidor ainda não aceita editar título e anotações de imagens e mídias.")
        }
    }

    public func delete(_ reference: Reference) async throws {
        _ = try await request("v1/references/\(reference.id)", method: "DELETE",
                              query: [.init(name: "revision", value: String(reference.revision))])
    }

    public func uploadImage(id: UUID, title: String, data: Data) async throws -> Reference {
        guard !data.isEmpty, data.count <= 12 * 1024 * 1024, title.count <= 200 else {
            throw QueepError.server("Escolha uma imagem de até 12 MB e um título de até 200 caracteres.")
        }
        let result = try await request("v1/references/\(id.uuidString.lowercased())/image", method: "PUT",
                                       query: [.init(name: "title", value: title)], body: data,
                                       contentType: "application/octet-stream", timeout: 120)
        return try Self.decoder().decode(Reference.self, from: result)
    }

    public func imageData(_ reference: Reference, thumbnail: Bool = false) async throws -> Data {
        try await request("v1/references/\(reference.id)/image", method: "GET",
                          query: [.init(name: "thumbnail", value: thumbnail ? "true" : "false")],
                          timeout: 60)
    }

    public func uploadMedia(id: UUID, title: String, file: URL) async throws -> Reference {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard file.isFileURL, size > 0, size <= 25 * 1024 * 1024, title.count <= 200 else {
            throw QueepError.server("Escolha um áudio ou vídeo de até 25 MB.")
        }
        let data = try await request("v1/references/\(id.uuidString.lowercased())/media", method: "PUT",
                                     query: [.init(name: "title", value: title)],
                                     contentType: "application/octet-stream", timeout: 150, file: file)
        return try Self.decoder().decode(Reference.self, from: data)
    }

    public func mediaData(_ reference: Reference, thumbnail: Bool = false) async throws -> Data {
        try await request("v1/references/\(reference.id)/media", method: "GET",
                          query: [.init(name: "thumbnail", value: thumbnail ? "true" : "false")], timeout: 90)
    }

    private func decoded<T: Decodable>(_ path: String, method: String = "GET",
                                       query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        let data = try await request(path, method: method, query: query, body: body)
        return try Self.decoder().decode(T.self, from: data)
    }

    private func request(_ path: String, method: String, query: [URLQueryItem] = [],
                         body: Data? = nil, contentType: String = "application/json",
                         timeout: TimeInterval = 20, file: URL? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = timeout
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        let data: Data
        let response: URLResponse
        do {
            if let file { (data, response) = try await session.upload(for: request, fromFile: file) }
            else { (data, response) = try await session.data(for: request) }
        }
        catch is CancellationError { throw CancellationError() }
        catch {
            if Task.isCancelled { throw CancellationError() }
            throw QueepError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw QueepError.unavailable }
        switch http.statusCode {
        case 200..<300: return data
        case 401:
            await onUnauthorized()
            throw QueepError.unauthorized
        case 409: throw QueepError.conflict
        case 422: throw QueepError.invalidCapture
        case 404: throw QueepError.server("Essa referência não está mais disponível.")
        case 402, 403, 413, 415, 429, 503:
            struct Failure: Decodable { let detail: String }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw QueepError.server(failure?.detail ?? "Serviço temporariamente indisponível. Tente novamente.")
        default: throw QueepError.unavailable
        }
    }
}
