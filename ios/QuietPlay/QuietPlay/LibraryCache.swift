import Foundation

/// Disk-backed cache of the `/library` response, keyed by profile ID.
/// On cold launch we render the cached copy instantly and refetch in
/// the background; if the fetch succeeds, the cache is updated and the
/// UI swaps in the fresh data. Turns a ~600 ms white-screen on launch
/// into a zero-frame load.
enum LibraryCache {
    private static let fm = FileManager.default

    private static var directory: URL? {
        guard
            let root = try? fm.url(
                for: .cachesDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        else { return nil }
        let dir = root.appendingPathComponent("QuietPlayLibrary", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func url(for profileID: UUID) -> URL? {
        directory?.appendingPathComponent("\(profileID.uuidString).json")
    }

    static func load(profileID: UUID) -> [LibraryChannel]? {
        guard let u = url(for: profileID), let data = try? Data(contentsOf: u) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode([LibraryChannel].self, from: data)
    }

    static func save(_ channels: [LibraryChannel], profileID: UUID) {
        guard let u = url(for: profileID) else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(channels) else { return }
        // Atomic write so a half-flushed file never gets read back on
        // next launch.
        try? data.write(to: u, options: .atomic)
    }
}
