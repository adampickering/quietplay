import SwiftUI
import UIKit

/// Shared motion system. Centralizing these makes the whole app feel
/// cohesive and lets us honor the system's Reduce Motion preference from
/// a single place.
enum Motion {
    /// The primary focus/press spring used for card lifts, button presses,
    /// and subtle hover feedback. Apple-ish: quick response, low bounce.
    static let focusSpring: Animation = .spring(response: 0.38, dampingFraction: 0.72)

    /// Shorter fade used for overlays and ambient transitions that should
    /// feel calm rather than springy.
    static let calmFade: Animation = .easeInOut(duration: 0.18)

    /// Respects the system's Reduce Motion setting: drops the spring's
    /// bounce when the user prefers it.
    @MainActor
    static var focusPreferred: Animation {
        UIAccessibility.isReduceMotionEnabled ? calmFade : focusSpring
    }
}

extension View {
    /// Apply the focus spring, falling back to a flat fade when the user
    /// has Reduce Motion enabled.
    func focusSpringAnimation<V: Equatable>(_ value: V, reduceMotion: Bool) -> some View {
        animation(reduceMotion ? .easeInOut(duration: 0.1) : Motion.focusSpring, value: value)
    }
}

/// Deterministic, quiet ambient tint for a channel. Picks a stable hue
/// from the UUID, with very low saturation and brightness so the
/// background stays dark and never fights the thumbnails.
func ambientTint(for channelID: UUID) -> Color {
    var hasher = Hasher()
    hasher.combine(channelID)
    let h = Double(UInt(truncatingIfNeeded: hasher.finalize()) % 360) / 360.0
    return Color(hue: h, saturation: 0.28, brightness: 0.14)
}
