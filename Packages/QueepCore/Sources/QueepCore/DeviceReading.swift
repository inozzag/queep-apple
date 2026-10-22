import Foundation

/// What the device read before an upload: Vision OCR, Speech transcript and pixel colors.
/// The API uses it instead of paid transcription and as extra evidence for interpretation.
public struct DeviceReading: Codable, Sendable, Equatable {
    public struct Segment: Codable, Sendable, Equatable {
        public let start: Double
        public let text: String

        public init(start: Double, text: String) {
            self.start = start
            self.text = text
        }
    }

    public var screenText: String
    public var transcript: String
    public var segments: [Segment]
    public var colors: [String]
    public var engine: String

    public init(screenText: String = "", transcript: String = "", segments: [Segment] = [],
                colors: [String] = [], engine: String = "") {
        self.screenText = screenText
        self.transcript = transcript
        self.segments = segments
        self.colors = colors
        self.engine = engine
    }

    public var isEmpty: Bool {
        screenText.isEmpty && transcript.isEmpty && colors.isEmpty
    }

    /// Trimmed to the API limits so a long screenshot or recording never fails the upload.
    public var bounded: DeviceReading {
        DeviceReading(screenText: String(screenText.prefix(8000)),
                      transcript: String(transcript.prefix(18000)),
                      segments: segments.prefix(600).map {
                          Segment(start: min(301, max(0, $0.start)), text: String($0.text.prefix(500)))
                      },
                      colors: Array(colors.prefix(8)),
                      engine: String(engine.prefix(40)))
    }

    enum CodingKeys: String, CodingKey {
        case screenText = "screen_text"
        case transcript, segments, colors, engine
    }
}

/// Reads an image or media file on the device. Returns nil when nothing useful was read.
public protocol DeviceReader: Sendable {
    func read(image: Data) async -> DeviceReading?
    func read(media: URL) async -> DeviceReading?
}

/// Keeps the search candidates that do not contradict the query, checked on the device.
public protocol SearchChecker: Sendable {
    func kept(query: String, candidates: [Reference]) async throws -> [String]
}

public extension SearchChecker {
    /// The server's head size. The rest of the ranked list is returned unchanged.
    static var headLimit: Int { 6 }

    /// Filters the head; any failure returns the ranked list as the server sent it.
    func filter(query: String, items: [Reference]) async -> [Reference] {
        let head = Array(items.prefix(Self.headLimit))
        guard !head.isEmpty, let ids = try? await kept(query: query, candidates: head) else { return items }
        let keep = Set(ids)
        return head.filter { keep.contains($0.id) } + items.dropFirst(head.count)
    }
}
