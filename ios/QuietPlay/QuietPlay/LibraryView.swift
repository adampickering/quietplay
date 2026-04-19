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
private let continueWatchingTitle = "Continue watching"

/// Sentinel UUID for the "Favorites" virtual channel — videos the kid
/// explicitly starred with the Play/Pause button. Pinned to the very top
/// of the list above Continue Watching since a star is a stronger intent
/// signal than "I stopped mid-video".
private let favoritesID = UUID(uuidString: "00000000-0000-0000-0000-0000000000FA")!
private let favoritesTitle = "Favorites"

/// Virtual channel IDs, handy for "is this a real channel?" checks.
private let virtualChannelIDs: Set<UUID> = [recentlyAddedID, continueWatchingID, favoritesID]

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

    private static func loadProgressSnapshot() -> [String: Double] {
        PlaybackProgressStore.all().compactMapValues { p in
            guard p.duration > 0 else { return nil }
            return min(1, max(0, p.position / p.duration))
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HeaderBar(app: app)
                .background(
                    Rectangle()
                        .fill(.black.opacity(0.55))
                        .background(.ultraThinMaterial)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(dividerColor).frame(height: 1)
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
                            .id(focusedChannel?.id ?? UUID())
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

        }
        .background {
            ZStack {
                backgroundGradient
                if let urlStr = channelBackdropURL, !urlStr.isEmpty {
                    BlurredBackdrop(urlString: urlStr)
                        .id(urlStr)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.45), value: channelBackdropURL)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.45), value: focusedChannelID)
        .task(id: app.currentProfile?.id) {
            await load()
        }
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
    /// background calm while the kid arrows through the grid.
    private var channelBackdropURL: String? {
        focusedChannel?.videos.first?.thumbnailUrl
    }

    private var backgroundGradient: LinearGradient {
        let tint = focusedChannel.map { Color.ambientTint(for: $0.id) } ?? baseTop
        // Mix the channel tint into the top half; bottom fades to pure
        // black. Very low-saturation so the wash is felt, not seen.
        return LinearGradient(
            colors: [tint, baseBottom],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var visibleChannels: [LibraryChannel] {
        var list = channels.sorted { a, b in
            let ad = a.videos.first?.publishedAt ?? .distantPast
            let bd = b.videos.first?.publishedAt ?? .distantPast
            if ad == bd {
                return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
            return ad > bd
        }
        // Pin Recently Added above real channels; Continue Watching sits
        // above both — the kid's last-interrupted video is the fastest
        // thing to surface.
        if let recent = recentlyAddedChannel {
            list.insert(recent, at: 0)
        }
        if let cont = continueWatchingChannel {
            list.insert(cont, at: 0)
        }
        if let favs = favoritesChannel {
            list.insert(favs, at: 0)
        }
        return list
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
            videos: videos
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
            videos: Array(videos.prefix(20))
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
            .prefix(20)
        guard !newest.isEmpty else { return nil }
        return LibraryChannel(
            id: recentlyAddedID,
            title: recentlyAddedTitle,
            thumbnailUrl: nil,
            videos: Array(newest)
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

    private func markSeen(_ channelID: UUID) {
        seenAt[channelID.uuidString] = Date()
        ChannelSeenStore.save(seenAt)
    }

    private func load() async {
        guard let profile = app.currentProfile else { return }
        do {
            channels = try await app.api.library(profileID: profile.id)
            focusedChannelID = visibleChannels.first?.id
            loadError = false
        } catch {
            channels = []
            loadError = true
        }
    }
}

// MARK: - Header

private struct HeaderBar: View {
    @Bindable var app: AppState

    var body: some View {
        HStack(spacing: 14) {
            LogoPlaceholder()
            Spacer(minLength: 24)
            ProfileSwitcher(app: app)
        }
        .padding(.horizontal, 56)
        .padding(.top, 36)
        .padding(.bottom, 26)
    }
}

private struct LogoPlaceholder: View {
    var body: some View {
        Image("QuietPlayLogo")
            .resizable()
            .renderingMode(.original)
            .aspectRatio(contentMode: .fit)
            .frame(height: 48)
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
        .padding(.top, 32)
        .padding(.bottom, 12)
    }
}

// MARK: - Channel list

private struct ChannelList: View {
    let channels: [LibraryChannel]
    @Binding var focusedID: UUID?
    let hasNew: (LibraryChannel) -> Bool
    let progress: (LibraryChannel) -> Double
    let markSeen: (UUID) -> Void
    let onPlay: (LibraryVideo, LibraryChannel) -> Void

    var body: some View {
        ScrollView {
            if channels.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "tray")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.3))
                    Text("No channels")
                        .font(.system(size: 16))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 64)
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(channels) { channel in
                        ChannelRowButton(
                            channel: channel,
                            focusedID: $focusedID,
                            hasNew: hasNew(channel),
                            progress: progress(channel),
                            onSeen: { markSeen(channel.id) },
                            onPlay: { onPlay($0, channel) }
                        )
                    }
                }
                .padding(.vertical, 32)
            }
        }
        .scrollClipDisabled()
    }
}

