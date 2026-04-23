import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

private let bgGradient = LinearGradient(
    colors: [Theme.Palette.baseTop, Theme.Palette.base],
    startPoint: .top,
    endPoint: .bottom
)

// MARK: - Splash

struct SplashView: View {
    @State private var pulse: Bool = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Branded splash artwork fills the whole frame. Subtle pulse
            // keeps it alive without fighting for attention.
            Image("LoadingSplash")
                .resizable()
                .renderingMode(.original)
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
                .ignoresSafeArea()
                .scaleEffect(pulse ? 1.012 : 1.0)
                .opacity(pulse ? 1.0 : 0.92)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

// MARK: - Retry (server unreachable)

struct RetryView: View {
    let message: String
    let onRetry: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            bgGradient.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 54, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Can't reach QuietPlay")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
                Text("Will keep trying every 30 seconds.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 12)

                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .medium))
                    Text("Try again")
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
                .onTapGesture(perform: onRetry)
                .animation(Motion.focusSpring, value: focused)
            }
        }
    }
}

// MARK: - First-launch setup (QR + URL)

struct SetupView: View {
    let adminURL: URL

    var body: some View {
        ZStack {
            bgGradient.ignoresSafeArea()
            VStack(spacing: 28) {
                Text("Welcome to QuietPlay")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .kerning(-0.3)

                Text("Scan to add channels")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(.white.opacity(0.6))

                if let qr = Self.generateQR(from: adminURL.absoluteString) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 360, height: 360)
                        .padding(24)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(.white)
                        )
                }

                VStack(spacing: 4) {
                    Text("Or open this URL on your computer")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(adminURL.absoluteString)
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, 8)
            }
            .padding(48)
        }
    }

    private static func generateQR(from text: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(text.data(using: .utf8), forKey: "inputMessage")
        filter.setValue("H", forKey: "inputCorrectionLevel")
        guard let raw = filter.outputImage else { return nil }
        let transform = CGAffineTransform(scaleX: 12, y: 12)
        let scaled = raw.transformed(by: transform)
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Profile picker (cold launch, 2+ profiles)

struct ProfilePickerView: View {
    let profiles: [Profile]
    let onPick: (Profile) -> Void

    var body: some View {
        ZStack {
            bgGradient.ignoresSafeArea()
            VStack(spacing: 40) {
                Text("Who's watching?")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)

                HStack(spacing: 36) {
                    ForEach(profiles) { profile in
                        ProfileCard(profile: profile, onPick: { onPick(profile) })
                    }
                }
            }
        }
    }
}

private struct ProfileCard: View {
    let profile: Profile
    let onPick: () -> Void
    @FocusState private var focused: Bool

    private var initials: String {
        let parts = profile.name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map(String.init).joined()
        return chars.isEmpty ? String(profile.name.prefix(1)) : chars
    }

    /// Look up a bundled profile photo by name: "Henry" → "ProfileHenry".
    /// Returns nil when no matching asset exists, which lets ProfileCard
    /// fall back to initials without an error.
    private var photo: UIImage? {
        let key = profile.name
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()
        guard !key.isEmpty else { return nil }
        return UIImage(named: "Profile\(key.capitalized)")
    }

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(focused ? 0.16 : 0.08)
                    Text(initials.uppercased())
                        .font(.system(size: 48, weight: .semibold))
                        .foregroundStyle(.white.opacity(focused ? 1.0 : 0.85))
                }
            }
            .frame(width: 180, height: 180)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .strokeBorder(.white.opacity(focused ? 0.55 : 0.15), lineWidth: focused ? 3 : 1.5)
            )
            .shadow(color: .black.opacity(focused ? 0.5 : 0.25), radius: focused ? 22 : 8, y: focused ? 12 : 4)

            Text(profile.name)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.white.opacity(focused ? 1.0 : 0.72))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onTapGesture(perform: onPick)
        .scaleEffect(focused ? 1.05 : 1.0)
        .animation(Motion.focusSpring, value: focused)
    }
}
