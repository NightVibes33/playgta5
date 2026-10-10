import UIKit
import UniformTypeIdentifiers

/// Compact game-first dashboard. Intentionally no duplicate UIKit navigation title.
final class LauncherViewController: UIViewController, UIDocumentPickerDelegate {
    private let background = CAGradientLayer()
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let deviceLabel = UILabel()
    private let storageTitle = UILabel()
    private let storageDetails = UILabel()
    private let fileIndicator = UIView()
    private let playButton = UIButton(type: .system)
    private let folderButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let controllerButton = UIButton(type: .system)
    private let logsButton = UIButton(type: .system)
    private let filePickerTestButton = UIButton(type: .system)
    private let indexFileButton = UIButton(type: .system)
    private let advancedButton = UIButton(type: .system)
    private let advancedPanel = UIStackView()
    private let runtimeTitle = UILabel()
    private let runtimeDetail = UILabel()
    private var expandedDiagnostics = false
    private let modeButtons = [UIButton(type: .system), UIButton(type: .system), UIButton(type: .system)]
    private var focusIndex = 0
    private var heldUp = false
    private var heldDown = false
    private var heldA = false
    private enum PickerIntent { case folder, diagnosticText, indexFile }
    private var pickerIntent: PickerIntent = .folder
    private var activePicker: UIDocumentPickerViewController?
    private var lastPickerAction = "None"
    private var pickerCallbackReceived = false
    private var pendingUSBCheck: UUID?


    private let mint = GTATheme.coral
    private let muted = GTATheme.subdued
    private let panel = GTATheme.raised

