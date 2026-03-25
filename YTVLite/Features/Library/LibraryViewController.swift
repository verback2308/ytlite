import UIKit

/// Main Library screen. On compact (iPhone portrait): shows a menu list, tapping pushes detail.
/// On regular width (iPad or landscape): shows sidebar + detail side by side.
final class LibraryViewController: UIViewController {

    // MARK: - Sections

    private enum Section: Int, CaseIterable {
        case history   = 0
        case downloads = 1
        case playlists = 2

        var title: String {
            switch self {
            case .history:   return "History"
            case .downloads: return "Downloads"
            case .playlists: return "Playlists"
            }
        }
        var icon: String {
            switch self {
            case .history:   return "clock.fill"
            case .downloads: return "arrow.down.circle.fill"
            case .playlists: return "list.bullet"
            }
        }
    }

    // MARK: - Child VCs (split layout only)

    private lazy var historyNavVC    = UINavigationController(rootViewController: HistoryViewController())
    private lazy var downloadsNavVC  = UINavigationController(rootViewController: DownloadsViewController())
    private lazy var playlistsNavVC  = UINavigationController(rootViewController: PlaylistsViewController())

    private var splitDetailVCs: [UINavigationController] {
        [historyNavVC, downloadsNavVC, playlistsNavVC]
    }

    private func makeCompactDetailVC(for section: Section) -> UIViewController {
        switch section {
        case .history:   return HistoryViewController()
        case .downloads: return DownloadsViewController()
        case .playlists: return PlaylistsViewController()
        }
    }

    // MARK: - Layout views

    private lazy var sidebarTable: UITableView = {
        if #available(iOS 13, *) {
            return UITableView(frame: .zero, style: .insetGrouped)
        } else {
            return UITableView(frame: .zero, style: .grouped)
        }
    }()
    private let detailContainer = UIView()

    private var sidebarWidthConstraint: NSLayoutConstraint?
    private var selectedSection: Section = .history
    private var isSplitLayout = false
    private var hasInitialLayout = false

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Library"
        setupLayout()
        applyTheme()
        NotificationCenter.default.addObserver(self, selector: #selector(applyTheme),
                                               name: ThemeManager.didChangeNotification, object: nil)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let wide = view.bounds.width > 600
        if wide != isSplitLayout || !hasInitialLayout {
            hasInitialLayout = true
            isSplitLayout = wide
            updateSidebarLayout()
        }
    }

    // MARK: - Layout

    private func setupLayout() {
        // Sidebar
        sidebarTable.register(UITableViewCell.self, forCellReuseIdentifier: "row")
        sidebarTable.dataSource = self
        sidebarTable.delegate   = self
        sidebarTable.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(sidebarTable)

        // Detail container — hidden by default until layout pass determines mode
        detailContainer.isHidden = true
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(detailContainer)

        sidebarWidthConstraint = sidebarTable.widthAnchor.constraint(equalToConstant: view.bounds.width)
        sidebarWidthConstraint?.isActive = true

        NSLayoutConstraint.activate([
            sidebarTable.topAnchor.constraint(equalTo: view.topAnchor),
            sidebarTable.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            sidebarTable.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            detailContainer.topAnchor.constraint(equalTo: view.topAnchor),
            detailContainer.leadingAnchor.constraint(equalTo: sidebarTable.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func updateSidebarLayout() {
        let sidebarWidth: CGFloat = isSplitLayout ? 260 : view.bounds.width
        sidebarWidthConstraint?.constant = sidebarWidth

        if isSplitLayout {
            // Show both panels
            detailContainer.isHidden = false
            showDetail(for: selectedSection, animated: false)
        } else {
            // Hide detail, show only sidebar (nav will push on tap)
            detailContainer.isHidden = true
            removeCurrentDetailChild()
        }
        view.layoutIfNeeded()
    }

    // MARK: - Detail presentation

    private var currentDetailChild: UIViewController?

    private func showDetail(for section: Section, animated: Bool) {
        if isSplitLayout {
            let vc = splitDetailVCs[section.rawValue]
            removeCurrentDetailChild()
            addChild(vc)
            vc.view.frame = detailContainer.bounds
            vc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            detailContainer.addSubview(vc.view)
            vc.didMove(toParent: self)
            currentDetailChild = vc
        } else {
            // Each push creates a fresh VC; AppCache ensures instant data restore.
            let vc = makeCompactDetailVC(for: section)
            navigationController?.pushViewController(vc, animated: animated)
        }
    }

    private func removeCurrentDetailChild() {
        currentDetailChild?.willMove(toParent: nil)
        currentDetailChild?.view.removeFromSuperview()
        currentDetailChild?.removeFromParent()
        currentDetailChild = nil
    }

    // MARK: - Theme

    @objc private func applyTheme() {
        let t = ThemeManager.shared
        view.backgroundColor = t.background
        sidebarTable.backgroundColor = t.background
        sidebarTable.separatorColor  = t.separator
        detailContainer.backgroundColor = t.background
        sidebarTable.reloadData()
    }
}

// MARK: - Sidebar DataSource / Delegate

extension LibraryViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        Section.allCases.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = Section(rawValue: indexPath.row)!
        let t = ThemeManager.shared
        let cell = tableView.dequeueReusableCell(withIdentifier: "row", for: indexPath)
        cell.textLabel?.text  = section.title
        cell.textLabel?.textColor = t.primaryText
        if #available(iOS 13, *) {
            cell.imageView?.image = UIImage(systemName: section.icon)?
                .withTintColor(UIColor(red: 1, green: 0, blue: 0, alpha: 1), renderingMode: .alwaysOriginal)
        }
        cell.backgroundColor  = t.surface
        cell.accessoryType    = isSplitLayout ? (selectedSection == section ? .checkmark : .none) : .disclosureIndicator
        cell.tintColor = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let section = Section(rawValue: indexPath.row)!
        selectedSection = section
        showDetail(for: section, animated: true)
        if isSplitLayout {
            tableView.reloadData()
        }
    }
}