private struct ChannelRowButton: View {
    let channel: LibraryChannel
    @Binding var focusedID: UUID?
    let hasNew: Bool
    let progress: Double
    let onSeen: () -> Void
    let onPlay: (LibraryVideo) -> Void
    @FocusState private var focused: Bool

    private static let dotColor = Theme.Palette.accentNew

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(focused ? 1.0 : 0))
                .frame(width: 3)
                .padding(.vertical, 4)

            HStack(spacing: 18) {
                if channel.id == favoritesID {
                    FavoritesIcon(size: 64)
                } else if channel.id == continueWatchingID {
                    ContinueWatchingIcon(size: 64)
                } else if channel.id == recentlyAddedID {
                    RecentlyAddedIcon(size: 64)
                } else {
                    ChannelAvatar(url: channel.thumbnailUrl, size: 64, progress: progress)
                }

                Text(channel.title)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(focused ? 1.0 : 0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)

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
                    Text("No videos yet")
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
        .onTapGesture {
            onSelect(video)
        }
        .onPlayPauseCommand {
            // Remote's Play/Pause doubles as the "star this" shortcut
            // while we're in the library grid. Gives Henry a one-button
            // way to curate without a settings menu.
            onToggleFavorite(video)
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
            .overlay(ThumbnailImage(url: video.thumbnailUrl))
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
            .shadow(color: .black.opacity(focused ? 0.45 : 0.22), radius: focused ? 22 : 6, x: 0, y: focused ? 12 : 3)
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
    @State private var sweep = false

    var body: some View {
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
                .trim(from: 0, to: 0.28)
                .stroke(
                    .white.opacity(0.85),
                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                )
                .rotationEffect(.degrees(sweep ? 360 : 0))
                .frame(width: size + 4, height: size + 4)
                .animation(
                    .linear(duration: 7).repeatForever(autoreverses: false),
                    value: sweep
                )

            Image(systemName: "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .offset(x: size * 0.03)
        }
        .onAppear { sweep = true }
    }
}

/// Stylized icon for the "Favorites" virtual channel: warm gold gradient
/// with a filled star and a gently pulsing halo. Distinct from the amber
/// Recently Added sparkle so at a glance the kid knows which row is
/// "videos I chose to keep" vs "videos that showed up recently."
private struct FavoritesIcon: View {
    let size: CGFloat
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 1, green: 0.78, blue: 0.25).opacity(pulse ? 0.35 : 0.18))
                .frame(width: size + 14, height: size + 14)
                .blur(radius: 6)
                .animation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: pulse
                )

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
        .onAppear { pulse = true }
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
            Color.white.opacity(0.06)
                .frame(width: size, height: size)
                .overlay(ThumbnailImage(url: url))
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
                            .blur(radius: 80, opaque: true)
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
