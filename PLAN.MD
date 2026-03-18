# YouTube Client iOS — MVP Plan

## Project Overview

A native iOS YouTube client for iPad mini 2 (iOS 12.5.7), written in Swift 5 with UIKit.
The app uses a hardcoded OAuth token for MVP, fetches data via YouTube Data API v3 + Innertube API,
and plays video via a local proxy server (yt-dlp backend) that serves merged mp4 files.

---

## Constraints & Requirements

- **Target device**: iPad mini 2, iOS 12.5.7
- **Minimum deployment target**: iOS 12.0
- **Language**: Swift 5
- **UI framework**: UIKit only (no SwiftUI — requires iOS 13+)
- **No third-party dependencies** for MVP (no CocoaPods, no SPM packages)
- **Async pattern**: Completion handlers + `DispatchQueue.main.async` for UI updates
- **Architecture**: MVC (simple, no MVVM/Coordinator for MVP)

---

## Proxy Server Integration

The app does NOT fetch video directly from YouTube.
All video playback goes through a local proxy server.

- **Base URL**: configurable constant, e.g. `http://192.168.1.100:3000`
- **Endpoint**: `GET /video/{videoId}` → returns merged mp4 file
- **Required server behavior** (Claude Code must add this to server if missing):
  - Response headers must include:
    - `Content-Type: video/mp4`
    - `Content-Length: <total_file_size_in_bytes>`
    - `Accept-Ranges: bytes`
  - Must support HTTP Range requests (`Range: bytes=0-1023`)
  - mp4 file must have `moov atom` at the start (faststart):
    ```
    ffmpeg -i video.mp4 -i audio.mp4 -c copy -movflags +faststart output.mp4
    ```
  - Without `Content-Length` and faststart, AVPlayer treats stream as live broadcast
    (no seek, no duration). This must be fixed before testing playback.

---

## Authentication (MVP)

Use a hardcoded OAuth 2.0 access token. No login screen for MVP.

Store credentials in `Config.swift`:

```swift
enum Config {
    static let accessToken = "YOUR_ACCESS_TOKEN_HERE"
    static let proxyBaseURL = "http://192.168.1.100:3000"
}
```

To obtain a token manually:
1. Go to https://developers.google.com/oauthplayground
2. Select scopes: `https://www.googleapis.com/auth/youtube.readonly`
3. Exchange and copy the access token into `Config.swift`

Note: token expires in ~1 hour. For MVP this is acceptable.
Full OAuth flow (SFSafariViewController + refresh token) is out of scope for MVP.

---

## Project Structure

```
YouTubeClient/
├── YouTubeClient.xcodeproj
└── YouTubeClient/
    ├── App/
    │   ├── AppDelegate.swift
    │   └── SceneDelegate.swift          # not needed for iOS 12, omit
    ├── Config/
    │   └── Config.swift                 # tokens, URLs, constants
    ├── API/
    │   ├── APIClient.swift              # base HTTP client (URLSession wrapper)
    │   ├── YouTubeAPIClient.swift       # YouTube Data API v3 calls
    │   ├── InnertubeClient.swift        # Innertube API for home feed
    │   └── Models/
    │       ├── Video.swift              # shared video model
    │       ├── Channel.swift
    │       └── SearchResult.swift
    ├── Features/
    │   ├── Home/
    │   │   ├── HomeViewController.swift
    │   │   └── HomeCell.swift
    │   ├── Subscriptions/
    │   │   ├── SubscriptionsViewController.swift
    │   │   └── SubscriptionCell.swift
    │   ├── Search/
    │   │   ├── SearchViewController.swift
    │   │   └── SearchCell.swift
    │   └── Player/
    │       └── PlayerViewController.swift
    ├── Common/
    │   ├── VideoCell.swift              # reusable cell for video lists
    │   ├── ThumbnailImageView.swift     # async image loading
    │   └── MainTabBarController.swift
    └── Resources/
        ├── Assets.xcassets
        └── Info.plist
```

---

## Screens & Navigation

### Tab Bar (MainTabBarController)
Three tabs:
1. **Home** — home feed (recommendations)
2. **Subscriptions** — subscription feed
3. **Search** — search

### HomeViewController
- `UICollectionView` with vertical layout
- Each cell: thumbnail, title, channel name, view count
- On tap → push `PlayerViewController`
- Pagination: load more on scroll to bottom (nextPageToken)
- Data source: Innertube API `/youtubei/v1/browse` with `browseId: "FEwhat_to_watch"`

### SubscriptionsViewController
- `UITableView` or `UICollectionView`
- Shows videos from subscribed channels, sorted by date
- Data source: YouTube Data API v3
  - `GET /youtube/v3/subscriptions?part=snippet&mine=true&maxResults=50`
  - Then `GET /youtube/v3/search?channelId={id}&order=date&maxResults=10` per channel
  - Or use `GET /youtube/v3/activities?home=true&part=snippet,contentDetails`
- On tap → push `PlayerViewController`

