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

/// 1-in-2000 launches a softly-tinted, low-saturation dot drifts
/// across the bottom of the library for ~1.8s, then vanishes. Calm
/// enough that it never reads as a rendering glitch. Henry tells a
/// friend in ten years and no one believes him.
struct BlobbySighting: View {
    @State private var offsetX: CGFloat = 1800
    @State private var shown: Bool = false

    var body: some View {
        GeometryReader { geo in
            if shown {
                ZStack {
                    Circle()
                        .fill(Color(red: 0.86, green: 0.70, blue: 0.78))
                        .frame(width: 34, height: 34)
                    ForEach(0..<4, id: \.self) { i in
                        Circle()
                            .fill(Color(red: 0.90, green: 0.82, blue: 0.55))
                            .frame(width: 7, height: 7)
                            .offset(x: [8, -9, 6, -4][i],
                                    y: [-7, 4, 8, -2][i])
                    }
                }
                .opacity(0.7)
                .offset(x: offsetX, y: geo.size.height - 90)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.8)) {
                        offsetX = -60
                    }
                }
            }
        }
        .task {
            // Roll once per mount. 1-in-2000 keeps it properly rare —
            // most Henrys will never see it.
            guard Int.random(in: 1...2000) == 1 else { return }
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
        "Even Thomas takes a wash at the shed.",
        "Pop out — check if it's still raining.",
        "The TV is feeling overworked.",
    ]

    @FocusState private var focused: Bool
    @State private var saying: String = sayings.randomElement() ?? sayings[0]

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()

            VStack(spacing: 26) {
                Image(systemName: "cup.and.saucer.fill")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(.white.opacity(0.9))
                    .symbolRenderingMode(.hierarchical)

                Text("Time for a break.")
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

// MARK: - British empty-state copy

enum BritishEmpty {
    static let noVideos: [String] = [
        "No videos yet — engineering works in progress",
        "Signal failure at the next station",
        "We apologise for the delay",
        "Awaiting clearance from control",
        "All quiet on the line",
        "Service suspended — try another platform",
        "The depot's gone home for the day",
        "Wagons due in shortly",
        "No arrivals scheduled",
        "Held at the home signal",
        "Track unavailable — awaiting clearance",
        "All trains diverted, none due",
        "Engineering works at this station",
    ]

    static let noChannels: [String] = [
        "Platform empty — ask Dad for a channel",
        "No services on this line",
        "Roster's bare. Ask Dad?",
        "Awaiting timetable from control",
        "Nothing scheduled. Ask Dad for a platform.",
        "Depot still asleep. Try Dad.",
        "Empty platform — ask Dad to add a service.",
        "No services listed. Speak with the stationmaster.",
    ]

    /// Pick deterministically by day so the copy stays stable within
    /// a session but cycles across days.
    static func pick(_ options: [String]) -> String {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        return options[day % options.count]
    }
}