    override func viewDidLoad() {
        super.viewDidLoad()
        title = ""
        view.backgroundColor = GTATheme.night
        background.colors = [
            GTATheme.night.cgColor,
            UIColor(red: 0.092, green: 0.104, blue: 0.135, alpha: 1).cgColor
        ]
        background.startPoint = CGPoint(x: 0, y: 0)
        background.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(background, at: 0)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.alignment = .fill
        content.spacing = 13
        content.isLayoutMarginsRelativeArrangement = false
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 19),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -19),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 15),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -18),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -38)
        ])

        // Compact native chrome followed by an illustrated Los Santos feature.
        // The hero is deliberately static: no bitmap/network work or idle timer.
        let top = UIStackView()
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 10
        let mark = UILabel()
        mark.text = "V"
        mark.textAlignment = .center
        mark.textColor = GTATheme.night
        mark.backgroundColor = GTATheme.coral
        mark.clipsToBounds = true
        mark.layer.cornerRadius = 9
        mark.layer.cornerCurve = .continuous
        mark.font = .systemFont(ofSize: 17, weight: .black)
        mark.translatesAutoresizingMaskIntoConstraints = false
        mark.widthAnchor.constraint(equalToConstant: 34).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let wordmark = GTATheme.section("GTAiOS")
        let build = GTATheme.caption("BUILD " + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))
        build.textAlignment = .right
        top.addArrangedSubview(mark)
        top.addArrangedSubview(wordmark)
        top.addArrangedSubview(UIView())
        top.addArrangedSubview(build)
        wordmark.setContentHuggingPriority(.required, for: .horizontal)
        content.addArrangedSubview(top)

        let hero = LosSantosHeroView()
        content.addArrangedSubview(hero)

        let storage = UIView()
        GTATheme.card(storage)
        storage.translatesAutoresizingMaskIntoConstraints = false
        storage.heightAnchor.constraint(greaterThanOrEqualToConstant: 81).isActive = true
        let srow = UIStackView()
        srow.translatesAutoresizingMaskIntoConstraints = false
        srow.axis = .horizontal
        srow.spacing = 11
        srow.alignment = .center
        storage.addSubview(srow)
        NSLayoutConstraint.activate([
            srow.leadingAnchor.constraint(equalTo: storage.leadingAnchor, constant: 14),
            srow.trailingAnchor.constraint(equalTo: storage.trailingAnchor, constant: -14),
            srow.topAnchor.constraint(equalTo: storage.topAnchor, constant: 11),
            srow.bottomAnchor.constraint(equalTo: storage.bottomAnchor, constant: -11)
        ])
        let disk = UIImageView(image: UIImage(systemName: "externaldrive.fill"))
        disk.tintColor = GTATheme.coral
        disk.contentMode = .scaleAspectFit
        disk.translatesAutoresizingMaskIntoConstraints = false
        disk.widthAnchor.constraint(equalToConstant: 29).isActive = true
        disk.heightAnchor.constraint(equalToConstant: 29).isActive = true
        let stateText = UIStackView()
        stateText.axis = .vertical; stateText.spacing = 4
        storageTitle.textColor = .white
        storageTitle.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 15, weight: .bold))
        storageTitle.adjustsFontForContentSizeCategory = true
        storageDetails.textColor = muted
        storageDetails.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 12))
        storageDetails.adjustsFontForContentSizeCategory = true
        storageDetails.numberOfLines = 2
        stateText.addArrangedSubview(storageTitle)
        stateText.addArrangedSubview(storageDetails)
        fileIndicator.backgroundColor = .systemOrange
        fileIndicator.layer.cornerRadius = 5
        fileIndicator.translatesAutoresizingMaskIntoConstraints = false
        fileIndicator.widthAnchor.constraint(equalToConstant: 10).isActive = true
        fileIndicator.heightAnchor.constraint(equalToConstant: 10).isActive = true
        srow.addArrangedSubview(disk)
        srow.addArrangedSubview(stateText)
        srow.addArrangedSubview(fileIndicator)
        content.addArrangedSubview(storage)

        let runtime = UIView()
        GTATheme.card(runtime)
        runtime.translatesAutoresizingMaskIntoConstraints = false
        let readiness = UIStackView()
        readiness.axis = .vertical
        readiness.spacing = 5
        readiness.translatesAutoresizingMaskIntoConstraints = false
        runtimeTitle.text = "ENGINE PORT • IN DEVELOPMENT"
        runtimeTitle.textColor = GTATheme.coral
        runtimeTitle.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12, weight: .bold))
        runtimeDetail.text = "The native Metal and USB systems are being validated. GTA world rendering and engine integration are not playable yet."
        runtimeDetail.textColor = muted
        runtimeDetail.font = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: .systemFont(ofSize: 13))
        runtimeDetail.adjustsFontForContentSizeCategory = true
        runtimeDetail.numberOfLines = 0
        readiness.addArrangedSubview(runtimeTitle)
        readiness.addArrangedSubview(runtimeDetail)
        runtime.addSubview(readiness)
        NSLayoutConstraint.activate([
            readiness.leadingAnchor.constraint(equalTo: runtime.leadingAnchor, constant: 15),
            readiness.trailingAnchor.constraint(equalTo: runtime.trailingAnchor, constant: -15),
            readiness.topAnchor.constraint(equalTo: runtime.topAnchor, constant: 14),
            readiness.bottomAnchor.constraint(equalTo: runtime.bottomAnchor, constant: -14)
        ])

        let tapStorage = UITapGestureRecognizer(target: self, action: #selector(chooseFolder))
        storage.addGestureRecognizer(tapStorage)
        storage.isUserInteractionEnabled = true
        storage.accessibilityLabel = "Choose USB game files folder"
        storage.accessibilityTraits = .button

        let profileHeading = GTATheme.section("Session profile")
        let modes = UIStackView()
        modes.axis = .horizontal
        modes.distribution = .fillEqually
        modes.spacing = 8
        for (i, name) in ["STORY", "FREE ROAM", "TEST WORLD"].enumerated() {
            let button = modeButtons[i]
            button.tag = i
            button.setTitle(name, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.78
            button.layer.cornerRadius = 9
            button.layer.borderWidth = 1
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 47).isActive = true
            button.addTarget(self, action: #selector(selectMode(_:)), for: .touchUpInside)
            modes.addArrangedSubview(button)
        }
        style(playButton, title: "RUN NATIVE CHECKS", symbol: "arrow.up.right", filled: true)
        playButton.addTarget(self, action: #selector(launch), for: .touchUpInside)
        playButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 58).isActive = true
        content.addArrangedSubview(playButton)

        let toolRow = UIStackView()
        toolRow.axis = .horizontal
        toolRow.distribution = .fillEqually
        toolRow.spacing = 8
        style(folderButton, title: "USB FILES", symbol: "externaldrive", filled: false)
        style(settingsButton, title: "GRAPHICS", symbol: "slider.horizontal.3", filled: false)
        style(controllerButton, title: "CONTROLS", symbol: "gamecontroller", filled: false)
        folderButton.addTarget(self, action: #selector(chooseFolder), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        controllerButton.addTarget(self, action: #selector(openControllerSetup), for: .touchUpInside)
        toolRow.addArrangedSubview(folderButton)
        toolRow.addArrangedSubview(settingsButton)
        toolRow.addArrangedSubview(controllerButton)
        content.addArrangedSubview(toolRow)
        content.addArrangedSubview(runtime)
        content.setCustomSpacing(20, after: runtime)
        content.addArrangedSubview(profileHeading)
        content.addArrangedSubview(modes)

        // Diagnostic-only file pickers stay behind the Advanced disclosure.
        // Keep the main launcher focused on connection, input and native boot.
        advancedPanel.axis = .vertical
        advancedPanel.spacing = 9
        advancedPanel.isHidden = true
        var advancedConfig = UIButton.Configuration.plain()
        advancedConfig.title = "File picker troubleshooting"
        advancedConfig.image = UIImage(systemName: "chevron.down")
        advancedConfig.imagePlacement = .leading
        advancedConfig.baseForegroundColor = muted
        advancedButton.configuration = advancedConfig
        advancedButton.contentHorizontalAlignment = .leading
        advancedButton.addTarget(self, action: #selector(toggleAdvanced), for: .touchUpInside)
        advancedButton.accessibilityHint = "Show optional Files compatibility diagnostics"
        content.addArrangedSubview(advancedButton)
        content.addArrangedSubview(advancedPanel)
        let pickerTip = label("FOLDER PICKER: TAP SELECT, CHOOSE playgta5.com, THEN OPEN", size: 10, weight: .medium, color: mint)
        pickerTip.numberOfLines = 2
        pickerTip.lineBreakMode = .byWordWrapping
        pickerTip.accessibilityLabel = "Select the playgta5.com folder with the Files selection control, then confirm Open; this does not copy the game"
        advancedPanel.addArrangedSubview(pickerTip)

        let probeRow = UIStackView()
        probeRow.axis = .horizontal
        probeRow.distribution = .fillEqually
        probeRow.spacing = 8
        style(filePickerTestButton, title: "TEST .TXT", symbol: "doc.text", filled: false)
        style(indexFileButton, title: "INDEX.HTML", symbol: "doc.text.magnifyingglass", filled: false)
        filePickerTestButton.addTarget(self, action: #selector(testFilesPicker), for: .touchUpInside)
        indexFileButton.addTarget(self, action: #selector(chooseIndexFile), for: .touchUpInside)
        probeRow.addArrangedSubview(filePickerTestButton)
        probeRow.addArrangedSubview(indexFileButton)
        advancedPanel.addArrangedSubview(probeRow)
        prepareDiagnosticTextFile()

        let bottom = UIStackView()
        bottom.axis = .horizontal; bottom.spacing = 8; bottom.alignment = .center
        deviceLabel.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12, weight: .medium))
        deviceLabel.textColor = muted
        deviceLabel.numberOfLines = 2
        let flexible = UIView()
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        style(logsButton, title: "LOGS", symbol: "doc.text", filled: false)
        logsButton.addTarget(self, action: #selector(exportLogs), for: .touchUpInside)
        logsButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 89).isActive = true
        bottom.addArrangedSubview(deviceLabel)
        bottom.addArrangedSubview(flexible)
        bottom.addArrangedSubview(logsButton)
        content.addArrangedSubview(bottom)
        NotificationCenter.default.addObserver(self, selector: #selector(storageChanged),
            name: USBStorageManager.changedNotification, object: nil)
        refresh()
    }

    @objc private func storageChanged() { refresh() }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        GameOrientation.request(.portrait, from: view)
        if activePicker != nil && !pickerCallbackReceived && presentedViewController == nil {
            LogStore.shared.write("usb-storage",
                "PICKER_GONE_WITHOUT_CALLBACK: document picker disappeared; no URL or cancel delegate fired")
            activePicker = nil
            storageDetails.text = "Files closed without returning a selection"
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        background.frame = view.bounds
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        ControllerManager.shared.onConnection = { [weak self] name in self?.updateDevice(name) }
        ControllerManager.shared.onState = { [weak self] state in self?.handleController(state) }
        ControllerManager.shared.begin()
        refresh()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ControllerManager.shared.stop()
    }

    private func label(_ title: String, size: CGFloat, weight: UIFont.Weight, color: UIColor) -> UILabel {
        let l = UILabel()
        l.text = title
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        return l
    }
    private func style(_ b: UIButton, title: String, symbol: String, filled: Bool) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = UIImage(systemName: symbol)
        config.imagePadding = filled ? 8 : 5
        config.imagePlacement = filled ? .trailing : .top
        config.titleLineBreakMode = .byTruncatingTail
        config.baseForegroundColor = filled ? GTATheme.night : GTATheme.cream
        config.background.backgroundColor = filled ? GTATheme.coral : GTATheme.inset
        config.cornerStyle = .large
        config.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 10, bottom: 11, trailing: 10)
        b.configuration = config
        b.titleLabel?.font = .systemFont(ofSize: filled ? 13 : 11, weight: .bold)
        b.titleLabel?.numberOfLines = 1
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.75
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: filled ? 56 : 64).isActive = true
    }
    private func refresh() {
        updateMode()
        playButton.configuration?.title = "RUN NATIVE CHECKS"
        if let root = USBStorageManager.shared.root {
            let missing = USBStorageManager.shared.missingStartupAssets()
            storageTitle.text = root.lastPathComponent
            storageDetails.text = missing.isEmpty ? "USB connected · Startup assets verified"
                : "Missing \(missing.count) required items · Change USB folder"
            storageDetails.textColor = missing.isEmpty ? GTATheme.success : UIColor.systemOrange
            fileIndicator.backgroundColor = missing.isEmpty ? GTATheme.success : UIColor.systemOrange
            playButton.isEnabled = true
            playButton.alpha = 1
            // Do not decode external artwork synchronously on the main thread.
            // USB can block for seconds in a Files provider.
        } else {
            storageTitle.text = "Connect your game library"
            storageDetails.text = "Choose the GTA V folder on your USB-C drive"
            storageDetails.textColor = muted
            fileIndicator.backgroundColor = .systemOrange
            playButton.isEnabled = true
            playButton.alpha = 1
            playButton.configuration?.title = "CHOOSE GAME FILES"
        }
        updateDevice(ControllerManager.shared.currentName)
        highlightFocus()
    }
    @objc private func toggleAdvanced() {
        expandedDiagnostics.toggle()
        advancedPanel.isHidden = !expandedDiagnostics
        advancedButton.configuration?.title = expandedDiagnostics
            ? "Hide picker troubleshooting" : "File picker troubleshooting"
        advancedButton.configuration?.image = UIImage(
            systemName: expandedDiagnostics ? "chevron.up" : "chevron.down")
        UISelectionFeedbackGenerator().selectionChanged()
        UIAccessibility.post(notification: .layoutChanged, argument: advancedButton)
    }

    private func updateMode() {
        let current = EngineOptions.value("mode")
        for (i, b) in modeButtons.enumerated() {
            let selected = ["story", "sandbox5", "sandbox6"][i] == current
            b.backgroundColor = selected ? GTATheme.coral.withAlphaComponent(0.13) : GTATheme.inset
            b.layer.borderColor = (selected ? GTATheme.coral : UIColor.white.withAlphaComponent(0.12)).cgColor
            b.setTitleColor(selected ? GTATheme.coral : GTATheme.cream, for: .normal)
        }
    }
    private func updateDevice(_ name: String) {
        deviceLabel.text = name == "No controller" ? "No controller · Pair in iOS Settings" : "Controller connected · " + name
        highlightFocus()
    }
    @objc private func selectMode(_ sender: UIButton) {
        EngineOptions.set("mode", value: ["story", "sandbox5", "sandbox6"][sender.tag])
        updateMode()
        UISelectionFeedbackGenerator().selectionChanged()
    }
    private var buttons: [UIButton] { [playButton, folderButton, settingsButton, controllerButton] + modeButtons + [logsButton] }
    private func highlightFocus() {
        // Present the focus ring only when a game controller is connected.
        let controllerConnected = ControllerManager.shared.currentName != "No controller"
        for (i, b) in buttons.enumerated() {
            let focused = controllerConnected && i == focusIndex
            b.layer.cornerRadius = 14
            b.layer.cornerCurve = .continuous
            b.clipsToBounds = true
            b.layer.borderColor = (focused ? GTATheme.coral : UIColor.clear).cgColor
            b.layer.borderWidth = focused ? 2 : 0
            b.accessibilityValue = focused ? "Controller focused" : nil
        }
    }
    private func handleController(_ state: [String: Double]) {
        guard presentedViewController == nil else { return }
        let up = (state["up"] ?? 0) > 0.6 || (state["ly"] ?? 0) > 0.7
        let down = (state["down"] ?? 0) > 0.6 || (state["ly"] ?? 0) < -0.7
        let a = (state["a"] ?? 0) > 0.6
        if up && !heldUp { focusIndex = max(0, focusIndex - 1); highlightFocus() }
        if down && !heldDown { focusIndex = min(buttons.count - 1, focusIndex + 1); highlightFocus() }
        if a && !heldA && buttons[focusIndex].isEnabled {
            buttons[focusIndex].sendActions(for: .touchUpInside)
        }
        heldUp = up; heldDown = down; heldA = a
    }
    // Direct, unwrapped directory picker following Apple's documented pattern.
    // We intentionally removed the action-sheet -> dismiss -> repesent chain;
    // it could race with Files' own presentation and delegate lifecycle.
    @objc private func chooseFolder() { openPicker(.folder) }

    @objc private func testFilesPicker() { openPicker(.diagnosticText) }

    @objc private func chooseIndexFile() { openPicker(.indexFile) }

    private func prepareDiagnosticTextFile() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let file = documents.appendingPathComponent("GTAiOS-Picker-Test.txt")
        if !FileManager.default.fileExists(atPath: file.path) {
            let content = "GTAiOS document picker test. Selecting this file verifies Files -> GTAiOS access.\n"
            do {
                try content.write(to: file, atomically: true, encoding: .utf8)
                LogStore.shared.write("usb-storage", "Created local text picker fixture: GTAiOS-Picker-Test.txt")
            } catch {
                LogStore.shared.write("usb-storage", "Failed to create local picker fixture: \(error.localizedDescription)")
            }
        }
    }

    private func openPicker(_ mode: PickerIntent) {
        guard presentedViewController == nil else {
            LogStore.shared.write("usb-storage",
                "PICKER_NOT_OPENED: another modal was still presented")
            return
        }
        pickerIntent = mode
        pickerCallbackReceived = false
        if mode == .diagnosticText {
            LogStore.shared.write("usb-storage",
                "TEXT_DIAGNOSTIC: On My iPhone > GTA V iOS > GTAiOS-Picker-Test.txt (asCopy=true)")
        } else if mode == .folder {
            LogStore.shared.write("usb-storage",
                "FOLDER_HELP: navigate INSIDE playgta5.com then tap the top-right Open button")
        }
        let picker: UIDocumentPickerViewController
        // LiveContainer's working "Fix File Picker" hook replaces narrow UTTypes
        // with [.item, .folder]. It also forces asCopy=true and multi-selection
        // for folder-only pickers. For a 21 GB USB game we MUST keep the original
        // file open in place; a copy-based folder import would fill device storage.
        // We use the publicly supported broad types + selection controls, while
        // deliberately preserving asCopy=false for USB access.
        switch mode {
        case .folder:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item, .folder], asCopy: false)
        case .diagnosticText:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item, .folder], asCopy: true)
        case .indexFile:
            picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item, .folder], asCopy: false)
        }
        picker.delegate = self
        // LiveContainer forces this true for a folder-only picker, which permits
        // explicit row selection instead of only navigating inside directories.
        picker.allowsMultipleSelection = mode == .folder
        picker.shouldShowFileExtensions = true
        activePicker = picker
        lastPickerAction = String(describing: mode)
        LogStore.shared.write("usb-storage",
            "PICKER_PRESENT_REQUEST mode=\(lastPickerAction) livecontainer_public_compat=1 types=item+folder asCopy=\(mode == .diagnosticText) multiselect=\(picker.allowsMultipleSelection)")
        present(picker, animated: true) { [weak self, weak picker] in
            guard let self else { return }
            LogStore.shared.write("usb-storage",
                "PICKER_PRESENTED mode=\(self.lastPickerAction), pickerAlive=\(picker != nil)")
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        pickerCallbackReceived = true
        let message = "Files picker cancelled, intent=\(pickerIntent), last=\(lastPickerAction). No URL was granted."
        LogStore.shared.write("usb-storage", message)
        storageDetails.text = "No folder selected • Files picker cancelled"
        activePicker = nil
        refresh()
        storageDetails.text = "Files cancelled • No selection URL was received"
    }

    // Some Files providers still invoke the deprecated single-URL delegate.
    // Forward it to the same nonblocking code path; ignore duplicate callbacks.
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        LogStore.shared.write("usb-storage", "LEGACY_FILES_CALLBACK: " + url.lastPathComponent)
        guard !pickerCallbackReceived else { return }
        documentPicker(controller, didPickDocumentsAt: [url])
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        pickerCallbackReceived = true
        let method = pickerIntent
        activePicker = nil
        LogStore.shared.write("usb-storage",
            "FILES CALLBACK RECEIVED: selected count=\(urls.count), intent=\(method)")
        // With multi-selection enabled, prefer the explicit game folder over a
        // random child asset; never attempt to copy or inspect all selected items.
        guard let url = urls.first(where: { $0.lastPathComponent == "playgta5.com" }) ?? urls.first else {
            LogStore.shared.write("usb-storage", "Files sent an empty selection")
            showPickerResult("Files returned nothing", "The picker did not provide a file URL.")
            return
        }

        // This probe tests the Files -> UIKit handoff using any small file.
        // If index.html was chosen, the same picker also tests GTA USB access.
        if method == .diagnosticText {
            LogStore.shared.write("usb-storage",
                "PICKER_DIAGNOSTIC_SUCCEEDED selectedName=\(url.lastPathComponent)")
            storageDetails.text = "Picker works: iOS delivered \(url.lastPathComponent)"
            showPickerResult("iOS file selection works",
                "Files returned \(url.lastPathComponent) to GTAiOS. The text-file picker works independently of game-folder access.")
            return
        }

        // The callback MUST return immediately. No FileManager, bookmark
        // resolution, NSFileCoordinator or USB access on UIKit's main queue.
        let token = UUID()
        pendingUSBCheck = token
        storageTitle.text = "CHECKING EXTERNAL USB"
        storageDetails.text = "Files selection received • Verifying drive permissions…"
        storageDetails.textColor = UIColor.systemOrange
        fileIndicator.backgroundColor = UIColor.systemOrange
        LogStore.shared.write("usb-storage",
            "USB_VALIDATION_BEGIN token=\(token) path=\(url.lastPathComponent), method=\(method)")

        if presentedViewController === controller {
            controller.dismiss(animated: true)
        }
        USBStorageManager.shared.chooseAsync(url, fromFile: method == .indexFile) { [weak self] result in
            guard let self, self.pendingUSBCheck == token else { return }
            self.pendingUSBCheck = nil
            self.refresh()
            switch result {
            case .success(let root):
                LogStore.shared.write("usb-storage",
                    "USB_VALIDATION_OK root=\(root.lastPathComponent)")
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                self.showPickerResult("USB game files connected",
                    "Verified access to game.wasm and the data directory. No game assets were copied to internal storage.")
            case .failure(let error):
                LogStore.shared.write("usb-storage",
                    "USB_VALIDATION_FAILED \(error.localizedDescription)")
                self.showPickerResult("USB file access failed",
                    error.localizedDescription + "\n\nExport the USB logs so we can distinguish a Files permission problem from a missing game asset.")
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 18) { [weak self] in
            guard let self, self.pendingUSBCheck == token else { return }
            // Ignore a late callback from the operation. A stalled external drive
            // must not freeze the UI, and the next attempt remains possible.
            self.pendingUSBCheck = nil
            LogStore.shared.write("usb-storage",
                "USB_VALIDATION_TIMEOUT after 18 seconds, token=\(token)")
            self.refresh()
            self.showPickerResult("USB verification timed out",
                "iOS returned your file selection, but opening the USB game data took more than 18 seconds. The Files provider may be stalled. Export the USB logs.")
        }
    }

    private func showPickerResult(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        alert.addAction(UIAlertAction(title: "Export USB logs", style: .default) { [weak self] _ in
            self?.exportLogs()
        })
        // UIKit sometimes hasn't fully dismissed Files when its delegate runs.
        if let picker = presentedViewController as? UIDocumentPickerViewController {
            picker.dismiss(animated: true) { [weak self] in
                self?.present(alert, animated: true)
            }
        } else if presentedViewController == nil {
            present(alert, animated: true)
        } else {
            LogStore.shared.write("usb-storage",
                "Result alert deferred: another modal was presented")
        }
    }
    @objc private func launch() {
        guard USBStorageManager.shared.root != nil else { chooseFolder(); return }
        let missing = USBStorageManager.shared.missingStartupAssets()
        if !missing.isEmpty {
            let alert = UIAlertController(title: "Missing game resources",
                message: missing.joined(separator: "\n") + "\n\nGTAiOS will not copy the full game dataset. Select the authorized root folder containing the engine and data resources.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Change folder", style: .default) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    self?.chooseFolder()
                }
            })
            alert.addAction(UIAlertAction(title: "Run native checks", style: .default) { [weak self] _ in self?.openGame() })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            present(alert, animated: true)
        } else { openGame() }
    }
    private func openGame() {
        navigationController?.pushViewController(GameViewController(), animated: true)
    }
    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }
    @objc private func openControllerSetup() {
        navigationController?.pushViewController(ControllerSettingsViewController(), animated: true)
    }
    @objc private func exportLogs() {
        let file = LogStore.shared.exportURL()
        let activity = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        if let p = activity.popoverPresentationController {
            p.sourceView = logsButton
            p.sourceRect = logsButton.bounds
        }
        present(activity, animated: true)
    }
}
