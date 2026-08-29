import AVFoundation
import SwiftUI

@main
struct QuietPlayApp: App {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView(app: app)
                .task { await app.bootstrap() }
                .preferredColorScheme(.dark)
                .onChange(of: phase) { _, newPhase in
                    if newPhase == .background || newPhase == .inactive {
                        // Push whatever's in the telemetry queue before
                        // tvOS suspends us — otherwise last few minutes
                        // of watching never land on the server.
                        Task { await app.flushTelemetry() }
                    }
                }
        }
    }
}

struct RootView: View {
    @Bindable var app: AppState

    enum Route: Hashable { case stream }

    @State private var path: [Route] = []
    @State private var showTutorial: Bool = !TutorialFlag.hasSeen()
    /// Flips true after a minimum splash-display duration. The splash
    /// stays up until BOTH bootstrap is done AND this elapses, so fast
    /// launches don't flash the splash for half a frame.
    @State private var splashHoldElapsed: Bool = false

    var body: some View {
        ZStack {
            if !splashHoldElapsed || app.bootstrapState == .loading {
                SplashView()
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(nanoseconds: 2_200_000_000)
                        splashHoldElapsed = true
                    }
            } else {
                bootstrapContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.55), value: splashHoldElapsed)
        .animation(.easeInOut(duration: 0.55), value: app.bootstrapState)
        .animation(.easeInOut(duration: 0.25), value: app.profilePickerPresented)
        .animation(.easeInOut(duration: 0.25), value: showTutorial)
        .animation(.easeInOut(duration: 0.25), value: app.breakSuggested)
    }

    @ViewBuilder
    private var bootstrapContent: some View {
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

            // First-run tutorial: only after bootstrap finishes and the
            // user has an actual profile to look at. Dismiss persists to
            // UserDefaults so it never shows again on this device.
            if showTutorial, case .ready = app.bootstrapState,
               !app.profilePickerPresented {
                TutorialView {
                    TutorialFlag.markSeen()
                    showTutorial = false
                }
                .transition(.opacity)
            }

            // Two-hour watch-time nudge. Sits over everything —
            // library or playback — because that's the moment the kid
            // needs to hear it. Dismissing persists so we don't nag
            // twice in the same day.
            if app.breakSuggested {
                BreakModal(onDismiss: { app.dismissBreakSuggestion() })
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: app.bootstrapState)
        .animation(.easeInOut(duration: 0.25), value: app.profilePickerPresented)
        .animation(.easeInOut(duration: 0.25), value: showTutorial)
        .animation(.easeInOut(duration: 0.25), value: app.breakSuggested)
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
