import Foundation

struct PlaybackProgress: Codable, Equatable {
    let position: Double
    let duration: Double
    let updatedAt: Date
}

/// Per-video playback position, persisted in UserDefaults so "resume where
/// you left off" survives app restarts. An in-memory mirror keeps UI reads
/// (progress bars on thumbnails, Continue Watching ordering) O(1).
enum PlaybackProgressStore {
    private static let key = "com.quietplay.playbackProgress.v1"
    /// Don't save if the kid only played a tiny snippet — avoids polluting
    /// Continue Watching with accidental taps.
    private static let minSaveSeconds: Double = 5
    /// At or above this fraction, the video is effectively finished. Drop
    /// the progress entry so Continue Watching stays focused on actually
    /// resumable videos.
    private static let completionFraction: Double = 0.95

    private static var cache: [String: PlaybackProgress] = loadFromDefaults()

    private static func loadFromDefaults() -> [String: PlaybackProgress] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let dict = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data)
        else { return [:] }
        return dict
    }

    private static func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func all() -> [String: PlaybackProgress] { cache }

    static func progress(for videoID: String) -> PlaybackProgress? {
        cache[videoID]
    }

    /// Stored fraction (0…1), nil if there's no progress yet or duration
    /// wasn't captured. Used for the thin progress bar under each
    /// thumbnail in the library grid.
    static func fraction(for videoID: String) -> Double? {
        guard let p = cache[videoID], p.duration > 0 else { return nil }
        return min(1, max(0, p.position / p.duration))
    }

    /// Seconds to resume from, nil if there's nothing worth resuming to
    /// (unstarted, or so close to the end we'd just want to restart).
    static func resumePosition(for videoID: String) -> Double? {
        guard let p = cache[videoID], p.duration > 0 else { return nil }
        let frac = p.position / p.duration
        if frac >= completionFraction { return nil }
        if p.position < minSaveSeconds { return nil }
        return p.position
    }

    static func save(videoID: String, position: Double, duration: Double) {
        guard position.isFinite, duration.isFinite, duration > 0 else { return }
        guard position >= minSaveSeconds else { return }
        if position / duration >= completionFraction {
            clear(videoID: videoID)
            return
        }
        cache[videoID] = PlaybackProgress(
            position: position,
            duration: duration,
            updatedAt: Date()
        )
        persist()
    }

    static func clear(videoID: String) {
        guard cache[videoID] != nil else { return }
        cache.removeValue(forKey: videoID)
        persist()
    }

    /// Video IDs with saved progress, most-recently-updated first. Used
    /// to populate the Continue Watching virtual channel.
    static func inProgressOrdered() -> [String] {
        cache
            .sorted { $0.value.updatedAt > $1.value.updatedAt }
            .map { $0.key }
    }
}
