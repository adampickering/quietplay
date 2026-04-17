import SwiftUI

struct ProfileSwitcher: View {
    @Bindable var app: AppState

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
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle")
                    Text(app.currentProfile?.name ?? "Profiles")
                        .font(.system(size: 20, weight: .regular))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
            }
        }
    }
}
