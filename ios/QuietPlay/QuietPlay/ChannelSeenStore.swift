import Foundation

enum ChannelSeenStore {
    private static let key = "com.quietplay.channelLastSeen.v1"

    static func load() -> [String: Date] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: Date] ?? [:]
    }

    static func save(_ map: [String: Date]) {
        UserDefaults.standard.set(map, forKey: key)
    }
}
