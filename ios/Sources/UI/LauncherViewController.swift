import UIKit
import UniformTypeIdentifiers

/// Game-first dashboard: cinematic library cover, one meaningful action,
/// two practical setup destinations and diagnostics tucked into overflow.
/// This deliberately avoids test-world menus, fake playable modes and
/// a home-screen-sized engineering status panel.
final class LauncherViewController: UIViewController, UIDocumentPickerDelegate {
    private let background = CAGradientLayer()
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let storageTitle = UILabel()
    private let storageDetails = UILabel()
    private let fileIndicator = UIView()
    private let playButton = UIButton(type: .system)
    private let folderButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let controllerButton = UIButton(type: .system)
    private let moreButton = UIButton(type: .system)
    private let logsButton = UIButton(type: .system)
    private let statusLine = UILabel()
    private let deviceLabel = UILabel()
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

    private let muted = GTATheme.subdued

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = ""
        view.backgroundColor = GTATheme.night
        background.colors = [
            GTATheme.night.cgColor,
            UIColor(red: 0.075, green: 0.083, blue: 0.102, alpha: 1).cgColor
        ]
        background.startPoint = CGPoint(x: 0, y: 0)
        background.endPoint = CGPoint(x: 0.9, y: 1)
        view.layer.insertSublayer(background, at: 0)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        content.axis = .vertical
        content.spacing = 15
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -20),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        // Small identity bar; version and technical information stay in About.
        let header = UIStackView()
        header.axis = .horizontal
        header.spacing = 11
        header.alignment = .center
        let monogram = UILabel()
        monogram.text = "V"
        monogram.textAlignment = .center
        monogram.font = .systemFont(ofSize: 18, weight: .black)
        monogram.textColor = GTATheme.night
        monogram.backgroundColor = GTATheme.coral
        monogram.layer.cornerRadius = 9
        monogram.layer.cornerCurve = .continuous
        monogram.clipsToBounds = true
        monogram.widthAnchor.constraint(equalToConstant: 36).isActive = true
        monogram.heightAnchor.constraint(equalToConstant: 36).isActive = true

        let brand = UILabel()
        brand.text = "GTAiOS"
        brand.font = .systemFont(ofSize: 21, weight: .bold)
        brand.textColor = GTATheme.cream
        brand.setContentCompressionResistancePriority(.required, for: .horizontal)

        let spacer = UIView()
        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = GTATheme.cream
        moreButton.backgroundColor = GTATheme.raised
        moreButton.layer.cornerRadius = 18
        moreButton.layer.cornerCurve = .continuous
        moreButton.accessibilityLabel = "More options and diagnostics"
        moreButton.widthAnchor.constraint(equalToConstant: 36).isActive = true
        moreButton.heightAnchor.constraint(equalToConstant: 36).isActive = true
        moreButton.addTarget(self, action: #selector(showMore), for: .touchUpInside)

        header.addArrangedSubview(monogram)
        header.addArrangedSubview(brand)
        header.addArrangedSubview(spacer)
        header.addArrangedSubview(moreButton)
        content.addArrangedSubview(header)
        content.setCustomSpacing(18, after: header)

        content.addArrangedSubview(LosSantosHeroView())

        let libraryHeading = UILabel()
        libraryHeading.text = "MY GAME"
        libraryHeading.textColor = GTATheme.cream.withAlphaComponent(0.87)
        libraryHeading.font = .systemFont(ofSize: 11, weight: .heavy)
        content.addArrangedSubview(libraryHeading)
        content.setCustomSpacing(9, after: libraryHeading)

        // The entire row is one clear library action—not a decorative card
        // followed by an unrelated second "USB FILES" button.
        let library = UIView()
        GTATheme.card(library)
        library.translatesAutoresizingMaskIntoConstraints = false
        library.heightAnchor.constraint(equalToConstant: 83).isActive = true

        let disk = UIImageView(image: UIImage(systemName: "externaldrive.fill"))
        disk.tintColor = GTATheme.coral
        disk.contentMode = .scaleAspectFit
        disk.translatesAutoresizingMaskIntoConstraints = false
        library.addSubview(disk)

        storageTitle.textColor = GTATheme.cream
        storageTitle.font = .systemFont(ofSize: 16, weight: .bold)
        storageTitle.lineBreakMode = .byTruncatingTail
        storageTitle.translatesAutoresizingMaskIntoConstraints = false
        library.addSubview(storageTitle)

        storageDetails.textColor = muted
        storageDetails.font = .systemFont(ofSize: 12, weight: .regular)
        storageDetails.lineBreakMode = .byTruncatingMiddle
        storageDetails.numberOfLines = 1
        storageDetails.translatesAutoresizingMaskIntoConstraints = false
        library.addSubview(storageDetails)

        fileIndicator.backgroundColor = GTATheme.coral
        fileIndicator.layer.cornerRadius = 4
        fileIndicator.translatesAutoresizingMaskIntoConstraints = false
        library.addSubview(fileIndicator)

        let chevron = UIImageView(image: UIImage(systemName: "chevron.right"))
        chevron.tintColor = muted
        chevron.translatesAutoresizingMaskIntoConstraints = false
        library.addSubview(chevron)
        NSLayoutConstraint.activate([
            disk.leadingAnchor.constraint(equalTo: library.leadingAnchor, constant: 17),
            disk.centerYAnchor.constraint(equalTo: library.centerYAnchor),
            disk.widthAnchor.constraint(equalToConstant: 27),
            disk.heightAnchor.constraint(equalToConstant: 27),
            storageTitle.leadingAnchor.constraint(equalTo: disk.trailingAnchor, constant: 14),
            storageTitle.trailingAnchor.constraint(lessThanOrEqualTo: fileIndicator.leadingAnchor, constant: -9),
            storageTitle.bottomAnchor.constraint(equalTo: library.centerYAnchor, constant: -1),
            storageDetails.leadingAnchor.constraint(equalTo: storageTitle.leadingAnchor),
            storageDetails.trailingAnchor.constraint(equalTo: fileIndicator.leadingAnchor, constant: -10),
            storageDetails.topAnchor.constraint(equalTo: library.centerYAnchor, constant: 4),
            fileIndicator.trailingAnchor.constraint(equalTo: chevron.leadingAnchor, constant: -9),
            fileIndicator.centerYAnchor.constraint(equalTo: library.centerYAnchor),
            fileIndicator.heightAnchor.constraint(equalToConstant: 8),
            fileIndicator.widthAnchor.constraint(equalToConstant: 8),
            chevron.trailingAnchor.constraint(equalTo: library.trailingAnchor, constant: -17),
            chevron.centerYAnchor.constraint(equalTo: library.centerYAnchor),
            chevron.widthAnchor.constraint(equalToConstant: 8),
            chevron.heightAnchor.constraint(equalToConstant: 14)
        ])

        folderButton.backgroundColor = .clear
        folderButton.translatesAutoresizingMaskIntoConstraints = false
        folderButton.accessibilityLabel = "Select or change your USB game library"
        folderButton.addTarget(self, action: #selector(chooseFolder), for: .touchUpInside)
        library.addSubview(folderButton)
        NSLayoutConstraint.activate([
            folderButton.leadingAnchor.constraint(equalTo: library.leadingAnchor),
            folderButton.trailingAnchor.constraint(equalTo: library.trailingAnchor),
            folderButton.topAnchor.constraint(equalTo: library.topAnchor),
            folderButton.bottomAnchor.constraint(equalTo: library.bottomAnchor)
        ])
        content.addArrangedSubview(library)

        configureMainAction()
        playButton.addTarget(self, action: #selector(launch), for: .touchUpInside)
        playButton.heightAnchor.constraint(equalToConstant: 56).isActive = true
        content.addArrangedSubview(playButton)
        content.setCustomSpacing(5, after: playButton)

        statusLine.textColor = muted
        statusLine.font = .systemFont(ofSize: 11, weight: .medium)
        statusLine.textAlignment = .center
        statusLine.numberOfLines = 2
        statusLine.translatesAutoresizingMaskIntoConstraints = false
        content.addArrangedSubview(statusLine)
        content.setCustomSpacing(18, after: statusLine)

        let secondary = UIStackView()
        secondary.axis = .horizontal
        secondary.spacing = 11
        secondary.distribution = .fillEqually
        setupSecondary(settingsButton, title: "Graphics", symbol: "slider.horizontal.3", action: #selector(openSettings))
        setupSecondary(controllerButton, title: "Controller", symbol: "gamecontroller", action: #selector(openControllerSetup))
        secondary.addArrangedSubview(settingsButton)
        secondary.addArrangedSubview(controllerButton)
        content.addArrangedSubview(secondary)

        let footer = UIStackView()
        footer.axis = .horizontal
        footer.alignment = .center
        deviceLabel.textColor = muted
        deviceLabel.font = .systemFont(ofSize: 11, weight: .medium)
        deviceLabel.lineBreakMode = .byTruncatingTail
        let build = GTATheme.caption("BUILD " + (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))
        build.font = .systemFont(ofSize: 10, weight: .medium)
        build.setContentHuggingPriority(.required, for: .horizontal)
        footer.addArrangedSubview(deviceLabel)
        footer.addArrangedSubview(UIView())
        footer.addArrangedSubview(build)
        content.addArrangedSubview(footer)

        NotificationCenter.default.addObserver(self, selector: #selector(storageChanged),
            name: USBStorageManager.changedNotification, object: nil)
        refresh()
    }

    private func configureMainAction() {
        var c = UIButton.Configuration.filled()
        c.title = "Choose Game Folder"
        c.image = UIImage(systemName: "arrow.up.right")
        c.imagePlacement = .trailing
        c.imagePadding = 10
        c.baseBackgroundColor = GTATheme.coral
        c.baseForegroundColor = GTATheme.night
        c.cornerStyle = .large
        c.contentInsets = NSDirectionalEdgeInsets(top: 15, leading: 20, bottom: 15, trailing: 20)
        playButton.configuration = c
        playButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        playButton.accessibilityLabel = "Choose game folder"
    }

    private func setupSecondary(_ button: UIButton, title: String, symbol: String, action: Selector) {
        var c = UIButton.Configuration.filled()
        c.title = title
        c.image = UIImage(systemName: symbol)
        c.imagePlacement = .leading
        c.imagePadding = 9
        c.baseBackgroundColor = GTATheme.raised
        c.baseForegroundColor = GTATheme.cream
        c.cornerStyle = .large
        c.contentInsets = NSDirectionalEdgeInsets(top: 13, leading: 13, bottom: 13, trailing: 13)
        button.configuration = c
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        button.heightAnchor.constraint(equalToConstant: 52).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func refresh() {
        if let root = USBStorageManager.shared.root {
            storageTitle.text = "Grand Theft Auto V"
            storageDetails.text = "Connected · " + root.lastPathComponent
            fileIndicator.backgroundColor = GTATheme.success
            playButton.configuration?.title = "Play GTA V"
            playButton.configuration?.image = UIImage(systemName: "play.fill")
            playButton.isEnabled = NativeEngineStatus.nativeEngineLinked
            playButton.alpha = NativeEngineStatus.nativeEngineLinked ? 1 : 0.65
            playButton.accessibilityLabel = NativeEngineStatus.nativeEngineLinked
                ? "Play Grand Theft Auto V" : "Play unavailable until native engine is ready"
            statusLine.text = NativeEngineStatus.nativeEngineLinked
                ? "Ready to play from USB-C"
                : "Native game engine integration is still in progress"
        } else {
            storageTitle.text = "Connect game files"
            storageDetails.text = "Select your GTA V folder on USB-C"
            fileIndicator.backgroundColor = GTATheme.coral
            playButton.configuration?.title = "Choose Game Folder"
            playButton.configuration?.image = UIImage(systemName: "arrow.up.right")
            playButton.isEnabled = true
            playButton.alpha = 1
            playButton.accessibilityLabel = "Choose game folder"
            statusLine.text = "Game data stays on your external drive"
        }
        updateDevice(ControllerManager.shared.currentName)
        highlightFocus()
    }

    @objc private func storageChanged() { refresh() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        background.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        GameOrientation.request(.portrait, from: view)
        if activePicker != nil && !pickerCallbackReceived && presentedViewController == nil {
            LogStore.shared.write("usb-storage",
                "PICKER_GONE_WITHOUT_CALLBACK: document picker disappeared; no URL or cancel delegate fired")
            activePicker = nil
        }
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

    private func updateDevice(_ name: String) {
        deviceLabel.text = name == "No controller" ? "Controller not connected" : name
    }

    private var focusTargets: [UIButton] {
        [playButton, folderButton, settingsButton, controllerButton, moreButton]
    }
    private func highlightFocus() {
        let connected = ControllerManager.shared.currentName != "No controller"
        for (i, button) in focusTargets.enumerated() {
            let focused = connected && focusIndex == i
            button.layer.borderColor = focused ? GTATheme.coral.cgColor : UIColor.clear.cgColor
            button.layer.borderWidth = focused ? 2 : 0
            button.layer.cornerRadius = 15
            button.accessibilityValue = focused ? "Controller focused" : nil
        }
    }
    private func handleController(_ state: [String: Double]) {
        guard presentedViewController == nil else { return }
        let up = (state["up"] ?? 0) > 0.6 || (state["ly"] ?? 0) > 0.7
        let down = (state["down"] ?? 0) > 0.6 || (state["ly"] ?? 0) < -0.7
        let a = (state["a"] ?? 0) > 0.6
        if up && !heldUp {
            focusIndex = max(0, focusIndex - 1)
            highlightFocus()
        }
        if down && !heldDown {
            focusIndex = min(focusTargets.count - 1, focusIndex + 1)
            highlightFocus()
        }
        if a && !heldA, focusTargets[focusIndex].isEnabled {
            focusTargets[focusIndex].sendActions(for: .touchUpInside)
        }
        heldUp = up
        heldDown = down
        heldA = a
    }

    @objc private func showMore() {
        let menu = UIAlertController(title: "GTAiOS",
            message: "Library and device options · Build " +
                (Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"),
            preferredStyle: .actionSheet)
        menu.addAction(UIAlertAction(title: "Choose a different game folder", style: .default) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.chooseFolder() }
        })
        menu.addAction(UIAlertAction(title: "Native runtime details", style: .default) { [weak self] _ in
            self?.openGame()
        })
        menu.addAction(UIAlertAction(title: "File picker troubleshooting", style: .default) { [weak self] _ in
            self?.showFileDiagnostics()
        })
        menu.addAction(UIAlertAction(title: "Export diagnostics", style: .default) { [weak self] _ in
            self?.exportLogs()
        })
        menu.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popup = menu.popoverPresentationController {
            popup.sourceView = moreButton
            popup.sourceRect = moreButton.bounds
        }
        present(menu, animated: true)
    }

    private func showFileDiagnostics() {
        let alert = UIAlertController(title: "Files diagnostics",
            message: "Optional tests for system file-picker compatibility.",
            preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "Test .TXT picker", style: .default) { [weak self] _ in
            self?.prepareDiagnosticTextFile()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.testFilesPicker() }
        })
        alert.addAction(UIAlertAction(title: "Select index.html", style: .default) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.chooseIndexFile() }
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popup = alert.popoverPresentationController {
            popup.sourceView = moreButton
            popup.sourceRect = moreButton.bounds
        }
        present(alert, animated: true)
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
        if !NativeEngineStatus.nativeEngineLinked {
            let alert = UIAlertController(title: "Game not ready",
                message: "Your game library is connected, but native GTA V engine integration is not complete. The game cannot launch yet.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .cancel))
            alert.addAction(UIAlertAction(title: "Runtime details", style: .default) { [weak self] _ in self?.openGame() })
            present(alert, animated: true)
            return
        }
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
            p.sourceView = moreButton
            p.sourceRect = moreButton.bounds
        }
        present(activity, animated: true)
    }
}
