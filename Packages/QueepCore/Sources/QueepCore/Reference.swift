import Foundation

public struct Reference: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let title: String
    public let text: String
    public let url: String?
    public let status: String
    public let revision: Int
    public let createdAt: Date
    public let updatedAt: Date
    public let analysis: Interpretation?
    public let image: ImageInfo?

    public var displayTitle: String {
        if !title.isEmpty { return title }
        if kind == "image" { return "Imagem" }
        if kind == "link", let url, let host = URL(string: url)?.host { return host }
        return String(text.split(separator: "\n").first.map(String.init)?.prefix(100) ?? "Nota")
    }

    public var kindLabel: String { kind == "image" ? "Imagem" : kind == "link" ? "Link" : "Nota" }
    public var kindSymbol: String { kind == "image" ? "photo" : kind == "link" ? "link" : "note.text" }

    public var statusLabel: String {
        switch status {
        case "queued": "Salvo · aguardando análise"
        case "processing": "Analisando"
        case "ready": analysis?.coverage == "partial" ? "Análise parcial" : "Pronto"
        case "error": "Falha na análise"
        default: "Salvo"
        }
    }
}

public struct ImageInfo: Codable, Sendable, Equatable {
    public let sha256: String
    public let contentType: String
    public let width: Int
    public let height: Int
    public let byteCount: Int
}

public struct Interpretation: Codable, Sendable, Equatable {
    public let summary: String
    public let topics: [String]
    public let entities: [String]
    public let usefulness: [String]
    public let appearance: [String]
    public let coverage: String
    public let limitations: [String]
}

public struct LibraryPage: Codable, Sendable {
    public let items: [Reference]
    public let nextCursor: String?
}

public struct SearchResults: Codable, Sendable {
    public let items: [Reference]
    public let hasPending: Bool
    public let candidateLimit: Int
}

public struct Capture: Encodable, Sendable {
    public let kind: String
    public let title: String
    public let text: String
    public let url: String?

    public init(kind: String, title: String, text: String, url: String? = nil) {
        self.kind = kind
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        self.url = url?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var isValid: Bool {
        guard title.count <= 200, text.count <= 30_000 else { return false }
        if kind == "note" { return !text.isEmpty && url == nil }
        guard kind == "link", let raw = url, raw.count <= 4096,
              let value = URLComponents(string: raw),
              ["http", "https"].contains(value.scheme?.lowercased() ?? ""),
              let host = value.host, !host.isEmpty,
              value.user == nil, value.password == nil else { return false }
        return true
    }
}

public enum QueepError: LocalizedError {
    case invalidCapture, unauthorized, conflict, unavailable, server(String)
    public var errorDescription: String? {
        switch self {
        case .invalidCapture: "Preencha uma nota ou um link HTTP válido."
        case .unauthorized: "Sua sessão expirou. Entre novamente."
        case .conflict: "Essa referência mudou em outro dispositivo. Atualize antes de salvar."
        case .unavailable: "Não foi possível conectar. Tente novamente."
        case .server(let message): message
        }
    }
}
