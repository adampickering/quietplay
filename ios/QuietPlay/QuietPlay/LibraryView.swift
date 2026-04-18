import SwiftUI

private let paneSplit: CGFloat = 0.28
private let bgGradient = LinearGradient(
    colors: [Color(red: 0.045, green: 0.045, blue: 0.05), .black],
    startPoint: .top,
    endPoint: .bottom
)
private let dividerColor = Color.white.opacity(0.08)

enum SortMode: String {
    case newest
    case alphabetical
}

struct LibraryView: View {
    @Bindable var app: AppState
    let onSelect: (LibraryVideo, LibraryChannel, [LibraryChannel]) -> Void

    @State private var channels: [LibraryChannel] = []
    @State private var focusedChannelID: UUID?
    @State private var loadError: Bool = false
    @State private var seenAt: [String: Date] = ChannelSeenStore.load()
    @State private var searchPresented: Bool = false
    @State private var searchText: String = ""
    @AppStorage("library.sort") private var sortRaw: String = SortMode.newest.rawValue

    private var sort: SortMode {
        SortMode(rawValue: sortRaw) ?? .newest
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                HeaderBar(
                    app: app,
                    sortRaw: $sortRaw,
                    onOpenSearch: { searchPresented = true }
                )

                Rectangle()
                    .fill(dividerColor)
                    .frame(height: 1)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        ChannelList(
                            channels: visibleChannels,
                            focusedID: $focusedChannelID,
                            hasNew: hasNew,
                            markSeen: markSeen,
                            onPlay: { video, channel in onSelect(video, channel, channels) }
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
                                videos: focusedChannel?.videos ?? []
                            ) { video in
                                if let ch = focusedChannel { onSelect(video, ch, channels) }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }

            if searchPresented {
                SearchOverlay(
                    channels: channels,
                    text: $searchText,
                    hasNew: hasNew,
                    onPick: { channel in
                        focusedChannelID = channel.id
                        markSeen(channel.id)
                        searchPresented = false
                        searchText = ""
                        let firstUnwatched = channel.videos.first(where: {
                            !WatchedVideoStore.isWatched($0.youtubeVideoId)
                        })
                        if let video = firstUnwatched ?? channel.videos.first {
                            onSelect(video, channel, channels)
                        }
                    },
                    onDismiss: {
                        searchPresented = false
                        searchText = ""
                    }
                )
                .transition(.opacity)
            }
        }
        .background(bgGradient)
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.2), value: searchPresented)
        .task(id: app.currentProfile?.id) {
            await load()
        }
    }

    private var visibleChannels: [LibraryChannel] {
        switch sort {
        case .newest:
            return channels.sorted { a, b in
                let ad = a.videos.first?.publishedAt ?? .distantPast
                let bd = b.videos.first?.publishedAt ?? .distantPast
                if ad == bd {
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
                return ad > bd
            }
        case .alphabetical:
            return channels.sorted { a, b in
                a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
            }
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
        guard let latest = channel.videos.first?.publishedAt else { return false }
        let last = seenAt[channel.id.uuidString] ?? .distantPast
        return latest > last
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
    @Binding var sortRaw: String
    let onOpenSearch: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            LogoPlaceholder()
            Spacer(minLength: 24)
            SortToggle(sortRaw: $sortRaw)
            SearchButton(action: onOpenSearch)
            ProfileSwitcher(app: app)
        }
        .padding(.horizontal, 56)
        .padding(.top, 36)
        .padding(.bottom, 26)
    }
}

private struct LogoPlaceholder: View {
    var body: some View {
        // Placeholder for the QuietPlay logo. Replace with Image(...) when
        // the brand asset is ready.
        HStack(spacing: 10) {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
            Text("QuietPlay")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .kerning(-0.3)
        }
    }
}

private struct GridHeader: View {
    let channel: LibraryChannel

    var body: some View {
        HStack(spacing: 10) {
            Text(channel.title)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            Text("·")
                .foregroundStyle(.white.opacity(0.3))
            Text("\(channel.videos.count) videos")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
            Spacer()
        }
        .padding(.horizontal, 48)
        .padding(.top, 32)
        .padding(.bottom, 8)
    }
}

// MARK: - Sort toggle

private struct SortToggle: View {
    @Binding var sortRaw: String

    var body: some View {
        HStack(spacing: 0) {
            SortButton(title: "Newest", active: sortRaw == SortMode.newest.rawValue) {
                sortRaw = SortMode.newest.rawValue
            }
            SortButton(title: "A–Z", active: sortRaw == SortMode.alphabetical.rawValue) {
                sortRaw = SortMode.alphabetical.rawValue
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.09), lineWidth: 1)
        )
    }
}

private struct SortButton: View {
    let title: String
    let active: Bool
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Text(title)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white.opacity(active ? 1.0 : (focused ? 0.9 : 0.55)))
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(active ? 0.14 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.28 : 0), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onTapGesture(perform: action)
            .animation(.easeOut(duration: 0.15), value: focused)
            .animation(.easeOut(duration: 0.15), value: active)
    }
}

// MARK: - Search button (opens overlay)

private struct SearchButton: View {
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
            Text("Search")
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(.white.opacity(focused ? 1.0 : 0.75))
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(focused ? 0.12 : 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.28 : 0.09), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onTapGesture(perform: action)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - Search overlay

private struct SearchOverlay: View {
    let channels: [LibraryChannel]
    @Binding var text: String
    let hasNew: (LibraryChannel) -> Bool
    let onPick: (LibraryChannel) -> Void
    let onDismiss: () -> Void

