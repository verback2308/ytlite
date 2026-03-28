# Refactor Plan For Agents

## Purpose

This document is the execution brief for refactoring the `YTVLite` project.
It is based on a static code review of the repository and focuses on the seven highest-value problem areas:

1. HTTP layer accepts `4xx/5xx` as success.
2. Thumbnail disk cache keys are collision-prone.
3. Thumbnail network tasks are not cancelled on reuse.
4. `AppCache` performs synchronous disk I/O on hot UI paths.
5. Subscriptions feed performs expensive full-array resorting with repeated date parsing.
6. Dependency injection is only partial; the project still relies heavily on global `ServiceContainer` access.
7. Search requests are vulnerable to stale-result races.

This plan is intended to be given directly to coding agents. It is written to support parallel work where possible.

## Constraints

- Target: iOS 12.0+
- UIKit only
- No SwiftUI
- No external dependencies
- Keep current architecture direction where reasonable:
  layered structure, protocol-based services, no over-engineering
- Preserve current behavior unless the task explicitly changes error semantics or performance behavior
- Avoid broad rewrites without a measurable gain

## Primary Goals

- Fix correctness bugs in infrastructure.
- Reduce unnecessary CPU, memory, and network usage.
- Remove architectural bottlenecks that will slow future work.
- Keep refactors incremental and reviewable.

## Non-Goals

- Do not redesign the whole UI.
- Do not migrate the codebase to Swift Concurrency as part of this plan.
- Do not replace manual JSON parsing with Codable across the Innertube layer.
- Do not rewrite playback architecture unless a task explicitly targets a bounded slice.

## Workstreams

### Workstream 1: HTTP Layer Hardening

Priority: P0

Problem:
- `APIClient` currently treats any HTTP response body as success if `data` exists.
- This causes `401`, `403`, `429`, and `5xx` to leak into parsing paths as fake success cases.

Source references:
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/API/APIClient.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Subscriptions/SubscriptionsViewController.swift`

Required changes:
- Validate `HTTPURLResponse.statusCode` in both `get` and `post`.
- Introduce a stronger `APIError` contract with dedicated cases for:
  - `unauthorized`
  - `forbidden`
  - `rateLimited`
  - `serverError(code: Int)`
  - `transport(Error)`
  - `invalidResponse`
  - `noData`
  - `decodingFailed`
- Keep cancellation behavior silent for `NSURLErrorCancelled`.
- Centralize response validation so status handling is not duplicated.

Acceptance criteria:
- `401` maps to `APIError.unauthorized`.
- `403` maps to `APIError.forbidden` or equivalent explicit error.
- `429` maps to `APIError.rateLimited`.
- `5xx` maps to `serverError(code:)`.
- Parsing code no longer receives error response payloads as normal success data.

Suggested implementation notes:
- Add a shared internal response handler in `APIClient`.
- Keep the public call shape stable where possible to limit churn.

Parallelization:
- This should be completed before any agent depends on stable network error semantics.

### Workstream 2: Cancellation Model Cleanup

Priority: P0

Problem:
- Cancellation support exists but is inconsistently applied.
- Interactive flows can still race or waste work.

Source references:
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Common/CancellationToken.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Search/SearchViewController.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Common/ThumbnailImageView.swift`

Required changes:
- Define a consistent rule for which async operations accept `CancellationToken`.
- Ensure interactive request flows use cancellation when a newer request supersedes an older one.
- Preserve current silent-cancel behavior.

Acceptance criteria:
- Search can cancel stale requests.
- Image loading can cancel in-flight requests on reuse.
- No stale callback should overwrite newer state in the targeted screens.

Parallelization:
- Can be done in parallel with Workstream 1 only if the agent does not change `APIClient` signatures in incompatible ways.

### Workstream 3: Thumbnail Pipeline Refactor

Priority: P0

Problem:
- `ThumbnailImageView` does not cancel in-flight network tasks.
- Disk cache key generation is unsafe and can collide.
- Memory cache has no explicit sizing policy.

