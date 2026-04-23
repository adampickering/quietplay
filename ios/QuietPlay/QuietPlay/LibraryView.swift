import SwiftUI

private let paneSplit: CGFloat = 0.28
private let baseTop = Theme.Palette.baseTop
private let baseBottom = Theme.Palette.base
private let dividerColor = Theme.Palette.divider

/// Sentinel UUID for the "Recently Added" virtual channel. Pinned near
/// the top of the channel list when there's at least one unwatched video
/// anywhere in the library.
private let recentlyAddedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000EE")!
private let recentlyAddedTitle = "Recently Added"

/// Sentinel UUID for the "Continue watching" virtual channel — in-progress
/// videos across every channel, sorted by most-recently-played. Pinned
/// near the top of the list whenever there's anything to resume.
private let continueWatchingID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FF")!
private let continueWatchingTitle = "Continue Watching"

/// Sentinel UUID for the "Favorites" virtual channel — videos the kid
/// explicitly starred with the Play/Pause button. Pinned to the very top
/// of the list above Continue Watching since a star is a stronger intent
/// signal than "I stopped mid-video".
private let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FA")!
private let favoritesTitle = "Favorites"

/// Sentinel UUID for the "Recommended" virtual channel — the pool of
/// channels Dad has flagged `is_recommended`. Sits near the top so
/// Henry bumps into handpicked stuff before wandering elsewhere.
private let recommendedID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FB")!
private let recommendedTitle = "Recommended"

/// Ordered category definitions. Each is a virtual "super-channel":
/// focus it and the right pane shows every video from every real
/// channel tagged with this category, newest first. Icons are SF
/// symbols, tint is the ring color used on the sidebar icon.
struct LibraryCategory: Identifiable, Hashable {
    let id: UUID
    let name: String      // Matches DB channels.category
    let display: String   // UI label
    let symbol: String
    let hue: Double       // 0…1
}

private let categoryList: [LibraryCategory] = [
    .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CA01")!,
          name: "Trains",      display: "Trains",       symbol: "tram.fill",                 hue: 0.05),
    .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CA02")!,
          name: "LEGO",        display: "LEGO",         symbol: "square.grid.3x3.fill",      hue: 0.13),
    .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CA03")!,
          name: "Cars",        display: "Cars & Motors", symbol: "car.fill",                 hue: 0.98),
    .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CA04")!,
          name: "Restoration", display: "Restoration",  symbol: "wrench.and.screwdriver.fill", hue: 0.08),
    .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CA05")!,
          name: "Engineering", display: "Engineering",  symbol: "atom",                      hue: 0.55),
    .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CA06")!,
          name: "History",     display: "History",      symbol: "building.columns.fill",     hue: 0.10),
    .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CA07")!,
          name: "Kids",        display: "Kids",         symbol: "figure.child",              hue: 0.33),
    .init(id: UUID(uuidString: "00000000-0000-0000-0000-00000000CA08")!,
          name: "Other",       display: "Other",        symbol: "ellipsis.circle.fill",      hue: 0.60),
]

private let categoryIDSet: Set<UUID> = Set(categoryList.map { $0.id })

/// Virtual channel IDs, handy for "is this a real channel?" checks.
private let virtualChannelIDs: Set<UUID> = {
    var s: Set<UUID> = [recentlyAddedID, continueWatchingID, favoritesID, recommendedID]
    s.formUnion(categoryIDSet)
    return s
}()

struct LibraryView: View {
    @Bindable var app: AppState
    let onSelect: (LibraryVideo, LibraryChannel, [LibraryChannel]) -> Void

    @State private var channels: [LibraryChannel] = []
    @State private var focusedChannelID: UUID?
    @State private var loadError: Bool = false
    @State private var seenAt: [String: Date] = ChannelSeenStore.load()
    @State private var watched: Set<String> = WatchedVideoStore.load()
    /// Per-video fraction (0…1), mirrored from PlaybackProgressStore. Kept
    /// as state so re-entering the library after playing something
    /// updates the thumbnail progress bars + Continue Watching row.
    @State private var videoProgress: [String: Double] = Self.loadProgressSnapshot()
    @State private var favorites: Set<String> = FavoritesStore.all()
    /// Cached, materialized sidebar list — real channels plus virtual
    /// pins. Rebuilt only when source data changes (`channels`,
    /// `favorites`, `watched`, `videoProgress`), never on every render.
    /// Before this cache, SwiftUI was recomputing ~7k-video flatMap
    /// passes on every arrow press; the 2017 Apple TV couldn't keep up.
    @State private var visibleChannelsCache: [LibraryChannel] = []
    @State private var searchPresented: Bool = false
    @State private var searchText: String = ""
    /// Channel ID the user has been focused on long enough to warrant
    /// expensive side-effects (backdrop image fetch, thumbnail
    /// prefetch). Decouples those from the every-arrow-press
    /// focusedChannelID so rapid scrolling doesn't thrash.
    @State private var settledChannelID: UUID?
    @State private var settleTask: Task<Void, Never>?

