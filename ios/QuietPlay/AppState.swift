import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    enum Mode {
        case loading
        case playing
        case empty
        case fallback
        case degraded
    }

    let api: QuietPlayAPI
    let player: AVPlayer

    var mode: Mode = .loading
    var profiles: [Profile] = []
    var currentProfile: Profile?
    var playable: [PlayableVideo] = []
    var index: Int = 0
    var overlayVisible: Bool = false
    var isLoading: Bool = false

    @ObservationIgnored private var consecutiveSkips: Int = 0
    @ObservationIgnored private var failureTimestamps: [Date] = []
    @ObservationIgnored private var overlayTask: Task<Void, Never>?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?

    init(api: QuietPlayAPI = .fromBundle()) {
        self.api = api
        self.player = AVPlayer()
        self.player.actionAtItemEnd = .none
        self.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advance()
            }
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    var currentVideo: PlayableVideo? {
        guard index >= 0, index < playable.count else { return nil }
        return playable[index]
    }

    // MARK: Bootstrap

    func bootstrap() async {
        mode = .loading
        do {
            let list = try await api.profiles()
            profiles = list.sorted { $0.position < $1.position }
            guard let first = profiles.first else {
                mode = .empty
                return
            }
            await switchProfile(first)
        } catch {
            mode = .degraded
        }
    }

    func switchProfile(_ profile: Profile) async {
        currentProfile = profile
        consecutiveSkips = 0
        failureTimestamps.removeAll()
        index = 0
        do {
            playable = try await api.playable(profileID: profile.id)
        } catch {
            playable = []
        }
        if playable.isEmpty {
            player.replaceCurrentItem(with: nil)
            mode = .empty
            return
        }
        start(at: 0)
    }

    // MARK: Navigation

    func advance() { start(at: index + 1) }
    func retreat() { start(at: index - 1) }

    func seed(toVideoID videoID: String) {
        if let i = playable.firstIndex(where: { $0.youtubeVideoId == videoID }) {
            start(at: i)
        }
    }

    func togglePlayPause() {
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    func toggleOverlay() {
        overlayVisible.toggle()
        overlayTask?.cancel()
        if overlayVisible {
            overlayTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.overlayVisible = false }
            }
        }
    }

    // MARK: Playback algorithm

    private func start(at target: Int) {
        playTask?.cancel()
        playTask = Task { [weak self] in
            await self?.play(at: target)
        }
    }

    private func play(at target: Int) async {
        guard !playable.isEmpty else { mode = .empty; return }
        guard target >= 0, target < playable.count else { mode = .empty; return }
        index = target

        let video = playable[target]
        isLoading = true
        defer { isLoading = false }

        do {
            try await resolveAndStart(videoID: video.youtubeVideoId)
            consecutiveSkips = 0
            mode = .playing
            prefetchNext()
        } catch {
            if isDegraded {
                player.pause()
                mode = .degraded
                return
            }
            consecutiveSkips += 1
            if consecutiveSkips >= 3 {
                player.pause()
                mode = .fallback
                return
            }
            await play(at: target + 1)
        }
    }

    /// Resolve once, then retry once, then start playback and wait for readiness.
    private func resolveAndStart(videoID: String) async throws {
        let url = try await resolveWithOneRetry(videoID: videoID)
        try await startPlayback(url: url)
    }

    private func resolveWithOneRetry(videoID: String) async throws -> URL {
        do {
            return try await resolveOnce(videoID: videoID)
        } catch {
            return try await resolveOnce(videoID: videoID)
        }
    }

    private func resolveOnce(videoID: String) async throws -> URL {
        do {
            let response = try await api.resolve(videoID: videoID)
            guard response.isOK, let streamURL = response.streamUrl, let url = URL(string: streamURL) else {
                recordResolverFailure()
                throw APIError.badStatus(0)
            }
            return url
        } catch {
            recordResolverFailure()
            throw error
        }
    }

    private func startPlayback(url: URL) async throws {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.play()
        try await waitForReady(item: item)
    }

    private func waitForReady(item: AVPlayerItem) async throws {
        final class Holder { var obs: NSKeyValueObservation?; var finished = false }
        let holder = Holder()
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            holder.obs = item.observe(\.status, options: [.initial, .new]) { item, _ in
                guard !holder.finished else { return }
                switch item.status {
                case .readyToPlay:
                    holder.finished = true
                    holder.obs?.invalidate()
                    cont.resume()
                case .failed:
                    holder.finished = true
                    holder.obs?.invalidate()
                    cont.resume(throwing: item.error ?? APIError.badStatus(-1))
                default:
                    break
                }
            }
            Task { [holder] in
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard !holder.finished else { return }
                holder.finished = true
                holder.obs?.invalidate()
                cont.resume(throwing: APIError.badStatus(-2))
            }
        }
    }

    private func prefetchNext() {
        let next = index + 1
        guard next < playable.count else { return }
        let id = playable[next].youtubeVideoId
        Task.detached { [api] in
            _ = try? await api.resolve(videoID: id)
        }
    }

    // MARK: Degraded mode tracking

    private func recordResolverFailure() {
        let now = Date()
        failureTimestamps.append(now)
        let cutoff = now.addingTimeInterval(-60)
        failureTimestamps.removeAll { $0 < cutoff }
    }

    private var isDegraded: Bool { failureTimestamps.count >= 5 }
}
