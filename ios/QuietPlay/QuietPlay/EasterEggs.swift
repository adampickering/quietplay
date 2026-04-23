import SwiftUI

// MARK: - Steam puff for Henry's avatar

/// Tiny steam wisp that drifts up from Henry's profile avatar every ~12s,
/// fades, and repeats. Henry shares his name with a Thomas & Friends
/// engine — the app isn't calling it out, just quietly acknowledging.
struct HenrySteamPuff: View {
    @State private var rise: Bool = false

    var body: some View {
        Text("🚂")
            .font(.system(size: 28))
            .opacity(rise ? 0 : 0.9)
            .offset(y: rise ? -30 : 0)
            .animation(.easeOut(duration: 2.4), value: rise)
            .task {
                while !Task.isCancelled {
                    // Long quiet stretch between puffs — Henry should
                    // catch it once a minute at most, not notice it
                    // otherwise.
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    if Task.isCancelled { break }
                    rise = true
                    try? await Task.sleep(nanoseconds: 2_400_000_000)
                    if Task.isCancelled { break }
                    rise = false
                }
            }
            .allowsHitTesting(false)
    }
}

// MARK: - Dinner-time chip

/// Small 🍽 chip that appears in the top corner of the library during
/// the kid's dinner window (17:30–18:30 local). Quiet reminder that
/// there's a dinner table somewhere.
struct DinnerTimeChip: View {
    @State private var inWindow: Bool = DinnerTimeChip.isDinnerTime()
    @State private var ticker: Timer?

    static func isDinnerTime() -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: Date())
        guard let h = c.hour, let m = c.minute else { return false }
        let minutes = h * 60 + m
        return minutes >= 17 * 60 + 30 && minutes <= 18 * 60 + 30
    }

    var body: some View {
        Group {
            if inWindow {
                HStack(spacing: 8) {
                    Text("🍽")
                        .font(.system(size: 18))
                    Text("Time for dinner")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(.black.opacity(0.5))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.4), value: inWindow)
        .onAppear {
            inWindow = Self.isDinnerTime()
            // Re-check every 60 seconds; covers the 17:30 and 18:30
            // edges without an expensive poll.
            ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                inWindow = Self.isDinnerTime()
            }
        }
        .onDisappear { ticker?.invalidate() }
    }
}

// MARK: - End-of-the-line turtle footer

/// Silly turtle tucked at the bottom of the channel list. Kid only
/// sees it by scrolling all the way through the sidebar. Pure reward
/// for curiosity.
struct EndOfLineTurtle: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("🐢")
                .font(.system(size: 22))
            Text("You've reached the end of the line.")
                .font(.system(size: 11, weight: .medium))
                .tracking(0.3)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.bottom, 28)
    }
}

// MARK: - Mr. Blobby rare sighting

/// 1-in-500 launches a pink-and-yellow-spotted dot tears across the
/// bottom of the library for ~1.1s, then vanishes. No sound, no
/// explanation. Henry tells a friend in ten years and no one believes
/// him.
struct BlobbySighting: View {
    @State private var offsetX: CGFloat = 1800
    @State private var shown: Bool = false

    var body: some View {
        GeometryReader { geo in
            if shown {
                ZStack {
                    Circle()
                        .fill(Color(red: 1.0, green: 0.55, blue: 0.75))
                        .frame(width: 38, height: 38)
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(.yellow)
                            .frame(width: 8, height: 8)
                            .offset(x: [8, -9, 6, -4][i],
                                    y: [-7, 4, 8, -2][i])
                    }
                }
                .offset(x: offsetX, y: geo.size.height - 90)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.1)) {
                        offsetX = -60
                    }
                }
            }
        }
        .task {
            // Roll once per mount. 1-in-500 keeps it truly rare.
            guard Int.random(in: 1...500) == 1 else { return }
            try? await Task.sleep(nanoseconds: 600_000_000)
            shown = true
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Take-a-break modal

struct BreakModal: View {
    let onDismiss: () -> Void

    private static let sayings: [String] = [
        "If you watch more telly, your eyes will go square.",
        "Even trains need water stops.",
        "Your bum has been in that chair for two hours.",
        "Pop outside — maybe see a real train?",
        "The Fat Controller orders: ten minutes in the garden.",
        "Biscuit? Glass of squash? Go on.",
        "Even Paddington takes a break for a marmalade sandwich.",
        "Your brain needs a stretch.",
        "Go annoy Dad for a snack.",
        "Two hours is enough telly for one sitting, chief.",
        "Even the signalman gets a tea break.",
        "Put the kettle on. (Ask a grown-up first.)",
    ]

    @FocusState private var focused: Bool
    @State private var saying: String = sayings.randomElement() ?? sayings[0]

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()

            VStack(spacing: 26) {
                Text("🍵")
                    .font(.system(size: 72))

                Text("Time for a break!")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)

                Text(saying)
                    .font(.system(size: 20, weight: .regular, design: .rounded))
                    .italic()
                    .foregroundStyle(.white.opacity(0.82))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 80)

                Button(action: onDismiss) {
                    Text("Alright then")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white.opacity(focused ? 1.0 : 0.85))
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .background(
                            Capsule().fill(.white.opacity(focused ? 0.16 : 0.08))
                        )
                        .overlay(
                            Capsule().strokeBorder(.white.opacity(focused ? 0.32 : 0.12), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .focused($focused)
                .focusEffectDisabled()
                .padding(.top, 4)
            }
            .padding(40)
        }
        .onExitCommand(perform: onDismiss)
        .onAppear { focused = true }
    }
}

