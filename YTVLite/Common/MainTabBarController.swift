import UIKit

class MainTabBarController: UITabBarController {

    override func viewDidLoad() {
        super.viewDidLoad()

        let home = UINavigationController(rootViewController: HomeViewController())
        home.tabBarItem = UITabBarItem(title: "Home", image: nil, tag: 0)

        let subs = UINavigationController(rootViewController: SubscriptionsViewController())
        subs.tabBarItem = UITabBarItem(title: "Subscriptions", image: nil, tag: 1)

        let search = UINavigationController(rootViewController: SearchViewController())
        search.tabBarItem = UITabBarItem(tabBarSystemItem: .search, tag: 2)

        viewControllers = [home, subs, search]
    }
}

// Temporary placeholder — will be replaced in later steps
class PlaceholderViewController: UIViewController {

    private let labelText: String

    init(title: String) {
        self.labelText = title
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let label = UILabel()
        label.text = labelText
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])

        // Test button — tap to play a hardcoded video via proxy
        let button = UIButton(type: .system)
        button.setTitle("Test Player", for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = UIColor.red.withAlphaComponent(0.8)
        button.layer.cornerRadius = 8
        button.contentEdgeInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addTarget(self, action: #selector(testPlayer), for: .touchUpInside)
        view.addSubview(button)
        NSLayoutConstraint.activate([
            button.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            button.topAnchor.constraint(equalTo: label.bottomAnchor, constant: 24),
        ])
    }

    @objc private func testPlayer() {
        let player = PlayerViewController(videoId: "dQw4w9WgXcQ")
        navigationController?.pushViewController(player, animated: true)
    }
}
