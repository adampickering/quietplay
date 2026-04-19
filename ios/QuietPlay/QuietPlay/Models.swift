import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let position: Int
}

struct LibraryVideo: Codable, Identifiable, Hashable {
    var id: String { youtubeVideoId }
    let channelId: UUID
    let youtubeVideoId: String
    let title: String
    let thumbnailUrl: String?
    let publishedAt: Date
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case youtubeVideoId = "youtube_video_id"
        case title
        case thumbnailUrl = "thumbnail_url"
        case publishedAt = "published_at"
        case durationSeconds = "duration_seconds"
    }
}

struct LibraryChannel: Codable, Identifiable, Hashable {
    let id: UUID
    let title: String
    let thumbnailUrl: String?
    let videos: [LibraryVideo]

    enum CodingKeys: String, CodingKey {
        case id, title
        case thumbnailUrl = "thumbnail_url"
        case videos
    }
}

struct ResolveResponse: Codable {
    let status: String
    let streamUrl: String?
    let expiresAt: Date?
    let error: String?

    var isOK: Bool { status == "ok" && streamUrl != nil }
}
