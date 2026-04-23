import Foundation

enum APIError: Error {
    case badURL
    case badStatus(Int)
    case decoding(Error)
    case transport(Error)
}

struct QuietPlayAPI {
    let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        let d = JSONDecoder()
        let fracFormatter = ISO8601DateFormatter()
        fracFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plainFormatter = ISO8601DateFormatter()
        plainFormatter.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = fracFormatter.date(from: raw) ?? plainFormatter.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "invalid ISO8601 date: \(raw)")
        }
        self.decoder = d
    }

    static func fromBundle() -> QuietPlayAPI {
        let raw = Bundle.main.object(forInfoDictionaryKey: "QuietPlayAPIBaseURL") as? String
        guard let raw, let url = URL(string: raw) else {
            fatalError("QuietPlayAPIBaseURL missing or invalid in Info.plist")
        }
        return QuietPlayAPI(baseURL: url)
    }

    /// URL of the admin UI — used by the first-launch QR code.
    var adminURL: URL {
        baseURL.appendingPathComponent("admin")
    }

    func profiles() async throws -> [Profile] {
        try await get("/profiles")
    }

    func library(profileID: UUID) async throws -> [LibraryChannel] {
        try await get("/library?profile=\(profileID.uuidString.lowercased())")
    }

    func resolve(videoID: String) async throws -> ResolveResponse {
        try await get("/resolve/\(videoID)")
    }

    /// Batched telemetry push. Silent on failure — caller decides
    /// whether to restore the snapshot to the queue.
    func postWatchEvents(profileID: UUID, events: [String: Int]) async throws {
        let payload: [String: Any] = [
            "profile_id": profileID.uuidString.lowercased(),
            "events": events.map { (id, seconds) -> [String: Any] in
                ["youtube_video_id": id, "seconds": seconds]
            }
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        guard let url = URL(string: "/events/watch", relativeTo: baseURL) else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.badStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
    }

    private func get<T: Decodable>(_ path: String) async throws -> T {
        guard let url = URL(string: path, relativeTo: baseURL) else { throw APIError.badURL }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.badStatus(-1) }
        guard (200..<300).contains(http.statusCode) else { throw APIError.badStatus(http.statusCode) }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}
