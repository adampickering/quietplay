import AVFoundation
import SwiftUI

/// Format a playback timestamp as `m:ss` (or `h:mm:ss` past an hour).
/// Shared by the pause card and the in-video progress strip so they
/// always agree.
fileprivate func formatPlaybackTime(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds)
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
    return String(format: "%d:%02d", m, s)
}

struct StreamView: View {
    @Bindable var app: AppState
    let onExitToLibrary: () -> Void

    @State private var showSpinner: Bool = false
    @State private var spinnerTask: Task<Void, Never>?
    /// Subtle enter animation: when we push into playback, the player
    /// layer starts slightly scaled-down + transparent and settles into
    /// place. Reads as "that thumbnail just expanded into the video"
    /// without a full matchedGeometry hero.
    @State private var entering: Bool = true
    /// 5-minutes-left warning pill. Flips true inside the five-minute
    /// pre-bedtime window (tracks Saturday's later curfew automatically),
    /// flips false eight seconds later. `FiveMinuteWarningStore`
    /// persists the "already shown tonight" flag so the kid doesn't see
    /// it twice in one evening.
    @State private var fiveMinutesWarningVisible: Bool = false
    @State private var fiveMinutesTask: Task<Void, Never>?
    /// Seek acceleration state: rapid same-direction presses grow the
    /// stride so a three-tap burst jumps 10 + 20 + 30 = 60 seconds.
    @State private var seekStride: Int = 10
    @State private var lastSeekDirection: Int = 0
    @State private var lastSeekAt: Date = .distantPast

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            PlayerLayerView(player: app.player)
                .ignoresSafeArea()
                .opacity(entering ? 0 : 1)
                .scaleEffect(entering ? 0.94 : 1)

            // Pause dim: a soft black wash instead of a full blur so the
            // frame is still legible behind the overlay. Dull, not hidden.
            if app.isPaused && app.mode == .playing {
                Color.black.opacity(0.32)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }

            if showSpinner && app.isLoading {
                LoadingView(
                    title: app.currentChannelVideo?.title,
                    channelTitle: app.currentChannel?.title
                )
                .transition(.opacity)
            }

            startChip
                .opacity(app.overlayVisible && !app.pickerPresented ? 1 : 0)
                .animation(.easeInOut(duration: 0.18), value: app.overlayVisible)
                .animation(.easeInOut(duration: 0.18), value: app.pickerPresented)

            // Paused card: play glyph + title + channel + elapsed / total.
            // Stays readable over the lightly-dimmed frame underneath.
            // Suppressed while loading so it doesn't stack on the
            // LoadingView's anchor logo + title block.
            if app.isPaused && app.mode == .playing && !app.pickerPresented && !app.isLoading {
                PausedCard(
                    videoTitle: app.currentChannelVideo?.title,
                    channelTitle: app.currentChannel?.title,
                    elapsed: app.elapsedSeconds,
                    duration: app.durationSeconds
                )
                .transition(.opacity)
            }

