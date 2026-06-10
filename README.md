# YTLite

A lightweight, privacy-focused YouTube client for iOS built entirely with UIKit. No ads, no tracking, no dependencies.

## Features

- **Video Playback** — HLS, DASH-to-HLS conversion, adaptive streaming
- **Background Audio** — Continue listening with the screen off
- **Picture-in-Picture** — Watch while using other apps
- **SponsorBlock** — Skip sponsored segments automatically
- **Return YouTube Dislike** — See dislike counts again
- **Subtitles** — Full subtitle/caption support with VTT parsing
- **Search & Browse** — Home feed, trending, channel pages, playlists
- **Subscriptions** — Follow channels with a local subscription feed
- **Watch History** — Track what you've watched with progress indicators
- **Autoplay** — Automatically play the next related video
- **Dark/Light Theme** — Manual theme switching via ThemeManager
- **Quality Selection** — Choose max video quality
- **Download** — Save videos for offline viewing

## Requirements

- iOS 12.0+
- Xcode 16+
- No external dependencies (no CocoaPods, no SPM packages)

## Building

```bash
git clone https://github.com/user/YTLite.git
cd YTLite
open YTLite.xcodeproj
```

Select the **YTVLite** scheme, choose your device or simulator, and build (⌘B).

### IPA for sideloading

```bash
./make_ipa.sh
```

Produces a self-signed IPA installable via AltStore, TrollStore, or Filza (jailbroken).

## Architecture

```
YTLite/
├── API/              YouTube Innertube API client
├── Auth/             OAuth device-code flow
├── Common/           Shared UI components & utilities
├── Config/           URLs, UserDefaults keys, constants
├── Extensions/       Swift extensions
├── Features/
│   ├── Channel/      Channel page with tabs
│   ├── Home/         Home feed
│   ├── Library/      Playlists & saved videos
│   ├── Player/       Video player & watch page
│   ├── Profile/      User profile
│   ├── Search/       Search with suggestions
│   └── Subscriptions/ Subscription feed
└── Services/         Business logic & playback
```

### Key Design Decisions

- **Zero external dependencies** — Networking via `URLSession`, images via custom `ThumbnailImageView`, playback via `AVPlayer`
- **All UIKit, no SwiftUI** — Programmatic layout, no storyboards
- **iOS 12+ support** — No SF Symbols, no SwiftUI, no Combine
- **Manual JSON parsing** — `JSONSerialization` + dictionary traversal for YouTube Innertube API responses
- **Dependency injection** — `ServiceContainer` provides services; view controllers receive dependencies via initializers

### Playback Pipeline

The player supports multiple strategies selected automatically:

1. **HLS** — Native `AVPlayer` with YouTube HLS manifest (preferred)
2. **DASH → HLS** — Converts DASH SIDX segments into HLS playlists for `AVPlayer`
3. **Progressive** — Direct MP4 URL with fast-start reordering
4. **Onesie** — YouTube proprietary streaming as fallback

### Authentication

OAuth device-code flow: the app requests a device code → user enters it at google.com/device → tokens are stored in Keychain. Anonymous browsing is supported.

## Project Structure

| Component | Purpose |
|-----------|---------|
| `InnertubeClient` | YouTube API: browse, search, player, comments, subscriptions |
| `PlaybackFacade` | Orchestrates playback strategy selection and player setup |
| `VideoPlayerView` | Custom player UI with controls, gestures, PiP |
| `WatchViewController` | Watch page: player + metadata + comments + related |
| `AppCache` | Dual-layer cache (memory + disk) with TTL |
| `SponsorBlockController` | SponsorBlock API integration |
| `ThemeManager` | App-wide theming (dark/light) |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

Please follow the existing code style. SwiftLint is configured and runs as a build phase.

## Legal

This project is for educational and personal use. It is not affiliated with, endorsed by, or connected to Google or YouTube. Use at your own risk.

## License

MIT
