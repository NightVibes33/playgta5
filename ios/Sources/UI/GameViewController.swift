import UIKit
import WebKit
import AVFoundation

final class GameViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let status = UILabel()
    private var initialLoad = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let controller = WKUserContentController()
        controller.add(self, name: "gtaDiagnostics")
        controller.addUserScript(WKUserScript(source: RuntimeDiagnostics.bootstrap,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        let back = UIButton(type: .system)
        back.setTitle("✕", for: .normal)
        back.tintColor = .white
        back.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        back.layer.cornerRadius = 12
        back.translatesAutoresizingMaskIntoConstraints = false
        back.addTarget(self, action: #selector(closeGame), for: .touchUpInside)
        view.addSubview(back)
        status.text = "Starting local runtime…"
        status.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        status.textColor = .white
        status.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)
        NSLayoutConstraint.activate([
            back.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            back.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            back.widthAnchor.constraint(equalToConstant: 44),
            back.heightAnchor.constraint(equalToConstant: 36),
            status.leadingAnchor.constraint(equalTo: back.trailingAnchor, constant: 12),
            status.centerYAnchor.constraint(equalTo: back.centerYAnchor),
            status.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -8)
        ])
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        AssetHTTPServer.shared.start { [weak self] result in
            switch result {
            case .success(let port):
                let options = UserDefaults.standard
                let fps = options.integer(forKey: "gtaios.fps") == 60 ? "0" : "30"
                let scale = options.double(forKey: "gtaios.scale")
                let actualScale = scale == 0 ? 0.65 : scale
                let urlString = "http://127.0.0.1:\(port)/?low=1&cores=2&nocache=1&log=1&fps=\(fps)&scale=\(actualScale)"
                if let url = URL(string: urlString) { self?.webView.load(URLRequest(url: url)) }
            case .failure(let error):
                self?.status.text = "Local server failed: \(error.localizedDescription)"
                LogStore.shared.write("boot", "Local server failure: \(error)")
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        ControllerManager.shared.onState = { [weak self] state in
            guard !state.isEmpty, let data = try? JSONSerialization.data(withJSONObject: state),
                  let json = String(data: data, encoding: .utf8) else { return }
            self?.webView?.evaluateJavaScript("window.__gtaNativePad && window.__gtaNativePad(\(json))")
        }
        ControllerManager.shared.onConnection = { [weak self] name in
            self?.status.text = name == "No controller" ? "Touch controls not yet implemented" : "Controller: \(name)"
        }
        ControllerManager.shared.begin()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        ControllerManager.shared.stop()
    }

    @objc private func closeGame() { navigationController?.popViewController(animated: true) }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        initialLoad = true
        status.text = "Checking CPU / WebGPU / shared-memory support"
        RuntimeDiagnostics.probe(webView)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                 withError error: Error) {
        status.text = error.localizedDescription
        LogStore.shared.write("boot", "WKWebView navigation error: \(error)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        status.text = "Web engine terminated — export logs"
        LogStore.shared.write("crashes", "WKWebView process terminated, likely runtime or memory pressure")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let details = message.body as? [String: Any] else { return }
        let kind = String(describing: details["type"] ?? "engine")
        let text = String(describing: details["detail"] ?? "")
        let channel = ["gpu", "shaders", "jit", "boot"].contains(kind) ? kind : "engine"
        LogStore.shared.write(channel, text)
        if kind == "gpu" || kind == "error" { status.text = text }
    }

    deinit { webView?.configuration.userContentController.removeScriptMessageHandler(forName: "gtaDiagnostics") }
}
