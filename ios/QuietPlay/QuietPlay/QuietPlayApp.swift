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
        NavigationStack(path: $path) {
            LibraryView(app: app) { video, channel in
                app.playInLibrary(video: video, channel: channel)
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
