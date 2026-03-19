import UIKit
import WebKit

final class ManifestWebPlayerView: UIView, WKNavigationDelegate, WKScriptMessageHandler {
    
    private let webView: WKWebView
    private var pendingManifestURL: URL?
    private var onError: ((String) -> Void)?
    
    override init(frame: CGRect) {
        let contentController = WKUserContentController()
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController = contentController
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        super.init(frame: frame)
        contentController.add(self, name: "playerEvent")
        backgroundColor = .black
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = .black
        webView.isOpaque = false
        webView.navigationDelegate = self
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError()
    }
    
    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "playerEvent")
    }
    
    func load(manifestURL: URL, onError: @escaping (String) -> Void) {
        pendingManifestURL = manifestURL
        self.onError = onError
        webView.loadHTMLString(Self.html, baseURL: nil)
    }
    
    func stop() {
        webView.evaluateJavaScript("window.stopPlayer && window.stopPlayer();", completionHandler: nil)
        webView.stopLoading()
        webView.navigationDelegate = nil
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let manifestURL = pendingManifestURL else { return }
        let escapedURL = manifestURL.absoluteString
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        webView.evaluateJavaScript("window.loadManifest && window.loadManifest(\"\(escapedURL)\");") { [weak self] _, error in
            if let error {
                self?.onError?("Manifest player init failed: \(error.localizedDescription)")
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError?("Manifest player navigation failed: \(error.localizedDescription)")
    }
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onError?("Manifest player load failed: \(error.localizedDescription)")
    }
    
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "playerEvent",
              let body = message.body as? [String: Any],
              let kind = body["kind"] as? String else {
            return
        }
        
        if kind == "error" {
            let details = body["message"] as? String ?? "Unknown manifest playback error"
            onError?(details)
        }
    }
    
    private static let html = """
<!doctype html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
  <style>
    html, body, video {
      margin: 0;
      padding: 0;
      width: 100%;
      height: 100%;
      background: #000;
      overflow: hidden;
    }
    video {
      object-fit: contain;
    }
  </style>
  <script src="https://cdn.jsdelivr.net/npm/shaka-player@4.12.6/dist/shaka-player.compiled.min.js"></script>
</head>
<body>
  <video id="video" playsinline autoplay controls></video>
  <script>
    let player = null;
    const video = document.getElementById('video');

    function post(kind, message) {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.playerEvent) {
        window.webkit.messageHandlers.playerEvent.postMessage({ kind, message });
      }
    }

    async function ensurePlayer() {
      if (player) return player;
      if (!window.shaka) {
        throw new Error('Shaka failed to load');
      }
      shaka.polyfill.installAll();
      player = new shaka.Player(video);
      player.addEventListener('error', (event) => {
        const detail = event && event.detail ? JSON.stringify(event.detail) : 'Unknown Shaka error';
        post('error', detail);
      });
      return player;
    }

    window.loadManifest = async function(url) {
      try {
        const activePlayer = await ensurePlayer();
        await activePlayer.load(url);
        await video.play();
      } catch (error) {
        post('error', error && error.message ? error.message : String(error));
      }
    };

    window.stopPlayer = async function() {
      try {
        if (player) {
          await player.destroy();
          player = null;
        }
        video.pause();
        video.removeAttribute('src');
        video.load();
      } catch (_) {}
    };
  </script>
</body>
</html>
"""
}
