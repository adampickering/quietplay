import SwiftUI

struct LibraryView: View {
    @Bindable var app: AppState
    let onSelect: (LibraryVideo) -> Void

    @State private var channels: [LibraryChannel] = []
    @State private var focusedChannelID: UUID?
    @State private var loadError: Bool = false

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ChannelList(
                    channels: channels,
                    focusedID: $focusedChannelID
                )
                .frame(width: geo.size.width * 0.30)

                Divider().background(.white.opacity(0.1))

                VideoGrid(
                    videos: focusedChannel?.videos ?? [],
                    onSelect: onSelect
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task(id: app.currentProfile?.id) {
            await load()
        }
    }

    private var focusedChannel: LibraryChannel? {
        guard let id = focusedChannelID else { return channels.first }
        return channels.first { $0.id == id }
    }

    private func load() async {
        guard let profile = app.currentProfile else { return }
        do {
            channels = try await app.api.library(profileID: profile.id)
            focusedChannelID = channels.first?.id
            loadError = false
        } catch {
            channels = []
            loadError = true
        }
    }
}

private struct ChannelList: View {
    let channels: [LibraryChannel]
    @Binding var focusedID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(channels) { channel in
                    ChannelRow(channel: channel)
                        .focusable()
                        .onFocusChange { isFocused in
                            if isFocused { focusedID = channel.id }
                        }
                }
            }
            .padding(.vertical, 32)
            .padding(.horizontal, 24)
        }
    }
}

private struct ChannelRow: View {
    let channel: LibraryChannel

    var body: some View {
        HStack(spacing: 16) {
            ThumbnailImage(url: channel.thumbnailUrl)
                .frame(width: 80, height: 80)
                .clipShape(Circle())
            Text(channel.title)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
    }
}

private struct VideoGrid: View {
    let videos: [LibraryVideo]
    let onSelect: (LibraryVideo) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24),
        GridItem(.flexible(), spacing: 24),
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(videos) { video in
                    Button {
                        onSelect(video)
                    } label: {
                        VideoCard(video: video)
                    }
                }
            }
            .padding(32)
        }
    }
}

private struct VideoCard: View {
    let video: LibraryVideo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ThumbnailImage(url: video.thumbnailUrl)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
            Text(video.title)
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ThumbnailImage: View {
    let url: String?
    var body: some View {
        if let urlStr = url, let u = URL(string: urlStr) {
            AsyncImage(url: u) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                default: Color.white.opacity(0.08)
                }
            }
        } else {
            Color.white.opacity(0.08)
        }
    }
}

private struct FocusChangeModifier: ViewModifier {
    let onChange: (Bool) -> Void
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .onChange(of: isFocused) { _, newValue in
                onChange(newValue)
            }
    }
}

private extension View {
    func onFocusChange(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(FocusChangeModifier(onChange: action))
    }
}
