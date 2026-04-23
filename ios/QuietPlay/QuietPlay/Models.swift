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
    let category: String?
    let isRecommended: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, category
        case thumbnailUrl = "thumbnail_url"
        case videos
        case isRecommended = "is_recommended"
    }

    init(id: UUID, title: String, thumbnailUrl: String?, videos: [LibraryVideo], category: String?, isRecommended: Bool = false) {
        self.id = id
        self.title = title
        self.thumbnailUrl = thumbnailUrl
        self.videos = videos
        self.category = category
        self.isRecommended = isRecommended
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        videos = try c.decode([LibraryVideo].self, forKey: .videos)
        category = try c.decodeIfPresent(String.self, forKey: .category)
        isRecommended = try c.decodeIfPresent(Bool.self, forKey: .isRecommended) ?? false
    }
}

struct ResolveResponse: Codable {
    let status: String
    let streamUrl: String?
    let expiresAt: Date?
    let error: String?

    var isOK: Bool { status == "ok" && streamUrl != nil }
}
