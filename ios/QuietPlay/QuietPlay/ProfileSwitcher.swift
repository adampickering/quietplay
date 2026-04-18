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
                        // AppState.switchProfile only resets state and
                        // updates currentProfile — LibraryView reacts
                        // via its .task(id: currentProfile?.id) modifier
                        // and fetches /library for the new profile.
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
