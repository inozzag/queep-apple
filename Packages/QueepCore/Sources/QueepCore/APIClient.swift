import Foundation

public struct APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let token: @Sendable () async throws -> String
    private let onPlanRequired: @Sendable (PlanRequirement) async -> Void
    private let onUnauthorized: @Sendable () async -> Void

    public init(baseURL: URL, session: URLSession = .shared,
                onUnauthorized: @escaping @Sendable () async -> Void = {},
                onPlanRequired: @escaping @Sendable (PlanRequirement) async -> Void = { _ in },
                token: @escaping @Sendable () async throws -> String) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
        self.onUnauthorized = onUnauthorized
        self.onPlanRequired = onPlanRequired
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
        let data = try await request(refresh ? "v1/billing/sync" : "v1/billing/access",
                                     method: refresh ? "POST" : "GET", timeout: 12)
        return try Self.decoder().decode(SubscriptionAccess.self, from: data)
    }

    public func requireMediaAccess() async throws {
        let access = try await subscriptionAccess()
        guard access.features.mediaAv else {
            let requirement = PlanRequirement.media(for: access.plan)
            await onPlanRequired(requirement)
            throw QueepError.planRequired(requirement)
        }
    }

    public func accountStatus() async throws -> AccountStatus {
        try await decoded("v1/account")
    }

    public func uploadAvatar(_ data: Data) async throws -> ImageInfo {
        guard !data.isEmpty, data.count <= 12 * 1024 * 1024 else {
            throw QueepError.server("Escolha uma foto de até 12 MB.")
        }
        let result = try await request("v1/account/avatar", method: "PUT", body: data,
                                       contentType: "application/octet-stream", timeout: 60)
        return try Self.decoder().decode(ImageInfo.self, from: result)
    }

    public func avatarData(thumbnail: Bool = true) async throws -> Data {
        try await request("v1/account/avatar", method: "GET",
                          query: [.init(name: "thumbnail", value: thumbnail ? "true" : "false")])
    }

    public func deleteAvatar() async throws {
        _ = try await request("v1/account/avatar", method: "DELETE")
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

    public func list(cursor: String? = nil, archived: Bool = false, spaceID: String? = nil) async throws -> LibraryPage {
        var query = [URLQueryItem(name: "archived", value: archived ? "only" : "exclude")]
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        if let spaceID { query.append(.init(name: "space_id", value: spaceID)) }
        return try await decoded("v1/references", query: query)
    }

    public func get(id: String) async throws -> Reference {
        try await decoded("v1/references/\(id)")
    }

    public func search(_ query: String, spaceID: String? = nil) async throws -> SearchResults {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...500).contains(term.count) else {
            throw QueepError.server("Escreva uma busca de 2 a 500 caracteres.")
        }
        var body = ["query": term]
        if let spaceID { body["space_id"] = spaceID }
        let data = try await request("v1/search", method: "POST",
                                     body: JSONEncoder().encode(body), timeout: 90)
        return try Self.decoder().decode(SearchResults.self, from: data)
    }

    public func retryAnalysis(_ reference: Reference) async throws -> Reference {
        try await decoded("v1/references/\(reference.id)/retry", method: "POST",
                          body: JSONEncoder().encode(["revision": reference.revision]))
    }

    public func setArchived(_ archived: Bool, reference: Reference) async throws -> Reference {
        try await decoded("v1/references/\(reference.id)", method: "PATCH",
                          body: JSONEncoder().encode(["archived": archived]))
    }

    public func setArchived(_ archived: Bool, ids: [String]) async throws -> [Reference] {
        guard (1...50).contains(ids.count) else {
            throw QueepError.server("Selecione de 1 a 50 referências.")
        }
        let body: [String: Any] = ["ids": ids, "archived": archived]
        let page: LibraryPage = try await decoded(
            "v1/references/batch-archive", method: "POST",
            body: JSONSerialization.data(withJSONObject: body)
        )
        return page.items
    }

    public func create(id: UUID, capture: Capture, spaceIDs: [String] = []) async throws -> Reference {
        guard capture.isValid else { throw QueepError.invalidCapture }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(capture)) as! [String: Any]
        if !spaceIDs.isEmpty { object["space_ids"] = spaceIDs }
        return try await decoded("v1/references/\(id.uuidString.lowercased())", method: "PUT",
                                 body: JSONSerialization.data(withJSONObject: object))
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

    /// Changes the title (and notes of an upload). Posts do not requeue analysis.
    public func editMetadata(_ reference: Reference, title: String, text: String,
                             mutationID: UUID) async throws -> Reference {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ["image", "audio", "video", "link"].contains(reference.kind),
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

    public func uploadImage(id: UUID, title: String, data: Data, spaceIDs: [String] = []) async throws -> Reference {
        guard !data.isEmpty, data.count <= 12 * 1024 * 1024, title.count <= 200 else {
            throw QueepError.server("Escolha uma imagem de até 12 MB e um título de até 200 caracteres.")
        }
        let result = try await request("v1/references/\(id.uuidString.lowercased())/image", method: "PUT",
                                       query: [.init(name: "title", value: title)] + spaceIDs.map { .init(name: "space_ids", value: $0) }, body: data,
                                       contentType: "application/octet-stream", timeout: 120)
        return try Self.decoder().decode(Reference.self, from: result)
    }

    public func imageData(_ reference: Reference, thumbnail: Bool = false, index: Int = 0,
                          role: String = "gallery") async throws -> Data {
        try await request("v1/references/\(reference.id)/image", method: "GET",
                          query: [.init(name: "thumbnail", value: thumbnail ? "true" : "false"),
                                  .init(name: "index", value: String(index)),
                                  .init(name: "role", value: role)],
                          timeout: 60)
    }

    public func uploadMedia(id: UUID, title: String, file: URL, spaceIDs: [String] = []) async throws -> Reference {
        let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard file.isFileURL, size > 0, size <= 25 * 1024 * 1024, title.count <= 200 else {
            throw QueepError.server("Escolha um áudio ou vídeo de até 25 MB.")
        }
        let data = try await request("v1/references/\(id.uuidString.lowercased())/media", method: "PUT",
                                     query: [.init(name: "title", value: title)] + spaceIDs.map { .init(name: "space_ids", value: $0) },
                                     contentType: "application/octet-stream", timeout: 150, file: file)
        return try Self.decoder().decode(Reference.self, from: data)
    }

    public func mediaData(_ reference: Reference, thumbnail: Bool = false) async throws -> Data {
        try await request("v1/references/\(reference.id)/media", method: "GET",
                          query: [.init(name: "thumbnail", value: thumbnail ? "true" : "false")], timeout: 90)
    }

    public func spaces() async throws -> [Space] {
        try await decoded("v1/spaces")
    }

    public func createSpace(name: String) async throws -> Space {
        try await saveSpace(name: name)
    }

    public func saveSpace(id: String? = nil, name: String? = nil, sortIndex: Int? = nil) async throws -> Space {
        var body: [String: Any] = [:]
        if let name {
            let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (1...40).contains(clean.unicodeScalars.count) else {
                throw QueepError.server("O nome do Space deve ter de 1 a 40 caracteres.")
            }
            body["name"] = clean
        }
        if let sortIndex { body["sort_index"] = sortIndex }
        do {
            return try await decoded(id.map { "v1/spaces/\($0)" } ?? "v1/spaces",
                                     method: id == nil ? "POST" : "PATCH",
                                     body: JSONSerialization.data(withJSONObject: body))
        } catch QueepError.conflict {
            throw QueepError.server("Já existe um Space com este nome.")
        }
    }

    public func deleteSpace(id: String) async throws {
        _ = try await request("v1/spaces/\(id)", method: "DELETE")
    }

    public func assignSpaces(referenceID: String, add: [String] = [], remove: [String] = []) async throws -> Reference {
        try await decoded("v1/references/\(referenceID)/spaces", method: "POST",
                          body: JSONEncoder().encode(["add": add, "remove": remove]))
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
            APIDiagnostics.report(method: method, path: path, status: nil)
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
        case 404:
            struct Failure: Decodable { let detail: String }
            if let failure = try? JSONDecoder().decode(Failure.self, from: data), !failure.detail.isEmpty {
                throw QueepError.server(failure.detail)
            }
            throw QueepError.server("Essa referência não está mais disponível.")
        case 402:
            struct Failure: Decodable { let detail: PlanRequirement }
            if let failure = try? Self.decoder().decode(Failure.self, from: data) {
                await onPlanRequired(failure.detail)
                throw QueepError.planRequired(failure.detail)
            }
            throw QueepError.server("Confira seu plano em Conta → Assinatura.")
        case 500..<600:
            APIDiagnostics.report(method: method, path: path, status: http.statusCode)
            struct Failure: Decodable { let detail: String }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw QueepError.server(failure?.detail ?? "Serviço temporariamente indisponível. Tente novamente.")
        case 403, 413, 415, 429:
            struct Failure: Decodable { let detail: String }
            let failure = try? JSONDecoder().decode(Failure.self, from: data)
            throw QueepError.server(failure?.detail ?? "Serviço temporariamente indisponível. Tente novamente.")
        default: throw QueepError.unavailable
        }
    }
}
