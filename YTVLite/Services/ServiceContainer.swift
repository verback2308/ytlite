import Foundation

enum ServiceContainer {
    static let video: VideoService = InnertubeClient()
}
