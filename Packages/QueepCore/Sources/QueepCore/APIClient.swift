import Foundation

public struct APIClient: Sendable {
    public let baseURL: URL
    private let session: URLSession
    private let token: @Sendable () async throws -> String

    public init(baseURL: URL, session: URLSession = .shared,
                token: @escaping @Sendable () async throws -> String) {
        self.baseURL = baseURL
        self.session = session
        self.token = token
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

    public func list(cursor: String? = nil) async throws -> LibraryPage {
        let query = cursor.map { [URLQueryItem(name: "cursor", value: $0)] } ?? []
        return try await decoded("v1/references", query: query)
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

    public func delete(_ reference: Reference) async throws {
        _ = try await request("v1/references/\(reference.id)", method: "DELETE",
                              query: [.init(name: "revision", value: String(reference.revision))])
    }

    private func decoded<T: Decodable>(_ path: String, method: String = "GET",
                                       query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        let data = try await request(path, method: method, query: query, body: body)
        return try Self.decoder().decode(T.self, from: data)
    }

    private func request(_ path: String, method: String, query: [URLQueryItem] = [],
                         body: Data? = nil) async throws -> Data {
        var components = URLComponents(url: baseURL.appendingPathComponent(path),
                                       resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 20
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(for: request) }
        catch is CancellationError { throw CancellationError() }
        catch { throw QueepError.unavailable }
        guard let http = response as? HTTPURLResponse else { throw QueepError.unavailable }
        switch http.statusCode {
        case 200..<300: return data
        case 401: throw QueepError.unauthorized
        case 409: throw QueepError.conflict
        case 422: throw QueepError.invalidCapture
        case 404: throw QueepError.server("Essa referência não está mais disponível.")
        default: throw QueepError.unavailable
        }
    }
}