    private static func loadProgressSnapshot() -> [String: Double] {
        PlaybackProgressStore.all().compactMapValues { p in
            guard p.duration > 0 else { return nil }
            return min(1, max(0, p.position / p.duration))
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HeaderBar(app: app, onOpenSearch: { searchPresented = true })
                .background(
                    // Airier header: gradient fading from a light scrim
                    // at the top to nearly clear at the bottom edge so
                    // the library backdrop bleeds through. A hairline
                    // keeps the break between header and grid readable.
                    LinearGradient(
                        colors: [.black.opacity(0.42), .black.opacity(0.1)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                    }
                    .ignoresSafeArea(edges: .top)
                )
                .zIndex(1)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ChannelList(
                            channels: visibleChannels,
                            focusedID: $focusedChannelID,
                            hasNew: hasNew,
                            progress: progress,
                            counts: watchedCounts,
                            markSeen: markSeen,
                            onPlay: { video, channel in
                                // If the row was Recently Added, resolve
                                // the video's real channel so playback
                                // context is correct.
                                let actual = (channel.id == recentlyAddedID)
                                    ? (realChannel(for: video) ?? channel)
                                    : channel
                                onSelect(video, actual, channels)
                            }
                        )
                        .frame(width: geo.size.width * paneSplit)

                        Rectangle()
                            .fill(dividerColor)
                            .frame(width: 1)

                        VStack(spacing: 0) {
                            if let channel = focusedChannel {
                                GridHeader(channel: channel)
                                    .zIndex(1)
                            }
                            VideoGrid(
                                videos: focusedChannel?.videos ?? [],
                                isWatched: { watched.contains($0.youtubeVideoId) },
                                progressFraction: { videoProgress[$0.youtubeVideoId] },
                                isFavorite: { favorites.contains($0.youtubeVideoId) },
                                otherChannels: otherRealChannels,
                                onSelect: { video in
                                    guard let ch = focusedChannel else { return }
                                    let actual = virtualChannelIDs.contains(ch.id)
                                        ? (realChannel(for: video) ?? ch)
                                        : ch
                                    onSelect(video, actual, channels)
                                },
                                onFocusVideo: { video in
                                    app.prefetchResolve(videoID: video.youtubeVideoId)
                                },
                                onToggleFavorite: { video in
                                    let isNow = FavoritesStore.toggle(video.youtubeVideoId)
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.65)) {
                                        if isNow { favorites.insert(video.youtubeVideoId) }
                                        else { favorites.remove(video.youtubeVideoId) }
                                    }
                                },
                                onPickChannel: { channel in
                                    focusedChannelID = channel.id
                                    markSeen(channel.id)
                                }
                            )
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        // Contain the bottom "Keep watching another
                        // channel" strip — scrollClipDisabled on its
                        // inner ScrollView was letting tiles paint
                        // under the sidebar on wide focus halos.
                        .clipped()
                    }
                }
            }

            if loadError {
                LibraryErrorOverlay(onRetry: {
                    loadError = false
                    Task { await load() }
                })
                .transition(.opacity)
            }

            if searchPresented {
                SearchOverlay(
                    channels: channels,
                    text: $searchText,
                    onPickChannel: { channel in
                        focusedChannelID = channel.id
                        settledChannelID = channel.id
                        markSeen(channel.id)
                        searchPresented = false
                        searchText = ""
                    },
                    onPickVideo: { video, channel in
                        searchPresented = false
                        searchText = ""
                        onSelect(video, channel, channels)
                    },
                    onDismiss: {
                        searchPresented = false
                        searchText = ""
                    }
                )
                .transition(.opacity)
            }

            // Easter eggs — unintrusive, non-hit-testing.
            BlobbySighting()
                .id("blobby")
                .allowsHitTesting(false)
        }
        .animation(.easeOut(duration: 0.18), value: searchPresented)
        .background {
            // One global pre-blurred QuietPlay art behind the whole
            // library. Rendered once, no per-channel thumbnail fetch,
            // no runtime blur. Dark scrim on top so text reads cleanly.
            ZStack {
                Color.black
                Image("LibraryBackdrop")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .opacity(0.75)
                LinearGradient(
                    colors: [.black.opacity(0.25), .black.opacity(0.55)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
        // Was 0.45s which made every arrow press feel sticky. 0.18s is
        // in the "fast fade" perceptual bucket and dominates the app's
        // snap-feel.
        .animation(.easeInOut(duration: 0.18), value: settledChannelID)
        .task(id: app.currentProfile?.id) {
            await load()
        }
        .onChange(of: focusedChannelID) { _, newID in
            // Debounce: if the kid holds an arrow, we don't want a
            // backdrop swap or a 40-URL prefetch burst on every tick.
            // Wait ~250ms for focus to settle, then commit.
            settleTask?.cancel()
            settleTask = Task { [newID] in
                try? await Task.sleep(nanoseconds: 250_000_000)
                if Task.isCancelled { return }
                await MainActor.run {
                    settledChannelID = newID
                }
            }
        }
        .onChange(of: settledChannelID) { _, _ in
            // Warm URLCache with the focused channel's thumbnails, plus
            // the adjacent channels' first-video thumbnails so the
            // backdrop doesn't go blank when the kid arrows off in
            // either direction next.
            if let ch = settledChannel {
                prefetchThumbnails(urls: ch.videos.prefix(40).compactMap { $0.thumbnailUrl })
            }
            prefetchAdjacentBackdrops()
        }
        .onChange(of: channels) { _, _ in rebuildVisibleChannels() }
        .onChange(of: favorites) { _, _ in rebuildVisibleChannels() }
        .onChange(of: watched) { _, _ in rebuildVisibleChannels() }
        .onChange(of: videoProgress) { _, _ in rebuildVisibleChannels() }
        .onAppear {
            // Pick up any videos that got marked-watched or had their
            // playback position advanced while we were away in Stream
            // mode, so avatar progress rings, the Continue Watching row,
            // and per-thumbnail progress bars all stay fresh.
            watched = WatchedVideoStore.load()
            withAnimation(.easeInOut(duration: 0.3)) {
                videoProgress = Self.loadProgressSnapshot()
                favorites = FavoritesStore.all()
            }
        }
    }

    /// Warm URLCache with the first-video thumbnail from the channel
    /// before and after the settled one. Costs 2 extra fetches but makes
    /// the backdrop appear instantly when the kid arrows a step in
    /// either direction.
    private func prefetchAdjacentBackdrops() {
        guard
            let id = settledChannelID,
            let idx = visibleChannelsCache.firstIndex(where: { $0.id == id })
        else { return }
        var urls: [String] = []
        if idx > 0, let u = visibleChannelsCache[idx - 1].videos.first?.thumbnailUrl {
            urls.append(u)
        }
        if idx + 1 < visibleChannelsCache.count,
           let u = visibleChannelsCache[idx + 1].videos.first?.thumbnailUrl {
            urls.append(u)
        }
        prefetchThumbnails(urls: urls)
    }

    /// Kick off a low-priority background fetch for each URL so
    /// URLCache warms up ahead of AsyncImage's on-demand loads. Called
    /// when the focused channel changes; the detached task just
    /// discards the bytes and lets the shared cache hold them.
    private func prefetchThumbnails(urls: [String]) {
        let urls = urls.compactMap(URL.init(string:))
        guard !urls.isEmpty else { return }
        Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for u in urls {
                    group.addTask {
                        _ = try? await URLSession.shared.data(from: u)
                    }
                }
            }
        }
    }

    /// Pick the channel we focus the sidebar on after a library load.
    /// Prefer Continue Watching so the kid lands back exactly where he
    /// was — that's his "right, carry on" moment. Falls back to the
    /// first visible row (Favorites, Recently Added, or first real
    /// channel) when there's nothing to resume.
    private func defaultFocusOnLoad() -> UUID? {
        if let cont = continueWatchingChannel { return cont.id }
        return visibleChannels.first?.id
    }

    /// Real channels except the one currently focused — the pool for the
    /// "Keep watching another channel" strip at the bottom of the grid.
    /// Virtual channels are excluded (already pinned in the sidebar).
    private var otherRealChannels: [LibraryChannel] {
        let focusID = focusedChannel?.id
        return channels.filter { ch in
            !virtualChannelIDs.contains(ch.id) && ch.id != focusID
        }
    }

    /// Stable per-channel backdrop source: the latest video's thumbnail.
    /// Using one image per channel (instead of per-focused-video) keeps the
    /// background calm while the kid arrows through the grid. Driven by
    /// the *settled* channel — not every momentary focus — so holding an
    /// arrow doesn't trigger a chain of blur operations.
    private var channelBackdropURL: String? {
        settledChannel?.videos.first?.thumbnailUrl
    }

    private var settledChannel: LibraryChannel? {
        guard let id = settledChannelID else { return focusedChannel }
        return visibleChannelsCache.first { $0.id == id } ?? focusedChannel
    }

    private var backgroundGradient: LinearGradient {
        let tint = settledChannel.map { Color.ambientTint(for: $0.id) } ?? baseTop
        // Mix the channel tint into the top half; bottom fades to pure
        // black. Very low-saturation so the wash is felt, not seen.
        return LinearGradient(
            colors: [tint, baseBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var visibleChannels: [LibraryChannel] { visibleChannelsCache }

    /// Rebuild the sidebar cache. Runs off the hot render path, called
    /// explicitly whenever the inputs it reads from change.
    private func rebuildVisibleChannels() {
        let realChannels = channels.sorted { a, b in
            let ad = a.videos.first?.publishedAt ?? .distantPast
            let bd = b.videos.first?.publishedAt ?? .distantPast
            if ad == bd {
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
            return ad > bd
        }

        var list: [LibraryChannel] = []
        // Top pins — what the kid specifically left behind last time.
        if let favs = favoritesChannel { list.append(favs) }
        if let cont = continueWatchingChannel { list.append(cont) }
        if let recent = recentlyAddedChannel { list.append(recent) }
        // Dad's picks — handpicked good stuff, sits above categories.
        if let rec = recommendedChannel { list.append(rec) }

        // Category super-channels in definition order; only show ones
        // that actually have at least one active channel attached.
        for cat in categoryList {
            if let ch = categoryChannel(for: cat) {
                list.append(ch)
            }
        }

        // Real channels by recency.
        list.append(contentsOf: realChannels)

        visibleChannelsCache = list
    }

    /// Pool of videos from every channel flagged `is_recommended` by
    /// the admin. Newest first, dedup'd by video ID, capped at 200.
    /// Nil when nothing's been recommended so the row disappears.
    private var recommendedChannel: LibraryChannel? {
        let members = channels.filter { $0.isRecommended }
        guard !members.isEmpty else { return nil }
        var seen = Set<String>()
        var pool: [LibraryVideo] = []
        for ch in members {
            for v in ch.videos where seen.insert(v.youtubeVideoId).inserted {
                pool.append(v)
            }
        }
        pool.sort { $0.publishedAt > $1.publishedAt }
        if pool.count > 200 { pool = Array(pool.prefix(200)) }
        return LibraryChannel(
            id: recommendedID,
            title: recommendedTitle,
            thumbnailUrl: nil,
            videos: pool,
            category: nil,
            isRecommended: false
        )
    }

    /// Build the virtual "super-channel" for a category. Pools videos
    /// from every real channel tagged with the category, dedup'd by
    /// video ID, sorted newest-first, capped at 200.
    private func categoryChannel(for cat: LibraryCategory) -> LibraryChannel? {
        let members = channels.filter { ($0.category ?? "Other") == cat.name }
        guard !members.isEmpty else { return nil }
        var seen = Set<String>()
        var pool: [LibraryVideo] = []
        for ch in members {
            for v in ch.videos where seen.insert(v.youtubeVideoId).inserted {
                pool.append(v)
            }
        }
        pool.sort { $0.publishedAt > $1.publishedAt }
        if pool.count > 200 { pool = Array(pool.prefix(200)) }
        return LibraryChannel(
            id: cat.id,
            title: cat.display,
            thumbnailUrl: nil,
            videos: pool,
            category: cat.name
        )
    }

    /// Virtual channel of starred videos. Preserves the order in which
    /// they were starred (newest first) by walking the current library in
    /// its natural order and filtering. Nil when empty so the row
    /// disappears completely until the kid stars something.
    private var favoritesChannel: LibraryChannel? {
        guard !favorites.isEmpty else { return nil }
        let videos = channels
            .flatMap { $0.videos }
            .filter { favorites.contains($0.youtubeVideoId) }
            .sorted { $0.publishedAt > $1.publishedAt }
        guard !videos.isEmpty else { return nil }
        return LibraryChannel(
            id: favoritesID,
            title: favoritesTitle,
            thumbnailUrl: nil,
            videos: videos,
            category: nil
        )
    }

    /// Virtual channel of in-progress videos, ordered most-recent first.
    /// Nil when the store is empty (so the row disappears once everything
    /// has been finished).
    private var continueWatchingChannel: LibraryChannel? {
        let ordered = PlaybackProgressStore.inProgressOrdered()
        guard !ordered.isEmpty else { return nil }
        var byID: [String: LibraryVideo] = [:]
        for ch in channels {
            for v in ch.videos where byID[v.youtubeVideoId] == nil {
                byID[v.youtubeVideoId] = v
            }
        }
        let videos = ordered.compactMap { byID[$0] }
        guard !videos.isEmpty else { return nil }
        return LibraryChannel(
            id: continueWatchingID,
            title: continueWatchingTitle,
            thumbnailUrl: nil,
            videos: Array(videos.prefix(20)),
            category: nil
        )
    }

    /// Virtual channel pinned to the top of the list: the 20 newest
    /// unwatched videos from across every real channel. Nil when there's
    /// nothing unwatched anywhere (hides the row to keep the list clean).
    private var recentlyAddedChannel: LibraryChannel? {
        let newest = channels
            .flatMap { $0.videos }
            .filter { !watched.contains($0.youtubeVideoId) }
            .sorted { $0.publishedAt > $1.publishedAt }
            .prefix(80)
        guard !newest.isEmpty else { return nil }
        return LibraryChannel(
            id: recentlyAddedID,
            title: recentlyAddedTitle,
            thumbnailUrl: nil,
            videos: Array(newest),
            category: nil
        )
    }

    /// Given a video from a virtual channel (Recently Added or Continue
    /// Watching), find the real channel it belongs to so playback context
    /// (channel queue, same-channel picker) stays correct.
    private func realChannel(for video: LibraryVideo) -> LibraryChannel? {
        channels.first { ch in
            !virtualChannelIDs.contains(ch.id)
                && ch.videos.contains { $0.youtubeVideoId == video.youtubeVideoId }
        }
    }

    private var focusedChannel: LibraryChannel? {
        let list = visibleChannels
        if let id = focusedChannelID, let match = list.first(where: { $0.id == id }) {
            return match
        }
        return list.first
    }

    private func hasNew(_ channel: LibraryChannel) -> Bool {
        // Virtual rows are themselves fresh-content affordances — adding
        // a dot would be redundant noise.
        if virtualChannelIDs.contains(channel.id) { return false }
        guard let latest = channel.videos.first?.publishedAt else { return false }
        let last = seenAt[channel.id.uuidString] ?? .distantPast
        return latest > last
    }

    private func progress(_ channel: LibraryChannel) -> Double {
        guard !channel.videos.isEmpty else { return 0 }
        // Virtual rows don't carry a meaningful watched-fraction (their
        // videos live in real channels elsewhere); skip the ring.
        if virtualChannelIDs.contains(channel.id) { return 0 }
        let w = channel.videos.reduce(0) { watched.contains($1.youtubeVideoId) ? $0 + 1 : $0 }
        return Double(w) / Double(channel.videos.count)
    }

    /// Watched count + total for a real channel, nil for virtual rows
    /// (Favorites / Continue Watching / Categories — those pool across
    /// channels so per-channel progress doesn't mean anything). Drives
    /// the small "24 / 80" badge in the sidebar row.
    private func watchedCounts(_ channel: LibraryChannel) -> (watched: Int, total: Int)? {
        if virtualChannelIDs.contains(channel.id) { return nil }
        let total = channel.videos.count
        guard total > 0 else { return nil }
        let w = channel.videos.reduce(0) { watched.contains($1.youtubeVideoId) ? $0 + 1 : $0 }
        return (w, total)
    }

    private func markSeen(_ channelID: UUID) {
        seenAt[channelID.uuidString] = Date()
        ChannelSeenStore.save(seenAt)
    }

    private func load() async {
        guard let profile = app.currentProfile else { return }

        // Stale-while-revalidate: render cached JSON immediately so
        // cold launch has zero white-screen, then refetch in the
        // background and swap in the fresh data when it arrives. Next
        // launch feels teleported.
        if channels.isEmpty, let cached = LibraryCache.load(profileID: profile.id) {
            channels = cached
            rebuildVisibleChannels()
            focusedChannelID = defaultFocusOnLoad()
            settledChannelID = focusedChannelID
            loadError = false
        }

        do {
            let fresh = try await app.api.library(profileID: profile.id)
            channels = fresh
            LibraryCache.save(fresh, profileID: profile.id)
            rebuildVisibleChannels()
            if focusedChannelID == nil {
                focusedChannelID = defaultFocusOnLoad()
                settledChannelID = focusedChannelID
            }
            loadError = false
            // Warm URLCache with scaled avatar URLs for every channel
            // in one burst so the sidebar doesn't fetch 86 originals
            // on the first scroll.
            prefetchThumbnails(urls: channels.compactMap {
                ChannelAvatar.scaledAvatarURL($0.thumbnailUrl)
            })
        } catch {
            // Only surface the error if we have nothing cached. If
            // we're showing a stale-but-valid library, a transient
            // network blip shouldn't nuke the UI.
            if channels.isEmpty {
                loadError = true
            }
        }
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @Bindable var app: AppState
    let onOpenSearch: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            LogoPlaceholder()
            DinnerTimeChip()
                .padding(.leading, 4)
            Spacer(minLength: 24)
            SearchButton(action: onOpenSearch)
            ProfileSwitcher(app: app)
        }
        .padding(.horizontal, 56)
        .padding(.top, 36)
        .padding(.bottom, 26)
    }
}

private struct SearchButton: View {
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
            Text("Search")
                .font(.system(size: 18, weight: .medium))
        }
        .foregroundStyle(.white.opacity(focused ? 1.0 : 0.75))
        .frame(height: 52)
        .padding(.horizontal, 22)
        .background(
            Capsule(style: .continuous)
                .fill(.white.opacity(focused ? 0.12 : 0.05))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.28 : 0.09), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onTapGesture(perform: action)
        .animation(Motion.focusSpring, value: focused)
    }
}

private struct LogoPlaceholder: View {
    var body: some View {
        Image("QuietPlayLogo")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(height: 56)
            .accessibilityLabel("QuietPlay")
    }
}

private struct GridHeader: View {
    let channel: LibraryChannel

    var body: some View {
        HStack(spacing: 12) {
            Text(channel.title)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
            Text("·")
                .font(.system(size: 22))
                .foregroundStyle(.white.opacity(0.3))
            Text("\(channel.videos.count) videos")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 24)
        // VideoGrid's ScrollView has scrollClipDisabled to preserve
        // focus shadows, which means scrolling content bleeds up into
        // the header area. A single translucent material pass is
        // enough to visually separate the title from the thumbnails
        // without dropping a heavy black bar on the design.
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.65)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                }
        }
    }
}

