import UIKit
import UniformTypeIdentifiers
import GameController

final class LauncherViewController: UIViewController, UIDocumentPickerDelegate {
    private let heading = UILabel()
    private let storageLabel = UILabel()
    private let statusLabel = UILabel()
    private let play = UIButton(type: .system)
    private let choose = UIButton(type: .system)
    private let settings = UIButton(type: .system)
    private let export = UIButton(type: .system)
    private let controllerButton = UIButton(type: .system)
    private var focusedButton = 0
    private var lastA = false
    private var lastUp = false
    private var lastDown = false
    private let scroll = UIScrollView()
    private let stack = UIStackView()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.055, green: 0.068, blue: 0.09, alpha: 1)
        title = "GTA V iOS"
        navigationController?.navigationBar.prefersLargeTitles = false
        let accent = UIColor(red: 0.32, green: 0.78, blue: 0.46, alpha: 1)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 14
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24)
        ])
        heading.text = "GRAND THEFT AUTO V"
        heading.font = .systemFont(ofSize: 25, weight: .black)
        heading.textColor = .white
        heading.textAlignment = .center
        heading.numberOfLines = 2
        stack.addArrangedSubview(heading)
        let subtitle = text("Local A18 execution • External USB-C assets • No streaming", size: 13)
        subtitle.textAlignment = .center
        stack.addArrangedSubview(subtitle)

        style(choose, title: "SELECT USB GAME FOLDER", color: .systemGray)
        choose.addTarget(self, action: #selector(chooseFolder), for: .touchUpInside)
        stack.addArrangedSubview(choose)

        storageLabel.textColor = .lightGray
        storageLabel.font = .monospacedSystemFont(ofSize: 12, weight: .medium)
        storageLabel.numberOfLines = 3
        storageLabel.textAlignment = .center
        stack.addArrangedSubview(storageLabel)

        style(play, title: "LAUNCH ENGINE", color: accent)
        play.addTarget(self, action: #selector(launch), for: .touchUpInside)
        stack.addArrangedSubview(play)

        style(settings, title: "GRAPHICS & RUNTIME SETTINGS", color: .darkGray)
        settings.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        stack.addArrangedSubview(settings)

        style(controllerButton, title: "CONTROLLER SETUP & LIVE TEST", color: .darkGray)
        controllerButton.addTarget(self, action: #selector(openControllerSetup), for: .touchUpInside)
        stack.addArrangedSubview(controllerButton)

        style(export, title: "EXPORT FULL DEBUG LOGS", color: .darkGray)
        export.addTarget(self, action: #selector(exportLogs), for: .touchUpInside)
        stack.addArrangedSubview(export)

        statusLabel.text = "Engine compatibility has not been verified on iOS. USB assets are never imported into app storage."
        statusLabel.textColor = .lightGray
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.numberOfLines = 5
        statusLabel.textAlignment = .center
        stack.addArrangedSubview(statusLabel)
        refresh()
        highlightControllerFocus()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ControllerManager.shared.onConnection = { [weak self] name in
            self?.statusLabel.text = name == "No controller"
                ? "No controller connected. Pair Bluetooth controllers in iOS Settings."
                : "Controller: \(name). D-pad and A navigate the launcher."
        }
        ControllerManager.shared.onState = { [weak self] state in
            self?.handleController(state)
        }
        ControllerManager.shared.begin()
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ControllerManager.shared.stop()
    }

    private var controlButtons: [UIButton] { [choose, play, settings, controllerButton, export] }

    private func highlightControllerFocus() {
        for (index, button) in controlButtons.enumerated() {
            button.layer.borderColor = UIColor.systemGreen.cgColor
            button.layer.borderWidth = index == focusedButton ? 3 : 0
        }
    }

    private func handleController(_ state: [String: Double]) {
        guard presentedViewController == nil else { return }
        let up = (state["up"] ?? 0) > 0.5 || (state["ly"] ?? 0) > 0.6
        let down = (state["down"] ?? 0) > 0.5 || (state["ly"] ?? 0) < -0.6
        let a = (state["a"] ?? 0) > 0.5
        if up && !lastUp {
            focusedButton = max(0, focusedButton - 1)
            highlightControllerFocus()
        }
        if down && !lastDown {
            focusedButton = min(controlButtons.count - 1, focusedButton + 1)
            highlightControllerFocus()
        }
        if a && !lastA && controlButtons[focusedButton].isEnabled {
            controlButtons[focusedButton].sendActions(for: .touchUpInside)
        }
        lastUp = up; lastDown = down; lastA = a
    }

    private func text(_ string: String, size: CGFloat) -> UILabel {
        let label = UILabel()
        label.text = string
        label.textColor = .lightGray
        label.font = .systemFont(ofSize: size)
        label.numberOfLines = 0
        return label
    }

    private func style(_ button: UIButton, title: String, color: UIColor) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .bold)
        button.backgroundColor = color
        button.layer.cornerRadius = 12
        button.heightAnchor.constraint(equalToConstant: 53).isActive = true
    }

    private func refresh() {
        if let root = USBStorageManager.shared.root {
            storageLabel.text = "USB: \(root.lastPathComponent)\nData folder available"
            play.isEnabled = true
            play.alpha = 1
        } else {
            storageLabel.text = "USB: No game directory selected"
            play.isEnabled = false
            play.alpha = 0.4
        }
    }

    @objc private func chooseFolder() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do { try USBStorageManager.shared.choose(url); refresh() }
        catch {
            let alert = UIAlertController(title: "Invalid game folder", message: error.localizedDescription, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }

    @objc private func launch() {
        guard USBStorageManager.shared.root != nil else { return }
        let missing = USBStorageManager.shared.missingStartupAssets()
        if !missing.isEmpty {
            let alert = UIAlertController(
                title: "Game files missing",
                message: "The selected mirror/playgta5.com folder is missing:\n" +
                    missing.joined(separator: "\n") +
                    "\n\nThe README's Windows Launch-Local.cmd is not used on iOS. This app starts its own local server.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "Select Folder", style: .cancel) { [weak self] _ in
                self?.chooseFolder()
            })
            alert.addAction(UIAlertAction(title: "Run Diagnostics Anyway", style: .default) { [weak self] _ in
                self?.navigationController?.pushViewController(GameViewController(), animated: true)
            })
            present(alert, animated: true)
            return
        }
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
        if let popover = activity.popoverPresentationController {
            popover.sourceView = export
            popover.sourceRect = export.bounds
        }
        present(activity, animated: true)
    }
}
