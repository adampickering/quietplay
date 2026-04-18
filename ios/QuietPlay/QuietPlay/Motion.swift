import SwiftUI
import UIKit

/// Shared motion system. Centralizing these makes the whole app feel
/// cohesive and lets us honor the system's Reduce Motion preference from
/// a single place: every `.animation(Motion.focusSpring, value: …)` call
/// site degrades gracefully to a flat fade when the accessibility flag
/// is on — no per-view @Environment boilerplate.
enum Motion {
    /// Flat fade used when Reduce Motion is enabled, and for overlays
    /// that should feel calm regardless.
    static let calmFade: Animation = .easeInOut(duration: 0.18)

    /// Apple-ish spring for card focus / press lifts. Honors Reduce
    /// Motion automatically.
    @MainActor
    static var focusSpring: Animation {
        UIAccessibility.isReduceMotionEnabled
            ? calmFade
            : .spring(response: 0.38, dampingFraction: 0.72)
    }
}

extension Color {
    /// Deterministic, quiet ambient tint for a channel. Picks a stable
    /// hue from the UUID; very low saturation/brightness so the
    /// background stays dark and never fights the thumbnails.
    static func ambientTint(for channelID: UUID) -> Color {
        var hasher = Hasher()
        hasher.combine(channelID)
        let h = Double(UInt(truncatingIfNeeded: hasher.finalize()) % 360) / 360.0
        return Color(hue: h, saturation: 0.28, brightness: 0.14)
    }
}
