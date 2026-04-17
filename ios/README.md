# QuietPlay tvOS app

Swift sources only. Create the Xcode project locally:

1. Xcode → New Project → **tvOS** → **App**.
   - Product Name: `QuietPlay`
   - Interface: SwiftUI
   - Language: Swift
   - Minimum tvOS: **17.0**
   - Save inside `ios/` (so it sits next to these sources).
2. Delete Xcode's generated `ContentView.swift`, `QuietPlayApp.swift`, and `Assets.xcassets` launch content if it conflicts.
3. Drag `QuietPlay/*.swift` and `Info.plist` into the target (Copy items off, Create groups).
4. In project settings → Info, set the app's Info.plist to the `QuietPlay/Info.plist` shipped here (or merge the `QuietPlayAPIBaseURL` key and `NSAppTransportSecurity` dict into the generated one).
5. Edit `QuietPlayAPIBaseURL` in `Info.plist` to point at your server (e.g. `http://<LAN-IP>:4000` for Simulator against a laptop-hosted server).
6. Build & Run on Apple TV Simulator.

## Verification checklist (per PRD)

- Cold launch goes straight into playback of the newest video.
- Swipe right / → advances; swipe left / ← retreats.
- Center click shows overlay; auto-dismisses after 3s.
- Play/Pause button toggles playback.
- Menu opens Library; Menu from Library returns to Stream.
- Selecting a video in Library plays it and continues from its global index.
- Killing the resolver: 5 resolver failures in 60s shows the degraded message.
- Switching profile in the overlay restarts playback at index 0.
