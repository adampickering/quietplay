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
        // Overall canvas size. The bundled LoadingBase.png was drawn on a
        // 264-unit viewBox with the outer circle at radius 101.4 and a
        // stroke width of 18; the overlay arc is sized to match those
        // proportions exactly so it rides the rim of the painted circle.
        let canvas: CGFloat = 220
        let arcFrame: CGFloat = canvas * (101.4 * 2 / 264)   // ~169
        let arcStroke: CGFloat = canvas * (18 / 264)         // ~15

        return ZStack {
            // Soft breathing halo so the pane doesn't feel static while
            // the arc spins. Very low opacity so it never fights the
            // character illustration in the center.
            Circle()
                .fill(.white.opacity(0.05))
                .frame(width: pulse ? canvas * 0.82 : canvas * 0.66,
                       height: pulse ? canvas * 0.82 : canvas * 0.66)
                .blur(radius: 22)
                .animation(
                    .easeInOut(duration: 1.9).repeatForever(autoreverses: true),
                    value: pulse
                )

            Image("LoadingBase")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: canvas, height: canvas)

            // Spinning white arc. The base PNG has the arc removed so
            // this overlay is the only one the eye sees turning — no
            // double-arc ghosting.
            Circle()
                .trim(from: 0, to: 0.085)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: arcStroke, lineCap: .round)
                )
                .frame(width: arcFrame, height: arcFrame)
                .rotationEffect(.degrees(pulse ? 360 : 0))
                .animation(
                    .linear(duration: 1.4).repeatForever(autoreverses: false),
                    value: pulse
                )
        }
        .frame(width: canvas, height: canvas)
    }
}