// MARK: - Channel list

private struct ChannelList: View {
    let channels: [LibraryChannel]
    @Binding var focusedID: UUID?
    let hasNew: (LibraryChannel) -> Bool
    let progress: (LibraryChannel) -> Double
    let counts: (LibraryChannel) -> (watched: Int, total: Int)?
    let markSeen: (UUID) -> Void
    let onPlay: (LibraryVideo, LibraryChannel) -> Void

    var body: some View {
        ScrollView {
            if channels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(BritishEmpty.pick(BritishEmpty.noChannels))
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(channels.enumerated()), id: \.element.id) { index, channel in
                        if let header = sectionHeader(before: channel, at: index) {
                            ChannelSectionHeader(title: header)
                        }
                        ChannelRowButton(
                            channel: channel,
                            focusedID: $focusedID,
                            hasNew: hasNew(channel),
                            progress: progress(channel),
                            counts: counts(channel),
                            onSeen: { markSeen(channel.id) },
                            onPlay: { onPlay($0, channel) }
                        )
                    }
                    // Footer easter egg — "end of the line" turtle,
                    // only visible to curious kids who scroll all the
                    // way to the bottom.
                    EndOfLineTurtle()
                }
                .padding(.top, 40)
                .padding(.bottom, 32)
            }
        }
        .scrollClipDisabled()
    }

    /// Decide whether a section label should appear above `channel`.
    /// Three sections in order: virtual pins (no label), categories
    /// ("CATEGORIES"), and real channels ("ALL CHANNELS"). Called once
    /// per row during render — negligible cost compared to the row
    /// body itself.
    private func sectionHeader(before channel: LibraryChannel, at index: Int) -> String? {
        let isCategory = categoryIDSet.contains(channel.id)
        let isVirtualPin = channel.id == favoritesID
            || channel.id == continueWatchingID
            || channel.id == recentlyAddedID
            || channel.id == recommendedID
        let isReal = !isCategory && !isVirtualPin

        if index == 0 { return nil }
        let prev = channels[index - 1]
        let prevIsCategory = categoryIDSet.contains(prev.id)
        let prevIsVirtualPin = prev.id == favoritesID
            || prev.id == continueWatchingID
            || prev.id == recentlyAddedID
            || prev.id == recommendedID
        let prevIsReal = !prevIsCategory && !prevIsVirtualPin

        if isCategory && !prevIsCategory { return "CATEGORIES" }
        if isReal && !prevIsReal { return "ALL CHANNELS" }
        return nil
    }
}

