import SwiftUI

struct ProfileSwitcher: View {
    @Bindable var app: AppState
    @FocusState private var focused: Bool

    var body: some View {
        if app.profiles.count <= 1 {
            EmptyView()
        } else {
            Menu {
                ForEach(app.profiles) { profile in
                    Button(profile.name) {
                        Task { await app.switchProfile(profile) }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 17, weight: .medium))
                    Text(app.currentProfile?.name ?? "Profiles")
                        .font(.system(size: 18, weight: .medium))
                }
                .foregroundStyle(.white.opacity(focused ? 1.0 : 0.75))
                .frame(height: 52)
                .padding(.horizontal, 22)
                .background(
                    Capsule(style: .continuous)
                        .fill(.white.opacity(focused ? 0.12 : 0.05))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(focused ? 0.28 : 0.09), lineWidth: 1)
                )
            }
            .menuStyle(.borderlessButton)
            .focused($focused)
            .focusEffectDisabled()
        }
    }
}
