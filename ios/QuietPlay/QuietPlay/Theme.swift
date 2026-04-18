import SwiftUI

/// Centralized design tokens. Every color, typography size, spacing, corner
/// radius, and motion duration used across the app should live here so
/// brand tweaks happen in one file instead of hunted across views.
enum Theme {

    // MARK: Palette

    enum Palette {
        /// Apple-blue, used for the "new videos" dot on channel rows.
        static let accentNew = Color(red: 0.039, green: 0.518, blue: 1.0)

        /// Apple-green, used for the watched checkmark badge.
        static let accentWatched = Color(red: 0.20, green: 0.78, blue: 0.35)

        static let base = Color.black
        static let baseTop = Color(red: 0.045, green: 0.045, blue: 0.05)

        /// Dim whites used for secondary text and inactive states.
        static let dimWhite72 = Color.white.opacity(0.72)
        static let dimWhite55 = Color.white.opacity(0.55)
        static let dimWhite40 = Color.white.opacity(0.40)

        /// Hairline/divider on dark backgrounds.
        static let divider = Color.white.opacity(0.08)
    }

    // MARK: Typography

    enum FontSize {
        static let xs: CGFloat = 13
        static let sm: CGFloat = 15
        static let md: CGFloat = 17
        static let lg: CGFloat = 19
        static let xl: CGFloat = 22
        static let xxl: CGFloat = 30
        static let xxxl: CGFloat = 34
        static let display: CGFloat = 36
    }

    // MARK: Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
        static let xxxl: CGFloat = 56
    }

    // MARK: Shape

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 10
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        static let xxl: CGFloat = 22
    }
}
