import AVFoundation
import SwiftUI

struct StreamView: View {
    @Bindable var app: AppState
    let onExitToLibrary: () -> Void

    @State private var showSpinner: Bool = false
    @State private var spinnerTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerLayerView(player: app.player)
                .ignoresSafeArea()

            if showSpinner && app.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }

            startChip
                .opacity(app.overlayVisible && !app.pickerPresented ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: app.overlayVisible)
                .animation(.easeInOut(duration: 0.18), value: app.pickerPresented)

            switch app.mode {
            case .empty:
                MessageView(text: "Ask Dad to add a channel")
            case .fallback:
                MessageView(text: "Nothing to play right now")
            case .degraded:
                MessageView(text: "Can't reach QuietPlay right now")
            case .loading, .playing:
                EmptyView()
            }

            if app.pickerPresented {
                PickerOverlay(
                    title: app.pickerTitle,
                    videos: app.pickerVideos,
                    onSelect: { app.pickerSelect($0) },
                    onBack: onExitToLibrary
                )
                .transition(.opacity)
            }

            RemoteInputView(
                onSelect: { handleSelect() },
                onLeft: { handleLeft() },
                onRight: { handleRight() },
                onPlayPause: { app.togglePlayPause() },
                onExit: { handleExit() }
            )
        }
        .animation(.easeOut(duration: 0.2), value: app.pickerPresented)
        .onChange(of: app.isLoading, initial: true) { _, loading in
            spinnerTask?.cancel()
            if loading {
                spinnerTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    if !Task.isCancelled { showSpinner = true }
                }
            } else {
                showSpinner = false
            }
        }
    }

    // Remote routing: when the picker is up, select/left/right are handled
    // by the picker's own focus traversal (SwiftUI Button focus). The
    // UIKit-level handler still catches Menu/Esc and routes it to "back".
    private func handleSelect() {
        if !app.pickerPresented { app.toggleOverlay() }
    }

    private func handleLeft() {
        if !app.pickerPresented { app.retreat() }
    }

    private func handleRight() {
        if !app.pickerPresented { app.advance() }
    }

    private func handleExit() {
        onExitToLibrary()
    }

    private var startChip: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if let v = app.currentChannelVideo, let ch = app.currentChannel {
                        Text(ch.title)
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.white.opacity(0.75))
                        Text(v.title)
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .kerning(-0.2)
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 2)

                Spacer()

                Image(systemName: app.player.rate == 0 ? "pause.fill" : "play.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 2)
            }
            .padding(.horizontal, 56)
            .padding(.top, 44)
            Spacer()
        }
    }
}

private struct MessageView: View {
    let text: String
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            Text(text)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}

// MARK: - Picker overlay

private struct PickerOverlay: View {
    let title: String
    let videos: [LibraryVideo]
    let onSelect: (LibraryVideo) -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))

                if videos.isEmpty {
                    // Channel exhausted — only Back-to-Library remains.
                    EmptyView()
                } else {
                    HStack(spacing: 28) {
                        ForEach(videos) { video in
                            PickerCard(video: video, onSelect: { onSelect(video) })
                        }
                    }
                    .padding(.horizontal, 48)
                }

                BackToLibraryButton(action: onBack)

                Spacer(minLength: 0)
            }
        }
        .onExitCommand(perform: onBack)
    }
}

private struct PickerCard: View {
    let video: LibraryVideo
    let onSelect: () -> Void
    @FocusState private var focused: Bool

    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Color.white.opacity(0.05)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay(Thumb(url: video.thumbnailUrl))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(focused ? 0.32 : 0), lineWidth: 1)
                )
                .shadow(color: .black.opacity(focused ? 0.55 : 0.3), radius: focused ? 22 : 10, x: 0, y: focused ? 12 : 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(video.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(focused ? 1.0 : 0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(Self.relative.localizedString(for: video.publishedAt, relativeTo: Date()))
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(focused ? 0.65 : 0.4))
            }
            .padding(.horizontal, 2)
        }
        .frame(width: 380)
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onTapGesture(perform: onSelect)
        .scaleEffect(focused ? 1.05 : 1.0)
        .animation(.easeOut(duration: 0.18), value: focused)
    }
}

private struct BackToLibraryButton: View {
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.left")
                .font(.system(size: 15, weight: .medium))
            Text("Back to Library")
                .font(.system(size: 17, weight: .medium))
        }
        .foregroundStyle(.white.opacity(focused ? 1.0 : 0.8))
        .padding(.horizontal, 26)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(.white.opacity(focused ? 0.14 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.32 : 0.1), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onTapGesture(perform: action)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

private struct Thumb: View {
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
