import UIKit
import UniformTypeIdentifiers
import Metal
import GameController
import AVKit
import AVFoundation

// Reference-driven native navigation: every destination has its own controller.
// Decorative GTA V images are bundled; all action/status data comes from iOS or runtime APIs.
enum GTAReference {
    static let green = UIColor(red: 0.29, green: 1.00, blue: 0.61, alpha: 1)
    static let blue = UIColor(red: 0.39, green: 0.72, blue: 1, alpha: 1)
    static let night = UIColor(red: 0.015, green: 0.029, blue: 0.057, alpha: 1)
    static let panel = UIColor(red: 0.053, green: 0.079, blue: 0.137, alpha: 1)
    static let ink = UIColor(red: 0.94, green: 0.96, blue: 1, alpha: 1)
    static let secondary = UIColor(red: 0.72, green: 0.77, blue: 0.88, alpha: 1)

    static func label(_ value: String, size: CGFloat = 14, weight: UIFont.Weight = .regular,
                      color: UIColor = GTAReference.ink) -> UILabel {
        let l = UILabel()
        l.text = value
        l.font = .systemFont(ofSize: size, weight: weight)
        l.textColor = color
        l.numberOfLines = 0
        l.adjustsFontForContentSizeCategory = true
        return l
    }
    static func image(_ name: String, height: CGFloat, radius: CGFloat = 16) -> UIImageView {
        let file = Bundle.main.url(forResource: name, withExtension: "jpg")
        let v = UIImageView(image: file.flatMap { UIImage(contentsOfFile: $0.path) })
        v.contentMode = .scaleAspectFill
        v.clipsToBounds = true
        v.layer.cornerRadius = radius
        v.layer.cornerCurve = .continuous
        v.backgroundColor = panel
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        return v
    }
    static func panelView(_ padding: CGFloat = 14) -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 8
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = .init(top: padding, leading: padding,
                                               bottom: padding, trailing: padding)
        stack.backgroundColor = panel
        stack.layer.cornerRadius = 17
        stack.layer.cornerCurve = .continuous
        stack.layer.borderWidth = 0.8
        stack.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        return stack
    }
    static func control(_ text: String, symbol: String, color: UIColor = panel) -> UIButton {
        let b = UIButton(type: .system)
        var cfg = UIButton.Configuration.filled()
        cfg.title = text
        cfg.image = UIImage(systemName: symbol)
        cfg.imagePlacement = .leading
        cfg.imagePadding = 8
        cfg.baseBackgroundColor = color
        cfg.baseForegroundColor = color == green ? night : ink
        cfg.cornerStyle = .large
        cfg.contentInsets = .init(top: 15, leading: 12, bottom: 15, trailing: 12)
        cfg.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { old in
            var result = old
            result.font = .systemFont(ofSize: 14, weight: .bold)
            return result
        }
        b.configuration = cfg
        b.titleLabel?.adjustsFontSizeToFitWidth = true
        b.titleLabel?.minimumScaleFactor = 0.8
        b.heightAnchor.constraint(greaterThanOrEqualToConstant: 55).isActive = true
        return b
    }
    static func statusRow(_ title: String, detail: UILabel, symbol: String) -> UIStackView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = blue
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 23).isActive = true
        row.addArrangedSubview(icon)
        row.addArrangedSubview(label(title, size: 13, weight: .semibold))
        row.addArrangedSubview(UIView())
        detail.textAlignment = .right
        detail.textColor = secondary
        detail.font = .systemFont(ofSize: 11, weight: .medium)
        detail.numberOfLines = 2
        detail.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(detail)
        return row
    }
    static func section(_ value: String) -> UILabel {
        label(value, size: 21, weight: .bold)
    }
    static func present(_ title: String, message: String, from controller: UIViewController) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        controller.present(alert, animated: true)
    }
    static func exportLogs(from controller: UIViewController) {
        let url = LogStore.shared.exportURL()
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = controller.view
        controller.present(activity, animated: true)
    }
}

