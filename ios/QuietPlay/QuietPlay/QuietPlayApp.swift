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

    enum Route: Hashable { case library }

    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            StreamView(app: app) {
                app.player.pause()
                path.append(.library)
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .library:
                    LibraryView(app: app) { video in
                        app.seed(toVideoID: video.youtubeVideoId)
                        path.removeAll()
                    }
                }
            }
        }
    }
}