Source references:
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Common/ThumbnailImageView.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Common/VideoCell.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Subscriptions/SubscriptionVideoCell.swift`

Required changes:
- Add `private var task: URLSessionDataTask?` to `ThumbnailImageView`.
- Cancel the previous task in:
  - `setImage(url:)`
  - `cancel()`
  - any relevant reuse lifecycle
- Replace current filename generation with a stable hashed key derived from the full URL string.
- Add `NSCache` limits:
  - `countLimit`
  - optionally `totalCostLimit`
- If practical within scope, add image downsampling before caching in memory.

Acceptance criteria:
- Reused cells do not continue downloading obsolete thumbnails.
- Two long but distinct thumbnail URLs cannot collide on disk key generation.
- Scrolling large lists creates less bandwidth and memory churn.

Suggested implementation notes:
- Keep the API surface of `ThumbnailImageView` simple.
- Avoid changing all call sites unless necessary.

Parallelization:
- Independent from Workstream 4.
- Can be assigned to a separate agent.

### Workstream 4: AppCache Off-Main-Thread Refactor

Priority: P0

Problem:
- `AppCache` performs synchronous disk reads and writes on hot paths.
- `Data(contentsOf:)`, `JSONEncoder`, and `JSONDecoder` are used in ways that can block the main thread.

Source references:
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Services/AppCache.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Home/HomeViewController.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Subscriptions/SubscriptionsViewController.swift`

Required changes:
- Move disk I/O to a dedicated serial background queue.
- Expose async read APIs with completion handlers that return on the main queue.
- Keep memory reads cheap and synchronous if already resident.
- Consider bounded in-memory policy for:
  - `watchPages`
  - `channelPages`
  - `channelInfoMemory`

Acceptance criteria:
- No disk read/write should occur directly on main-thread hot paths.
- Feed screens can still show cached content quickly.
- Existing call sites remain readable and do not become callback spaghetti.

Suggested implementation notes:
- Prefer incremental API evolution over rewriting all cache consumers at once.
- Start with home/subscriptions/history paths.

Parallelization:
- Can be developed mostly independently.
- Coordinate carefully if another agent modifies feed screen loading logic.

### Workstream 5: Subscriptions Sorting Optimization

Priority: P1

Problem:
- `SubscriptionsViewController.appendPage(_:)` sorts the full array after each append.
- Relative date strings are reparsed repeatedly inside the sort comparator.

