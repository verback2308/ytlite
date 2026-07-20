import UIKit

// MARK: - Data & Actions

extension ChannelViewController {
    func applyChannelInfo(_ info: ChannelInfo) {
        // Keep the About sheet in sync — it reads the page's info.
        currentChannelPage?.info = info
        headerView.update(with: info, fallback: initialChannelName)
        title = info.title.isEmpty ? initialChannelName : info.title
        updateInfoBarButton(for: info)
    }

    func applyChannelPage(_ page: ChannelPage) {
        currentChannelPage = page
        headerView.update(
            with: page.info, fallback: initialChannelName
        )
        title = page.info.title.isEmpty
            ? initialChannelName : page.info.title
        applyPageSubscription(page)
        updateInfoBarButton(for: page.info)
        let enriched = page.withChannelAvatars()
        cache.setChannelPage(enriched, channelId: channelId)
        cache.setChannelInfo(page.info, channelId: channelId)
        setPage(enriched.videosPage)
        errorLabel.isHidden = videoCount > 0
        if let cv = collectionView {
            handleScroll(cv)
        }
    }

    func applyPageSubscription(_ page: ChannelPage) {
        let txt = page.subscribeButtonText
            ?? (page.isSubscribed ? "已订阅" : "订阅")
        headerView.updateSubscription(
            title: txt, isEnabled: !OAuthClient.shared.isAnonymous
        )
        isSubscribed = page.isSubscribed
        headerView.applyTheme(isSubscribed: isSubscribed)
    }

    @objc
    func showAbout() {
        guard let page = currentChannelPage
        else {
            return
        }
        let vc = ChannelAboutViewController(page: page)
        let nav = RotatingNavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    @objc
    func subscribeButtonTapped() {
        let wasSubscribed = isSubscribed
        isSubscribed = !wasSubscribed
        updateSubscribeUI(subscribed: isSubscribed, enabled: false)
        let handler = buildCompletion(wasSubscribed: wasSubscribed)
        if wasSubscribed {
            engagementClient.unsubscribeFromChannel(
                channelId: channelId,
                completion: handler
            )
        } else {
            engagementClient.subscribeToChannel(
                channelId: channelId,
                completion: handler
            )
        }
    }

    func buildCompletion(
        wasSubscribed: Bool
    ) -> (Result<Void, Error>) -> Void {
        { [weak self] result in
            DispatchQueue.main.async {
                self?.handleSubscribeResult(
                    result,
                    wasSubscribed: wasSubscribed
                )
            }
        }
    }

    func handleSubscribeResult(
        _ result: Result<Void, Error>,
        wasSubscribed: Bool
    ) {
        updateSubscribeUI(subscribed: isSubscribed, enabled: true)
        switch result {
        case .success:
            let act = wasSubscribed ? "退订" : "订阅"
            AppLog.subscribe("\(act) channelId=\(channelId)")
        case .failure(let error):
            let act = wasSubscribed ? "退订" : "订阅"
            AppLog.subscribe(
                "\(act) failed channelId=\(channelId): \(error)"
            )
            isSubscribed = wasSubscribed
            updateSubscribeUI(
                subscribed: wasSubscribed,
                enabled: true
            )
        }
    }

    func updateSubscribeUI(
        subscribed: Bool,
        enabled: Bool
    ) {
        let txt = subscribed ? "已订阅" : "订阅"
        headerView.updateSubscription(
            title: txt,
            isEnabled: enabled
        )
        headerView.applyTheme(isSubscribed: subscribed)
    }
}
