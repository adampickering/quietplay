import Foundation

/// A picker candidate pairs each "up next" card's video with the real
/// channel it belongs to so that selecting a cross-library card can
/// switch the playback queue transparently.
struct PickerCandidate: Identifiable, Hashable {
    var id: String { video.youtubeVideoId }
    let video: LibraryVideo
    let channel: LibraryChannel
}

/// Pure, testable assembly of the "up next" picker. Given the current
/// channel context and the full library slate, returns the 3 same-channel
/// unwatched candidates — or, if the channel is exhausted, the 3 newest-
/// unwatched candidates from other channels. Never includes the currently-
/// playing video.
enum PickerBuilder {
    struct Result: Equatable {
        let title: String
        let candidates: [PickerCandidate]
    }

    static func build(
        currentChannel: LibraryChannel,
        channelVideos: [LibraryVideo],
        channelIndex: Int,
        libraryChannels: [LibraryChannel],
        isWatched: (String) -> Bool
    ) -> Result {
        // Same-channel unwatched videos older than the current position.
        let tail = channelVideos.dropFirst(channelIndex + 1)
        let sameChannel = tail
            .filter { !isWatched($0.youtubeVideoId) }
            .prefix(3)
            .map { PickerCandidate(video: $0, channel: currentChannel) }

        if !sameChannel.isEmpty {
            return Result(title: "Up next", candidates: Array(sameChannel))
        }

        // Channel exhausted → 3 newest-unwatched from other channels.
        let other = libraryChannels
            .filter { $0.id != currentChannel.id }
            .flatMap { ch in ch.videos.map { PickerCandidate(video: $0, channel: ch) } }
            .filter { !isWatched($0.video.youtubeVideoId) }
            .sorted { $0.video.publishedAt > $1.video.publishedAt }
            .prefix(3)

        let candidates = Array(other)
        let title: String
        if candidates.isEmpty {
            title = "You've watched everything new"
        } else {
            title = "You've seen all of \(currentChannel.title) — try something else"
        }
        return Result(title: title, candidates: candidates)
    }
}
