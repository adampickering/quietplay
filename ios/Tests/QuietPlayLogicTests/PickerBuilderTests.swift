import XCTest
@testable import QuietPlayLogic

final class PickerBuilderTests: XCTestCase {

    // MARK: Helpers

    private func makeVideo(_ id: String, publishedAt: Date = Date()) -> LibraryVideo {
        let json = """
        {
          "channel_id": "\(UUID().uuidString)",
          "youtube_video_id": "\(id)",
          "title": "Video \(id)",
          "thumbnail_url": null,
          "published_at": "\(ISO8601DateFormatter().string(from: publishedAt))"
        }
        """
        let decoder = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            return fmt.date(from: s) ?? Date()
        }
        return try! decoder.decode(LibraryVideo.self, from: Data(json.utf8))
    }

    private func makeChannel(title: String, videos: [LibraryVideo]) -> LibraryChannel {
        // LibraryChannel has synthesizable init through its fields — we
        // build via JSON round-trip to avoid depending on its memberwise
        // availability across target boundaries.
        let vidArr = videos.map { v -> [String: Any] in
            let iso = ISO8601DateFormatter().string(from: v.publishedAt)
            return [
                "channel_id": v.channelId.uuidString,
                "youtube_video_id": v.youtubeVideoId,
                "title": v.title,
                "thumbnail_url": NSNull(),
                "published_at": iso,
            ]
        }
        let dict: [String: Any] = [
            "id": UUID().uuidString,
            "title": title,
            "thumbnail_url": NSNull(),
            "videos": vidArr,
        ]
        let data = try! JSONSerialization.data(withJSONObject: dict)
        let decoder = JSONDecoder()
        let fmt = ISO8601DateFormatter()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            return fmt.date(from: s) ?? Date()
        }
        return try! decoder.decode(LibraryChannel.self, from: data)
    }

    // MARK: Same-channel path

    func testReturnsNext3SameChannelUnwatchedWhenAvailable() throws {
        let now = Date()
        let videos = (0..<5).map { i in
            makeVideo("v\(i)", publishedAt: now.addingTimeInterval(Double(-i) * 60))
        }
        let channel = makeChannel(title: "C", videos: videos)

        let result = PickerBuilder.build(
            currentChannel: channel,
            channelVideos: videos,
            channelIndex: 0,
            libraryChannels: [channel],
            isWatched: { _ in false }
        )

        XCTAssertEqual(result.title, "Up next")
        XCTAssertEqual(result.candidates.count, 3)
        XCTAssertEqual(result.candidates.map(\.video.youtubeVideoId), ["v1", "v2", "v3"])
    }

    func testSkipsAlreadyWatchedSameChannelVideos() throws {
        let now = Date()
        let videos = (0..<6).map { i in
            makeVideo("v\(i)", publishedAt: now.addingTimeInterval(Double(-i) * 60))
        }
        let channel = makeChannel(title: "C", videos: videos)

        // Current is v0; v1 and v2 already watched.
        let watched: Set<String> = ["v1", "v2"]

        let result = PickerBuilder.build(
            currentChannel: channel,
            channelVideos: videos,
            channelIndex: 0,
            libraryChannels: [channel],
            isWatched: { watched.contains($0) }
        )

        XCTAssertEqual(result.title, "Up next")
        XCTAssertEqual(result.candidates.map(\.video.youtubeVideoId), ["v3", "v4", "v5"])
    }

    // MARK: Cross-library fallback

    func testFallsBackToOtherChannelsWhenCurrentChannelExhausted() throws {
        let now = Date()
        let curVideos = [makeVideo("cur-0", publishedAt: now)]
        let cur = makeChannel(title: "Current", videos: curVideos)

        let other = makeChannel(title: "Other", videos: [
            makeVideo("other-0", publishedAt: now.addingTimeInterval(-10)),
            makeVideo("other-1", publishedAt: now.addingTimeInterval(-20)),
            makeVideo("other-2", publishedAt: now.addingTimeInterval(-30)),
        ])

        let result = PickerBuilder.build(
            currentChannel: cur,
            channelVideos: curVideos,
            channelIndex: 0,
            libraryChannels: [cur, other],
            isWatched: { _ in false }
        )

        XCTAssertTrue(result.title.contains("Current"))
        XCTAssertTrue(result.title.contains("try something else"))
        XCTAssertEqual(result.candidates.map(\.video.youtubeVideoId), ["other-0", "other-1", "other-2"])
        // All cross-library candidates should be tagged with the other channel.
        XCTAssertTrue(result.candidates.allSatisfy { $0.channel.id == other.id })
    }

    func testReturnsEverythingWatchedMessageWhenAllConsumed() throws {
        let now = Date()
        let curVideos = [makeVideo("cur-0", publishedAt: now)]
        let cur = makeChannel(title: "Current", videos: curVideos)
        let other = makeChannel(title: "Other", videos: [
            makeVideo("other-0", publishedAt: now.addingTimeInterval(-10)),
        ])

        // Everything is watched.
        let watched: Set<String> = ["cur-0", "other-0"]

        let result = PickerBuilder.build(
            currentChannel: cur,
            channelVideos: curVideos,
            channelIndex: 0,
            libraryChannels: [cur, other],
            isWatched: { watched.contains($0) }
        )

        XCTAssertEqual(result.title, "You've watched everything new")
        XCTAssertEqual(result.candidates.count, 0)
    }

    // MARK: Edge cases

    func testLastVideoInChannelTriggersFallbackToOtherChannels() throws {
        let now = Date()
        let curVideos = [
            makeVideo("cur-0", publishedAt: now),
            makeVideo("cur-1", publishedAt: now.addingTimeInterval(-10)),
        ]
        let cur = makeChannel(title: "Current", videos: curVideos)
        let other = makeChannel(title: "Other", videos: [
            makeVideo("other-0", publishedAt: now.addingTimeInterval(-20)),
        ])

        // Kid just finished the LAST video in Current (index 1, no tail).
        let result = PickerBuilder.build(
            currentChannel: cur,
            channelVideos: curVideos,
            channelIndex: 1,
            libraryChannels: [cur, other],
            isWatched: { _ in false }
        )

        XCTAssertEqual(result.candidates.map(\.video.youtubeVideoId), ["other-0"])
    }

    func testDoesNotIncludeCurrentChannelVideosInFallback() throws {
        let now = Date()
        let curVideos = [makeVideo("cur-0", publishedAt: now)]
        let cur = makeChannel(title: "Current", videos: curVideos)

        // Library has only the current channel, everything watched.
        let watched: Set<String> = ["cur-0"]

        let result = PickerBuilder.build(
            currentChannel: cur,
            channelVideos: curVideos,
            channelIndex: 0,
            libraryChannels: [cur],
            isWatched: { watched.contains($0) }
        )

        XCTAssertEqual(result.candidates.count, 0)
    }
}
