import SwiftUI

/// Full-screen "your video is on its way" overlay, shown while we wait for
/// /resolve + AVPlayer readiness. A slowly-sweeping ring around a gently
/// breathing play glyph, plus a rotating deadpan quip ("Asking YouTube
/// nicely…"). Calm enough for bedtime, playful enough that the kid knows
/// the app is actually working.
struct LoadingView: View {
    let title: String?
    let channelTitle: String?

    @State private var pulse = false
    @State private var quipIndex: Int = Int.random(in: 0..<LoadingView.quips.count)

    fileprivate static let quips: [String] = [
        "Warming up the pixels…",
        "Asking YouTube nicely…",
        "Untangling the cables…",
        "Tuning the antenna…",
        "Buttering the popcorn…",
        "Fluffing the couch cushions…",
        "Waking the video gnomes…",
        "Shushing the commercials…",
        "Pressing play really hard…",
        "Rewinding in reverse…",
        "Polishing the lens…",
        "Feeding the hamster…",
    ]

    var body: some View {
        ZStack {
            // Soft dark wash — subtler than plain black; keeps the screen
            // from feeling like the app crashed during the 1-2s resolve.
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.06, blue: 0.08),
                    Color(red: 0.01, green: 0.01, blue: 0.02),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 34) {
                ringAndGlyph

                VStack(spacing: 12) {
                    if let title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    if let channelTitle, !channelTitle.isEmpty {
                        Text(channelTitle)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }

                    Text(Self.quips[quipIndex])
                        .font(.system(size: 19, weight: .regular, design: .rounded))
                        .italic()
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .id(quipIndex)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 6)),
                            removal: .opacity.combined(with: .offset(y: -6))
                        ))
                        .padding(.top, 10)
                }
                .multilineTextAlignment(.center)
                .padding(.horizontal, 80)
            }
        }
        .task {
            // Kick off the looping scale + rotation once.
            pulse = true
            // Rotate the quip every ~2.4s for the life of this view. The
            // .task modifier cancels this automatically when the loading
            // screen goes away, so no leaks.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                if Task.isCancelled { break }
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.35)) {
                        var next = quipIndex
                        while next == quipIndex && Self.quips.count > 1 {
                            next = Int.random(in: 0..<Self.quips.count)
                        }
                        quipIndex = next
                    }
                }
            }
        }
    }

    private var ringAndGlyph: some View {
        ZStack {
            // Faint background track.
            Circle()
                .stroke(.white.opacity(0.08), lineWidth: 2)
                .frame(width: 180, height: 180)

            // Slow sweeping arc — the "we're working on it" signal. Very
            // short arc so it reads as activity without feeling busy.
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(
                    .white.opacity(0.9),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round)
                )
                .frame(width: 180, height: 180)
                .rotationEffect(.degrees(pulse ? 360 : 0))
                .animation(
                    .linear(duration: 1.6).repeatForever(autoreverses: false),
                    value: pulse
                )

            // Soft breathing glow behind the glyph.
            Circle()
                .fill(.white.opacity(0.06))
                .frame(width: pulse ? 150 : 120, height: pulse ? 150 : 120)
                .blur(radius: 20)
                .animation(
                    .easeInOut(duration: 1.8).repeatForever(autoreverses: true),
                    value: pulse
                )

            Image(systemName: "play.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .scaleEffect(pulse ? 1.06 : 0.96)
                .animation(
                    .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: pulse
                )
        }
    }
}
