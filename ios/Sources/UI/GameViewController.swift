import UIKit
import WebKit
import AVFoundation

/// Native iOS host for the original WebAssembly game runtime.
/// Performs a lightweight compatibility check before risking a multi-GB game boot.
final class GameViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    private let status = UILabel()
    private let closeButton = UIButton(type: .system)
    private let utilityButton = UIButton(type: .system)
    private let modeControl = UISegmentedControl(items: ["On Foot", "Driving", "Flying"])
    private var serverPort: UInt16?
    private var engineStarted = false
    private var preflightComplete = false
    private var alertVisible = false
    private var lastPadForward: TimeInterval = 0

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        let userContent = WKUserContentController()
        userContent.add(self, name: "gtaDiagnostics")
        userContent.addUserScript(WKUserScript(source: RuntimeDiagnostics.bootstrap,
            injectionTime: .atDocumentStart, forMainFrameOnly: false))
        let config = WKWebViewConfiguration()
        config.userContentController = userContent
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
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = UIColor.white.withAlphaComponent(0.9)
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        closeButton.layer.cornerRadius = 17
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(closeGame), for: .touchUpInside)
        view.addSubview(closeButton)
        utilityButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        utilityButton.tintColor = .white
        utilityButton.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        utilityButton.layer.cornerRadius = 17
        utilityButton.translatesAutoresizingMaskIntoConstraints = false
        utilityButton.addTarget(self, action: #selector(toggleUtilities), for: .touchUpInside)
        view.addSubview(utilityButton)

        modeControl.selectedSegmentIndex = 0
        modeControl.backgroundColor = UIColor.black.withAlphaComponent(0.82)
        modeControl.selectedSegmentTintColor = .darkGray
        modeControl.setTitleTextAttributes([.foregroundColor: UIColor.white], for: .normal)
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.addTarget(self, action: #selector(profileChanged), for: .valueChanged)
        modeControl.isHidden = true
        view.addSubview(modeControl)

        status.text = "Starting local asset server…"
        status.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        status.textColor = .white
        status.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        status.numberOfLines = 3
        status.textAlignment = .center
        status.layer.cornerRadius = 7
        status.clipsToBounds = true
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 7),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 7),
            closeButton.heightAnchor.constraint(equalToConstant: 34),
            closeButton.widthAnchor.constraint(equalToConstant: 34),
            utilityButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -7),
            utilityButton.topAnchor.constraint(equalTo: closeButton.topAnchor),
            utilityButton.heightAnchor.constraint(equalToConstant: 34),
            utilityButton.widthAnchor.constraint(equalToConstant: 34),
            modeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeControl.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 7),
            modeControl.widthAnchor.constraint(equalToConstant: 290),
            status.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -6),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.widthAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.widthAnchor, multiplier: 0.92),
            status.heightAnchor.constraint(greaterThanOrEqualToConstant: 30)
        ])
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        AssetHTTPServer.shared.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let port):
                self.serverPort = port
                self.startPreflight(port: port)
            case .failure(let error):
                self.showFailure("Could not start local HTTP server: " + error.localizedDescription)
                LogStore.shared.write("boot", "Local HTTP server failure: " + error.localizedDescription)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        GameOrientation.request(.landscape, from: view)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        ControllerManager.shared.onState = { [weak self] state in
            guard let self, self.engineStarted else { return }
            let now = Date.timeIntervalSinceReferenceDate
            // Preserve native 60Hz input sampling while bounding expensive WKWebView IPC.
            guard now - self.lastPadForward >= (1.0 / 30.0) || (state["connected"] ?? 0) == 0 else { return }
            self.lastPadForward = now
            guard let bytes = try? JSONSerialization.data(withJSONObject: state),
                  let json = String(data: bytes, encoding: .utf8) else { return }
            self.webView.evaluateJavaScript("window.__gtaNativePad && window.__gtaNativePad(\(json))")
        }
        ControllerManager.shared.onConnection = { name in
            LogStore.shared.write("controller", "Current controller: " + name)
        }
        ControllerManager.shared.begin()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ControllerManager.shared.stop()
    }

    private func startPreflight(port: UInt16) {
        guard let url = URL(string: "http://127.0.0.1:\(port)/ios/preflight.html") else {
            showFailure("Invalid local preflight URL"); return
        }
        status.text = "Checking WebAssembly, WebGPU and USB files…"
        LogStore.shared.write("boot", "Preflight started at " + url.absoluteString)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData))
        DispatchQueue.main.asyncAfter(deadline: .now() + 24) { [weak self] in
            guard let self, !self.preflightComplete, !self.alertVisible, self.view.window != nil else { return }
            self.showFailure("Runtime compatibility check timed out. Check the local server and iPhone WebKit diagnostics.")
        }
    }

    private func launchEngine() {
        guard !engineStarted, let port = serverPort, let url = EngineOptions.launchURL(port: port) else {
            return
        }
        engineStarted = true
        status.text = "Launching original GTA V engine…"
        LogStore.shared.write("boot", "Loading game runtime: " + url.absoluteString)
        webView.load(URLRequest(url: url))
    }

    private func onPreflight(_ raw: String) {
        guard !preflightComplete else { return }
        preflightComplete = true
        LogStore.shared.write("boot", "iPhone 16 runtime preflight: " + raw)
        guard let data = raw.data(using: .utf8),
              let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            showFailure("Runtime preflight result could not be decoded"); return
        }
        if result["ok"] as? Bool == true {
            // WebKit accepts a tiny memory64 allocation, but the real engine
            // still requires 3GiB initially. This is not proof of enough RAM.
            LogStore.shared.write("boot", "memory64 probe passed: 1 page, max 65536 pages; engine requires 49152 initial pages (3GiB)")
            launchEngine()
        } else {
            let failed = (result["failures"] as? [String] ?? ["unknown compatibility issue"])
            if failed.contains("memory64Cap") {
                let cause = result["memory64Error"] as? String ?? "WebKit rejected the memory64 probe"
                showFailure("This iOS WebKit build cannot create the game's shared WebAssembly memory64 configuration (4GiB maximum). " + cause + ". The engine originally requests a 3GiB initial heap and cannot safely launch without memory64 support.")
            } else {
                showFailure("Runtime requirements failed: " + failed.joined(separator: ", "))
            }
        }
    }

    private func showFailure(_ message: String) {
        LogStore.shared.write("crashes", message)
        status.isHidden = false
        status.text = message
        guard !alertVisible, isViewLoaded, view.window != nil else { return }
        alertVisible = true
        let alert = UIAlertController(title: "GTA V startup check", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Export diagnostics", style: .default) { [weak self] _ in
            self?.alertVisible = false
            self?.exportLogs()
        })
        alert.addAction(UIAlertAction(title: "Attempt engine anyway", style: .default) { [weak self] _ in
            self?.alertVisible = false
            self?.preflightComplete = true
            self?.launchEngine()
        })
        alert.addAction(UIAlertAction(title: "Back", style: .cancel) { [weak self] _ in
            self?.alertVisible = false
            self?.closeGame()
        })
        present(alert, animated: true)
    }

    @objc private func toggleUtilities() {
        let sheet = UIAlertController(title: "Game tools", message: "Keep overlays hidden during the original GTA V loading sequence.", preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: modeControl.isHidden ? "Show controller mode" : "Hide controller mode", style: .default) { [weak self] _ in
            self?.modeControl.isHidden.toggle()
        })
        sheet.addAction(UIAlertAction(title: "Export diagnostics", style: .default) { [weak self] _ in self?.exportLogs() })
        sheet.addAction(UIAlertAction(title: "Close game", style: .destructive) { [weak self] _ in self?.closeGame() })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = utilityButton
        sheet.popoverPresentationController?.sourceRect = utilityButton.bounds
        present(sheet, animated: true)
    }

    private func exportLogs() {
        let url = LogStore.shared.exportURL()
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let pop = activity.popoverPresentationController {
            pop.sourceView = utilityButton
            pop.sourceRect = utilityButton.bounds
        }
        present(activity, animated: true)
    }

    @objc private func profileChanged() {
        let profile = ["foot", "drive", "air"][modeControl.selectedSegmentIndex]
        webView.evaluateJavaScript("window.__gtaNativePadProfile && window.__gtaNativePadProfile('\(profile)')")
        LogStore.shared.write("controller", "Input profile: " + profile)
    }

    @objc private func closeGame() {
        navigationController?.popViewController(animated: true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView.url?.path != "/ios/preflight.html" else {
            RuntimeDiagnostics.probe(webView)
            return
        }
        status.text = "WebAssembly loader started; waiting for engine events…"
        RuntimeDiagnostics.probe(webView)
        let saved = UserDefaults.standard
        let sensitivity = saved.object(forKey: ControllerManager.sensitivityKey) == nil
            ? 1.0 : saved.double(forKey: ControllerManager.sensitivityKey)
        webView.evaluateJavaScript("window.__gtaNativePadSensitivity && window.__gtaNativePadSensitivity(\(sensitivity))")
        let mappings = saved.dictionary(forKey: ControllerSettingsViewController.bindingKey) as? [String: String]
            ?? ControllerSettingsViewController.defaults
        if let data = try? JSONSerialization.data(withJSONObject: mappings),
           let json = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("window.__gtaNativePadMappings && window.__gtaNativePadMappings(\(json))")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        showFailure("WebKit navigation failed: " + error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showFailure("Web content process terminated. The engine may have exceeded the iPhone memory limit.")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let details = message.body as? [String: Any] else { return }
        let kind = details["type"] as? String ?? "engine"
        let text = details["detail"] as? String ?? ""
        switch kind {
        case "preflight":
            onPreflight(text)
        case "preflightStage":
            LogStore.shared.write("boot", text)
            status.text = text
        case "controllerProfile":
            if let index = ["foot", "drive", "air"].firstIndex(of: text) {
                modeControl.selectedSegmentIndex = index
            }
            LogStore.shared.write("controller", text)
        case "gpu", "shaders":
            LogStore.shared.write(kind, text)
            if kind == "gpu" { status.text = text }
        case "error", "promise":
            LogStore.shared.write("engine", text)
            status.text = text
        case "engine":
            LogStore.shared.write("engine", text)
            if text.contains("first world frame") { status.isHidden = true }
        default:
            LogStore.shared.write(["boot", "warn"].contains(kind) ? "boot" : "engine", text)
        }
    }

    deinit {
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "gtaDiagnostics")
    }
}