// MARK: - Bedtime lock

/// Hard curfew: from 19:30 through 06:00 the next morning the app
/// refuses to play. Shows a gentle "Goodnight" screen that sits above
/// everything and ignores all remote input. Auto-clears at 06:00.
struct BedtimeLock: View {
    let profileName: String?

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.02, blue: 0.08),
                    Color(red: 0.00, green: 0.00, blue: 0.03),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 84, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                    .symbolRenderingMode(.hierarchical)

                Text(greeting)
                    .font(.system(size: 42, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("See you in the morning.")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))
                    .italic()
            }
        }
    }

    private var greeting: String {
        if let n = profileName, !n.isEmpty { return "Goodnight, \(n)" }
        return "Goodnight"
    }

    /// Curfew window: 19:30–06:00 local. Inclusive of the start edge,
    /// exclusive of the end (at 06:00 sharp the kid can use the app
    /// again). Simulator builds skip the lock entirely so the app
    /// is demo-able at any hour.
    static func isActive(now: Date = Date()) -> Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        guard let h = c.hour, let m = c.minute else { return false }
        let minutes = h * 60 + m
        return minutes >= 19 * 60 + 30 || minutes < 6 * 60
        #endif
    }
}

// MARK: - 5-minutes-left warning

/// Small pill that slides in from the top-right of the video at
/// 18:55 and fades out eight seconds later. Gentle "winding down"
/// nudge — not a takeover, doesn't pause playback, doesn't block the
/// remote. Shows at most once per evening.
struct FiveMinutesLeftToast: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.white.opacity(0.92))
            Text("5 minutes left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.black.opacity(0.55))
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
        )
        .shadow(color: .black.opacity(0.4), radius: 10, y: 3)
        .accessibilityLabel(Text("Five minutes of TV time left."))
    }
}

/// Per-day flag: "we've already flashed the 5-minute warning tonight"
/// so the kid doesn't see it again if he starts a new video at 6:56.
enum FiveMinuteWarningStore {
    private static let prefix = "com.quietplay.fiveMinuteWarning."

    private static var todayKey: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func hasShownTonight() -> Bool {
        UserDefaults.standard.bool(forKey: prefix + todayKey)
    }

    static func markShownTonight() {
        UserDefaults.standard.set(true, forKey: prefix + todayKey)
    }

    /// We fire anywhere in a five-minute window starting at 18:55 so a
    /// late-starting video at 18:56 still catches the warning. Stops
    /// at 19:00 — after that it'd read as a lie.
    static func inFireWindow(now: Date = Date()) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        guard let h = c.hour, let m = c.minute else { return false }
        let minutes = h * 60 + m
        return minutes >= 18 * 60 + 55 && minutes <= 19 * 60
    }
}

// MARK: - British empty-state copy

enum BritishEmpty {
    static let noVideos: [String] = [
        "No videos yet",
        "Signal failure at the next station",
        "Engineering works are in progress",
        "We apologise for the delay",
    ]

    static let noChannels: [String] = [
        "No channels",
        "The platform is empty",
        "Ask Dad for a channel",
    ]

    /// Pick deterministically by day so the copy stays stable within
    /// a session but cycles across days.
    static func pick(_ options: [String]) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return options[day % options.count]
    }
}
