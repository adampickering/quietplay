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

    enum BootstrapState: Equatable {
        case loading
        case needsSetup
        case error(String)
        case ready
    }

    let api: QuietPlayAPI
    let player: AVPlayer

    var mode: Mode = .loading
    var bootstrapState: BootstrapState = .loading
    var profilePickerPresented: Bool = false
    var profiles: [Profile] = []
    var currentProfile: Profile?

    // Per-channel playback context (library-first model)
    var currentChannel: LibraryChannel?
    var channelVideos: [LibraryVideo] = []
    var channelIndex: Int = 0
    var libraryChannels: [LibraryChannel] = []

    var overlayVisible: Bool = false
    var isLoading: Bool = false

    // Progress UI (updated by the periodic time observer; rendered in the
    // playback overlay)
    var elapsedSeconds: Double = 0
    var durationSeconds: Double = 0
    var playbackProgress: Double { durationSeconds > 0 ? elapsedSeconds / durationSeconds : 0 }
    var isPaused: Bool = true

    // Picker state
    var pickerPresented: Bool = false
    var pickerCandidates: [PickerCandidate] = []
    var pickerTitle: String = ""

    /// -1 = rewind flash visible, +1 = forward flash visible, 0 = hidden.
    /// Drives a centered HUD in StreamView for the 700ms after a seek.
    var seekHUDDirection: Int = 0

    @ObservationIgnored private var consecutiveSkips: Int = 0
    @ObservationIgnored private var failureTimestamps: [Date] = []
    @ObservationIgnored private var overlayTask: Task<Void, Never>?
    @ObservationIgnored private var playTask: Task<Void, Never>?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var timeObserverToken: Any?
    /// Last wall-clock second we wrote progress to disk. Throttles
    /// UserDefaults writes to roughly one every 5 seconds of playback.
    @ObservationIgnored private var lastSavedProgressAt: Double = -100
    @ObservationIgnored private var prefetchTask: Task<Void, Never>?
    @ObservationIgnored private var seekHUDTask: Task<Void, Never>?

    init(api: QuietPlayAPI = .fromBundle()) {
        self.api = api
        self.player = AVPlayer()
        self.player.actionAtItemEnd = .none

        // End-of-video → mark watched, clear resume state, show picker.
        self.endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let v = self.currentChannelVideo {
                    WatchedVideoStore.markWatched(v.youtubeVideoId)
                    PlaybackProgressStore.clear(videoID: v.youtubeVideoId)
                }
                self.showPicker()
            }
        }

        // Drives both the progress bar UI (every second) and the
        // 80%-reached "mark watched" signal.
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        self.timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isPaused = self.player.rate == 0
                guard let item = self.player.currentItem else { return }
                let duration = item.duration.seconds
                let t = time.seconds
                if duration.isFinite, duration > 0 {
                    self.durationSeconds = duration
                }
                if t.isFinite {
                    self.elapsedSeconds = t
                }
                if duration.isFinite, duration > 0, t.isFinite,
                   t / duration >= 0.8,
                   let v = self.currentChannelVideo {
                    WatchedVideoStore.markWatched(v.youtubeVideoId)
                    // Once the video is effectively finished, wipe
                    // resume state so it doesn't show up in Continue
                    // Watching.
                    PlaybackProgressStore.clear(videoID: v.youtubeVideoId)
                    self.lastSavedProgressAt = t
                } else if
                    duration.isFinite, duration > 0, t.isFinite,
                    let v = self.currentChannelVideo,
                    abs(t - self.lastSavedProgressAt) >= 5
                {
                    // Throttled checkpoint: one UserDefaults write per
                    // ~5s of playback keeps resume-state fresh without
                    // thrashing disk.
                    self.lastSavedProgressAt = t
                    PlaybackProgressStore.save(
                        videoID: v.youtubeVideoId,
                        position: t,
                        duration: duration
                    )
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

    @ObservationIgnored private var retryTask: Task<Void, Never>?

    func bootstrap() async {
        retryTask?.cancel()
        bootstrapState = .loading
        do {
            let list = try await api.profiles()
            profiles = list.sorted { $0.position < $1.position }

            if profiles.isEmpty {
                bootstrapState = .needsSetup
                return
            }

            if profiles.count == 1 {
                await switchProfile(profiles[0])
                profilePickerPresented = false
                bootstrapState = .ready
            } else {
                // Multiple profiles — show picker before anything else.
                profilePickerPresented = true
                bootstrapState = .ready
            }
        } catch {
            let msg = (error as? APIError).map(describe) ?? error.localizedDescription
            bootstrapState = .error(msg)
            scheduleAutoRetry()
        }
    }

    func retryBootstrap() {
        retryTask?.cancel()
        Task { await bootstrap() }
    }

    func pickProfile(_ profile: Profile) {
        profilePickerPresented = false
        Task { await switchProfile(profile) }
    }

    private func scheduleAutoRetry() {
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.bootstrap()
        }
    }

    private func describe(_ err: APIError) -> String {
        switch err {
        case .badURL: return "Server address is invalid"
        case .badStatus(let code): return "Server error (\(code))"
        case .decoding: return "Couldn't read server response"
        case .transport: return "Can't reach QuietPlay"
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

    func playInLibrary(video: LibraryVideo, channel: LibraryChannel, allChannels: [LibraryChannel]) {
        currentChannel = channel
        channelVideos = channel.videos
        libraryChannels = allChannels
        pickerPresented = false
        // Wipe any lingering seek-HUD state from the previous playback
        // session so the new StreamView doesn't inherit a phantom
        // "+10 s" pill from a seek that happened right before the kid
        // hit Menu.
        seekHUDTask?.cancel()
        seekHUDDirection = 0

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

    /// Seek by ±N seconds, clamping to the item's bounds. Called from
    /// the left/right arrow handlers in StreamView. Flashes a centered
    /// seek HUD so the kid sees something confirming the skip.
    func seekRelative(_ delta: Double) {
        guard let item = player.currentItem else { return }
        let duration = item.duration.seconds
        guard duration.isFinite, duration > 0 else { return }
        let current = player.currentTime().seconds
        let target = max(0, min(duration - 0.5, current + delta))
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: CMTime(seconds: 0.5, preferredTimescale: 600)
        )
        flashSeekHUD(delta > 0 ? 1 : -1)
    }

    private func flashSeekHUD(_ direction: Int) {
        seekHUDDirection = direction
        seekHUDTask?.cancel()
        seekHUDTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.seekHUDDirection = 0 }
        }
    }

    /// Debounced background resolve for a video the kid is merely
    /// *hovering* on. Server caches the result in Redis, so the actual
    /// play-press later is an instant hit instead of a 1–2s cold
    /// resolve. The 350ms delay means arrow-mashing through the grid
    /// doesn't spam the resolver.
    func prefetchResolve(videoID: String) {
        prefetchTask?.cancel()
        prefetchTask = Task { [api] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            _ = try? await api.resolve(videoID: videoID)
        }
    }

    /// Retry the current channel video after a .fallback or .degraded error.
    /// Clears failure accounting and re-enters the playback pipeline.
    func retryCurrentVideo() {
        consecutiveSkips = 0
        failureTimestamps.removeAll()
        startChannel(at: channelIndex)
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

        guard let channel = currentChannel else {
            pickerCandidates = []
            pickerTitle = ""
            pickerPresented = true
            return
        }

        let result = PickerBuilder.build(
            currentChannel: channel,
            channelVideos: channelVideos,
            channelIndex: channelIndex,
            libraryChannels: libraryChannels,
            isWatched: WatchedVideoStore.isWatched
        )
        pickerCandidates = result.candidates
        pickerTitle = result.title
        pickerPresented = true
    }

    func dismissPicker() {
        pickerPresented = false
    }

    func pickerSelect(_ candidate: PickerCandidate) {
        pickerPresented = false
        if candidate.channel.id == currentChannel?.id,
           let idx = channelVideos.firstIndex(where: { $0.youtubeVideoId == candidate.video.youtubeVideoId }) {
            startChannel(at: idx)
        } else {
            playInLibrary(video: candidate.video, channel: candidate.channel, allChannels: libraryChannels)
        }
    }

    // MARK: Playback engine (channel-scoped)

    private func startChannel(at target: Int) {
        playTask?.cancel()
        playTask = Task { [weak self] in
            await self?.play(atChannelIndex: target)
        }
    }

    private func play(atChannelIndex target: Int) async {
        // Honor cancellation from the enclosing playTask, otherwise the
        // skip-recursion chain can keep running after the user has
        // already picked a different video or bailed to the library.
        if Task.isCancelled { return }

        guard !channelVideos.isEmpty else { mode = .empty; return }
        guard target >= 0, target < channelVideos.count else { mode = .empty; return }
        channelIndex = target

        let video = channelVideos[target]
        isLoading = true
        defer { isLoading = false }

        do {
            try await resolveAndStart(videoID: video.youtubeVideoId)
            if Task.isCancelled { return }
            consecutiveSkips = 0
            mode = .playing
            flashStartChip()
            prefetchNext()
        } catch {
            if Task.isCancelled { return }
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
        elapsedSeconds = 0
        durationSeconds = 0
        lastSavedProgressAt = -100
        let item = AVPlayerItem(url: url)
        // Replace the current item but hold off on calling play() until
        // after we know whether we need to seek. Otherwise a resumed
        // video flashes a second or two of frame-zero before jumping,
        // which reads as a bug.
        player.replaceCurrentItem(with: item)
        try await waitForReady(item: item)

        if let v = currentChannelVideo,
           let resume = PlaybackProgressStore.resumePosition(for: v.youtubeVideoId) {
            let target = CMTime(seconds: resume, preferredTimescale: 600)
            await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                player.seek(
                    to: target,
                    toleranceBefore: .zero,
                    toleranceAfter: CMTime(seconds: 0.75, preferredTimescale: 600)
                ) { _ in cont.resume() }
            }
        }

        player.play()
    }

    private func waitForReady(item: AVPlayerItem) async throws {
        final class Holder: @unchecked Sendable {
            var obs: NSKeyValueObservation?
            var finished = false
        }
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
