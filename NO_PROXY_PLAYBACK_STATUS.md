# No-Proxy Playback Status

Updated: 2026-03-19

## Goal

Убрать `ProxyClient` из playback path и добиться прямого воспроизведения YouTube stream'ов в `AVPlayer`/`SZAVPlayer`.

## Current State

Сейчас playback все еще не работает без proxy, но прогресс существенный:

- direct `/player` fetch работает
- `WebPoTokenService` уже успешно минтит реальные WebPO token'ы
- повторный `/player` запрос с `contentPoToken` тоже работает
- финальный `videoplayback` request все еще получает `403`

То есть текущий стоп-фактор уже не в BotGuard/WebPO minting, а в самом media request path.

## What Is Already Implemented

### 1. Direct playback flow in `WatchViewController`

Файл: [YTVLite/Features/Player/WatchViewController.swift](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Player/WatchViewController.swift)

- `startPlayback()` больше идет в `client.fetchDirectPlayback(...)`
- если есть `progressiveURL`, запускается `startDirectPlayback(_:)`
- минтятся два токена:
  - session-bound token по `visitorData`
  - content-bound token по `videoId`
- затем выполняется повторный `/player` запрос с `contentPoToken`
- в итоговый `videoplayback` URL дописывается `pot=<session token>`
- direct stream отдается в `SZAVPlayer`

### 2. `/player` now accepts `poToken`

Файл: [YTVLite/API/InnertubeClient.swift](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/API/InnertubeClient.swift)

- `fetchDirectPlayback(videoId:poToken:completion:)`
- `executeDirectPlayback(...)` теперь отправляет:

```json
{
  "serviceIntegrityDimensions": {
    "poToken": "..."
  }
}
```

### 3. Direct playback info carries `visitorData`

Файл: [YTVLite/API/Models/Video.swift](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/API/Models/Video.swift)

- `DirectPlaybackInfo` теперь содержит `visitorData`

### 4. Real WebPO minting service

Файл: [YTVLite/Services/WebPoTokenService.swift](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Services/WebPoTokenService.swift)

Сервис уже делает:

- hidden `WKWebView`
- `Waa/Create`
- BotGuard interpreter execution
- VM init
- snapshot
- native `GenerateIT` через `URLSession`
- final mint callback inside `WKWebView`

Важно: это уже не placeholder/cold-start fallback, а реальный minted path.

### 5. Vendored `SZAVPlayer`

Папка: [YTVLite/ThirdParty/SZAVPlayer](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/ThirdParty/SZAVPlayer)

Локальные изменения:

- отключаем disk cache через `disableDiskCache`
- подробные логи на content-info/data requests
- принудительный `Range: bytes=0-1` для initial probe

## Latest Confirmed Runtime Result

Источник: `logs/log.txt`

Подтверждено по свежему логу:

- `WebPoTokenService`:
  - `snapshot:signal:length:1`
  - `snapshot:signal:types:function`
  - `generate_it:native:status 200`
  - `mint:ok`
  - `mint success`
- это происходит дважды:
  - для `visitorData`
  - для `videoId`
- потом идет повторный:
  - `[Innertube] fetchDirectPlayback start: EvFkGIojoDE`
  - `/player` возвращает fresh direct URLs
- затем:
  - `[WatchViewController] direct URL prepared with pot`
  - `[SZAVPlayer] content info status EvFkGIojoDE: 403`
  - `[SZAVPlayer] content info response EvFkGIojoDE: mime=text/plain len=0 ranges=false`
  - `[WatchViewController] SZAVPlayer status: loading`
  - `[WatchViewController] SZAVPlayer status: loadingFailed`

## Main Conclusion

WebPO minting уже не является blocker.

Текущий blocker:

- `googlevideo` все еще режет media request `403`, даже когда:
  - `/player` был запрошен с `contentPoToken`
  - media URL содержит `pot=<session token>`

## Most Likely Remaining Causes

По текущему состоянию самые вероятные причины такие:

1. В media request не хватает обязательных headers
2. `TVHTML5` context для `/player` не подходит для этого playback path
3. `googlevideo` требует еще одну часть client identity помимо текущих `pot`/headers

## Best Next Step

Следующий pragmatic шаг:

1. Добавить в media requests `X-Goog-Visitor-Id: <visitorData>`
2. Явно залогировать весь набор request headers, который уходит в `SZAVPlayer`
3. Если `403` не уйдет, пробовать не `TVHTML5`, а другой `/player` client context:
   - `WEB`
   - `MWEB`

## Files Touched In This Work

- [YTVLite/API/InnertubeClient.swift](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/API/InnertubeClient.swift)
- [YTVLite/API/Models/Video.swift](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/API/Models/Video.swift)
- [YTVLite/Common/VideoCell.swift](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Common/VideoCell.swift)
- [YTVLite/Features/Player/WatchViewController.swift](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Player/WatchViewController.swift)
- [YTVLite/Services/WebPoTokenService.swift](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Services/WebPoTokenService.swift)
- [YTVLite/ThirdParty/SZAVPlayer](/Users/andrew/Projects/YTLite/YTVLite/YTVLite/ThirdParty/SZAVPlayer)

## Git/Workspace Snapshot

На момент сохранения статус был такой:

- modified:
  - `YTVLite/API/InnertubeClient.swift`
  - `YTVLite/API/Models/Video.swift`
  - `YTVLite/Common/VideoCell.swift`
  - `YTVLite/Features/Player/WatchViewController.swift`
- untracked:
  - `YTVLite/Services/WebPoTokenService.swift`
  - `YTVLite/ThirdParty/`

## If Work Resumes Later

Начинать стоит не с BotGuard, а сразу с media request debugging:

- проверить headers в `SZAVPlayer`
- добавить `X-Goog-Visitor-Id`
- сравнить response для `TVHTML5` vs `WEB` player context

WebPO/service-integrity слой уже доведен до рабочего состояния и не должен быть первой целью следующей сессии.
## March 19, 2026 Update

### User Priority
- The goal is not more diagnostics or incremental experiments.
- The goal is a final working no-proxy playback path.
- Do not keep iterating on dead branches once logs have already disproven them.

### What Is Now Considered Dead
- Direct progressive playback via `googlevideo` URL plus `pot` plus headers.
- Current SABR startup path using direct `videoplayback?...&sabr=1` POST startup requests.

These were measured repeatedly and are now considered disproven enough to stop spending time on them.

### Evidence
- `WebPO` minting succeeds.
- Progressive media request still returns `403` with `mime=text/plain`.
- SABR startup request still returns `403 application/vnd.yt-ump`.
- Startup response contains no usable session state:
  - `playbackCookie=0`
  - `activeContexts=[]`
  - `nextPolicy=false`

This means the current SABR startup request is rejected before the server gives us any usable SABR session state.

### Instruction For Next Agent
- Do not keep tweaking the current `videoplayback?sabr=1` startup flow.
- Do not keep tweaking progressive playback headers/params.
- Move to a different startup protocol path, closer to `onesie/initplayback` / reference startup flow from `googlevideo` and `kira`.
- Use references first, not guesswork.

### Tone / Collaboration Note
- The user explicitly does not want repeated partial “progress” updates without a working result.
- The user expects reference-driven engineering, not endless trial-and-error.