            switch app.mode {
            case .empty:
                MessageView(text: "Nothing in the depot. Ask Dad to add a channel.", onExit: onExitToLibrary)
            case .fallback:
                MessageView(
                    text: "Tried a few — none would play. Pick a different one?",
                    actionTitle: "Try again",
                    action: { app.retryCurrentVideo() },
                    onExit: onExitToLibrary
                )
            case .degraded:
                MessageView(
                    text: "Server's having a lie down. Give it a moment?",
                    actionTitle: "Try again",
                    action: { app.retryCurrentVideo() },
                    onExit: onExitToLibrary
                )
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

            // When the picker or a MessageView (fallback/degraded/empty)
            // is up, stop capturing raw presses via the UIKit responder —
            // SwiftUI's focus engine needs control of the remote so the
            // picker cards, retry pill, or Back button can be focused and
            // selected.
            if !app.pickerPresented && !app.autoAdvanceActive && app.mode == .playing {
                RemoteInputView(
                    onSelect: { handleSelect() },
                    onLeft: { handleLeft() },
                    onRight: { handleRight() },
                    onPlayPause: { app.togglePlayPause() },
                    onExit: { handleExit() }
                )
            }

            if app.seekHUDSeconds != 0 {
                SeekHUD(seconds: app.seekHUDSeconds)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            if app.autoAdvanceActive {
                VStack {
                    Spacer()
                    UpNextChip(
                        title: app.autoAdvanceNextTitle,
                        secondsLeft: app.autoAdvanceSecondsLeft,
                        onPlayNow: { app.skipToAutoAdvanceNow() },
                        onCancel: { app.cancelAutoAdvance() }
                    )
                    .padding(.bottom, 72)
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // "5 minutes left" wind-down nudge. Top-right so it doesn't
            // collide with the title chip that lives top-left. Ignores
            // the remote, doesn't pause playback.
            if fiveMinutesWarningVisible {
                VStack {
                    HStack {
                        Spacer()
                        FiveMinutesLeftToast()
                            .padding(.top, 44)
                            .padding(.trailing, 56)
                    }
                    Spacer()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.18), value: app.seekHUDSeconds)
        .animation(.easeInOut(duration: 0.35), value: fiveMinutesWarningVisible)
        .animation(.easeInOut(duration: 0.3), value: app.autoAdvanceActive)
        .animation(.easeOut(duration: 0.2), value: app.pickerPresented)
        .animation(.easeInOut(duration: 0.18), value: app.isPaused)
        .onAppear {
            withAnimation(.easeOut(duration: 0.38)) {
                entering = false
            }
            startFiveMinuteWarningPoll()
        }
        .onDisappear {
            fiveMinutesTask?.cancel()
            fiveMinutesTask = nil
        }
        .onChange(of: app.isLoading, initial: true) { _, loading in
            spinnerTask?.cancel()
            if loading {
                // Short grace period: quick resolves shouldn't flash the
                // loading screen. ~180ms is below the perceptual threshold
                // for "something's happening" but long enough to dodge
                // cached/instant plays.
                spinnerTask = Task {
                    try? await Task.sleep(nanoseconds: 180_000_000)
                    if !Task.isCancelled {
                        withAnimation(.easeOut(duration: 0.25)) {
                            showSpinner = true
                        }
                    }
                }
            } else {
                withAnimation(.easeIn(duration: 0.2)) {
                    showSpinner = false
                }
            }
        }
    }

    // Remote routing: when the picker is up, select/left/right are handled
    // by the picker's own focus traversal (SwiftUI Button focus). The
    // UIKit-level handler still catches Menu/Esc and routes it to "back".
    private func handleSelect() {
        if !app.pickerPresented { app.toggleOverlay() }
    }

    // Left/right on the remote scrub the video. Each press jumps 10s,
    // and rapid same-direction presses accelerate: 10 → 20 → 30 → 60s
    // (cap). Reverses or a >900ms pause reset the stride back to 10s,
    // so a single tap is always a precise 10-second nudge.
    private func handleLeft() {
        guard !app.pickerPresented else { return }
        app.seekRelative(Double(-nextSeekStride(direction: -1)))
    }

    private func handleRight() {
        guard !app.pickerPresented else { return }
        app.seekRelative(Double(nextSeekStride(direction: 1)))
    }

    private func nextSeekStride(direction: Int) -> Int {
        let now = Date()
        let withinChain = direction == lastSeekDirection
            && now.timeIntervalSince(lastSeekAt) <= 0.9
        seekStride = withinChain ? min(seekStride + 10, 60) : 10
        lastSeekDirection = direction
        lastSeekAt = now
        return seekStride
    }

    private func handleExit() {
        onExitToLibrary()
    }

    /// Poll every 30 seconds while playback is mounted. If we've
    /// entered the five-minute pre-bedtime firing window and haven't
    /// already flashed tonight, show the toast for 8 seconds, then mark
    /// it as shown so the kid doesn't see it on every subsequent video.
    private func startFiveMinuteWarningPoll() {
        fiveMinutesTask?.cancel()
        fiveMinutesTask = Task { @MainActor in
            while !Task.isCancelled {
                if FiveMinuteWarningStore.inFireWindow(),
                   !FiveMinuteWarningStore.hasShownTonight() {
                    fiveMinutesWarningVisible = true
                    try? await Task.sleep(nanoseconds: 8_000_000_000)
                    if Task.isCancelled { break }
                    fiveMinutesWarningVisible = false
                    FiveMinuteWarningStore.markShownTonight()
                }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
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

            if app.durationSeconds > 0 {
                ProgressStrip(
                    elapsed: app.elapsedSeconds,
                    duration: app.durationSeconds
                )
                .padding(.horizontal, 56)
                .padding(.bottom, 40)
                .transition(.opacity)
            }
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
                Text(formatPlaybackTime(elapsed))
                Spacer()
                Text(formatPlaybackTime(duration))
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
}

private struct MessageView: View {
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    let onExit: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 22) {
                Text(text)
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)

                if let title = actionTitle, let action = action {
                    RetryPill(title: title, action: action)
                }
            }
            .padding(40)
        }
        .onExitCommand(perform: onExit)
    }
}

private struct RetryPill: View {
    let title: String
    let action: () -> Void
    @FocusState private var focused: Bool
    /// 600ms disable after a press so a panicky kid mashing Select
    /// during a degraded state can't fire three retries in a row.
    @State private var cooldown: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 15, weight: .medium))
            Text(title)
                .font(.system(size: 17, weight: .medium))
        }
        .foregroundStyle(.white.opacity(focused ? 1.0 : 0.8))
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.white.opacity(focused ? 0.16 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(focused ? 0.32 : 0.1), lineWidth: 1)
        )
        .opacity(cooldown ? 0.5 : 1.0)
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onTapGesture {
            guard !cooldown else { return }
            action()
            cooldown = true
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                await MainActor.run { cooldown = false }
            }
        }
        .animation(Motion.focusSpring, value: focused)
    }
}