final class GTAFiveTabController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = GTAReference.night
        delegate = self
        let pages: [(UIViewController, String, String)] = [
            (GTAReferenceHomeController(), "Home", "house.fill"),
            (GTAReferenceLibraryController(), "Library", "folder.fill"),
            (GTAReferenceGraphicsController(), "Graphics", "display"),
            (ControllerSettingsViewController(), "Controls", "gamecontroller.fill"),
            (GTAReferenceMoreController(), "More", "ellipsis")
        ]
        viewControllers = pages.map { entry in
            let nav = GameNavigationController(rootViewController: entry.0)
            nav.setNavigationBarHidden(true, animated: false)
            nav.navigationBar.tintColor = GTAReference.green
            nav.navigationBar.barStyle = .black
            nav.tabBarItem = UITabBarItem(title: entry.1, image: UIImage(systemName: entry.2), tag: 0)
            return nav
        }
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = GTAReference.night
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.14)
        let item = appearance.stackedLayoutAppearance
        item.normal.iconColor = GTAReference.secondary
        item.normal.titleTextAttributes = [.foregroundColor: GTAReference.secondary,
            .font: UIFont.systemFont(ofSize: 10, weight: .medium)]
        item.selected.iconColor = GTAReference.green
        item.selected.titleTextAttributes = [.foregroundColor: GTAReference.green,
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold)]
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = GTAReference.green
        tabBar.unselectedItemTintColor = GTAReference.secondary
        tabBar.isTranslucent = false
        #if targetEnvironment(simulator)
        chooseSnapshotTab()
        #endif
    }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        if let nav = selectedViewController as? UINavigationController,
           nav.topViewController is GameViewController { return .allButUpsideDown }
        return .portrait
    }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        if let nav = selectedViewController as? UINavigationController,
           nav.topViewController is GameViewController { return .landscapeRight }
        return .portrait
    }
    func select(_ index: Int) { selectedIndex = index }
    #if targetEnvironment(simulator)
    private func chooseSnapshotTab() {
        // Only used by GitHub simulator screenshots. No status values are mocked.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--snapshot-library") { selectedIndex = 1 }
        if arguments.contains("--snapshot-graphics") { selectedIndex = 2 }
        if arguments.contains("--snapshot-controls") { selectedIndex = 3 }
        if arguments.contains("--snapshot-more") { selectedIndex = 4 }
    }
    #endif
}
extension GTAFiveTabController: UITabBarControllerDelegate {}

class GTAReferencePage: UIViewController {
    let scroll = UIScrollView()
    let stack = UIStackView()
    var extendsHeroUnderStatusBar: Bool { false }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = GTAReference.night
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsVerticalScrollIndicator = false
        scroll.alwaysBounceVertical = true
        view.addSubview(scroll)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 15
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: extendsHeroUnderStatusBar ? view.topAnchor : view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: extendsHeroUnderStatusBar ? 0 : 12),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -30),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 17),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -17)
        ])
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    func switchTab(_ index: Int) { (tabBarController as? GTAFiveTabController)?.select(index) }
    func openEngineReport() {
        navigationController?.setNavigationBarHidden(false, animated: true)
        let gameplay = GameViewController()
        gameplay.hidesBottomBarWhenPushed = true
        navigationController?.pushViewController(gameplay, animated: true)
    }
    func installHero(_ name: String, height: CGFloat) {
        let cover = GTAReference.image(name, height: height)
        cover.accessibilityLabel = "Grand Theft Auto V Los Santos artwork"
        stack.addArrangedSubview(cover)
    }
}

