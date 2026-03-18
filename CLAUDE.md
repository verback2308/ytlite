# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YTVLite is a native iOS YouTube client for iPad mini 2 (iOS 12.5.7), written in Swift 5 with UIKit. It fetches data via YouTube Data API v3 + Innertube API and plays video through a local proxy server (yt-dlp backend) that serves merged mp4 files.

## Build & Run

Build and run using Xcode only — no Makefile or CLI build scripts exist.

- Open `YTVLite.xcodeproj` in Xcode 14+
- Target device: iPad mini 2 (iOS 12.0 deployment target)
- Scheme: YTVLite
- No tests exist yet

## Key Constraints

- **UIKit only** — no SwiftUI (requires iOS 13+)
- **No third-party dependencies** — no CocoaPods, no SPM packages
- **Async pattern**: completion handlers + `DispatchQueue.main.async` for UI updates (no async/await — requires iOS 13+)
- **Architecture**: MVC
- **No Storyboards** — build all UI programmatically; only LaunchScreen.storyboard is kept
- **iOS 12 compatibility**: never use APIs marked `@available(iOS 13, *)` without availability checks; `@UIApplicationMain` is used (not `@main`)
- No SceneDelegate (deleted for iOS 12 compatibility)

## Architecture

### Planned Folder Structure

```
YTVLite/
├── App/            AppDelegate.swift
├── Config/         Config.swift — tokens, proxy URL constants
├── API/            APIClient.swift, YouTubeAPIClient.swift, InnertubeClient.swift
│   └── Models/     Video.swift, SearchResult.swift, Channel.swift
├── Features/
│   ├── Home/       HomeViewController + HomeCell (Innertube API)
│   ├── Subscriptions/  SubscriptionsViewController + SubscriptionCell
│   ├── Search/     SearchViewController + SearchCell
│   └── Player/     PlayerViewController (AVPlayerViewController)
└── Common/         VideoCell.swift, ThumbnailImageView.swift, MainTabBarController.swift
```

### Authentication

Hardcoded OAuth 2.0 access token stored in `Config.swift` (expires ~1 hour). If API returns 401, manually refresh token at https://developers.google.com/oauthplayground using scope `https://www.googleapis.com/auth/youtube.readonly`.

```swift
enum Config {
    static let accessToken = "YOUR_ACCESS_TOKEN_HERE"
    static let proxyBaseURL = "http://192.168.1.100:3000"  // replace with actual LAN IP
}
```

### API Layer

- **APIClient.swift** — base `URLSession` wrapper; does NOT dispatch to main thread, callers are responsible
- **YouTubeAPIClient.swift** — YouTube Data API v3 (`https://www.googleapis.com/youtube/v3`); auth via `Authorization: Bearer` header
- **InnertubeClient.swift** — Innertube API (`https://www.youtube.com/youtubei/v1`); POST `/browse` with `browseId: "FEwhat_to_watch"` for home feed; response structure changes frequently — if parsing returns 0 videos, log raw JSON and inspect manually

### Video Playback (Proxy Server)

Video is never fetched directly from YouTube. All playback goes through a local yt-quality-helper proxy (`server.mjs` at `/Users/andrew/Projects/yt-quality/Archive/server.mjs`).

**Session-based API** (implemented in `ProxyClient.swift`):
1. `POST /api/session` body `{"url": "https://youtube.com/watch?v=VIDEO_ID"}` → `{id, ready, videoUrl, playerPageUrl}`
2. Server downloads + merges the video in background via yt-dlp + ffmpeg (`-movflags +faststart`)
3. `GET /session/{id}/video.mp4` → 202 while downloading, 200 + mp4 stream when ready
4. `HEAD /session/{id}/video.mp4` → used for polling readiness

**PlayerViewController flow**: create session → poll HEAD until 200 → play `videoUrl` with AVPlayer. Server deduplicates by videoId (reuses sessions up to 2h TTL).

### Info.plist Requirements

Must include `NSAppTransportSecurity` to allow HTTP to the LAN proxy IP:

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>192.168.1.100</key>  <!-- replace with actual proxy IP -->
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

## Implementation Order

1. `Config.swift` → 2. `APIClient.swift` → 3. Models → 4. `MainTabBarController` → 5. `PlayerViewController` (verify proxy playback first) → 6. `ThumbnailImageView` + `VideoCell` → 7. `SearchViewController` → 8. `SubscriptionsViewController` → 9. `HomeViewController` (Innertube, most complex) → 10. Wire navigation
