import UIKit

/// Library screen with a UISegmentedControl in the nav bar titleView.
/// Three embedded child nav controllers — no push/pop, instant switching.
final class LibraryViewController: UIViewController {
    // MARK: - Segments

    private enum Segment: Int, CaseIterable {
        case history   = 0
        case downloads = 1
        case playlists = 2

        var title: String {
            switch self {
            case .history:
                return "History"
            case .downloads:
                return "Downloads"
            case .playlists:
                return "Playlists"
            }
        }
    }

    private let dependencies: AppDependencies

    // MARK: - Child nav controllers

    private lazy var childNavVCs: [UINavigationController] = {
        let navs = [
            UINavigationController(
                rootViewController: HistoryViewController(
                    service: dependencies.historyService,
                    channelViewControllerFactory:
                        dependencies.makeChannelViewController
                )
            ),
            UINavigationController(rootViewController: DownloadsViewController()),
            UINavigationController(
                rootViewController: PlaylistsViewController(
                    service: dependencies.playlistService,
                    channelViewControllerFactory:
                        dependencies.makeChannelViewController
                )
            )
        ]
        navs.forEach { $0.setNavigationBarHidden(true, animated: false) }
        return navs
    }()

    // MARK: - UI

    private let segmentedControl = UISegmentedControl(
        items: Segment.allCases.map(\.title)
    )

    private let contentView = UIView()
    private var currentChild: UINavigationController?

    // MARK: - Lifecycle

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSegmentedControl()
        setupContentView()
        ToolbarManager.shared.install(in: self)
        applyTheme()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applyTheme),
            name: ThemeManager.didChangeNotification,
            object: nil
        )
        show(segment: .history, animated: false)
    }

    // MARK: - Setup

    private func setupSegmentedControl() {
        segmentedControl.selectedSegmentIndex = 0
        segmentedControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)
        // Size it to fit comfortably in the nav bar
        segmentedControl.sizeToFit()
        segmentedControl.frame.size.width = min(segmentedControl.frame.width, 360)
        navigationItem.titleView = segmentedControl
    }

    private func setupContentView() {
        contentView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Segment switching

    @objc
    private func segmentChanged() {
        let segment = Segment(rawValue: segmentedControl.selectedSegmentIndex) ?? .history
        show(segment: segment, animated: false)
    }

    private func show(segment: Segment, animated: Bool) {
        let newChild = childNavVCs[segment.rawValue]
        guard newChild !== currentChild else {
            return
        }

        // Remove old child
        if let old = currentChild {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
        }

        // Add new child
        addChild(newChild)
        newChild.view.frame = contentView.bounds
        newChild.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(newChild.view)
        newChild.didMove(toParent: self)
        currentChild = newChild
    }

    // MARK: - Theme

    @objc
    private func applyTheme() {
        let theme = ThemeManager.shared
        view.backgroundColor = theme.background
        contentView.backgroundColor = theme.background
        if #available(iOS 13, *) {
            segmentedControl.selectedSegmentTintColor = theme.accent
            segmentedControl.setTitleTextAttributes(
                [.foregroundColor: theme.primaryText],
                for: .normal
            )
            segmentedControl.setTitleTextAttributes(
                [.foregroundColor: UIColor.white],
                for: .selected
            )
        }
    }
}