final class GTAReferenceHomeController: GTAReferencePage {
    override var extendsHeroUnderStatusBar: Bool { true }
    private let play = GTAReference.control("Play GTA V", symbol: "play.fill", color: GTAReference.green)
    private let readiness = GTAReference.label("", size: 11, weight: .medium, color: GTAReference.secondary)
    override func viewDidLoad() {
        super.viewDidLoad()
        // Reference-matched full-bleed GTA V artwork with a real, state-driven action.
        let hero = UIView()
        hero.clipsToBounds = true
        hero.layer.cornerRadius = 17
        hero.layer.cornerCurve = .continuous
        hero.translatesAutoresizingMaskIntoConstraints = false
        hero.heightAnchor.constraint(equalToConstant: 370).isActive = true
        let art = GTAReference.image("gtav-official-cover", height: 370, radius: 0)
        hero.addSubview(art)
        NSLayoutConstraint.activate([
            art.leadingAnchor.constraint(equalTo: hero.leadingAnchor),
            art.trailingAnchor.constraint(equalTo: hero.trailingAnchor),
            art.topAnchor.constraint(equalTo: hero.topAnchor),
            art.bottomAnchor.constraint(equalTo: hero.bottomAnchor)
        ])
        play.titleLabel?.font = .systemFont(ofSize: 19, weight: .bold)
        play.layer.borderWidth = 1
        play.layer.borderColor = GTAReference.green.withAlphaComponent(0.9).cgColor
        play.layer.cornerRadius = 19
        play.addTarget(self, action: #selector(playPressed), for: .touchUpInside)
        play.translatesAutoresizingMaskIntoConstraints = false
        hero.addSubview(play)
        NSLayoutConstraint.activate([
            play.leadingAnchor.constraint(equalTo: hero.leadingAnchor, constant: 19),
            play.trailingAnchor.constraint(equalTo: hero.trailingAnchor, constant: -19),
            play.bottomAnchor.constraint(equalTo: hero.bottomAnchor, constant: -14),
            play.heightAnchor.constraint(equalToConstant: 63)
        ])
        stack.addArrangedSubview(hero)
        readiness.textAlignment = .center
        stack.addArrangedSubview(readiness)
        let actions = UIStackView()
        actions.axis = .horizontal
        actions.distribution = .fillEqually
        actions.spacing = 11
        let graphics = GTAReference.control("Game Settings", symbol: "gearshape.fill")
        graphics.addTarget(self, action: #selector(openGraphics), for: .touchUpInside)
        let files = GTAReference.control("Game Files", symbol: "folder.fill")
        files.addTarget(self, action: #selector(openLibrary), for: .touchUpInside)
        actions.addArrangedSubview(graphics)
        actions.addArrangedSubview(files)
        stack.addArrangedSubview(actions)
        let city = GTAReference.panelView(0)
        city.addArrangedSubview(GTAReference.image("gtav-official-header", height: 132))
        let cityText = GTAReference.label("Los Santos", size: 16, weight: .bold)
        cityText.textAlignment = .center
        city.addArrangedSubview(cityText)
        let subtitle = GTAReference.label("Grand Theft Auto V · Local USB game library", size: 12,
                                         color: GTAReference.secondary)
        subtitle.textAlignment = .center
        city.addArrangedSubview(subtitle)
        stack.addArrangedSubview(city)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let hasFiles = USBStorageManager.shared.root != nil
        let engine = NativeEngineStatus.nativeEngineLinked
        // A real unavailable engine never yields a fictitious working Play action.
        let title = !hasFiles ? "Select GTA V Files" : (engine ? "Play GTA V" : "Check Engine")
        play.configuration?.title = title
        play.configuration?.image = UIImage(systemName: engine && hasFiles ? "play.fill" : "folder.fill")
        readiness.text = !hasFiles ? "No accessible GTA V folder selected" :
            (engine ? "GTA V runtime linked" : "GTA V engine not linked · gameplay unavailable")
    }
    @objc private func playPressed() {
        guard USBStorageManager.shared.root != nil else { switchTab(1); return }
        guard NativeEngineStatus.nativeEngineLinked else { openEngineReport(); return }
        openEngineReport()
    }
    @objc private func openGraphics() { switchTab(2) }
    @objc private func openLibrary() { switchTab(1) }
}

final class GTAReferenceLibraryController: GTAReferencePage, UIDocumentPickerDelegate {
    private let connection = GTAReference.label("", size: 12, weight: .semibold,
                                                color: GTAReference.secondary)
    private let diskInfo = GTAReference.label("", size: 12, weight: .medium,
                                              color: GTAReference.secondary)
    private let engineInfo = GTAReference.label("", size: 11, weight: .medium,
                                                color: GTAReference.secondary)
    private var selectedAsFile = false
    override func viewDidLoad() {
        super.viewDidLoad()
        stack.addArrangedSubview(GTAReference.section("Game Library"))
        stack.addArrangedSubview(GTAReference.label("Manage Grand Theft Auto V game files", size: 13,
                                                      color: GTAReference.secondary))
        let card = GTAReference.panelView(15)
        let cardRow = UIStackView()
        cardRow.axis = .horizontal
        cardRow.spacing = 13
        cardRow.alignment = .center
        let cover = GTAReference.image("gtav-official-cover", height: 165, radius: 12)
        cover.widthAnchor.constraint(equalToConstant: 130).isActive = true
        cardRow.addArrangedSubview(cover)
        let detail = UIStackView()
        detail.axis = .vertical
        detail.spacing = 8
        detail.addArrangedSubview(GTAReference.label("Grand Theft Auto V", size: 17, weight: .bold))
        detail.addArrangedSubview(GTAReference.label("Rockstar Games", size: 12,
                                                   color: GTAReference.secondary))
        connection.numberOfLines = 2
        detail.addArrangedSubview(connection)
        detail.addArrangedSubview(GTAReference.label("USB-C · local game assets", size: 11,
                                                   color: GTAReference.blue))
        cardRow.addArrangedSubview(detail)
        card.addArrangedSubview(cardRow)
        card.addArrangedSubview(diskInfo)
        stack.addArrangedSubview(card)
        stack.addArrangedSubview(GTAReference.section("Quick Actions"))
        let actions = UIStackView()
        actions.axis = .horizontal
        actions.spacing = 8
        actions.distribution = .fillEqually
        let browse = GTAReference.control("Browse Files", symbol: "folder.fill")
        browse.addTarget(self, action: #selector(browsePressed), for: .touchUpInside)
        let validate = GTAReference.control("Validate", symbol: "checkmark.shield.fill")
        validate.addTarget(self, action: #selector(validatePressed), for: .touchUpInside)
        let disconnect = GTAReference.control("Disconnect", symbol: "externaldrive.badge.xmark")
        disconnect.addTarget(self, action: #selector(disconnectPressed), for: .touchUpInside)
        actions.addArrangedSubview(browse)
        actions.addArrangedSubview(validate)
        actions.addArrangedSubview(disconnect)
        stack.addArrangedSubview(actions)
        let banner = GTAReference.image("gtav-official-header", height: 180)
        stack.addArrangedSubview(banner)
        let infoCard = GTAReference.panelView()
        infoCard.addArrangedSubview(GTAReference.label("Game Information", size: 19, weight: .bold))
        infoCard.addArrangedSubview(GTAReference.label("Title: Grand Theft Auto V · Developer: Rockstar Games",
                                                       size: 12, color: GTAReference.secondary))
        infoCard.addArrangedSubview(engineInfo)
        stack.addArrangedSubview(infoCard)
        NotificationCenter.default.addObserver(self, selector: #selector(storageChanged),
            name: USBStorageManager.changedNotification, object: nil)
        refresh()
    }
    deinit { NotificationCenter.default.removeObserver(self) }
    override func viewWillAppear(_ animated: Bool) { super.viewWillAppear(animated); refresh() }
    @objc private func storageChanged() { refresh() }
    private func refresh() {
        if let root = USBStorageManager.shared.root {
            let missing = USBStorageManager.shared.missingStartupAssets()
            connection.text = missing.isEmpty ? "Game data readable ✓" : "Game folder selected · missing assets"
            connection.textColor = missing.isEmpty ? GTAReference.green : GTAReference.blue
            diskInfo.text = "Selected folder: " + root.lastPathComponent
            engineInfo.text = "Run Validate to inspect real engine file bytes"
        } else {
            connection.text = "Not selected"
            connection.textColor = GTAReference.blue
            diskInfo.text = "Select your own local game mirror from the Files app"
            engineInfo.text = "Game engine archive: not connected"
        }
    }
    @objc private func browsePressed() {
        let sheet = UIAlertController(title: "Choose GTA V Files", message: nil,
                                      preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Choose Folder", style: .default) { [weak self] _ in
            self?.pick(useFile: false)
        })
        sheet.addAction(UIAlertAction(title: "Select index.html fallback", style: .default) { [weak self] _ in
            self?.pick(useFile: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        present(sheet, animated: true)
    }
    private func pick(useFile: Bool) {
        selectedAsFile = useFile
        let types: [UTType] = useFile ? [.html] : [.folder]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        picker.delegate = self
        picker.allowsMultipleSelection = false
        present(picker, animated: true)
    }
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let chosen = urls.first else { return }
        USBStorageManager.shared.chooseAsync(chosen, fromFile: selectedAsFile) { [weak self] result in
            guard let self else { return }
            self.refresh()
            switch result {
            case .success: break
            case .failure(let err):
                GTAReference.present("Cannot read GTA V files", message: err.localizedDescription, from: self)
            }
        }
    }
    @objc private func validatePressed() {
        guard USBStorageManager.shared.root != nil else { browsePressed(); return }
        NativeEngineStatus.inspect { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let value):
                let bytes = ByteCountFormatter.string(fromByteCount: value.byteCount, countStyle: .file)
                self.engineInfo.text = "Inspected game.wasm: " + bytes
                GTAReference.present("Game files inspected", message:
                    "WebAssembly engine readable: " + bytes +
                    ". Shader index found. This does not establish playable GTA V runtime.", from: self)
            case .failure(let error):
                GTAReference.present("File validation failed", message: error.localizedDescription, from: self)
            }
        }
    }
    @objc private func disconnectPressed() {
        guard USBStorageManager.shared.root != nil else {
            GTAReference.present("No connected library", message:
                "Select a GTA V folder from your external drive first.", from: self)
            return
        }
        let alert = UIAlertController(title: "Disconnect GTA V Library?",
            message: "Remove the bookmark and release USB access. No game files will be deleted.",
            preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Disconnect", style: .destructive) { [weak self] _ in
            USBStorageManager.shared.disconnect {
                self?.refresh()
            }
        })
        present(alert, animated: true)
    }
    @objc private func exportPressed() { GTAReference.exportLogs(from: self) }
}

final class GTAReferenceGraphicsController: GTAReferencePage {
    private let metal = GTAReference.label("", size: 11, weight: .semibold)
    private let thermal = GTAReference.label("", size: 11, color: GTAReference.secondary)
    private let readiness = GTAReference.label("", size: 11, color: GTAReference.secondary)
    private var engineButtons: [(UIButton, String)] = []
    private var valueLabels: [(UILabel, String)] = []
    private var presetButton: UIButton?
    private let controlScheme = GTAReference.label("", size: 12, color: GTAReference.green)
    private let outputRoute = GTAReference.label("", size: 12, color: GTAReference.secondary)

    override func viewDidLoad() {
        super.viewDidLoad()
        stack.addArrangedSubview(GTAReference.section("Game Settings"))
        installHero("gtav-official-hero", height: 195)

        let performance = GTAReference.panelView(11)
        performance.addArrangedSubview(GTAReference.label("Performance Monitor", size: 18, weight: .bold))
        performance.addArrangedSubview(GTAReference.label(
            "Real iPhone hardware status · gameplay telemetry is unavailable", size: 11,
            color: GTAReference.secondary))
        performance.addArrangedSubview(metal)
        performance.addArrangedSubview(thermal)
        performance.addArrangedSubview(readiness)
        stack.addArrangedSubview(performance)

        let display = GTAReference.panelView(9)
        display.addArrangedSubview(GTAReference.label("Graphics", size: 19, weight: .bold))
        let preset = GTAReference.control("Graphics Preset", symbol: "camera.filters")
        preset.accessibilityIdentifier = "graphics-preset"
        preset.addTarget(self, action: #selector(showPresets), for: .touchUpInside)
        display.addArrangedSubview(preset)
        presetButton = preset
        addScale(to: display)
        addSwitch(to: display, title: "VSync", detail: "Preference saved; game renderer pending",
                  symbol: "arrow.triangle.2.circlepath", key: "vsync", fallback: true)
        for id in ["textureQuality", "shadowQuality", "reflectionQuality", "particleQuality", "grassQuality"] {
            addEngineOption(id, to: display)
        }
        let aa = GTAReference.control("Anti-Aliasing", symbol: "circle.hexagongrid")
        aa.accessibilityIdentifier = "staged-anti-aliasing"
        aa.addAction(UIAction { [weak self, weak aa] _ in
            guard let self, let aa else { return }
            let sheet = UIAlertController(title: "Anti-Aliasing",
                message: "Stored for future GTA V renderer integration; not yet an active shader setting.",
                preferredStyle: .actionSheet)
            for quality in ["Off", "FXAA", "TAA"] {
                sheet.addAction(UIAlertAction(title: quality, style: .default) { _ in
                    GTALaunchPreferences.setText("antiAliasing", value: quality)
                    aa.configuration?.title = "Anti-Aliasing · " + quality + " (staged)"
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.sourceView = aa
            self.present(sheet, animated: true)
        }, for: .touchUpInside)
        display.addArrangedSubview(aa)
        stack.addArrangedSubview(display)

        let controls = GTAReference.panelView(9)
        controls.addArrangedSubview(GTAReference.label("Controls", size: 19, weight: .bold))
        let scheme = GTAReference.control("Control Scheme", symbol: "gamecontroller.fill")
        scheme.addAction(UIAction { [weak self, weak scheme] _ in
            guard let self, let scheme else { return }
            let sheet = UIAlertController(title: "Control Scheme",
                message: "Preferred input mode saved locally. Hardware detection always remains active.",
                preferredStyle: .actionSheet)
            for value in ["Automatic", "Touch", "Controller"] {
                sheet.addAction(UIAlertAction(title: value, style: .default) { _ in
                    GTALaunchPreferences.setText("controlScheme", value: value)
                    scheme.configuration?.title = "Control Scheme · " + value + " (staged)"
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.sourceView = scheme
            self.present(sheet, animated: true)
        }, for: .touchUpInside)
        controls.addArrangedSubview(scheme)
        controlScheme.numberOfLines = 2
        controls.addArrangedSubview(controlScheme)
        addSwitch(to: controls, title: "Vibration", detail: "Real connected-controller haptic test",
                  symbol: "dot.radiowaves.left.and.right", key: "controllerVibration", fallback: true)
        addFraction(to: controls, title: "Touch Control Opacity", symbol: "hand.tap",
                    key: "touchOpacity", fallback: 0.7,
                    footnote: "Applied to the native touch overlay")
        addFraction(to: controls, title: "Aim Sensitivity", symbol: "scope",
                    key: "aimSensitivity", fallback: 0.5,
                    footnote: "Saved for engine integration; analog camera tuning is in Controls")
        let mapping = GTAReference.control("Controller Mapping & Deadzone", symbol: "slider.horizontal.3")
        mapping.addAction(UIAction { [weak self] _ in
            self?.tabBarController?.selectedIndex = 3
        }, for: .touchUpInside)
        controls.addArrangedSubview(mapping)
        stack.addArrangedSubview(controls)

        let advanced = GTAReference.panelView(9)
        advanced.addArrangedSubview(GTAReference.label("Advanced", size: 19, weight: .bold))
        addEngineOption("fps", to: advanced)
        stack.addArrangedSubview(advanced)

        let audio = GTAReference.panelView(9)
        audio.addArrangedSubview(GTAReference.label("Audio & Haptics", size: 19, weight: .bold))
        let route = UIStackView()
        route.axis = .horizontal
        route.spacing = 8
        route.alignment = .center
        route.addArrangedSubview(GTAReference.label("Audio Output", size: 13, weight: .semibold))
        route.addArrangedSubview(UIView())
        let picker = AVRoutePickerView(frame: CGRect(x: 0, y: 0, width: 45, height: 45))
        picker.tintColor = GTAReference.blue
        picker.activeTintColor = GTAReference.green
        picker.widthAnchor.constraint(equalToConstant: 45).isActive = true
        picker.heightAnchor.constraint(equalToConstant: 45).isActive = true
        route.addArrangedSubview(picker)
        audio.addArrangedSubview(route)
        audio.addArrangedSubview(outputRoute)
        addFraction(to: audio, title: "Master Volume", symbol: "speaker.wave.2",
                    key: "masterVolume", fallback: 1.0,
                    footnote: "Live native PCM mixer gain")
        addFraction(to: audio, title: "Music Volume", symbol: "music.note",
                    key: "musicVolume", fallback: 0.6,
                    footnote: "Staged until the game engine exposes music streams")
        addFraction(to: audio, title: "Dialogue Volume", symbol: "text.bubble",
                    key: "dialogueVolume", fallback: 0.8,
                    footnote: "Staged until the game engine exposes dialogue streams")
        stack.addArrangedSubview(audio)

        let note = GTAReference.panelView()
        note.addArrangedSubview(GTAReference.label(
            "Controls marked staged are saved, not simulated. Real GTA V graphics and separate audio " +
            "mixing require the unlinked native game engine.", size: 11,
            color: GTAReference.secondary))
        stack.addArrangedSubview(note)

        let reset = GTAReference.control("Reset All Preferences", symbol: "arrow.counterclockwise")
        reset.addTarget(self, action: #selector(resetPressed), for: .touchUpInside)
        stack.addArrangedSubview(reset)
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
    }

    private func refresh() {
        metal.text = MTLCreateSystemDefaultDevice().map { "Metal GPU: " + $0.name }
            ?? "Metal GPU: unavailable"
        let thermals = ["Nominal", "Fair", "Serious", "Critical"]
        let state = ProcessInfo.processInfo.thermalState.rawValue
        thermal.text = "Device thermal state: " +
            (state >= 0 && state < thermals.count ? thermals[state] : "Unknown")
        readiness.text = NativeEngineStatus.nativeEngineLinked ?
            "Native engine linked · game FPS must be measured inside gameplay" :
            "GTA V engine not linked · game FPS / shader usage unavailable"
        controlScheme.text = GCController.controllers().first(where: { $0.extendedGamepad != nil })
            .flatMap { $0.vendorName }.map { "Hardware detected: " + $0 } ??
            "Hardware detected: none"
        outputRoute.text = "Current audio route: " +
            (AVAudioSession.sharedInstance().currentRoute.outputs.first?.portName ?? "Unavailable")
        presetButton?.configuration?.title = "Graphics Preset · " +
            GTALaunchPreferences.text("preset", fallback: "Custom")
        for (button, id) in engineButtons {
            if let spec = EngineOptions.option(id) {
                button.configuration?.title = spec.title + " · " + EngineOptions.display(id)
            }
        }
        for (label, id) in valueLabels where id == "scale" {
            label.text = EngineOptions.display("scale")
        }
    }

    @objc private func showPresets(_ sender: UIButton) {
        let sheet = UIAlertController(title: "Graphics Preset",
            message: "Presets write actual engine-option configuration; they are not proof of playable GTA V.",
            preferredStyle: .actionSheet)
        for name in ["Low", "Balanced", "High"] {
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                GTALaunchPreferences.applyPreset(name)
                self?.refresh()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = sender
        present(sheet, animated: true)
    }

    private func addEngineOption(_ id: String, to panel: UIStackView) {
        guard let spec = EngineOptions.option(id) else { return }
        let button = GTAReference.control(spec.title, symbol: "slider.horizontal.3")
        button.accessibilityIdentifier = "engine-option-" + id
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self, let button else { return }
            let sheet = UIAlertController(title: spec.title,
                message: spec.subtitle + "\nSaved for the native engine; effective in-game state pending.",
                preferredStyle: .actionSheet)
            for (label, value) in spec.choices {
                sheet.addAction(UIAlertAction(title: label, style: .default) { [weak self] _ in
                    EngineOptions.set(id, value: value)
                    GTALaunchPreferences.setText("preset", value: "Custom")
                    button.configuration?.title = spec.title + " · " + EngineOptions.display(id)
                    self?.refresh()
                })
            }
            sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            sheet.popoverPresentationController?.sourceView = button
            self.present(sheet, animated: true)
        }, for: .touchUpInside)
        panel.addArrangedSubview(button)
        engineButtons.append((button, id))
    }

    private func addScale(to panel: UIStackView) {
        let row = GTAReference.panelView(9)
        row.addArrangedSubview(GTAReference.label("Resolution Scale", size: 13, weight: .semibold))
        let track = UIStackView()
        track.axis = .horizontal
        track.spacing = 10
        track.alignment = .center
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 4
        slider.tintColor = GTAReference.green
        let choices = EngineOptions.option("scale")?.choices ?? []
        slider.value = Float(choices.firstIndex(where: { $0.1 == EngineOptions.value("scale") }) ?? 0)
        let value = GTAReference.label(EngineOptions.display("scale"), size: 12,
                                      color: GTAReference.green)
        value.widthAnchor.constraint(equalToConstant: 49).isActive = true
        slider.addAction(UIAction { _ in
            let index = Int(slider.value.rounded())
            guard choices.indices.contains(index) else { return }
            slider.value = Float(index)
            EngineOptions.set("scale", value: choices[index].1)
            GTALaunchPreferences.setText("preset", value: "Custom")
            value.text = EngineOptions.display("scale")
        }, for: .valueChanged)
        track.addArrangedSubview(slider)
        track.addArrangedSubview(value)
        row.addArrangedSubview(track)
        panel.addArrangedSubview(row)
        valueLabels.append((value, "scale"))
    }

    private func addSwitch(to panel: UIStackView, title: String, detail: String,
                           symbol: String, key: String, fallback: Bool) {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 9
        row.alignment = .center
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = GTAReference.blue
        icon.contentMode = .scaleAspectFit
        icon.widthAnchor.constraint(equalToConstant: 24).isActive = true
        row.addArrangedSubview(icon)
        let text = UIStackView()
        text.axis = .vertical
        text.spacing = 3
        text.addArrangedSubview(GTAReference.label(title, size: 13, weight: .semibold))
        text.addArrangedSubview(GTAReference.label(detail, size: 10, color: GTAReference.secondary))
        row.addArrangedSubview(text)
        let toggle = UISwitch()
        toggle.onTintColor = GTAReference.green
        toggle.isOn = GTALaunchPreferences.enabled(key, fallback: fallback)
        toggle.addAction(UIAction { _ in
            GTALaunchPreferences.setEnabled(key, value: toggle.isOn)
            if key == "controllerVibration" && toggle.isOn {
                _ = ControllerManager.shared.testRumble()
            }
        }, for: .valueChanged)
        row.addArrangedSubview(toggle)
        panel.addArrangedSubview(row)
    }

    private func addFraction(to panel: UIStackView, title: String, symbol: String,
                             key: String, fallback: Double, footnote: String) {
        let group = GTAReference.panelView(8)
        let heading = UIStackView()
        heading.axis = .horizontal
        heading.spacing = 7
        let icon = UIImageView(image: UIImage(systemName: symbol))
        icon.tintColor = GTAReference.blue
        icon.widthAnchor.constraint(equalToConstant: 20).isActive = true
        heading.addArrangedSubview(icon)
        heading.addArrangedSubview(GTAReference.label(title, size: 13, weight: .semibold))
        group.addArrangedSubview(heading)
        let controls = UIStackView()
        controls.axis = .horizontal
        controls.spacing = 9
        controls.alignment = .center
        let slider = UISlider()
        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.value = Float(GTALaunchPreferences.fraction(key, fallback: fallback))
        slider.tintColor = GTAReference.green
        let value = GTAReference.label(String(Int(slider.value * 100)) + "%", size: 12,
                                       color: GTAReference.green)
        value.widthAnchor.constraint(equalToConstant: 40).isActive = true
        slider.addAction(UIAction { _ in
            GTALaunchPreferences.setFraction(key, value: Double(slider.value))
            value.text = String(Int(slider.value * 100)) + "%"
            if key == "masterVolume" { NativePCMOutput.shared.setMasterVolume(slider.value) }
        }, for: .valueChanged)
        controls.addArrangedSubview(slider)
        controls.addArrangedSubview(value)
        group.addArrangedSubview(controls)
        group.addArrangedSubview(GTAReference.label(footnote, size: 10,
                                                    color: GTAReference.secondary))
        panel.addArrangedSubview(group)
    }

    @objc private func resetPressed() {
        let sheet = UIAlertController(title: "Reset All Settings?",
            message: "Restore all graphics, controls and audio preferences to defaults.",
            preferredStyle: .alert)
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            EngineOptions.resetAll()
            GTALaunchPreferences.reset()
            NativePCMOutput.shared.setMasterVolume(1)
            guard let self else { return }
            // Recreate only the settings controller; calling viewDidLoad
            // a second time caused stacked duplicate views and observers.
            if let nav = self.navigationController {
                var controllers = nav.viewControllers
                if !controllers.isEmpty {
                    controllers[controllers.count - 1] = GTAReferenceGraphicsController()
                    nav.setViewControllers(controllers, animated: false)
                }
            }
        })
        present(sheet, animated: true)
    }
}

final class GTAReferenceMoreController: GTAReferencePage {
    private let controllerStatus = GTAReference.label("", size: 12, color: GTAReference.secondary)
    override func viewDidLoad() {
        super.viewDidLoad()
        stack.addArrangedSubview(GTAReference.section("More"))
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
        let about = GTAReference.panelView()
        about.addArrangedSubview(GTAReference.label("GTA V iOS Launcher", size: 19, weight: .bold))
        about.addArrangedSubview(GTAReference.label("Version " + version + " · Build " + build,
                                                       size: 12, color: GTAReference.secondary))
        about.addArrangedSubview(controllerStatus)
        stack.addArrangedSubview(about)
        let operations: [(String, String, Selector)] = [
            ("Game Library", "externaldrive", #selector(library)),
            ("Graphics", "display", #selector(graphics)),
            ("Controls", "gamecontroller.fill", #selector(controls)),
            ("Native Runtime Checks", "cpu", #selector(engine)),
            ("Export Diagnostic Logs", "square.and.arrow.up", #selector(logs))
        ]
        for (title, icon, handler) in operations {
            let button = GTAReference.control(title, symbol: icon)
            button.addTarget(self, action: handler, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
        stack.addArrangedSubview(GTAReference.label(
            "All operations are local. No storefront, cloud sync, updates, save progress or gameplay " +
            "statistics are claimed without corresponding implementations.",
            size: 12, color: GTAReference.secondary))
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Query the actual iOS hardware inventory, not a manager that may
        // have been stopped when the Controls tab disappeared.
        let name = GCController.controllers().first?.vendorName
        controllerStatus.text = name.map { "Controller: " + $0 } ??
            "Controller: not connected"
    }
    @objc private func library() { switchTab(1) }
    @objc private func graphics() { switchTab(2) }
    @objc private func controls() { switchTab(3) }
    @objc private func engine() { openEngineReport() }
    @objc private func logs() { GTAReference.exportLogs(from: self) }
}