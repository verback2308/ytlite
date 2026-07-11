import Foundation

/// Default abstract-factory implementation: creates the concrete `VideoSource`
/// for a kind, injecting the shared Innertube `WatchService` into the ones that
/// need it.
struct DefaultVideoSourceFactory: VideoSourceFactory {
    let apiClient: WatchService

    func make(kind: VideoSourceKind) -> VideoSource {
        switch kind {
        case .androidVR:
            return AndroidVRSource(apiClient: apiClient)
        case .progressive:
            return ProgressiveSource(apiClient: apiClient)
        case .mwebPot:
            return MWebSource(apiClient: apiClient)
        }
    }
}
