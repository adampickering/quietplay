import Foundation

/// Tracks which YouTube videos the current device has watched (reached ~80% or
/// hit end-of-stream). Used to filter the "up next" picker so it doesn't
/// surface a video the kid just finished.
enum WatchedVideoStore {
    private static let key = "com.quietplay.watchedVideos.v1"

    static func load() -> Set<String> {
        let arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        return Set(arr)
    }

    static func isWatched(_ id: String) -> Bool {
        load().contains(id)
    }

    static func markWatched(_ id: String) {
        var set = load()
        guard !set.contains(id) else { return }
        set.insert(id)
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}