    @FocusState private var fieldFocused: Bool

    private var results: [LibraryChannel] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            return channels.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        return channels
            .filter { $0.title.localizedCaseInsensitiveContains(q) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: 28) {
                HStack(spacing: 16) {
                    HStack(spacing: 14) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.white.opacity(fieldFocused ? 0.9 : 0.5))

                        TextField("Search channels", text: $text)
                            .textFieldStyle(.plain)
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white)
                            .focused($fieldFocused)
                            .submitLabel(.done)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(.white.opacity(fieldFocused ? 0.10 : 0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(.white.opacity(fieldFocused ? 0.32 : 0.1), lineWidth: 1)
                    )

                    SearchDismissButton(action: onDismiss)
                }
                .padding(.horizontal, 80)
                .padding(.top, 64)

                if results.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.white.opacity(0.3))
                        Text(text.isEmpty ? "Start typing to search your channels" : "No matching channels")
                            .font(.system(size: 17))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(results) { channel in
                                SearchResultRow(
                                    channel: channel,
                                    hasNew: hasNew(channel),
                                    onPick: { onPick(channel) }
                                )
                            }
                        }
                        .padding(.horizontal, 80)
                        .padding(.bottom, 48)
                    }
                    .scrollClipDisabled()
                }
            }
        }
        .onExitCommand(perform: onDismiss)
        .onAppear {
            DispatchQueue.main.async { fieldFocused = true }
        }
        .animation(.easeOut(duration: 0.15), value: text)
    }
}

private struct SearchDismissButton: View {
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white.opacity(focused ? 1.0 : 0.6))
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(.white.opacity(focused ? 0.12 : 0.06))
            )
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(focused ? 0.3 : 0.09), lineWidth: 1)
            )
            .contentShape(Circle())
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onTapGesture(perform: action)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}

private struct SearchResultRow: View {
    let channel: LibraryChannel
    let hasNew: Bool
    let onPick: () -> Void
    @FocusState private var focused: Bool

    private static let dotColor = Color(red: 0.039, green: 0.518, blue: 1.0)
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack(spacing: 18) {
            Color.white.opacity(0.06)
                .frame(width: 56, height: 56)
                .overlay(ThumbnailImage(url: channel.thumbnailUrl))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.title)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let latest = channel.videos.first?.publishedAt {
                    Text("Latest · \(Self.relative.localizedString(for: latest, relativeTo: Date()))")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer(minLength: 8)

            Circle()
                .fill(Self.dotColor)
                .frame(width: 10, height: 10)
                .opacity(hasNew ? 1.0 : 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.white.opacity(focused ? 0.09 : 0))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.25 : 0), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onTapGesture(perform: onPick)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - Channel list

private struct ChannelList: View {
    let channels: [LibraryChannel]
    @Binding var focusedID: UUID?
    let hasNew: (LibraryChannel) -> Bool
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
    let onSeen: () -> Void
    let onPlay: (LibraryVideo) -> Void
    @FocusState private var focused: Bool

    private static let dotColor = Color(red: 0.039, green: 0.518, blue: 1.0)

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(.white.opacity(focused ? 1.0 : 0))
                .frame(width: 3)
                .padding(.vertical, 4)

            HStack(spacing: 14) {
                Color.white.opacity(0.06)
                    .frame(width: 48, height: 48)
                    .overlay(ThumbnailImage(url: channel.thumbnailUrl))
                    .clipShape(Circle())

                Text(channel.title)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.white.opacity(focused ? 1.0 : 0.72))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Circle()
                    .fill(Self.dotColor)
                    .frame(width: 10, height: 10)
                    .opacity(hasNew ? 1.0 : 0)
                    .animation(.easeOut(duration: 0.2), value: hasNew)
            }
            .padding(.leading, 20)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
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
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - Video grid

private struct VideoGrid: View {
    let videos: [LibraryVideo]
    let onSelect: (LibraryVideo) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 40) {
                ForEach(videos) { video in
                    VideoCardButton(video: video, onSelect: onSelect)
                }
            }
            .padding(.horizontal, 48)
            .padding(.vertical, 24)
        }
        .scrollClipDisabled()
    }
}

private struct VideoCardButton: View {
    let video: LibraryVideo
    let onSelect: (LibraryVideo) -> Void
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
        .onTapGesture {
            onSelect(video)
        }
        .scaleEffect(focused ? 1.035 : 1.0)
        .animation(.easeOut(duration: 0.18), value: focused)
    }

    private var thumbnail: some View {
        Color.white.opacity(0.05)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay(ThumbnailImage(url: video.thumbnailUrl))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.20 : 0), lineWidth: 1)
            )
            .shadow(color: .black.opacity(focused ? 0.45 : 0.22), radius: focused ? 18 : 6, x: 0, y: focused ? 10 : 3)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(video.title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white.opacity(focused ? 1.0 : 0.88))
                .lineLimit(1)
                .truncationMode(.tail)
                .kerning(-0.1)
            Text(Self.relative.localizedString(for: video.publishedAt, relativeTo: Date()))
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(focused ? 0.6 : 0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }
}

// MARK: - Helpers

private struct ThumbnailImage: View {
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
