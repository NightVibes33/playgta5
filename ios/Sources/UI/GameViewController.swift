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
    private let touchButton = UIButton(type: .system)
    private let statsLabel = UILabel()
    private let touchControls = NativeTouchControlsView(frame: .zero)
    private var statsTicker: CADisplayLink?
    private var frameCounter = 0
    private var frameStart = CACurrentMediaTime()
    private var lastStats: TimeInterval = 0
    private var inspectStarted = false
    private var gamepadSnapshot: [String: Double] = [:]
    private var lastInputBridgeResult: Int32 = Int32.min

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
    override var prefersStatusBarHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        // Map /userdata/* to app-private Documents, never to the USB game assets.
        let saveDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GTAiOS-Userdata", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: saveDirectory,
                withIntermediateDirectories: true)
            let setup = saveDirectory.path.withCString { gta_userdata_set_root($0) }
            LogStore.shared.write("native", "GTA native userdata persistence sandbox configured: rc=\(setup)")
        } catch {
            LogStore.shared.write("native", "GTA native userdata sandbox unavailable: \(error.localizedDescription)")
        }
        view.backgroundColor = .black

        surface = NativeMetalSurface(frame: .zero)
        surface.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(surface)

        // Render no fake GTA gameplay. Native game controls are genuine
        // interactive UIKit events staged for the forthcoming engine ABI.
        touchControls.onState = { values in
            NativeInputState.shared.updateTouch(values)
        }
        touchControls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(touchControls)
        let storedVisibility = UserDefaults.standard.object(forKey: "gtaios.touch.visible")
        touchControls.alpha = CGFloat(GTALaunchPreferences.fraction("touchOpacity", fallback: 0.7))
        switch GTALaunchPreferences.text("controlScheme", fallback: "Automatic") {
        case "Controller": touchControls.isHidden = true
        case "Touch": touchControls.isHidden = false
        default:
            touchControls.isHidden = storedVisibility == nil
                ? false : !UserDefaults.standard.bool(forKey: "gtaios.touch.visible")
        }

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

        var touchConfig = UIButton.Configuration.tinted()
        touchConfig.title = touchControls.isHidden ? "SHOW TOUCH" : "HIDE TOUCH"
        touchConfig.baseForegroundColor = .white
        touchConfig.background.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        touchButton.configuration = touchConfig
        touchButton.titleLabel?.font = .systemFont(ofSize: 10, weight: .semibold)
        touchButton.addTarget(self, action: #selector(toggleTouch), for: .touchUpInside)
        touchButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(touchButton)
        statsLabel.textAlignment = .center
        statsLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        statsLabel.backgroundColor = UIColor.black.withAlphaComponent(0.25)
        statsLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
        statsLabel.numberOfLines = 2
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statsLabel)
        UIDevice.current.isBatteryMonitoringEnabled = true
        updateStats(seconds: 0)

        NSLayoutConstraint.activate([
            touchControls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            touchControls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            touchControls.topAnchor.constraint(equalTo: view.topAnchor),
            touchControls.bottomAnchor.constraint(equalTo: view.bottomAnchor),
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
            logsButton.heightAnchor.constraint(equalToConstant: 36),
            touchButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            touchButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            touchButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 35),
            statsLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            statsLabel.topAnchor.constraint(equalTo: touchButton.bottomAnchor, constant: 6),
            statsLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 176)
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
        // iOS 27 can reject an immediate geometry request while a portrait
        // navigation push is still resolving. Invalidate UIKit's orientation
        // masks and request landscape on the next run loop after presentation.
        setNeedsUpdateOfSupportedInterfaceOrientations()
        navigationController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        DispatchQueue.main.async { [weak self] in
            guard let self, self.view.window != nil else { return }
            self.navigationController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            GameOrientation.request(.landscape, from: self.view)
        }
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
        // Executed-machine-code test (not simply Wasmtime deserialization).
        // The fixture is a tiny original module AOT-compiled for iPhone ARM64
        // during CI; it is completely separate from proprietary GTA game code.
        if let fixture = Bundle.main.path(forResource: "native-aot-smoke", ofType: "cwasm") {
            var smokeMessage = [CChar](repeating: 0, count: 640)
            let rc = fixture.withCString {
                gta_ios_wasmtime_execute_smoke($0, &smokeMessage, smokeMessage.count)
            }
            let detail = String(cString: smokeMessage)
            LogStore.shared.write("native",
                "AOT native machine-code execution: rc=\(rc), result=\(detail)")
        } else {
            LogStore.shared.write("native",
                "AOT native smoke fixture absent from IPA: cannot verify iOS executable AOT pages")
        }
        // Separate, real AOT execution check with imported shared memory64.
        // This is intentionally a 64 KiB host allocation, not the GTA
        // module's 3 GiB shared heap. The C runtime compares guest output
        // AND independently reads the host-visible bytes to prove coherence.
        if let sharedFixture = Bundle.main.path(forResource: "native-memory64-smoke", ofType: "cwasm") {
            var memoryMessage = [CChar](repeating: 0, count: 640)
            let memoryResult = sharedFixture.withCString {
                gta_ios_wasmtime_memory64_smoke($0, &memoryMessage, memoryMessage.count)
            }
            let summary = String(cString: memoryMessage)
            LogStore.shared.write("native",
                "Shared memory64 native AOT execution: rc=\(memoryResult), detail=\(summary)")
        } else {
            LogStore.shared.write("native",
                "Shared memory64 AOT fixture missing from IPA; device compatibility not tested")
        }
        var registered: UInt32 = 0
        var hostMessage = [CChar](repeating: 0, count: 512)
        let basicProbe = gta_ios_wasmtime_basic_host_probe(&registered, &hostMessage, hostMessage.count)
        let hostDetail = String(cString: hostMessage)
        LogStore.shared.write("native",
            "Real GTA native host callbacks: result=\(basicProbe), registered=\(registered)/85, message=\(hostDetail)")
        if basicProbe != 0 || registered != 29 {
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
                            let headline = details.components(separatedBy: "\n").first ?? details
                            self.status.text = "Actual AArch64 GTA AOT module deserialized.\nImported host bindings: \(imports).\nVerified native callbacks: \(linked).\n\n\(headline)\n\nFull unresolved ABI list is in exported logs. Game NOT instantiated."
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
            NativeInputState.shared.updateHardware(state)
        }
        ControllerManager.shared.begin()
        // CADisplayLink measures the native UIKit/Metal surface tick rate,
        // not GTA render FPS; display the distinction explicitly.
        statsTicker?.invalidate()
        statsTicker = CADisplayLink(target: self, selector: #selector(tickStats))
        statsTicker?.preferredFramesPerSecond = 30
        statsTicker?.add(to: .main, forMode: .common)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ControllerManager.shared.stop()
        statsTicker?.invalidate()
        statsTicker = nil
        touchControls.reset()
        NativeInputState.shared.clearHardware()
    }

    @objc private func toggleTouch() {
        touchControls.isHidden.toggle()
        if touchControls.isHidden { touchControls.reset() }
        UserDefaults.standard.set(!touchControls.isHidden, forKey: "gtaios.touch.visible")
        touchButton.configuration?.title = touchControls.isHidden ? "SHOW TOUCH" : "HIDE TOUCH"
        UISelectionFeedbackGenerator().selectionChanged()
        LogStore.shared.write("native", "Native touch overlay visible=\(!touchControls.isHidden)")
    }

    private func syncNativeInput() {
        // Verified original wasm_input_publish_js block: hardware/touch merged
        // into the existing keyboard + mouse shared-memory input ABI.
        let state = NativeInputState.shared.snapshot
        func axis(_ name: String) -> Float {
            Float(max(-1, min(1, state[name] ?? 0)))
        }
        var pad = gta_native_pad_frame_t()
        pad.lx = axis("lx"); pad.ly = axis("ly")
        pad.rx = axis("rx"); pad.ry = axis("ry")
        pad.lt = axis("lt"); pad.rt = axis("rt")
        let names = ["a","b","x","y","lb","rb","l3","r3",
                     "up","down","left","right","menu","options"]
        var mask: UInt32 = 0
        for (index,name) in names.enumerated() where (state[name] ?? 0) > 0.5 {
            mask |= UInt32(1) << UInt32(index)
        }
        pad.buttons = mask
        pad.profile = (state["drivingProfile"] ?? 0) > 0.5 ? 1 : 0
        pad.active = (state["connected"] ?? 0) > 0.5 ||
            (state["touchActive"] ?? 0) > 0.5 ? 1 : 0
        pad.width = UInt32(max(1, min(8192, surface.drawableSize.width)))
        pad.height = UInt32(max(1, min(8192, surface.drawableSize.height)))
        let rc = gta_native_input_apply(&pad)
        if rc != lastInputBridgeResult {
            lastInputBridgeResult = rc
            LogStore.shared.write("native",
                "Real WASM keyboard/mouse bridge: rc=\(rc) (0=applied, 1=pending guest memory, negative=invalid address). Input is not GTA gameplay until module instantiation.")
        }
    }

    @objc private func tickStats(_ link: CADisplayLink) {
        syncNativeInput()
        frameCounter += 1
        let now = CACurrentMediaTime()
        let elapsed = now - frameStart
        if elapsed >= 1 {
            // Drain bounded engine guest diagnostic messages into Files-exported
            // LogStore. This is safe even before the 3GiB game memory exists.
            var guestLine = [CChar](repeating: 0, count: 256)
            for _ in 0..<8 {
                guard gta_text_host_next_log(&guestLine, guestLine.count) == 1 else { break }
                LogStore.shared.write("engine", String(cString: guestLine))
            }
            let userdataFailure = gta_userdata_take_error()
            if userdataFailure < 0 {
                LogStore.shared.write("engine", "GTA native userdata save/delete failed: code=\(userdataFailure)")
            }
            let fps = Double(frameCounter) / elapsed
            updateStats(seconds: fps)
            frameCounter = 0
            frameStart = now
        }
    }

    private func updateStats(seconds fps: Double) {
        let process = ProcessInfo.processInfo
        let state: String
        switch process.thermalState {
        case .nominal: state = "COOL"
        case .fair: state = "WARM"
        case .serious: state = "HOT"
        case .critical: state = "CRITICAL"
        @unknown default: state = "UNKNOWN"
        }
        let battery = UIDevice.current.batteryLevel >= 0
            ? "\(Int(UIDevice.current.batteryLevel * 100))%" : "--"
        statsLabel.text = "UI \(Int(fps.rounded())) Hz · THERMAL \(state) · BATTERY \(battery)\nNOT GAME FPS"
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
