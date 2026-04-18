import AVFoundation
import SwiftUI

@main
struct QuietPlayApp: App {
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .task { await app.bootstrap() }
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @Bindable var app: AppState

    enum Route: Hashable { case stream }

    @State private var path: [Route] = []

    var body: some View {
        ZStack {
            switch app.bootstrapState {
            case .loading:
                SplashView()
                    .transition(.opacity)
            case .needsSetup:
                SetupView(adminURL: app.api.adminURL)
                    .transition(.opacity)
            case .error(let msg):
                RetryView(message: msg, onRetry: { app.retryBootstrap() })
                    .transition(.opacity)
            case .ready:
                if app.profilePickerPresented {
                    ProfilePickerView(profiles: app.profiles) { profile in
                        app.pickProfile(profile)
                    }
                    .transition(.opacity)
                } else {
                    libraryStack
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.bootstrapState)
        .animation(.easeInOut(duration: 0.25), value: app.profilePickerPresented)
    }

    private var libraryStack: some View {
        NavigationStack(path: $path) {
            LibraryView(app: app) { video, channel, allChannels in
                app.playInLibrary(video: video, channel: channel, allChannels: allChannels)
                if path.isEmpty { path.append(.stream) }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .stream:
                    StreamView(app: app) {
                        app.player.pause()
                        path.removeAll()
                    }
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }
    }
}
