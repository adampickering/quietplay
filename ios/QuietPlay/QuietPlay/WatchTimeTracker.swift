import Foundation

/// Per-day accumulated watch seconds, persisted in UserDefaults. Used
/// by AppState to nag the kid with a "time for a break!" modal once
/// he crosses the two-hour line. Resets at midnight because the
/// storage key includes the local date.
enum WatchTimeTracker {
    private static let secondsPrefix = "com.quietplay.watchSeconds."
    private static let breakShownPrefix = "com.quietplay.breakShown."

    private static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func accumulate(seconds: Int) {
        let key = secondsPrefix + todayKey
        let prev = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(prev + seconds, forKey: key)
    }

    static func todaySeconds() -> Int {
        UserDefaults.standard.integer(forKey: secondsPrefix + todayKey)
    }

    static func hasShownBreakToday() -> Bool {
        UserDefaults.standard.bool(forKey: breakShownPrefix + todayKey)
    }

    static func markBreakShown() {
        UserDefaults.standard.set(true, forKey: breakShownPrefix + todayKey)
    }
}
