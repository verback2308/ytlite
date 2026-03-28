import UIKit

final class VideoRouter {
    static let shared = VideoRouter()

    var watchViewControllerFactory: ((Video) -> WatchViewController)?
    private var watchVC: WatchViewController?

    private init() {}

    func open(video: Video, from presenter: UIViewController) {
        if let existing = watchVC,
           existing.presentingViewController != nil {
            existing.loadVideo(video)
            return
        }
        guard let watchViewControllerFactory else {
            assertionFailure("VideoRouter is not configured")
            return
        }
        let vc = watchViewControllerFactory(video)
        watchVC = vc
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        let root = presenter.view.window?.rootViewController
            ?? presenter
        let target = root.presentedViewController ?? root
        target.present(nav, animated: true)
    }

    func clearCurrentWatch() {
        watchVC = nil
    }
}
