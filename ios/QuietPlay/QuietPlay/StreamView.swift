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

            // Big centered play icon while paused — clear visual cue the
            // video is stopped. Fades with overlay transitions.
            if app.isPaused && app.mode == .playing && !app.pickerPresented {
                Image(systemName: "play.fill")
                    .font(.system(size: 90, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.55), radius: 20, y: 6)
                    .transition(.opacity)
            }

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
                    candidates: app.pickerCandidates,
                    showChannelName: shouldShowPickerChannelName,
                    onSelect: { app.pickerSelect($0) },
                    onBack: onExitToLibrary
                )
                .transition(.opacity)
            }

            // When the picker is up, stop capturing raw presses via the
            // UIKit responder — SwiftUI's focus engine needs control of
            // the remote so the picker cards and Back button can be
            // focused and selected.
            if !app.pickerPresented {
                RemoteInputView(
                    onSelect: { handleSelect() },
                    onLeft: { handleLeft() },
                    onRight: { handleRight() },
                    onPlayPause: { app.togglePlayPause() },
                    onExit: { handleExit() }
                )
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.pickerPresented)
        .animation(.easeInOut(duration: 0.18), value: app.isPaused)
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

    // When all candidates are from the same channel as the current one we can
    // hide the channel label (kid already knows what they're watching). When
    // the picker falls back to other channels we show it so "Thomas" and
    // "Connor Creates" are distinguishable.
    private var shouldShowPickerChannelName: Bool {
        guard let cur = app.currentChannel?.id else { return true }
        return app.pickerCandidates.contains(where: { $0.channel.id != cur })
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

                Image(systemName: app.isPaused ? "pause.fill" : "play.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 10, x: 0, y: 2)
            }
            .padding(.horizontal, 56)
            .padding(.top, 44)

            Spacer()

            ProgressStrip(
                elapsed: app.elapsedSeconds,
                duration: app.durationSeconds
            )
            .padding(.horizontal, 56)
            .padding(.bottom, 40)
        }
    }
}

private struct ProgressStrip: View {
    let elapsed: Double
    let duration: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.22))
                    Capsule()
                        .fill(.white)
                        .frame(width: max(0, min(geo.size.width, geo.size.width * fraction)))
                }
            }
            .frame(height: 4)
            .shadow(color: .black.opacity(0.55), radius: 8, y: 2)

            HStack {
                Text(Self.format(elapsed))
                Spacer()
                Text(Self.format(duration))
            }
            .font(.system(size: 14, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.82))
            .shadow(color: .black.opacity(0.55), radius: 8, y: 2)
        }
    }

    private var fraction: Double {
        guard duration > 0 else { return 0 }
        return max(0, min(1, elapsed / duration))
    }

    private static func format(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
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
    let candidates: [AppState.PickerCandidate]
    let showChannelName: Bool
    let onSelect: (AppState.PickerCandidate) -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()

            VStack(spacing: 36) {
                Spacer(minLength: 0)

                Text(title)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)

                if !candidates.isEmpty {
                    HStack(spacing: 28) {
                        ForEach(candidates) { candidate in
                            PickerCard(
                                candidate: candidate,
                                showChannelName: showChannelName,
                                onSelect: { onSelect(candidate) }
                            )
                        }
                    }
                    .padding(.horizontal, 48)
                    .focusSection()
                }

                BackToLibraryButton(action: onBack)
                    .focusSection()

                Spacer(minLength: 0)
            }
        }
        .onExitCommand(perform: onBack)
    }
}

private struct PickerCard: View {
    let candidate: AppState.PickerCandidate
    let showChannelName: Bool
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
                .overlay(Thumb(url: candidate.video.thumbnailUrl))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(focused ? 0.32 : 0), lineWidth: 1)
                )
                .shadow(color: .black.opacity(focused ? 0.55 : 0.3), radius: focused ? 22 : 10, x: 0, y: focused ? 12 : 5)

            VStack(alignment: .leading, spacing: 3) {
                if showChannelName {
                    Text(candidate.channel.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(focused ? 0.75 : 0.5))
                        .lineLimit(1)
                }
                Text(candidate.video.title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(focused ? 1.0 : 0.88))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(Self.relative.localizedString(for: candidate.video.publishedAt, relativeTo: Date()))
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
