import Foundation

/// Per-device "starred" video IDs, mirrored into memory for O(1) reads.
/// Stars are fully client-side — a single-family setup doesn't justify
/// syncing them to the server, and keeping it on-device means the kid's
/// list doesn't mix with a parent's.
enum FavoritesStore {
    private static let key = "com.quietplay.favorites.v1"
    private static var cache: Set<String> = loadFromDefaults()

    private static func loadFromDefaults() -> Set<String> {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let arr = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Set(arr)
    }

    private static func persist() {
        guard let data = try? JSONEncoder().encode(Array(cache)) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func all() -> Set<String> { cache }

    static func isFavorite(_ videoID: String) -> Bool {
        cache.contains(videoID)
    }

    /// Flip starred state and persist. Returns the new value so the UI can
    /// drive its animation from it.
    @discardableResult
    static func toggle(_ videoID: String) -> Bool {
        if cache.contains(videoID) {
            cache.remove(videoID)
            persist()
            return false
        } else {
            cache.insert(videoID)
            persist()
            return true
        }
    }
}