### SearchViewController
- `UISearchBar` at top
- Results in `UITableView`
- Data source: `GET /youtube/v3/search?part=snippet&q={query}&type=video&maxResults=25`
- On tap → push `PlayerViewController`

### PlayerViewController
- Full screen `AVPlayerViewController` (system player UI, no custom controls needed for MVP)
- Receives `videoId: String` on init
- On `viewDidLoad`: constructs URL `{proxyBaseURL}/video/{videoId}`, creates `AVPlayer`, plays
- No background playback, no PiP, no Now Playing for MVP

---

## Data Models

### Video.swift
```swift
struct Video {
    let id: String
    let title: String
    let channelName: String
    let thumbnailURL: String
    let viewCount: String?
    let publishedAt: String?
    let duration: String?
}
```

### SearchResult.swift
```swift
struct SearchResult {
    let videoId: String
    let title: String
    let channelName: String
    let thumbnailURL: String
}
```

---

## API Layer

### APIClient.swift
Base HTTP client. All requests go through this.

```swift
class APIClient {
    func get(url: URL, headers: [String: String], completion: @escaping (Result<Data, Error>) -> Void)
    func post(url: URL, headers: [String: String], body: Data, completion: @escaping (Result<Data, Error>) -> Void)
}
```

- Uses `URLSession.shared`
- On error: calls completion with `.failure`
- On success: calls completion with `.success(data)`
- Does NOT dispatch to main thread — callers are responsible for that

### YouTubeAPIClient.swift
Wraps YouTube Data API v3. Base URL: `https://www.googleapis.com/youtube/v3`
Auth header: `Authorization: Bearer {Config.accessToken}`

Methods:
```swift
func fetchSubscriptionFeed(completion: @escaping (Result<[Video], Error>) -> Void)
func searchVideos(query: String, completion: @escaping (Result<[SearchResult], Error>) -> Void)
```

### InnertubeClient.swift
Wraps Innertube API for home feed. Base URL: `https://www.youtube.com/youtubei/v1`

POST `/browse` with body:
```json
{
  "context": {
    "client": {
      "clientName": "WEB",
      "clientVersion": "2.20231121.08.00"
    }
  },
  "browseId": "FEwhat_to_watch"
}
```

Auth header: `Authorization: Bearer {Config.accessToken}`

Methods:
```swift
func fetchHomeFeed(completion: @escaping (Result<[Video], Error>) -> Void)
```

Parsing Innertube response is complex. Focus on extracting from:
`contents.twoColumnBrowseResultsRenderer.tabs[0].tabRenderer.content
  .richGridRenderer.contents[].richItemRenderer.content.videoRenderer`

Fields to extract per video:
- `videoId`
- `title.runs[0].text`
- `thumbnail.thumbnails` → pick highest resolution
- `ownerText.runs[0].text` (channel name)
- `viewCountText.simpleText`

---

## Common Components

### ThumbnailImageView.swift
`UIImageView` subclass with async image loading via `URLSession`.
- Simple in-memory cache (`NSCache<NSString, UIImage>`)
- Shows placeholder while loading
- Cancels previous request if cell is reused

### VideoCell.swift
Reusable `UICollectionViewCell` for video lists:
- Thumbnail (16:9 aspect ratio)
- Title label (2 lines max)
- Channel name label
- View count label

---

## Info.plist Requirements

Add the following keys:
```xml
<!-- Allow HTTP to local proxy server -->
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
    <!-- If proxy is not on localhost but on LAN IP, also add: -->
    <key>NSExceptionDomains</key>
    <dict>
        <key>192.168.1.100</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

---

## Implementation Order

Claude Code should implement in this order to allow incremental testing:

1. **Project setup** — create Xcode project, folder structure, `Config.swift`
2. **APIClient.swift** — base HTTP layer, test with a simple GET
3. **Models** — `Video.swift`, `SearchResult.swift`
4. **MainTabBarController** — tab bar with 3 empty placeholder VCs
5. **PlayerViewController** — hardcode a test videoId, verify AVPlayer plays from proxy
6. **ThumbnailImageView + VideoCell** — reusable UI components
7. **SearchViewController** — simplest screen, YouTube Data API search
8. **SubscriptionsViewController** — YouTube Data API subscriptions
9. **HomeViewController** — Innertube API (most complex parsing, do last)
10. **Wire up navigation** — tap on any cell pushes PlayerViewController with correct videoId

---

## Known Issues & Notes

- **Innertube API response structure changes frequently**. If parsing returns 0 videos,
  log the raw JSON response and inspect the structure manually.
- **Access token expiry**: hardcoded token expires in ~1 hour. If API returns 401,
  the user needs to manually refresh the token in `Config.swift`.
- **LAN IP in Info.plist**: replace `192.168.1.100` with actual proxy server IP.
- **iOS 12 + Xcode**: set deployment target to 12.0. Use Xcode 14 or later.
  Do not use any API marked `@available(iOS 13, *)` without availability checks.
- **No Storyboards**: build all UI programmatically in code. Storyboards are error-prone
  when modified by AI agents.