import UIKit

final class PlayerPanelViewController: UIViewController, UIGestureRecognizerDelegate {
    let watchVC: WatchViewController
    private let navigationWrapper: RotatingNavigationController
    private lazy var expandedPanGesture: UIPanGestureRecognizer = makeExpandedPanGesture()
    private lazy var miniPanGesture: UIPanGestureRecognizer = makeMiniPanGesture()

    private(set) var isExpanded = true
    weak var miniBar: MiniPlayerBar? {
        didSet {
            oldValue?.removeGestureRecognizer(miniPanGesture)
            configureMiniBar()
        }
    }
    var onClose: (() -> Void)?

    init(watchVC: WatchViewController) {
        self.watchVC = watchVC
        navigationWrapper = RotatingNavigationController(rootViewController: watchVC)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.clipsToBounds = true
        installNavigationWrapper()
        view.addGestureRecognizer(expandedPanGesture)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        view.transform = isExpanded ? .identity : collapsedTransform()
    }

    func expand(animated: Bool) {
        isExpanded = true
        refreshMiniBar()
        let animations = {
            self.view.transform = .identity
            self.miniBar?.alpha = 0
            self.miniBar?.transform = .identity
        }
        let completion: (Bool) -> Void = { _ in
            self.miniBar?.isHidden = true
        }
        if animated {
            miniBar?.isHidden = false
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.curveEaseOut],
                animations: animations,
                completion: completion
            )
        } else {
            animations()
            completion(true)
        }
    }

    func collapse(animated: Bool) {
        isExpanded = false
        refreshMiniBar()
        miniBar?.transform = .identity
        miniBar?.alpha = 0
        miniBar?.isHidden = false
        let animations = {
            self.view.transform = self.collapsedTransform()
            self.miniBar?.alpha = 1
        }
        if animated {
            UIView.animate(
                withDuration: 0.25,
                delay: 0,
                options: [.curveEaseOut],
                animations: animations,
                completion: nil
            )
        } else {
            animations()
        }
    }

    func close() {
        watchVC.exitFullscreenIfNeeded()
        watchVC.videoPlayerView?.player?.pause()
        miniBar?.layer.removeAllAnimations()
        miniBar?.transform = .identity
        guard let tabBarController = parent as? MainTabBarController else {
            onClose?()
            return
        }
        tabBarController.removePlayerPanel(self)
        onClose?()
    }

    func refreshMiniBar() {
        let player = watchVC.videoPlayerView?.player
        let isPlaying = (player?.rate ?? 0) != 0
        miniBar?.update(
            title: watchVC.initialVideo.title,
            channel: watchVC.initialVideo.channelName,
            isPlaying: isPlaying,
            thumbnailURL: watchVC.initialVideo.thumbnailURL
        )
        miniBar?.attachPlayer(player)
        miniBar?.applyTheme()
    }
}

private extension PlayerPanelViewController {
    func installNavigationWrapper() {
        addChild(navigationWrapper)
        navigationWrapper.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(navigationWrapper.view)
        NSLayoutConstraint.activate([
            navigationWrapper.view.topAnchor.constraint(equalTo: view.topAnchor),
            navigationWrapper.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            navigationWrapper.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            navigationWrapper.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        navigationWrapper.didMove(toParent: self)
    }

    func configureMiniBar() {
        miniBar?.removeGestureRecognizer(miniPanGesture)
        miniBar?.onClose = { [weak self] in
            self?.close()
        }
        miniBar?.onTap = { [weak self] in
            self?.expand(animated: true)
        }
        miniBar?.addGestureRecognizer(miniPanGesture)
        refreshMiniBar()
    }

    func togglePlayback() {
        guard let player = watchVC.videoPlayerView?.player else {
            return
        }
        if player.rate == 0 {
            player.play()
        } else {
            player.pause()
        }
        refreshMiniBar()
    }

    func collapsedTransform() -> CGAffineTransform {
        let parentHeight = parent?.view.bounds.height ?? view.bounds.height
        return CGAffineTransform(translationX: 0, y: parentHeight)
    }

    func makeExpandedPanGesture() -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleExpandedPan(_:))
        )
        gesture.delegate = self
        return gesture
    }

    func makeMiniPanGesture() -> UIPanGestureRecognizer {
        let gesture = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleMiniPan(_:))
        )
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        return gesture
    }

    func isControlView(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UIControl {
                return true
            }
            current = candidate.superview
        }
        return false
    }

    @objc
    func handleExpandedPan(_ gesture: UIPanGestureRecognizer) {
        guard isExpanded else {
            return
        }
        let translationY = max(0, gesture.translation(in: view).y)
        let velocityY = gesture.velocity(in: view).y
        switch gesture.state {
        case .changed:
            view.transform = CGAffineTransform(translationX: 0, y: translationY)
        case .ended, .cancelled, .failed:
            if translationY > 120 || velocityY > 600 {
                collapse(animated: true)
            } else {
                expand(animated: true)
            }
        default:
            break
        }
    }

    @objc
    func handleMiniPan(_ gesture: UIPanGestureRecognizer) {
        guard !isExpanded, let miniBar else {
            return
        }
        let translationY = max(0, gesture.translation(in: miniBar).y)
        let velocityY = gesture.velocity(in: miniBar).y
        switch gesture.state {
        case .changed:
            miniBar.transform = CGAffineTransform(translationX: 0, y: translationY)
        case .ended, .cancelled, .failed:
            if translationY > 60 || velocityY > 600 {
                close()
            } else {
                UIView.animate(withDuration: 0.2) {
                    miniBar.transform = .identity
                }
            }
        default:
            break
        }
    }
}

extension PlayerPanelViewController {
    func gestureRecognizerShouldBegin(
        _ gestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        if gestureRecognizer === expandedPanGesture {
            guard isExpanded,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer
            else {
                return false
            }
            let velocity = pan.velocity(in: view)
            let location = pan.location(in: view)
            let touchedView = view.hitTest(location, with: nil)
            return abs(velocity.y) > abs(velocity.x)
                && velocity.y > 0
                && !isControlView(touchedView)
        }
        if gestureRecognizer === miniPanGesture {
            guard !isExpanded,
                  let bar = miniBar,
                  let pan = gestureRecognizer as? UIPanGestureRecognizer
            else {
                return false
            }
            let location = pan.location(in: bar)
            let velocity = pan.velocity(in: bar)
            let touchedView = bar.hitTest(location, with: nil)
            return abs(velocity.y) > abs(velocity.x)
                && velocity.y > 0
                && !isControlView(touchedView)
        }
        return true
    }
}