/// Small-caps row separator for the channel list. Non-focusable — the
/// tvOS focus engine skips straight to the next `ChannelRowButton`.
private struct ChannelSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .tracking(1.8)
            .foregroundStyle(.white.opacity(0.55))
            .padding(.leading, 26)
            .padding(.top, 28)
            .padding(.bottom, 10)
    }
}

/// SF-symbol glyph on a tinted circle, used as the avatar for every
/// category super-channel in the sidebar. Cheaper than the fancy
/// gradients on FavoritesIcon — just a flat saturated color per hue,
/// which reads cleanly and keeps render cost negligible.
private struct CategoryIcon: View {
    let category: LibraryCategory
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hue: category.hue, saturation: 0.55, brightness: 0.55))
                .frame(width: size, height: size)
            Image(systemName: category.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

private struct ChannelRowButton: View {
    let channel: LibraryChannel
    @Binding var focusedID: UUID?
    let hasNew: Bool
    let progress: Double
    let counts: (watched: Int, total: Int)?
    let onSeen: () -> Void
    let onPlay: (LibraryVideo) -> Void
    @FocusState private var focused: Bool

    private static let dotColor = Theme.Palette.accentNew

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(focused ? 1.0 : 0))
                .frame(width: 5)
                .padding(.vertical, 4)
                .shadow(color: .white.opacity(focused ? 0.35 : 0), radius: 6)

            HStack(spacing: 18) {
                if channel.id == favoritesID {
                    FavoritesIcon(size: 64)
                } else if channel.id == recommendedID {
                    RecommendedIcon(size: 64)
                } else if channel.id == continueWatchingID {
                    ContinueWatchingIcon(size: 64)
                } else if channel.id == recentlyAddedID {
                    RecentlyAddedIcon(size: 64)
                } else if let cat = categoryList.first(where: { $0.id == channel.id }) {
                    CategoryIcon(category: cat, size: 64)
                } else {
                    ChannelAvatar(url: channel.thumbnailUrl, size: 64, progress: progress)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(focused ? 1.0 : 0.76))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .kerning(-0.2)
                    if let c = counts, c.watched > 0 {
                        Text("\(c.watched) / \(c.total) watched")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(focused ? 0.65 : 0.42))
                    }
                }

                Spacer(minLength: 8)

                Circle()
                    .fill(Self.dotColor)
                    .frame(width: 12, height: 12)
                    .opacity(hasNew ? 1.0 : 0)
                    .animation(.easeOut(duration: 0.2), value: hasNew)
            }
            .padding(.leading, 22)
            .padding(.trailing, 18)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
        }
        // Soft full-row highlight stripe on focus. Gradient fades from
        // the left accent bar outward so the row reads as "selected"
        // while staying quiet. Transparent when not focused.
        .background(
            LinearGradient(
                colors: focused
                    ? [.white.opacity(0.14), .white.opacity(0.06), .white.opacity(0.02)]
                    : [.clear, .clear, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text("Plays the newest unwatched video."))
        .onTapGesture {
            focusedID = channel.id
            onSeen()
            // Play first unwatched video in the channel's display order
            // (handles serial shows where the kid wants to continue from
            // where they left off); fall back to position 0 if every
            // video is already watched (rewatch).
            let firstUnwatched = channel.videos.first(where: {
                !WatchedVideoStore.isWatched($0.youtubeVideoId)
            })
            if let video = firstUnwatched ?? channel.videos.first {
                onPlay(video)
            }
        }
        .onChange(of: focused) { _, newValue in
            if newValue {
                focusedID = channel.id
                onSeen()
            }
        }
        .animation(Motion.focusSpring, value: focused)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [channel.title]
        if hasNew { parts.append("new videos") }
        if progress >= 1 { parts.append("all watched") }
        else if progress > 0 {
            parts.append("\(Int(progress * 100)) percent watched")
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Video grid

private struct VideoGrid: View {
    let videos: [LibraryVideo]
    let isWatched: (LibraryVideo) -> Bool
    let progressFraction: (LibraryVideo) -> Double?
    let isFavorite: (LibraryVideo) -> Bool
    let otherChannels: [LibraryChannel]
    let onSelect: (LibraryVideo) -> Void
    let onFocusVideo: (LibraryVideo) -> Void
    let onToggleFavorite: (LibraryVideo) -> Void
    let onPickChannel: (LibraryChannel) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 28),
        GridItem(.flexible(), spacing: 28),
        GridItem(.flexible(), spacing: 28),
    ]

    var body: some View {
        ScrollView {
            if videos.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "film")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text(BritishEmpty.pick(BritishEmpty.noVideos))
                        .font(.system(size: 17))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: columns, spacing: 40) {
                    ForEach(videos) { video in
                        VideoCardButton(
                            video: video,
                            watched: isWatched(video),
                            progressFraction: progressFraction(video),
                            favorite: isFavorite(video),
                            onSelect: onSelect,
                            onFocus: onFocusVideo,
                            onToggleFavorite: onToggleFavorite
                        )
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 24)

                // Henry's ask: after the last video, a horizontal row of
                // other channels so he can hop without going back to the
                // sidebar. Only shows when there's actually somewhere
                // else to go.
                if !otherChannels.isEmpty {
                    KeepWatchingStrip(
                        channels: otherChannels,
                        onPick: onPickChannel
                    )
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .scrollClipDisabled()
    }
}

private struct VideoCardButton: View {
    let video: LibraryVideo
    let watched: Bool
    /// 0…1 if this video has saved playback progress, nil otherwise.
    let progressFraction: Double?
    let favorite: Bool
    let onSelect: (LibraryVideo) -> Void
    let onFocus: (LibraryVideo) -> Void
    let onToggleFavorite: (LibraryVideo) -> Void
    @FocusState private var focused: Bool

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            thumbnail
            caption
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isButton)
        .onTapGesture { onSelect(video) }
        .onPlayPauseCommand {
            // Remote's Play/Pause doubles as the "star this" shortcut
            // while we're in the library grid. Gives Henry a one-button
            // way to curate without a settings menu.
            onToggleFavorite(video)
        }
        .onChange(of: focused) { _, isFocused in
            // When a card gains focus, quietly warm up the resolver
            // (server caches the stream URL in Redis so tap-to-play
            // lands instantly).
            if isFocused { onFocus(video) }
        }
        .scaleEffect(focused ? 1.05 : 1.0)
        .animation(Motion.focusSpring, value: focused)
    }

    private var accessibilityLabel: String {
        var parts: [String] = [
            video.title,
            Self.relative.localizedString(for: video.publishedAt, relativeTo: Date()),
        ]
        if let d = video.durationSeconds, d > 0 {
            parts.append(Self.formatDurationLong(d))
        }
        if watched {
            parts.append("watched")
        } else if let frac = progressFraction, frac >= 0.02 {
            parts.append("\(Int(frac * 100)) percent watched, resume available")
        }
        if favorite { parts.append("favorited") }
        return parts.joined(separator: ", ")
    }

    private static func formatDurationLong(_ seconds: Int) -> String {
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        if h > 0 { return "\(h) hour\(h == 1 ? "" : "s") \(m) minute\(m == 1 ? "" : "s")" }
        if m > 0 { return "\(m) minute\(m == 1 ? "" : "s")" }
        return "\(seconds) seconds"
    }

    private var thumbnail: some View {
        Color.white.opacity(0.05)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            // 3-col grid on 1920px tvOS ≈ 580px per card. Downsample to
            // 600px max to kill main-thread decode cost during scroll.
            .overlay(FastImage(url: video.thumbnailUrl, targetPixelSize: 600))
            .overlay(alignment: .topLeading) {
                if favorite {
                    StarBadge()
                        .padding(12)
                        .transition(.scale(scale: 0.3).combined(with: .opacity))
                }
            }
            .overlay(alignment: .topTrailing) {
                if watched {
                    ZStack {
                        Circle()
                            .fill(Theme.Palette.accentWatched)
                        Image(systemName: "checkmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.4), radius: 6, x: 0, y: 2)
                    .padding(12)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if let d = video.durationSeconds, d > 0 {
                    DurationBadge(seconds: d)
                        .padding(10)
                }
            }
            .overlay(alignment: .bottom) {
                // Thin "you were here" bar for videos the kid has started
                // but not finished. Hidden on fully-watched cards so the
                // green check stands alone. Animates its fill so walking
                // back into the library after a playback session reads as
                // "the bar grew while I was away."
                if !watched, let frac = progressFraction, frac >= 0.02 {
                    ProgressLineBar(fraction: frac)
                        .frame(height: 6)
                        .transition(.opacity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.20 : 0), lineWidth: 1)
            )
            // Focus shadow removed — shadow(radius:) on 80+ cells that
            // re-render on every focus change was the worst repeated
            // effect on the 2017 Apple TV. Scale + stroke alone reads
            // as "selected" without the GPU cost.
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(video.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white.opacity(titleOpacity))
                .lineLimit(2)
                .truncationMode(.tail)
                .kerning(-0.1)
            Text(Self.relative.localizedString(for: video.publishedAt, relativeTo: Date()))
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(dateOpacity))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var titleOpacity: Double {
        if watched { return focused ? 0.7 : 0.55 }
        return focused ? 1.0 : 0.88
    }

    private var dateOpacity: Double {
        if watched { return focused ? 0.45 : 0.3 }
        return focused ? 0.6 : 0.4
    }
}

// MARK: - Helpers

/// Error overlay shown when the /library fetch fails. Sits above the
/// empty library so the user has a clear "couldn't load" signal and an
/// explicit retry button instead of staring at blankness.
private struct LibraryErrorOverlay: View {
    let onRetry: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Couldn't load your library")
                    .font(.system(size: Theme.FontSize.xxxl, weight: .semibold))
                    .foregroundStyle(.white)
                Text("Check that QuietPlay is running, then try again.")
                    .font(.system(size: Theme.FontSize.md))
                    .foregroundStyle(Theme.Palette.dimWhite55)

                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                    Text("Try again")
                        .font(.system(size: Theme.FontSize.md, weight: .medium))
                }
                .foregroundStyle(.white.opacity(focused ? 1.0 : 0.85))
                .padding(.horizontal, 26)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                        .fill(.white.opacity(focused ? 0.16 : 0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                        .strokeBorder(.white.opacity(focused ? 0.32 : 0.12), lineWidth: 1)
                )
                .contentShape(Rectangle())
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .onTapGesture(perform: onRetry)
                .accessibilityAddTraits(.isButton)
                .animation(Motion.focusSpring, value: focused)
                .padding(.top, 8)
            }
        }
    }
}