Source references:
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Subscriptions/SubscriptionsViewController.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Common/VideoFormatters.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/API/Models/Video.swift`

Required changes:
- Remove repeated date parsing inside the comparator.
- Introduce a precomputed sort key if sorting is actually required.
- If the feed already arrives in the correct order, remove the sort entirely.
- If sort is still required, reduce work:
  - precompute once per video
  - or merge sorted segments instead of full resort

Acceptance criteria:
- Pagination no longer reparses every existing item's date on each append.
- CPU usage during large subscriptions pagination is materially reduced.
- Ordering remains correct.

Parallelization:
- Safe to give to a separate agent.
- Should not overlap with a broad `Video` model redesign unless coordinated.

### Workstream 6: Dependency Injection Migration

Priority: P1

Problem:
- The project advertises protocol-driven architecture but still relies on global `ServiceContainer`.
- This makes testing, alternate compositions, and future multi-session support harder.

Source references:
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Services/ServiceContainer.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Home/HomeViewController.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Search/SearchViewController.swift`
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Subscriptions/SubscriptionsViewController.swift`

Required changes:
- Introduce a composition root near app startup.
- Pass service dependencies through initializers for selected screens.
- Keep `ServiceContainer` temporarily as a compatibility shim during migration.
- Remove direct uses of `ServiceContainer.video` in targeted screens.

Recommended migration order:
1. `HomeViewController`
2. `SearchViewController`
3. `SubscriptionsViewController`
4. other screens later

Acceptance criteria:
- Targeted screens can be constructed with explicit dependencies.
- `ServiceContainer.video` use is reduced or eliminated in migrated areas.
- No behavior regressions in navigation setup.

Suggested implementation notes:
- Do not try to migrate the whole app in one patch.
- Prefer bounded constructor injection over introducing a larger container abstraction.

Parallelization:
- Can happen in parallel with Workstream 5.
- Avoid overlapping ownership of the same view controllers.

### Workstream 7: Search Race Fix

Priority: P1

Problem:
- Search results can arrive out of order.
- Older requests may overwrite newer results.

Source references:
- `/Users/andrew/Projects/YTLite/YTVLite/YTVLite/Features/Search/SearchViewController.swift`

Required changes:
- Track the active search request.
- Cancel stale requests when a new search starts.
- Before applying results, verify they still match the active query.
- Preserve current UI behavior unless explicitly improved.

Acceptance criteria:
- Old queries cannot overwrite the latest query results.
- Pull-to-refresh still works correctly for the current query.
- Empty-query clearing behavior remains correct.

Suggested implementation notes:
- This can be implemented with `CancellationToken`.
- Do not introduce debounce unless explicitly requested.

Parallelization:
- Small, self-contained task.
- Can be grouped with Workstream 2 if one agent owns cancellation cleanup.

## Sequencing

Recommended execution order:

1. Workstream 1: HTTP Layer Hardening
2. Workstream 2: Cancellation Model Cleanup
3. Workstream 3: Thumbnail Pipeline Refactor
4. Workstream 4: AppCache Off-Main-Thread Refactor
5. Workstream 5: Subscriptions Sorting Optimization
6. Workstream 7: Search Race Fix
7. Workstream 6: Dependency Injection Migration

Rationale:
- Fix correctness and infrastructure first.
- Then remove the biggest performance waste.
- Then improve architecture once behavior is stable.

## Parallel Agent Split

If assigning to multiple agents, use this split:

- Agent A:
  Workstream 1
  Ownership:
  - `API/APIClient.swift`
  - small downstream adjustments caused by new error semantics

- Agent B:
  Workstream 3
  Ownership:
  - `Common/ThumbnailImageView.swift`
  - related cell integration only if needed

- Agent C:
  Workstream 4
  Ownership:
  - `Services/AppCache.swift`
  - bounded feed screen call-site updates

- Agent D:
  Workstream 5 and Workstream 7
  Ownership:
  - `Features/Subscriptions/SubscriptionsViewController.swift`
  - `Features/Search/SearchViewController.swift`
  - `Common/VideoFormatters.swift`
  - `API/Models/Video.swift` only if required for a sort key

- Agent E:
  Workstream 6
  Ownership:
  - `Services/ServiceContainer.swift`
  - app composition entry points
  - explicitly selected view controller initializers

## Rules For Agents

- Keep patches narrowly scoped to the assigned workstream.
- Do not revert unrelated local changes.
- Do not rewrite broad architecture unless required by the assigned task.
- Prefer incremental compatibility over sweeping cleanup.
- If touching shared files, minimize surface area and document the reasoning.
- If changing public method signatures, document downstream updates clearly.

## Definition Of Done

The refactor plan is complete when all of the following are true:

- HTTP status handling is explicit and correct.
- Cancellation prevents stale or obsolete async work from mutating UI state.
- Thumbnail loading no longer wastes bandwidth on reused cells.
- Disk cache key generation for images is collision-safe.
- `AppCache` no longer performs blocking disk work in hot main-thread paths.
- Subscriptions pagination avoids repeated full-array expensive sorting work.
- Search cannot show stale results from older queries.
- Selected screens no longer depend directly on global `ServiceContainer.video`.

## Suggested Delivery Strategy

Deliver in small PR-sized patches:

1. HTTP hardening
2. Image pipeline
3. Cache threading
4. Search and subscriptions performance
5. DI migration

Each patch should include:
- code changes
- risk summary
- behavior changes, if any
- manual verification notes

