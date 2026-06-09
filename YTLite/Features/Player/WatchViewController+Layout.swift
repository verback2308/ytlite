// swiftlint:disable file_length
import UIKit

extension WatchViewController {
    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        adjustForFloatingNavBar()
    }

    func setupNavigationBar() {
        let theme = ThemeManager.shared
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = theme.surface
            appearance.titleTextAttributes = [.foregroundColor: theme.primaryText]
            navigationItem.standardAppearance = appearance
            // UINavigationBar.scrollEdgeAppearance is iOS 13+; without it the bar
            // becomes transparent when the scroll view is at the top (iOS 15+ default),
            // which makes the player appear to overlap the Dynamic Island.
            navigationController?.navigationBar.scrollEdgeAppearance = appearance
            if #available(iOS 15.0, *) {
                navigationItem.scrollEdgeAppearance = appearance
            }
        } else {
            let navBar = navigationController?.navigationBar
            navBar?.barTintColor = theme.surface
            navBar?.isTranslucent = false
            navBar?.titleTextAttributes = [.foregroundColor: theme.primaryText]
        }
        let bar = navigationController?.navigationBar
        bar?.tintColor = theme.isDark ? .white : theme.accent
        navigationController?.setNavigationBarHidden(false, animated: false)
        updateLeftBarButton()
    }
    func addNotificationObservers() {
        let nc = NotificationCenter.default
        let tn = ThemeManager.didChangeNotification
        let bg = UIApplication.didEnterBackgroundNotification
        let fg = UIApplication.willEnterForegroundNotification
        nc.addObserver(self, selector: #selector(applyTheme), name: tn, object: nil)
        nc.addObserver(self, selector: #selector(appDidEnterBackground), name: bg, object: nil)
        nc.addObserver(self, selector: #selector(appWillEnterForeground), name: fg, object: nil)
        // On iPhone the interface is portrait-locked; handle landscape fullscreen
        // by observing raw device orientation changes instead of relying on rotation.
        if UIDevice.current.userInterfaceIdiom != .pad {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            nc.addObserver(
                self,
                selector: #selector(handleDeviceOrientationChange),
                name: UIDevice.orientationDidChangeNotification,
                object: nil
            )
        }
    }
    func setupLayout() {
        setupScrollAndPlayer()
        setupPlayerOverlays()
        setupMetaViews()
        setupChannelViews()
        setupActionBar()
        setupCommentsSection()
        setupRelatedCollection()
        activateMetaConstraints()
        activateChannelConstraints()
        activateBottomConstraints()
        let sel = #selector(openChannel)
        channelAvatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: sel))
        channelNameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: sel))
    }
    func setupScrollAndPlayer() {
        [scrollView, playerContainer, sidebarContainer, contentView].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        scrollView.alwaysBounceVertical = true
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.panGestureRecognizer.cancelsTouchesInView = false
        scrollView.delegate = self
        [scrollView, playerContainer, sidebarContainer].forEach { view.addSubview($0) }
        scrollView.addSubview(contentView)
        let pc = playerContainer, sv = scrollView
        let sc = sidebarContainer, safe = view.safeAreaLayoutGuide
        scrollTrailingConstraint = sv.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        scrollToSidebarConstraint = sv.trailingAnchor.constraint(equalTo: sc.leadingAnchor)
        playerTopConstraint = pc.topAnchor.constraint(equalTo: safe.topAnchor)
        // Use safe area for leading so content respects rounded corners in iPhone landscape.
        // In portrait there is no horizontal safe area inset so this is equivalent to
        // view.leadingAnchor on both iPhone and iPad.
        playerLeadingConstraint = pc.leadingAnchor.constraint(equalTo: safe.leadingAnchor)
        playerTrailingConstraint = pc.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        playerToSidebarConstraint = pc.trailingAnchor.constraint(equalTo: sc.leadingAnchor)
        playerAspectConstraint = pc.heightAnchor.constraint(
            equalTo: pc.widthAnchor,
            multiplier: 9.0 / 16.0
        )
        scrollTopToPlayerConstraint = sv.topAnchor.constraint(equalTo: pc.bottomAnchor)
        sidebarTopConstraint = sc.topAnchor.constraint(equalTo: safe.topAnchor)
        // Respect right safe area so sidebar content clears the rounded corner on iPhone landscape.
        sidebarTrailingConstraint = sc.trailingAnchor.constraint(equalTo: safe.trailingAnchor)
        sidebarBottomConstraint = sc.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        sidebarWidthConstraint = sc.widthAnchor.constraint(equalToConstant: 340)
        activateScrollConstraints()
    }
    func activateScrollConstraints() {
        let cv = contentView, sv = scrollView
        let cl = sv.contentLayoutGuide, fl = sv.frameLayoutGuide
        NSLayoutConstraint.activate(
            [
                playerTopConstraint, playerLeadingConstraint,
                playerTrailingConstraint, playerAspectConstraint,
                scrollTopToPlayerConstraint, scrollTrailingConstraint,
                // Use safe area for leading to match playerLeadingConstraint so the
                // scroll content aligns with the player edge on iPhone landscape.
                sv.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                sv.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                cv.topAnchor.constraint(equalTo: cl.topAnchor),
                cv.leadingAnchor.constraint(equalTo: cl.leadingAnchor),
                cv.trailingAnchor.constraint(equalTo: cl.trailingAnchor),
                cv.bottomAnchor.constraint(equalTo: cl.bottomAnchor),
                cv.widthAnchor.constraint(equalTo: fl.widthAnchor)
            ].compactMap { $0 }
        )
    }
    func setupPlayerOverlays() {
        let ps = playerSpinner, sl = playerStatusLabel, pc = playerContainer
        [ps, sl].forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        ps.startAnimating()
        pc.addSubview(ps)
        sl.text = "Preparing video..."
        sl.textAlignment = .center
        sl.numberOfLines = 0
        sl.font = UIFont.systemFont(ofSize: 14)
        pc.addSubview(sl)
        NSLayoutConstraint.activate([
            ps.centerXAnchor.constraint(equalTo: pc.centerXAnchor),
            ps.centerYAnchor.constraint(equalTo: pc.centerYAnchor, constant: -10),
            sl.topAnchor.constraint(equalTo: ps.bottomAnchor, constant: 14),
            sl.leadingAnchor.constraint(equalTo: pc.leadingAnchor, constant: 24),
            sl.trailingAnchor.constraint(equalTo: pc.trailingAnchor, constant: -24)
        ])
    }
    func setupMetaViews() {
        let cv = contentView
        [titleLabel, metaLabel, descriptionLabel, descriptionButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: .semibold)
        titleLabel.numberOfLines = 0
        cv.addSubview(titleLabel)
        metaLabel.font = UIFont.systemFont(ofSize: 13)
        metaLabel.numberOfLines = 0
        cv.addSubview(metaLabel)
        descriptionLabel.font = UIFont.systemFont(ofSize: 13)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.isHidden = true
        cv.addSubview(descriptionLabel)
        descriptionButton.titleLabel?.font = UIFont.systemFont(ofSize: 12)
        descriptionButton.addTarget(self, action: #selector(toggleDescription), for: .touchUpInside)
        descriptionButton.setTitle("More", for: .normal)
        cv.addSubview(descriptionButton)
    }
    func setupChannelViews() {
        let cv = contentView
        [channelAvatarView, channelNameLabel, channelMetaLabel, subscribeButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        channelAvatarView.layer.cornerRadius = 22
        channelAvatarView.layer.masksToBounds = true
        channelAvatarView.isUserInteractionEnabled = true
        cv.addSubview(channelAvatarView)
        channelNameLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        channelNameLabel.isUserInteractionEnabled = true
        cv.addSubview(channelNameLabel)
        channelMetaLabel.font = UIFont.systemFont(ofSize: 12)
        channelMetaLabel.numberOfLines = 2
        cv.addSubview(channelMetaLabel)
        subscribeButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        subscribeButton.layer.cornerRadius = 18
        subscribeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 18, bottom: 10, right: 18)
        subscribeButton.isEnabled = !OAuthClient.shared.isAnonymous
        let sel = #selector(subscribeButtonTapped)
        subscribeButton.addTarget(self, action: sel, for: .touchUpInside)
        cv.addSubview(subscribeButton)
    }
    func setupActionBar() {
        actionBar.axis = .horizontal
        actionBar.distribution = .fillEqually
        actionBar.spacing = 8
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(actionBar)
        buildActionBarItems()
        shareButton.addTarget(self, action: #selector(shareTapped), for: .touchUpInside)
        likeButton.addTarget(self, action: #selector(likeTapped), for: .touchUpInside)
        dislikeButton.addTarget(self, action: #selector(dislikeTapped), for: .touchUpInside)
    }

    private func buildActionBarItems() {
        let items: [ActionBarItem] = [
            ActionBarItem(
                button: likeButton,
                icon: "icon_thumb_up",
                label: nil,
                countLabel: likeCountLabel
            ),
            ActionBarItem(
                button: dislikeButton,
                icon: "icon_thumb_down",
                label: nil,
                countLabel: dislikeCountLabel
            ),
            ActionBarItem(button: shareButton, icon: "icon_share", label: "Share"),
            ActionBarItem(button: saveButton, icon: "icon_bookmark", label: "Save"),
            ActionBarItem(button: downloadButton, icon: "icon_download", label: "Download")
        ]
        for item in items {
            actionBar.addArrangedSubview(
                makeActionItem(
                    btn: item.button,
                    iconName: item.icon,
                    staticLabel: item.label,
                    countLabel: item.countLabel
                )
            )
        }
    }
    func makeActionItem(
        btn: UIButton,
        iconName: String,
        staticLabel: String?,
        countLabel: UILabel? = nil
    ) -> UIStackView {
        if let img = UIImage(named: iconName) {
            let sz = CGSize(width: 22, height: 22)
            let rendered = UIGraphicsImageRenderer(size: sz).image { _ in
                img.draw(in: CGRect(origin: .zero, size: sz))
            }
            btn.setImage(rendered.withRenderingMode(.alwaysTemplate), for: .normal)
        }
        btn.tintColor = ThemeManager.shared.primaryText
        btn.translatesAutoresizingMaskIntoConstraints = false
        btn.heightAnchor.constraint(equalToConstant: 28).isActive = true
        let label = countLabel ?? UILabel()
        label.font = UIFont.systemFont(ofSize: 11)
        label.textAlignment = .center
        label.textColor = ThemeManager.shared.secondaryText
        label.text = staticLabel ?? "—"
        label.translatesAutoresizingMaskIntoConstraints = false
        let stack = UIStackView(arrangedSubviews: [btn, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }
    func setupCommentsSection() {
        let cv = contentView
        [commentsLabel, commentsStackView, loadMoreCommentsButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
        }
        commentsLabel.font = UIFont.systemFont(ofSize: 16, weight: .semibold)
        commentsLabel.text = "Comments"
        cv.addSubview(commentsLabel)
        commentsStackView.axis = .vertical
        commentsStackView.spacing = 12
        cv.addSubview(commentsStackView)
        loadMoreCommentsButton.contentHorizontalAlignment = .left
        loadMoreCommentsButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        loadMoreCommentsButton.setTitle("Load more comments", for: .normal)
        loadMoreCommentsButton.addTarget(
            self,
            action: #selector(loadMoreCommentsTapped),
            for: .touchUpInside
        )
        cv.addSubview(loadMoreCommentsButton)
    }
    func setupRelatedCollection() {
        let rv = relatedCollectionView
        rv.register(VideoCell.self, forCellWithReuseIdentifier: VideoCell.reuseId)
        rv.dataSource = self
        rv.delegate = self
        rv.translatesAutoresizingMaskIntoConstraints = false
        rv.isScrollEnabled = false
        // Disable automatic inset adjustment: in portrait the outer scroll view manages
        // all scrolling; in landscape the sidebar is already positioned below the nav bar
        // via safeAreaLayoutGuide, so automatic adjustment would add a redundant top inset
        // that pushes the first related video down or off-screen.
        rv.contentInsetAdjustmentBehavior = .never
        contentView.addSubview(rv)
        relatedHeightConstraint = rv.heightAnchor.constraint(equalToConstant: 0)
    }

    /// On iOS 26+ the navigation bar uses a floating "Liquid Glass" style that
    /// no longer contributes its height to `view.safeAreaInsets`.  When that
    /// happens the player appears behind the bar.  We detect the gap and
    /// compensate via `additionalSafeAreaInsets` so Auto Layout still works.
    func adjustForFloatingNavBar() {
        guard let navBar = navigationController?.navigationBar,
              !navBar.isHidden else {
            if additionalSafeAreaInsets.top != 0 {
                additionalSafeAreaInsets.top = 0
            }
            return
        }
        let navBarBottom = navBar.convert(
            CGPoint(x: 0, y: navBar.bounds.height),
            to: view
        ).y
        let systemTop = view.safeAreaInsets.top - additionalSafeAreaInsets.top
        let extra = max(0, navBarBottom - systemTop)
        if abs(additionalSafeAreaInsets.top - extra) > 0.5 {
            additionalSafeAreaInsets.top = extra
        }
    }
}

// MARK: - iPhone landscape rotation → auto-fullscreen
extension WatchViewController {
    @objc
    func handleDeviceOrientationChange() {
        let orientation = UIDevice.current.orientation
        guard let playerView = videoPlayerView else {
            return
        }
        if orientation.isLandscape, fullscreenSnapshot == nil {
            enterLandscapeFullscreen(playerView: playerView, orientation: orientation)
        } else if orientation == .portrait, isLandscapeFullscreen {
            exitLandscapeFullscreen(playerView: playerView)
        }
    }
}

struct ActionBarItem {
    let button: UIButton
    let icon: String
    let label: String?
    var countLabel: UILabel?
}
