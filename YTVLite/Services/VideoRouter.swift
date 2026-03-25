import UIKit

final class VideoRouter {
    static let shared = VideoRouter()
    private init() {}

    private var watchVC: WatchViewController?

    func open(video: Video, from presenter: UIViewController) {
        if let existing = watchVC, existing.presentingViewController != nil {
            existing.loadVideo(video)
            return
        }
        let vc = WatchViewController(video: video)
        watchVC = vc
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .fullScreen
        let root = presenter.view.window?.rootViewController ?? presenter
        let target = root.presentedViewController ?? root
        target.present(nav, animated: true)
    }
}
