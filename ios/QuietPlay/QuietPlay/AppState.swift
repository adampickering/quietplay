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

    // Per-channel playback context (library-first model)
    var currentChannel: LibraryChannel?
    var channelVideos: [LibraryVideo] = []
    var channelIndex: Int = 0

    var overlayVisible: Bool = false
    var isLoading: Bool = false

    // Picker state
    var pickerPresented: Bool = false
    var pickerVideos: [LibraryVideo] = []
    var pickerTitle: String = ""

    @ObservationIgnored private var consecutiveSkips: Int = 0
    @ObservationIgnored private var failureTimestamps: [Date] = []
    @ObservationIgnored private var overlayTask: Task<Void, Never>?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserverToken: Any?

    init(api: QuietPlayAPI = .fromBundle()) {
        self.api = api
        self.player = AVPlayer()
        self.player.actionAtItemEnd = .none

        // End-of-video → mark watched, show picker
        self.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let v = self.currentChannelVideo {
                    WatchedVideoStore.markWatched(v.youtubeVideoId)
                }
                self.showPicker()
            }
        }

        // 80%-progress → mark watched
        let interval = CMTime(seconds: 5, preferredTimescale: 600)
        self.timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard let item = self.player.currentItem else { return }
                let duration = item.duration.seconds
                guard duration.isFinite, duration > 0 else { return }
                let t = time.seconds
                guard t.isFinite else { return }
                if t / duration >= 0.8, let v = self.currentChannelVideo {
                    WatchedVideoStore.markWatched(v.youtubeVideoId)
                }
            }
        }
    }

    deinit {
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let timeObserverToken { player.removeTimeObserver(timeObserverToken) }
    }

    var currentChannelVideo: LibraryVideo? {
        guard channelIndex >= 0, channelIndex < channelVideos.count else { return nil }
        return channelVideos[channelIndex]
    }

    // MARK: Bootstrap

    func bootstrap() async {
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
        channelVideos = []
        channelIndex = 0
        currentChannel = nil
        pickerPresented = false
        player.replaceCurrentItem(with: nil)
        mode = .loading
    }

    // MARK: Entry point from Library

    func playInLibrary(video: LibraryVideo, channel: LibraryChannel) {
        currentChannel = channel
        channelVideos = channel.videos
        pickerPresented = false

        let idx = channel.videos.firstIndex(where: { $0.youtubeVideoId == video.youtubeVideoId }) ?? 0
        startChannel(at: idx)
    }

    // MARK: Remote-driven navigation

    /// Swipe-right and video-end: stop and show picker.
    func advance() {
        if let v = currentChannelVideo {
            WatchedVideoStore.markWatched(v.youtubeVideoId)
        }
        showPicker()
    }

    /// Swipe-left: play previous (newer) video in the same channel.
    func retreat() {
        guard channelIndex > 0 else { return }
        startChannel(at: channelIndex - 1)
    }

    func togglePlayPause() {
        if player.rate == 0 { player.play() } else { player.pause() }
    }

    func toggleOverlay() {
        overlayVisible.toggle()
        if overlayVisible {
            scheduleOverlayHide()
        } else {
            overlayTask?.cancel()
        }
    }

    /// Briefly show the channel/title chip (auto-hide after 3s). Used at the
    /// start of each new video.
    func flashStartChip() {
        overlayVisible = true
        scheduleOverlayHide()
    }

    private func scheduleOverlayHide() {
        overlayTask?.cancel()
        overlayTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.overlayVisible = false }
        }
    }

    // MARK: Picker

    func showPicker() {
        player.pause()

        // Next 3 same-channel unwatched videos (older than current).
        let tail = channelVideos.dropFirst(channelIndex + 1)
        let unwatched = tail.filter { !WatchedVideoStore.isWatched($0.youtubeVideoId) }
        pickerVideos = Array(unwatched.prefix(3))

        if pickerVideos.isEmpty {
            let name = currentChannel?.title ?? "this channel"
            pickerTitle = "You've seen all of \(name)"
        } else {
            pickerTitle = "Up next"
        }

        pickerPresented = true
    }

    func dismissPicker() {
        pickerPresented = false
    }

    func pickerSelect(_ video: LibraryVideo) {
        guard let idx = channelVideos.firstIndex(where: { $0.youtubeVideoId == video.youtubeVideoId }) else {
            return
        }
        pickerPresented = false
        startChannel(at: idx)
    }

    // MARK: Playback engine (channel-scoped)

    private func startChannel(at target: Int) {
        playTask?.cancel()
        playTask = Task { [weak self] in
            await self?.play(atChannelIndex: target)
        }
    }

    private func play(atChannelIndex target: Int) async {
        guard !channelVideos.isEmpty else { mode = .empty; return }
        guard target >= 0, target < channelVideos.count else { mode = .empty; return }
        channelIndex = target

        let video = channelVideos[target]
        isLoading = true
        defer { isLoading = false }

        do {
            try await resolveAndStart(videoID: video.youtubeVideoId)
            consecutiveSkips = 0
            mode = .playing
            flashStartChip()
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
            await play(atChannelIndex: target + 1)
        }
    }

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
        let next = channelIndex + 1
        guard next < channelVideos.count else { return }
        let id = channelVideos[next].youtubeVideoId
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
