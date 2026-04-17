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

            overlay
                .opacity(app.overlayVisible ? 1 : 0)
                .animation(.easeInOut(duration: 0.15), value: app.overlayVisible)

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

            // Transparent full-screen input layer
            InputLayer(
                onSelect: { app.toggleOverlay() },
                onLeft: { app.retreat() },
                onRight: { app.advance() },
                onPlayPause: { app.togglePlayPause() },
                onExit: onExitToLibrary
            )
        }
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

    private var overlay: some View {
        VStack {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    if let v = app.currentVideo {
                        Text(v.channelTitle)
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white.opacity(0.7))
                        Text(v.title)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 16) {
                    ProfileSwitcher(app: app)
                    Image(systemName: app.player.rate == 0 ? "pause.fill" : "play.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                }
            }
            .padding(48)
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

private struct InputLayer: View {
    let onSelect: () -> Void
    let onLeft: () -> Void
    let onRight: () -> Void
    let onPlayPause: () -> Void
    let onExit: () -> Void

    var body: some View {
        Button(action: onSelect) {
            Color.clear
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onMoveCommand { direction in
            switch direction {
            case .left: onLeft()
            case .right: onRight()
            default: break
            }
        }
        .onPlayPauseCommand(perform: onPlayPause)
        .onExitCommand(perform: onExit)
    }
}
