import Foundation

/// Warms the server's resolve cache while the kid is still navigating.
/// Two guardrails the first version got wrong:
///   * Long dwell (1500ms) — only tiles the kid actually pauses on get
///     fired, not every flyover.
///   * Single in-flight prefetch — if one is still running we drop the
///     next one. yt-dlp ~15–20s; firing more than one in that window
///     trips YouTube's per-IP rate limit and slows the kid's actual tap.
@MainActor
final class ResolvePrefetcher {
    private let dwellNanoseconds: UInt64 = 1_500_000_000
    private var debounceTask: Task<Void, Never>?
    private var inflightTask: Task<Void, Never>?
    private var resolved: Set<String> = []

    func onFocus(videoID: String, api: QuietPlayAPI) {
        if resolved.contains(videoID) { return }
        debounceTask?.cancel()
        debounceTask = Task { [weak self, dwellNanoseconds] in
            try? await Task.sleep(nanoseconds: dwellNanoseconds)
            if Task.isCancelled { return }
            guard let self else { return }
            if self.inflightTask != nil { return }
            self.inflightTask = Task { [weak self] in
                _ = try? await api.resolve(videoID: videoID)
                self?.resolved.insert(videoID)
                self?.inflightTask = nil
            }
        }
    }
}