// MARK: - Picker overlay

private struct PickerOverlay: View {
    let title: String
    let candidates: [PickerCandidate]
    let showChannelName: Bool
    let onSelect: (PickerCandidate) -> Void
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
    let candidate: PickerCandidate
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
                .overlay(ThumbnailImage(url: candidate.video.thumbnailUrl))
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
        .animation(Motion.focusSpring, value: focused)
    }
}

/// Netflix/YouTube-style "Up next in 5s" bubble that replaces the
/// picker between videos. Shows the title, a live countdown, and two
/// focusable actions — Play now (click center) and Cancel.
private struct UpNextChip: View {
    let title: String
    let secondsLeft: Int
    let onPlayNow: () -> Void
    let onCancel: () -> Void

    @FocusState private var focusedButton: Button?
    private enum Button: Hashable { case play, cancel }

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Up next")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(.white.opacity(0.6))
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: 520, alignment: .leading)
            }

            ZStack {
                Circle()
                    .stroke(.white.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: CGFloat(secondsLeft) / 5)
                    .stroke(.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1.0), value: secondsLeft)
                Text("\(secondsLeft)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .frame(width: 48, height: 48)

            HStack(spacing: 12) {
                chipButton(label: "Play now", systemImage: "play.fill", kind: .play, action: onPlayNow)
                chipButton(label: "Cancel", systemImage: "xmark", kind: .cancel, action: onCancel)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(0.7))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 20, y: 8)
        .padding(.horizontal, 48)
    }

    private func chipButton(label: String, systemImage: String, kind: Button, action: @escaping () -> Void) -> some View {
        let isFocused = focusedButton == kind
        return HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
            Text(label)
                .font(.system(size: 15, weight: .medium))
        }
        .foregroundStyle(.white.opacity(isFocused ? 1.0 : 0.85))
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Capsule().fill(.white.opacity(isFocused ? 0.22 : 0.08)))
        .overlay(Capsule().strokeBorder(.white.opacity(isFocused ? 0.4 : 0.14), lineWidth: 1))
        .contentShape(Capsule())
        .focusable()
        .focusEffectDisabled()
        .focused($focusedButton, equals: kind)
        .onTapGesture(perform: action)
        .animation(Motion.focusSpring, value: isFocused)
    }
}

/// Brief centered "±N s" pill that fades in for ~700ms after a seek
/// press, so the kid sees the skip land even when the frame content
/// hasn't visibly changed yet. The magnitude grows when presses chain
/// together (10 → 20 → 30 → 60s).
private struct SeekHUD: View {
    let seconds: Int  // signed: − rewind, + forward

    private var rewind: Bool { seconds < 0 }
    private var magnitude: Int { abs(seconds) }
    private var glyph: String {
        // SF Symbols only ships a few baked-in numbers (10/15/30/45/60/75/90).
        switch magnitude {
        case 10: return rewind ? "gobackward.10" : "goforward.10"
        case 15: return rewind ? "gobackward.15" : "goforward.15"
        case 30: return rewind ? "gobackward.30" : "goforward.30"
        case 45: return rewind ? "gobackward.45" : "goforward.45"
        case 60: return rewind ? "gobackward.60" : "goforward.60"
        default: return rewind ? "gobackward" : "goforward"
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: glyph)
                .font(.system(size: 44, weight: .semibold))
            Text("\(rewind ? "−" : "+")\(magnitude) s")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
        .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
        .accessibilityLabel(Text(rewind ? "Rewound \(magnitude) seconds" : "Forward \(magnitude) seconds"))
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
        .animation(Motion.focusSpring, value: focused)
    }
}

private struct PausedCard: View {
    let videoTitle: String?
    let channelTitle: String?
    let elapsed: Double
    let duration: Double

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "play.fill")
                .font(.system(size: 76, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .shadow(color: .black.opacity(0.55), radius: 18, y: 6)

            VStack(spacing: 8) {
                if let v = videoTitle {
                    Text(v)
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .kerning(-0.2)
                }
                if let ch = channelTitle {
                    Text(ch)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white.opacity(0.72))
                }
                Text("\(formatPlaybackTime(elapsed)) / \(formatPlaybackTime(duration))")
                    .font(.system(size: 18, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 4)
            }
            .shadow(color: .black.opacity(0.6), radius: 10, y: 2)
            .padding(.horizontal, 80)
        }
    }
}
