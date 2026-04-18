import Foundation

/// Tracks which YouTube videos the current device has watched (reached ~80%
/// or hit end-of-stream). Used to filter the "up next" picker so it
/// doesn't surface a video the kid just finished.
///
/// An in-memory set shadows UserDefaults so the hot path (isWatched()
/// called in tap handlers and inside PickerBuilder) is just a Set lookup
/// rather than deserializing the whole array on every call. Writes keep
/// both in sync.
enum WatchedVideoStore {
    private static let key = "com.quietplay.watchedVideos.v1"

    // Accessed from MainActor in practice (all tap handlers / UI paths).
    nonisolated(unsafe) private static var cache: Set<String>?

    static func load() -> Set<String> {
        if let cache { return cache }
        let arr = UserDefaults.standard.stringArray(forKey: key) ?? []
        let set = Set(arr)
        cache = set
        return set
    }

    static func isWatched(_ id: String) -> Bool {
        load().contains(id)
    }

    static func markWatched(_ id: String) {
        var set = load()
        guard !set.contains(id) else { return }
        set.insert(id)
        cache = set
        UserDefaults.standard.set(Array(set), forKey: key)
    }
}
