import UIKit
import UniformTypeIdentifiers

/// Compact game-first dashboard. Intentionally no duplicate UIKit navigation title.
final class LauncherViewController: UIViewController, UIDocumentPickerDelegate {
    private let background = CAGradientLayer()
    private let scrollView = UIScrollView()
    private let content = UIStackView()
    private let gameIcon = UIImageView()
    private let deviceLabel = UILabel()
    private let storageTitle = UILabel()
    private let storageDetails = UILabel()
    private let fileIndicator = UIView()
    private let playButton = UIButton(type: .system)
    private let folderButton = UIButton(type: .system)
    private let settingsButton = UIButton(type: .system)
    private let controllerButton = UIButton(type: .system)
    private let logsButton = UIButton(type: .system)
    private let modeButtons = [UIButton(type: .system), UIButton(type: .system), UIButton(type: .system)]
    private var focusIndex = 0
    private var heldUp = false
    private var heldDown = false
    private var heldA = false
    private enum PickerIntent { case folder, indexFile }
    private var pickerIntent: PickerIntent = .folder
    private var activePicker: UIDocumentPickerViewController?
    private var lastPickerAction = "None"

    private let mint = UIColor(red: 0.67, green: 0.92, blue: 0.66, alpha: 1)
    private let muted = UIColor(red: 0.63, green: 0.68, blue: 0.69, alpha: 1)
    private let panel = UIColor(red: 0.085, green: 0.105, blue: 0.115, alpha: 1)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = ""
        view.backgroundColor = .black
        background.colors = [
            UIColor(red: 0.065, green: 0.095, blue: 0.095, alpha: 1).cgColor,
            UIColor(red: 0.02, green: 0.03, blue: 0.035, alpha: 1).cgColor
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
        view.addSubview(scrollView)
        scrollView.addSubview(content)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 19),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -19),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 17),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -18),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -38)
        ])

        let top = UIStackView()
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 10
        let dot = UIView()
        dot.backgroundColor = mint
        dot.layer.cornerRadius = 4
        dot.translatesAutoresizingMaskIntoConstraints = false
        dot.widthAnchor.constraint(equalToConstant: 8).isActive = true
        dot.heightAnchor.constraint(equalToConstant: 8).isActive = true
        let wordmark = label("GTAV  /  iOS", size: 13, weight: .bold, color: .white)
        let build = label("LOCAL RUNTIME  •  0.2", size: 10, weight: .medium, color: muted)
        build.textAlignment = .right
        top.addArrangedSubview(dot)
        top.addArrangedSubview(wordmark)
        top.addArrangedSubview(build)
        wordmark.setContentHuggingPriority(.required, for: .horizontal)
        content.addArrangedSubview(top)

        let hero = UIStackView()
        hero.axis = .horizontal
        hero.spacing = 12
        hero.alignment = .center
        let heroCopy = UIStackView()
        heroCopy.axis = .vertical
        heroCopy.alignment = .leading
        heroCopy.spacing = 4
        let eyebrow = label("PLAY ON THIS DEVICE", size: 10, weight: .bold, color: mint)
        let title = label("GRAND THEFT AUTO V", size: 27, weight: .black, color: .white)
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.67
        title.numberOfLines = 1
        let sub = label("A18 • WebAssembly • WebGPU / Metal", size: 12, weight: .regular, color: muted)
        sub.adjustsFontSizeToFitWidth = true
        sub.minimumScaleFactor = 0.75
        heroCopy.addArrangedSubview(eyebrow)
        heroCopy.addArrangedSubview(title)
        heroCopy.addArrangedSubview(sub)
        gameIcon.contentMode = .scaleAspectFit
        gameIcon.tintColor = mint
        gameIcon.image = UIImage(systemName: "gamecontroller.fill")
        gameIcon.backgroundColor = UIColor.white.withAlphaComponent(0.035)
        gameIcon.layer.cornerRadius = 12
        gameIcon.clipsToBounds = true
        gameIcon.translatesAutoresizingMaskIntoConstraints = false
        gameIcon.widthAnchor.constraint(equalToConstant: 67).isActive = true
        gameIcon.heightAnchor.constraint(equalToConstant: 67).isActive = true
        hero.addArrangedSubview(heroCopy)
        hero.addArrangedSubview(gameIcon)
        heroCopy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        content.addArrangedSubview(hero)

        let storage = UIView()
        storage.backgroundColor = panel
        storage.layer.cornerRadius = 13
        storage.layer.borderWidth = 1
        storage.layer.borderColor = UIColor.white.withAlphaComponent(0.085).cgColor
        storage.translatesAutoresizingMaskIntoConstraints = false
        storage.heightAnchor.constraint(greaterThanOrEqualToConstant: 71).isActive = true
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
        disk.tintColor = mint
        disk.contentMode = .scaleAspectFit
        disk.translatesAutoresizingMaskIntoConstraints = false
        disk.widthAnchor.constraint(equalToConstant: 29).isActive = true
        disk.heightAnchor.constraint(equalToConstant: 29).isActive = true
        let stateText = UIStackView()
        stateText.axis = .vertical; stateText.spacing = 4
        storageTitle.textColor = .white
        storageTitle.font = .systemFont(ofSize: 14, weight: .bold)
        storageDetails.textColor = muted
        storageDetails.font = .systemFont(ofSize: 11)
        storageDetails.numberOfLines = 2
        stateText.addArrangedSubview(storageTitle)
        stateText.addArrangedSubview(storageDetails)
        fileIndicator.backgroundColor = UIColor.systemOrange
        fileIndicator.layer.cornerRadius = 5
        fileIndicator.translatesAutoresizingMaskIntoConstraints = false
        fileIndicator.widthAnchor.constraint(equalToConstant: 10).isActive = true
        fileIndicator.heightAnchor.constraint(equalToConstant: 10).isActive = true
        srow.addArrangedSubview(disk)
        srow.addArrangedSubview(stateText)
        srow.addArrangedSubview(fileIndicator)
        content.addArrangedSubview(storage)
        let tapStorage = UITapGestureRecognizer(target: self, action: #selector(chooseFolder))
        storage.addGestureRecognizer(tapStorage)
        storage.isUserInteractionEnabled = true
        storage.accessibilityLabel = "Choose USB game files folder"
        storage.accessibilityTraits = .button

        content.addArrangedSubview(label("START SESSION", size: 10, weight: .bold, color: muted))
        let modes = UIStackView()
        modes.axis = .horizontal
        modes.distribution = .fillEqually
        modes.spacing = 8
        for (i, name) in ["STORY", "FREE ROAM", "ENV_TEST"].enumerated() {
            let button = modeButtons[i]
            button.tag = i
            button.setTitle(name, for: .normal)
            button.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.78
            button.layer.cornerRadius = 9
            button.layer.borderWidth = 1
            button.heightAnchor.constraint(equalToConstant: 43).isActive = true
            button.addTarget(self, action: #selector(selectMode(_:)), for: .touchUpInside)
            modes.addArrangedSubview(button)
        }
        content.addArrangedSubview(modes)
        style(playButton, title: "LAUNCH GAME", symbol: "play.fill", filled: true)
        playButton.addTarget(self, action: #selector(launch), for: .touchUpInside)
        playButton.heightAnchor.constraint(equalToConstant: 50).isActive = true
        content.addArrangedSubview(playButton)

        let toolRow = UIStackView()
        toolRow.axis = .horizontal
        toolRow.distribution = .fillEqually
        toolRow.spacing = 8
        style(folderButton, title: "FILES", symbol: "folder", filled: false)
        style(settingsButton, title: "SETTINGS", symbol: "slider.horizontal.3", filled: false)
        style(controllerButton, title: "GAMEPAD", symbol: "gamecontroller", filled: false)
        folderButton.addTarget(self, action: #selector(chooseFolder), for: .touchUpInside)
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        controllerButton.addTarget(self, action: #selector(openControllerSetup), for: .touchUpInside)
        toolRow.addArrangedSubview(folderButton)
        toolRow.addArrangedSubview(settingsButton)
        toolRow.addArrangedSubview(controllerButton)
        content.addArrangedSubview(toolRow)

        let bottom = UIStackView()
        bottom.axis = .horizontal; bottom.spacing = 8; bottom.alignment = .center
        deviceLabel.font = .systemFont(ofSize: 10)
        deviceLabel.textColor = muted
        deviceLabel.numberOfLines = 2
        let flexible = UIView()
        flexible.setContentHuggingPriority(.defaultLow, for: .horizontal)
        style(logsButton, title: "LOGS", symbol: "doc.text", filled: false)
        logsButton.addTarget(self, action: #selector(exportLogs), for: .touchUpInside)
        logsButton.widthAnchor.constraint(equalToConstant: 86).isActive = true
        bottom.addArrangedSubview(deviceLabel)
        bottom.addArrangedSubview(flexible)
        bottom.addArrangedSubview(logsButton)
        content.addArrangedSubview(bottom)
        refresh()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .portrait }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        GameOrientation.request(.portrait, from: view)
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
        config.imagePadding = 5
        config.imagePlacement = .top
        config.titleLineBreakMode = .byTruncatingTail
        config.baseForegroundColor = filled ? UIColor.black : .white
        config.background.backgroundColor = filled ? mint : panel
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 9, leading: 4, bottom: 9, trailing: 4)
        b.configuration = config
        b.titleLabel?.font = .systemFont(ofSize: 11, weight: .bold)
        b.titleLabel?.numberOfLines = 1
        b.titleLabel?.lineBreakMode = .byTruncatingTail
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.75
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: filled ? 45 : 68).isActive = true
    }
    private func refresh() {
        updateMode()
        playButton.configuration?.title = "LAUNCH GAME"
        if let root = USBStorageManager.shared.root {
            let missing = USBStorageManager.shared.missingStartupAssets()
            storageTitle.text = root.lastPathComponent + "  /  USB"
            storageDetails.text = missing.isEmpty ? "Files detected • Ready for engine check"
                : "Missing \(missing.count) required startup resources • Tap FILES"
            storageDetails.textColor = missing.isEmpty ? mint : UIColor.systemOrange
            fileIndicator.backgroundColor = missing.isEmpty ? mint : UIColor.systemOrange
            playButton.isEnabled = true
            playButton.alpha = 1
            if let file = USBStorageManager.shared.file("b/8b0b5899ed/title/logo.png"),
               let image = UIImage(contentsOfFile: file.path) {
                gameIcon.image = image
                gameIcon.tintColor = .white
            }
        } else {
            storageTitle.text = "GAME DATA NOT SELECTED"
            storageDetails.text = "Connect USB-C • Tap FILES for folder or index.html fallback"
            storageDetails.textColor = muted
            fileIndicator.backgroundColor = .systemOrange
            playButton.isEnabled = true
            playButton.alpha = 1
            playButton.configuration?.title = "SELECT GAME FILES"
        }
        updateDevice(ControllerManager.shared.currentName)
        highlightFocus()
    }
    private func updateMode() {
        let current = EngineOptions.value("mode")
        for (i, b) in modeButtons.enumerated() {
            let selected = ["story", "sandbox5", "sandbox6"][i] == current
            b.backgroundColor = selected ? mint.withAlphaComponent(0.13) : panel
            b.layer.borderColor = (selected ? mint : UIColor.white.withAlphaComponent(0.11)).cgColor
            b.setTitleColor(selected ? mint : muted, for: .normal)
        }
    }
    private func updateDevice(_ name: String) {
        deviceLabel.text = name == "No controller" ? "◯  NO CONTROLLER  ·  PAIR IN IOS SETTINGS" : "●  " + name.uppercased()
    }
    @objc private func selectMode(_ sender: UIButton) {
        EngineOptions.set("mode", value: ["story", "sandbox5", "sandbox6"][sender.tag])
        updateMode()
        UISelectionFeedbackGenerator().selectionChanged()
    }
    private var buttons: [UIButton] { modeButtons + [playButton, folderButton, settingsButton, controllerButton, logsButton] }
    private func highlightFocus() {
        for (i, b) in buttons.enumerated() {
            b.layer.shadowColor = mint.cgColor
            b.layer.shadowOpacity = i == focusIndex ? 0.5 : 0
            b.layer.shadowRadius = 5
            b.layer.shadowOffset = .zero
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
    @objc private func chooseFolder() {
        let choices = UIAlertController(
            title: "Connect game files",
            message: "Choose the USB game folder. If tapping Open does nothing, use the index.html fallback to test this drive's file access.",
            preferredStyle: .actionSheet)
        choices.addAction(UIAlertAction(title: "Select playgta5.com folder", style: .default) { [weak self] _ in
            self?.openPicker(.folder)
        })
        choices.addAction(UIAlertAction(title: "Select index.html instead (USB fallback)", style: .default) { [weak self] _ in
            self?.openPicker(.indexFile)
        })
        choices.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        choices.popoverPresentationController?.sourceView = folderButton
        choices.popoverPresentationController?.sourceRect = folderButton.bounds
        present(choices, animated: true)
    }

    private func openPicker(_ mode: PickerIntent) {
        if let shown = presentedViewController {
            // UIAlertController actions can run before the sheet finishes dismissal.
            // Never swallow the picker action just because that sheet is still visible.
            shown.dismiss(animated: true) { [weak self] in
                self?.openPicker(mode)
            }
            return
        }
        pickerIntent = mode
        lastPickerAction = "Opened " + (mode == .folder ? "folder" : "index.html") + " picker"
        // Apple documents [.folder] as the sole content type for recursive USB
        // directory grants. The alternate picker is file-only, never a claim that
        // choosing one file grants permission to its sibling archives.
        let picker: UIDocumentPickerViewController
        switch mode {
        case .folder:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        case .indexFile:
            picker = UIDocumentPickerViewController(forOpeningContentTypes: [.html], asCopy: false)
        }
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.shouldShowFileExtensions = true
        // Don't force fullScreen: the Files extension owns the selection UI.
        // Keeping a strong delegate/host reference prevents premature teardown.
        activePicker = picker
        LogStore.shared.write("usb-storage", "Files picker presented, mode=\(lastPickerAction)")
        present(picker, animated: true) { [weak self] in
            self?.storageDetails.text = "Choose in Files and tap Open. For USB problems, use the index.html fallback."
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        let message = "Files picker cancelled, intent=\(pickerIntent), last=\(lastPickerAction). No URL was granted."
        LogStore.shared.write("usb-storage", message)
        storageDetails.text = "No folder selected • Files picker cancelled"
        activePicker = nil
        refresh()
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let method = pickerIntent
        activePicker = nil
        LogStore.shared.write("usb-storage",
            "documentPicker didPickDocumentsAt invoked: urls=\(urls.count), mode=\(method)")
        guard let url = urls.first else {
            LogStore.shared.write("usb-storage", "Folder picker returned an empty selection")
            showPickerResult("No selection", "Files returned no URL. Retry or use the index.html fallback.")
            return
        }
        LogStore.shared.write("usb-storage",
            "Picker URL: \(url.path), isFileURL=\(url.isFileURL)")
        let result: Result<URL, Error>
        do {
            switch method {
            case .folder:
                try USBStorageManager.shared.choose(url)
            case .indexFile:
                try USBStorageManager.shared.chooseIndexFile(url)
            }
            result = .success(url)
        } catch {
            result = .failure(error)
        }
        refresh()
        switch result {
        case .success:
            LogStore.shared.write("usb-storage",
                "Picker accepted, game root=\(USBStorageManager.shared.root?.path ?? "nil")")
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showPickerResult("USB game files connected",
                "Verified game.wasm signature and access to the data directory. The game will continue reading assets from USB-C, not internal storage.")
        case .failure(let error):
            LogStore.shared.write("usb-storage",
                "Picker selection rejected: \(error.localizedDescription)")
            showPickerResult("Could not access game files",
                error.localizedDescription + "\n\nIf the folder picker won't grant access, try the index.html fallback. If that fails too, iOS has not granted this app permission to read the entire USB game folder.")
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
        } else {
            present(alert, animated: true)
        }
    }
    @objc private func launch() {
        guard USBStorageManager.shared.root != nil else { chooseFolder(); return }
        let missing = USBStorageManager.shared.missingStartupAssets()
        if !missing.isEmpty {
            let alert = UIAlertController(title: "Missing game resources",
                message: missing.joined(separator: "\n") + "\n\nThe local server runs inside the app; Launch-Local.cmd is Windows-only.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Change folder", style: .default) { [weak self] _ in self?.chooseFolder() })
            alert.addAction(UIAlertAction(title: "Diagnostics boot", style: .default) { [weak self] _ in self?.openGame() })
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
