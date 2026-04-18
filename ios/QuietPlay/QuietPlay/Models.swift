import Foundation

struct Profile: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let position: Int
}

struct PlayableVideo: Codable, Identifiable, Hashable {
    var id: String { youtubeVideoId }
    let youtubeVideoId: String
    let title: String
    let thumbnailUrl: String?
    let publishedAt: Date
    let channelId: UUID
    let channelTitle: String

    enum CodingKeys: String, CodingKey {
        case youtubeVideoId = "youtube_video_id"
        case title
        case thumbnailUrl = "thumbnail_url"
        case publishedAt = "published_at"
        case channelId = "channel_id"
        case channelTitle = "channel_title"
    }
}

struct LibraryVideo: Codable, Identifiable, Hashable {
    var id: String { youtubeVideoId }
    let channelId: UUID
    let youtubeVideoId: String
    let title: String
    let thumbnailUrl: String?
    let publishedAt: Date

    enum CodingKeys: String, CodingKey {
        case channelId = "channel_id"
        case youtubeVideoId = "youtube_video_id"
        case title
        case thumbnailUrl = "thumbnail_url"
        case publishedAt = "published_at"
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

    enum CodingKeys: String, CodingKey {
        case status
        case streamUrl = "streamUrl"
        case expiresAt = "expiresAt"
        case error
    }

    var isOK: Bool { status == "ok" && streamUrl != nil }
}