/// Thin "progress so far" bar that lives at the bottom of any partially-
/// watched thumbnail. White-on-scrim so it reads on any frame; the scrim
/// fades right-to-left so it doesn't visually cut the image in half.
private struct ProgressLineBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [.black.opacity(0.55), .black.opacity(0.2)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                Rectangle()
                    .fill(Color.white)
                    .frame(width: max(2, geo.size.width * min(1, max(0, fraction))))
                    .animation(.easeOut(duration: 0.4), value: fraction)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Compact `12:34` or `1:02:15` pill shown bottom-right of every
/// thumbnail. Uses a solid black scrim for legibility on any background
/// and a thin hairline stroke to keep it visually attached to the card.
private struct DurationBadge: View {
    let seconds: Int

    var body: some View {
        Text(Self.format(seconds))
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.black.opacity(0.78))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 1)
            )
            .accessibilityHidden(true)
    }

    private static func format(_ total: Int) -> String {
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}

/// Warm amber star badge for favorited videos. Drop-shadow + soft glow
/// so it reads on any thumbnail without feeling stickered-on.
private struct StarBadge: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 1.00, green: 0.82, blue: 0.28),
                            Color(red: 0.95, green: 0.62, blue: 0.10),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)
                .shadow(color: Color(red: 1, green: 0.7, blue: 0.2).opacity(0.5), radius: 10)
            Image(systemName: "star.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
        }
        .shadow(color: .black.opacity(0.45), radius: 6, y: 2)
        .accessibilityHidden(true)
    }
}

