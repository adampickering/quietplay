import SwiftUI
import UIKit

/// Circular avatar button in the header that opens the full-screen
/// "Who's watching?" picker on tap. Shows the current profile's photo
/// (matched by name to a bundled imageset like `ProfileHenry`), or
/// initials when no photo exists.
struct ProfileSwitcher: View {
    @Bindable var app: AppState
    @FocusState private var focused: Bool

    private static let size: CGFloat = 56

    var body: some View {
        if app.profiles.count <= 1 {
            EmptyView()
        } else {
            avatar
                .frame(width: Self.size, height: Self.size)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(.white.opacity(focused ? 0.55 : 0.18), lineWidth: focused ? 3 : 1.5)
                )
                .scaleEffect(focused ? 1.08 : 1.0)
                .contentShape(Circle())
                .focusable()
                .focusEffectDisabled()
                .focused($focused)
                .accessibilityLabel(Text("Switch profile"))
                .accessibilityAddTraits(.isButton)
                .onTapGesture {
                    // Reuse the existing cold-launch picker by flipping
                    // the flag QuietPlayApp already renders against.
                    app.profilePickerPresented = true
                }
                .animation(Motion.focusSpring, value: focused)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let photo {
            Image(uiImage: photo)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color.white.opacity(focused ? 0.16 : 0.08)
                Text(initials)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(focused ? 1.0 : 0.85))
            }
        }
    }

    private var photo: UIImage? {
        guard let name = app.currentProfile?.name else { return nil }
        let key = name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        guard !key.isEmpty else { return nil }
        return UIImage(named: "Profile\(key.capitalized)")
    }

    private var initials: String {
        guard let name = app.currentProfile?.name else { return "?" }
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map(String.init).joined()
        return (chars.isEmpty ? String(name.prefix(1)) : chars).uppercased()
    }
}
