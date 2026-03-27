# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build

This is an Xcode project (no SPM/CocoaPods). Build with:
```bash
xcodebuild -project YTVLite.xcodeproj -scheme YTVLite -sdk iphoneos build
```
Or open `YTVLite.xcodeproj` in Xcode and build (Cmd+B). Deployment target is **iOS 12.0**.

There are no tests or linting configured.

## iOS 12 Constraints

The app targets iOS 12+. Do not use:
- SF Symbols (iOS 13+) — use bundled image assets or UIKit built-ins
- `UIColor.systemBackground` / dynamic system colors (iOS 13+) — use `ThemeManager` colors
- `UIUserInterfaceStyle` / dark mode traits (iOS 13+) — theme is managed manually via `ThemeManager`
- Any API marked iOS 13+ or later without an `@available` guard

## Architecture

**Layered structure** under `YTVLite/`:

| Layer | Path | Purpose |
|-------|------|---------|
| **API** | `API/` | YouTube Innertube API client, request execution, JSON parsing |
| **Services** | `Services/` | Business logic: caching, playback routing, SABR/Onesie streaming, SponsorBlock, RYD |
| **Features** | `Features/` | View controllers organized by screen (Home, Search, Player, Channel, Library, Subscriptions, Profile) |
| **Common** | `Common/` | Shared UI (VideoCell, ThemeManager, MainTabBarController, SettingsVC) and utilities |
| **Auth** | `Auth/` | OAuth device-code flow, splash screen |
| **Config** | `Config/` | URLs, UserDefaults keys, app constants |
| **ThirdParty** | `ThirdParty/` | Vendored SZAVPlayer (AVPlayer wrapper with buffering/caching) |

### Key patterns

- **ServiceContainer** — singleton registry; `ServiceContainer.video` holds the `VideoService` (protocol implemented by `InnertubeClient`)
- **CancellationToken** — passed into async operations to silence stale in-flight requests on navigation
- **Manual JSON parsing** — Innertube responses are parsed with `JSONSerialization` + dictionary traversal (no Codable for API responses, no protobuf codegen)
- **All UI is UIKit** — no SwiftUI, no storyboards (programmatic layout)
- **Zero external dependencies** — networking via URLSession, images via custom `ThumbnailImageView`

### InnertubeClient structure

The Innertube API client is split across files:
- `InnertubeClient.swift` — main class, client contexts, method dispatch
- `InnertubeClientExecute.swift` — network request execution (browse, search, watchNext, player, comments, subscribe)
- `InnertubeClientParsing.swift` — shared parsing helpers (renderer extraction, video building)
- `InnertubeClientBrowseParsing.swift` — feed/browse response parsing
- `InnertubeClientSearchParsing.swift` — search result parsing
- `InnertubeContexts.swift` — request context definitions for 5 client types (web, android, tv, androidVR, ios)
- `DirectPlaybackClient.swift` — enum of client spoofing strategies for playback URLs

### Video playback pipeline

Multiple playback strategies, selected by `WatchViewController`:
1. **HLS** (preferred) — native AVPlayer with HLS manifest
2. **DASH → HLS** — `HLSGenerator` converts SIDX segments into HLS playlists (`ytv-hls://` scheme)
3. **FastStart** — `FastStartResourceLoader` reorders mp4 moov atom for instant playback (`faststart://` scheme)
4. **ManifestWebPlayerView** — WebKit-based DASH-MPD fallback
5. **SABR/Onesie** — YouTube proprietary adaptive streaming (probe → session → streaming)

`VideoPlayerView` (955 lines) provides the custom player UI with controls, SponsorBlock segment visualization, PiP, and gesture handling.

### Auth flow

OAuth device-code flow (`OAuthClient`): request device code → user enters code at google.com/device → poll for tokens → store in Keychain. Supports anonymous mode.

### Caching

`AppCache` provides dual-layer caching (in-memory + disk at `~/Library/Caches/FeedCache/`) with 1-hour TTL for home, subscriptions, history, and watch pages.
