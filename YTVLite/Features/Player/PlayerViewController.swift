import UIKit
import AVKit

class PlayerViewController: UIViewController {

    private let videoId: String
    private let proxy = ProxyClient()

    private let statusLabel = UILabel()
    private let spinner = UIActivityIndicatorView(style: .whiteLarge)

    init(videoId: String) {
        self.videoId = videoId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupLoadingUI()
        startPlayback()
    }

    private func setupLoadingUI() {
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()
        view.addSubview(spinner)

        statusLabel.text = "Starting download…"
        statusLabel.textColor = .lightGray
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -20),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 16),
            statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    private func startPlayback() {
        proxy.createSession(videoId: videoId) { [weak self] result in
            switch result {
            case .failure(let error):
                self?.showError(error.localizedDescription)
            case .success(let session):
                DispatchQueue.main.async {
                    self?.statusLabel.text = session.ready ? "Ready, loading player…" : "Downloading video…"
                }
                self?.proxy.waitUntilReady(session: session) { result in
                    switch result {
                    case .failure(let error):
                        self?.showError(error.localizedDescription)
                    case .success(let videoURL):
                        DispatchQueue.main.async {
                            self?.play(url: videoURL)
                        }
                    }
                }
            }
        }
    }

    private func play(url: URL) {
        spinner.stopAnimating()
        statusLabel.isHidden = true

        let player = AVPlayer(url: url)
        let playerVC = AVPlayerViewController()
        playerVC.player = player

        addChild(playerVC)
        playerVC.view.frame = view.bounds
        playerVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(playerVC.view)
        playerVC.didMove(toParent: self)

        player.play()
    }

    private func showError(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.spinner.stopAnimating()
            self?.statusLabel.text = "Error: \(message)"
            self?.statusLabel.textColor = .systemRed
        }
    }
}
