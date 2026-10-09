import UIKit
import MetalKit
import AVFoundation

/// Native-only device and asset readiness screen. No WebKit engine playback.
/// Only a linked AOT RAGE executable could advance this to true gameplay.
final class GameViewController: UIViewController {
    private var surface: NativeMetalSurface!
    private let heading = UILabel()
    private let status = UILabel()
    private let controllerStatus = UILabel()
    private let closeButton = UIButton(type: .system)
    private let logsButton = UIButton(type: .system)
    private var inspectStarted = false
    private var gamepadSnapshot: [String: Double] = [:]

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        surface = NativeMetalSurface(frame: .zero)
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)

        heading.text = "GTA V • NATIVE ARM64"
        heading.textAlignment = .center
        heading.textColor = .white
        heading.font = .systemFont(ofSize: 20, weight: .bold)
        heading.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(heading)

        status.text = "Validating native Metal device and external game files…"
        status.textColor = UIColor(white: 0.86, alpha: 1)
        status.textAlignment = .center
        status.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        status.numberOfLines = 0
        status.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(status)

        controllerStatus.text = "Bluetooth controller: checking…"
        controllerStatus.textAlignment = .center
        controllerStatus.textColor = UIColor(white: 0.65, alpha: 1)
        controllerStatus.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        controllerStatus.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controllerStatus)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        closeButton.layer.cornerRadius = 18
        closeButton.addTarget(self, action: #selector(closeGame), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        logsButton.setTitle("EXPORT NATIVE LOGS", for: .normal)
        logsButton.titleLabel?.font = .systemFont(ofSize: 11, weight: .semibold)
        logsButton.tintColor = .white
        logsButton.addTarget(self, action: #selector(exportLogs), for: .touchUpInside)
        logsButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(logsButton)

        NSLayoutConstraint.activate([
            surface.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            surface.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            surface.topAnchor.constraint(equalTo: view.topAnchor),
            surface.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            heading.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            heading.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 34),
            heading.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.9),
            status.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            status.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            status.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.82),
            controllerStatus.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            controllerStatus.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            controllerStatus.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.82),
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            logsButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -10),
            logsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 5),
            logsButton.heightAnchor.constraint(equalToConstant: 36)
        ])
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            LogStore.shared.write("native", "Native audio session available; game audio engine NOT linked")
        } catch {
            LogStore.shared.write("native", "Native audio setup failed: \(error.localizedDescription)")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        GameOrientation.request(.landscape, from: view)
        guard !inspectStarted else { return }
        inspectStarted = true
        #if targetEnvironment(simulator)
        LogStore.shared.write("native", "Wasmtime ARM64 static host: simulator excluded by design")
        #else
        let hostProbe = gta_ios_wasmtime_engine_probe()
        LogStore.shared.write("native", "Wasmtime native host initialization: status=\(hostProbe)")
        if hostProbe != 0 {
            status.text = "Native Wasmtime runtime could not initialize (\(hostProbe)). Check code signing and runtime diagnostics."
            return
        }
        var registered: UInt32 = 0
        var hostMessage = [CChar](repeating: 0, count: 512)
        let basicProbe = gta_ios_wasmtime_basic_host_probe(&registered, &hostMessage, hostMessage.count)
        let hostDetail = String(cString: hostMessage)
        LogStore.shared.write("native",
            "Real GTA native host callbacks: result=\(basicProbe), registered=\(registered)/85, message=\(hostDetail)")
        if basicProbe != 0 || registered != 5 {
            status.text = "Native Wasmtime host callback test failed (\(basicProbe)). \(hostDetail)"
            return
        }
        #endif
        if !surface.gpuReady {
            status.text = "Metal device or command queue unavailable. Native rendering cannot start."
            LogStore.shared.write("native", "Metal hardware check failed")
            return
        }
        LogStore.shared.write("native", "Native device boot: Metal ready. Browser/WKWebView gameplay disabled.")
        NativeEngineStatus.inspect { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let info):
                let m = info.memory
                let mem = "\(m.minimumPages) initial pages • \(m.maximumPages.map(String.init) ?? "unbounded") maximum"
                LogStore.shared.write("native", "Engine asset present (\(info.byteCount) bytes), \(mem)")
                if !m.memory64 || !m.shared {
                    self.status.text = "WASM engine requires an unsupported host contract.\nDetected memory64=\(m.memory64), shared=\(m.shared). Native AOT conversion required."
                } else if !NativeEngineStatus.nativeEngineLinked {
                    self.status.text = "USB game.wasm and shader index found.\nMetal GPU ready.\nChecking optional native ARM64 AOT engine file…"
                    NativeAOTModuleProbe.inspect { [weak self] result in
                        guard let self else { return }
                        switch result {
                        case .notSupplied:
                            self.status.text = "USB engine validated.\nFor native AOT compatibility testing, place real-gta-ios.cwasm next to index.html on the USB drive.\n\nGTA V gameplay is NOT implemented."
                            LogStore.shared.write("native", "Optional AOT module absent from USB root. No game engine linked.")
                        case .deserialized(let imports, let linked, let details):
                            self.status.text = "Actual AArch64 GTA AOT module deserialized.\nImported host bindings: \(imports).\nVerified native callbacks: \(linked).\n\n\(details)\n\nEngine execution and GTA rendering are not yet implemented."
                            LogStore.shared.write("native", "Actual GTA Wasmtime AOT module parsed, imports=\(imports), linked=\(linked), no instantiation")
                        case .failed(let why):
                            self.status.text = "Native AOT compatibility test failed:\n\(why)\n\nNo game execution attempted."
                            LogStore.shared.write("native", "Real AOT compatibility failure: \(why)")
                        }
                    }
                } else {
                    // Add actual engine launch only once a verified AOT backend exists.
                    self.status.text = "Native engine backend linked; initialization pending."
                }
            case .failure(let error):
                self.status.text = "Native asset verification failed:\n" + error.localizedDescription
                LogStore.shared.write("native", "Asset validation failed: \(error.localizedDescription)")
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        ControllerManager.shared.onConnection = { [weak self] name in
            self?.controllerStatus.text = "Controller: \(name)"
            LogStore.shared.write("native", "GameController connected: \(name)")
        }
        ControllerManager.shared.onState = { [weak self] state in
            // Preserve full analog values for the future native engine ABI.
            // The current binary has NO native controller-consumer interface.
            self?.gamepadSnapshot = state
        }
        ControllerManager.shared.begin()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ControllerManager.shared.stop()
    }

    @objc private func closeGame() {
        navigationController?.popViewController(animated: true)
    }

    @objc private func exportLogs() {
        let report = LogStore.shared.exportURL()
        let sheet = UIActivityViewController(activityItems: [report], applicationActivities: nil)
        if let pop = sheet.popoverPresentationController {
            pop.sourceView = logsButton
            pop.sourceRect = logsButton.bounds
        }
        present(sheet, animated: true)
    }
}
