import Foundation

/// Tiny buffer of watch seconds per YouTube video ID. `AppState` drops
/// 1s each tick during active playback; every ~60s the queue is
/// flushed to the server as a single `POST /events/watch`. Backed by
/// UserDefaults so a crash or a terminate doesn't lose the last few
/// minutes of data.
enum TelemetryQueue {
    private static let key = "com.quietplay.telemetryQueue.v1"

    /// Map of youtube_video_id → accumulated seconds pending flush.
    private static var cache: [String: Int] = loadFromDefaults()

    private static func loadFromDefaults() -> [String: Int] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let dict = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return dict
    }

    private static func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func enqueue(videoID: String, seconds: Int = 1) {
        cache[videoID, default: 0] += seconds
        persist()
    }

    /// Snapshot the current queue and clear it atomically. Caller is
    /// responsible for POSTing the snapshot; if the POST fails, the
    /// caller can re-enqueue via `restore`.
    static func drain() -> [String: Int] {
        let snapshot = cache
        cache.removeAll()
        persist()
        return snapshot
    }

    static func restore(_ snapshot: [String: Int]) {
        for (id, seconds) in snapshot {
            cache[id, default: 0] += seconds
        }
        persist()
    }

    static var pendingSeconds: Int {
        cache.values.reduce(0, +)
    }
}