/// Stylized icon for the "Continue watching" virtual channel: cool blue
/// gradient with a curved forward arrow — visually distinct from the
/// amber Recently Added sparkle so kids can tell the two pinned rows
/// apart at a glance. A slow rotation on the outer ring adds a quiet
/// "clock still ticking" cue without ever demanding attention.
private struct ContinueWatchingIcon: View {
    let size: CGFloat

    var body: some View {
        // Continuous rotation removed — it ran forever on a sidebar row
        // that's always on-screen, dirtying the render tree every frame.
        // A static arc reads as "progress" without the cost.
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [
                        Color(hue: 0.58, saturation: 0.55, brightness: 0.70),
                        Color(hue: 0.62, saturation: 0.65, brightness: 0.40),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)

            Circle()
                .trim(from: 0.05, to: 0.33)
                .stroke(
                    .white.opacity(0.85),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: size + 4, height: size + 4)

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
        }
    }
}

/// Stylized icon for the "Recommended" virtual channel (Dad's picks):
/// teal gradient with a bold thumbs-up. Distinct from Favorites (gold
/// star) so at a glance the kid reads "someone else chose these for me"
/// vs "I chose these."
private struct RecommendedIcon: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 0.30, green: 0.76, blue: 0.82),
                        Color(red: 0.12, green: 0.44, blue: 0.60),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
            Image(systemName: "hand.thumbsup.fill")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .offset(y: -size * 0.02)
        }
    }
}

