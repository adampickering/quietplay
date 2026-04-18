import SwiftUI

/// One-time onboarding shown on the first library load. Teaches the kid
/// (and any first-time user) how the Siri Remote drives the app.
struct TutorialView: View {
    let onDismiss: () -> Void

    @State private var step: Int = 0

    private struct Card {
        let icon: String
        let title: String
        let body: String
    }

    private let cards: [Card] = [
        Card(
            icon: "rectangle.portrait.on.rectangle.portrait.angled",
            title: "Pick a channel",
            body: "Scroll the left side to pick a channel, then press the center to start the newest video."
        ),
        Card(
            icon: "arrow.left.arrow.right",
            title: "Swipe to skip",
            body: "Swipe right to pick something else to watch, swipe left to go back a video."
        ),
        Card(
            icon: "arrow.uturn.backward",
            title: "Menu goes back",
            body: "Press the Menu button (or Esc) at any time to return to the library."
        ),
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()

            VStack(spacing: Theme.Spacing.xl) {
                Spacer(minLength: 0)

                Image(systemName: cards[step].icon)
                    .font(.system(size: 84, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: 120)
                    .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    .id(step)

                VStack(spacing: 14) {
                    Text(cards[step].title)
                        .font(.system(size: Theme.FontSize.xxxl, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(cards[step].body)
                        .font(.system(size: Theme.FontSize.md))
                        .foregroundStyle(Theme.Palette.dimWhite72)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 640)
                }

                HStack(spacing: 10) {
                    ForEach(0..<cards.count, id: \.self) { i in
                        Circle()
                            .fill(i == step ? Color.white : Color.white.opacity(0.25))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, Theme.Spacing.sm)

                TutorialButton(
                    title: step == cards.count - 1 ? "Got it" : "Next",
                    action: advance
                )

                Spacer(minLength: 0)
            }
            .padding(60)
        }
        .onExitCommand(perform: onDismiss)
        .animation(.easeInOut(duration: 0.2), value: step)
        .accessibilityAction(named: Text("Next")) { advance() }
    }

    private func advance() {
        if step == cards.count - 1 {
            onDismiss()
        } else {
            step += 1
        }
    }
}

private struct TutorialButton: View {
    let title: String
    let action: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        Text(title)
            .font(.system(size: Theme.FontSize.md, weight: .medium))
            .foregroundStyle(.white.opacity(focused ? 1.0 : 0.85))
            .padding(.horizontal, 36)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                    .fill(.white.opacity(focused ? 0.16 : 0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.xxl, style: .continuous)
                    .strokeBorder(.white.opacity(focused ? 0.32 : 0.12), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .animation(Motion.focusSpring, value: focused)
    }
}

enum TutorialFlag {
    private static let key = "com.quietplay.tutorialSeen.v1"

    static func hasSeen() -> Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func markSeen() {
        UserDefaults.standard.set(true, forKey: key)
    }
}