/// Stylized icon for the "Favorites" virtual channel: warm gold gradient
/// with a filled star and a gently pulsing halo. Distinct from the amber
/// Recently Added sparkle so at a glance the kid knows which row is
/// "videos I chose to keep" vs "videos that showed up recently."
private struct FavoritesIcon: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            // Continuously-animated halo dropped — it re-rendered every
            // frame just to exist, on a row that's always visible.
            Circle()
                .fill(LinearGradient(
                    colors: [
                        Color(red: 1.00, green: 0.82, blue: 0.28),
                        Color(red: 0.92, green: 0.55, blue: 0.05),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)

            Image(systemName: "star.fill")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Stylized icon for the "Recently Added" virtual channel: soft amber
/// gradient circle with a sparkles glyph, distinct from real channel
/// avatars so kids recognize it as the cross-library freshness shortcut.
private struct RecentlyAddedIcon: View {
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [
                        Color(hue: 0.14, saturation: 0.55, brightness: 0.65),
                        Color(hue: 0.05, saturation: 0.6, brightness: 0.38),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: size, height: size)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

/// Circular channel avatar with an optional watched-progress ring. The ring
/// is hidden entirely at 0% so "unwatched" channels stay visually quiet;
/// it appears as soon as the kid has finished a video, and fills to a
/// complete circle once the channel is fully consumed — a calm visual
/// earn-it cue without any counters.
private struct ChannelAvatar: View {
    let url: String?
    let size: CGFloat
    let progress: Double

    var body: some View {
        ZStack {
            // Small avatars don't need 900px images. YouTube's CDN URLs
            // carry their size as an inline token ("=s900-..."); rewriting
            // to =s176 gets us a sharper-at-1x-Retina image that
            // downloads in a fraction of the bytes.
            Color.white.opacity(0.06)
                .frame(width: size, height: size)
                // Avatars display at 64pt; decode at 128px for 2x.
                .overlay(FastImage(url: Self.scaledAvatarURL(url), targetPixelSize: 128))
                .clipShape(Circle())

            if progress > 0 {
                // Faint background track.
                Circle()
                    .stroke(.white.opacity(0.18), lineWidth: 2.5)
                    .frame(width: size + 4, height: size + 4)
                // Arc for the watched fraction.
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        .white.opacity(0.82),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: size + 4, height: size + 4)
                    .animation(Motion.focusSpring, value: progress)
            }
        }
    }

    /// Rewrite YouTube CDN avatar URLs from the default `=s900` size
    /// token down to `=s176`. Cuts bytes-per-channel by ~25× without
    /// touching the path/query pattern the CDN expects.
    static func scaledAvatarURL(_ urlString: String?) -> String? {
        guard let urlString else { return nil }
        guard let range = urlString.range(of: #"=s\d+-"#, options: .regularExpression) else {
            return urlString
        }
        return urlString.replacingCharacters(in: range, with: "=s176-")
    }
}

/// Full-bleed, heavily blurred backdrop of a video thumbnail. Fades in over
/// the library's ambient channel tint whenever a video card gains focus —
/// the whole library dresses itself around whatever the kid is looking at.
private struct BlurredBackdrop: View {
    let urlString: String

    var body: some View {
        GeometryReader { geo in
            if let u = URL(string: urlString) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                            // Radius 80 looks lush on M-series Macs but
                            // costs ~6ms per frame on the 2017 Apple TV.
                            // 32 still reads as "very blurred" and is
                            // ~4× cheaper on the GPU.
                            .blur(radius: 32, opaque: true)
                            .overlay(
                                LinearGradient(
                                    colors: [.black.opacity(0.45), .black.opacity(0.7)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    default:
                        Color.clear
                    }
                }
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Search overlay

/// Full-screen searcher across channels AND videos in the library. Uses
/// lowercased prefix indexes built lazily the first time the overlay
/// opens so the kid can type fluidly against 6,000+ videos without
/// hitting the filter cost every keystroke.
/// Native tvOS search. Wraps the results in a NavigationStack + List
/// and uses `.searchable()` — this hands the keyboard and text-entry
/// UI to the system, which is the only way to get the canonical
/// Apple-TV-Plus-style search experience. Fighting it with a custom
/// TextField + overlay produced the jarring white strip over the
/// darkened library (because tvOS presents its own system input view
/// on top of any focused TextField).
private struct SearchOverlay: View {
    let channels: [LibraryChannel]
    @Binding var text: String
    let onPickChannel: (LibraryChannel) -> Void
    let onPickVideo: (LibraryVideo, LibraryChannel) -> Void
    let onDismiss: () -> Void

    private var videoIndex: [(title: String, video: LibraryVideo, channel: LibraryChannel)] {
        channels.flatMap { ch in
            ch.videos.map { (title: $0.title.lowercased(), video: $0, channel: ch) }
        }
    }

    private var channelResults: [LibraryChannel] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return channels
            .filter { $0.title.lowercased().contains(q) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var videoResults: [(LibraryVideo, LibraryChannel)] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 2 else { return [] }
        return videoIndex
            .filter { $0.title.contains(q) }
            .prefix(40)
            .map { ($0.video, $0.channel) }
    }

    var body: some View {
        ZStack {
            // Opaque black floor so tvOS's native search keyboard and
            // field don't render through to the library behind. Without
            // this the system UI looks ghosted on top of the grid.
            Color.black.ignoresSafeArea()

            NavigationStack {
                List {
                    if text.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 10) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 36, weight: .light))
                                    .foregroundStyle(.white.opacity(0.35))
                                Text("Start typing to search")
                                    .font(.system(size: 17))
                                    .foregroundStyle(.white.opacity(0.55))
                            }
                            .padding(.vertical, 80)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                } else if channelResults.isEmpty && videoResults.isEmpty {
                    Section {
                        Text("No matches")
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .listRowBackground(Color.clear)
                    }
                } else {
                    if !channelResults.isEmpty {
                        Section("Channels") {
                            ForEach(channelResults) { channel in
                                Button { onPickChannel(channel) } label: {
                                    HStack(spacing: 16) {
                                        ChannelAvatar(url: channel.thumbnailUrl, size: 52, progress: 0)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(channel.title)
                                                .font(.system(size: 20, weight: .medium))
                                                .foregroundStyle(.white)
                                            if let cat = channel.category {
                                                Text(cat)
                                                    .font(.system(size: 13))
                                                    .foregroundStyle(.white.opacity(0.55))
                                            }
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if !videoResults.isEmpty {
                        Section("Videos") {
                            ForEach(Array(videoResults.enumerated()), id: \.offset) { _, pair in
                                Button { onPickVideo(pair.0, pair.1) } label: {
                                    HStack(spacing: 16) {
                                        FastImage(url: pair.0.thumbnailUrl, targetPixelSize: 200)
                                            .frame(width: 128, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(pair.0.title)
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundStyle(.white)
                                                .lineLimit(1)
                                            Text(pair.1.title)
                                                .font(.system(size: 13))
                                                .foregroundStyle(.white.opacity(0.55))
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Search")
            }
            .searchable(text: $text, placement: .automatic, prompt: "Channels or videos")
        }
        .onExitCommand(perform: onDismiss)
    }
}

struct ThumbnailImage: View {
    let url: String?
    var body: some View {
        GeometryReader { geo in
            if let urlStr = url, let u = URL(string: urlStr) {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    default:
                        Color.clear
                    }
                }
            } else {
                Color.clear
            }
        }
    }
}

// MARK: - Keep-watching channel strip

/// Horizontal row of other channel avatars that appears at the bottom of
/// the grid. Henry's ask: once he's scrolled past every video in a
/// channel, he wants to keep browsing without going back to the sidebar.
/// The strip is focus-sectioned so the tvOS focus engine treats it as a
/// single stop below the grid — down-press from the last row lands here.
private struct KeepWatchingStrip: View {
    let channels: [LibraryChannel]
    let onPick: (LibraryChannel) -> Void

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Keep watching another channel")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(0.78))
                Spacer()
            }
            .padding(.horizontal, 48)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 32) {
                    ForEach(Array(channels.enumerated()), id: \.element.id) { index, ch in
                        StripChannelTile(
                            channel: ch,
                            onPick: { onPick(ch) }
                        )
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 10)
                        .animation(
                            .spring(response: 0.55, dampingFraction: 0.82)
                                .delay(0.04 * Double(min(index, 8))),
                            value: appeared
                        )
                    }
                }
                .padding(.horizontal, 48)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
        .padding(.top, 48)
        .padding(.bottom, 60)
        .focusSection()
        .onAppear {
            // One-shot stagger so the tiles slide up into place on first
            // reveal; subsequent scrolls just show them instantly.
            if !appeared { appeared = true }
        }
    }
}

private struct StripChannelTile: View {
    let channel: LibraryChannel
    let onPick: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                // Focus halo — soft bloom behind the avatar on focus.
                Circle()
                    .fill(.white.opacity(focused ? 0.16 : 0))
                    .frame(width: 108, height: 108)
                    .blur(radius: 14)

                ChannelAvatar(url: channel.thumbnailUrl, size: 92, progress: 0)
            }

            Text(channel.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(focused ? 1.0 : 0.65))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 124)
                .multilineTextAlignment(.center)
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Go to channel, \(channel.title)"))
        .accessibilityAddTraits(.isButton)
        .onTapGesture(perform: onPick)
        .scaleEffect(focused ? 1.10 : 1.0)
        .shadow(color: .black.opacity(focused ? 0.45 : 0), radius: focused ? 18 : 0, y: focused ? 10 : 0)
        .animation(Motion.focusSpring, value: focused)
    }
}
