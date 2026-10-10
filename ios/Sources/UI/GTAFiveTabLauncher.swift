import UIKit
import UniformTypeIdentifiers
import Metal
import GameController

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
        installHero("gtaios-reference-home", height: 370)
        play.titleLabel?.font = .systemFont(ofSize: 19, weight: .bold)
        play.heightAnchor.constraint(equalToConstant: 63).isActive = true
        play.layer.borderWidth = 1
        play.layer.borderColor = GTAReference.green.withAlphaComponent(0.8).cgColor
        play.addTarget(self, action: #selector(playPressed), for: .touchUpInside)
        stack.addArrangedSubview(play)
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
        city.addArrangedSubview(GTAReference.image("gtaios-library-skyline", height: 132))
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
        let cover = GTAReference.image("gtaios-library-thumb", height: 165, radius: 12)
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
        let logs = GTAReference.control("Export Logs", symbol: "square.and.arrow.up")
        logs.addTarget(self, action: #selector(exportPressed), for: .touchUpInside)
        actions.addArrangedSubview(browse)
        actions.addArrangedSubview(validate)
        actions.addArrangedSubview(logs)
        stack.addArrangedSubview(actions)
        let banner = GTAReference.image("gtaios-library-skyline", height: 180)
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
    @objc private func exportPressed() { GTAReference.exportLogs(from: self) }
}

final class GTAReferenceGraphicsController: GTAReferencePage {
    private let metalStatus = GTAReference.label("", size: 12, weight: .semibold)
    private let engineStatus = GTAReference.label("", size: 12, color: GTAReference.secondary)
    private let thermalStatus = GTAReference.label("", size: 12, color: GTAReference.secondary)
    override func viewDidLoad() {
        super.viewDidLoad()
        stack.addArrangedSubview(GTAReference.section("Game Settings"))
        installHero("gtaios-settings-hero", height: 205)
        let info = GTAReference.panelView()
        info.addArrangedSubview(GTAReference.label("Graphics", size: 19, weight: .bold))
        info.addArrangedSubview(GTAReference.label("Current device capability and stored renderer preferences",
                                                      size: 12, color: GTAReference.secondary))
        info.addArrangedSubview(metalStatus)
        info.addArrangedSubview(thermalStatus)
        info.addArrangedSubview(engineStatus)
        stack.addArrangedSubview(info)
        let graphics = GTAReference.panelView(8)
        graphics.addArrangedSubview(GTAReference.label("Graphics Settings", size: 18, weight: .bold))
        for specID in ["scale", "textureQuality", "shadowQuality", "reflectionQuality", "particleQuality", "grassQuality"] {
            addSetting(specID, to: graphics)
        }
        stack.addArrangedSubview(graphics)
        let advanced = GTAReference.panelView(8)
        advanced.addArrangedSubview(GTAReference.label("Advanced", size: 18, weight: .bold))
        addSetting("fps", to: advanced)
        stack.addArrangedSubview(advanced)
        let note = GTAReference.panelView()
        note.addArrangedSubview(GTAReference.label("Native engine status", size: 17, weight: .bold))
        note.addArrangedSubview(GTAReference.label(
            "The values above are saved locally. The Metal frame target is available in the native " +
            "preview; GTA V graphics options will apply only after the ARM64 game engine is integrated.",
            size: 12, color: GTAReference.secondary))
        stack.addArrangedSubview(note)
        let reset = GTAReference.control("Reset saved preferences", symbol: "arrow.counterclockwise")
        reset.addTarget(self, action: #selector(resetPressed), for: .touchUpInside)
        stack.addArrangedSubview(reset)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        metalStatus.text = MTLCreateSystemDefaultDevice().map { "Metal GPU: " + $0.name } ??
            "Metal GPU unavailable"
        let thermal: String
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = "Nominal"
        case .fair: thermal = "Fair"
        case .serious: thermal = "Serious"
        case .critical: thermal = "Critical"
        @unknown default: thermal = "Unavailable"
        }
        thermalStatus.text = "Device thermal state: " + thermal
        engineStatus.text = NativeEngineStatus.nativeEngineLinked ? "Native GTA V engine linked" :
            "Native GTA V engine not linked · in-game FPS unavailable"
    }
    private func addSetting(_ id: String, to panel: UIStackView) {
        guard let spec = EngineOptions.option(id) else { return }
        let button = GTAReference.control(spec.title + "   ·   " + EngineOptions.display(id),
                                          symbol: symbol(for: id))
        button.accessibilityIdentifier = "engine-option-" + id
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let self, let button else { return }
            self.presentOption(spec, button: button)
        }, for: .touchUpInside)
        panel.addArrangedSubview(button)
    }
    private func symbol(for id: String) -> String {
        switch id {
        case "fps": return "speedometer"
        case "scale": return "rectangle.expand.vertical"
        case "textureQuality": return "square.3.layers.3d"
        case "shadowQuality": return "sun.max"
        default: return "slider.horizontal.3"
        }
    }
    private func presentOption(_ spec: EngineOptions.Option, button: UIButton) {
        let sheet = UIAlertController(title: spec.title, message: spec.subtitle +
            "\nSaved locally · full-game support pending", preferredStyle: .actionSheet)
        for (label, value) in spec.choices {
            let selected = EngineOptions.value(spec.id) == value
            sheet.addAction(UIAlertAction(title: (selected ? "✓  " : "") + label, style: .default) { _ in
                EngineOptions.set(spec.id, value: value)
                button.configuration?.title = spec.title + "   ·   " + EngineOptions.display(spec.id)
                UISelectionFeedbackGenerator().selectionChanged()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = button
        present(sheet, animated: true)
    }
    @objc private func resetPressed() {
        EngineOptions.resetAll()
        for container in stack.arrangedSubviews {
            guard let panel = container as? UIStackView else { continue }
            for view in panel.arrangedSubviews {
                guard let button = view as? UIButton,
                      let id = button.accessibilityIdentifier?.replacingOccurrences(of: "engine-option-", with: ""),
                      let option = EngineOptions.option(id) else { continue }
                button.configuration?.title = option.title + "   ·   " + EngineOptions.display(id)
            }
        }
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
        let name = ControllerManager.shared.currentName
        controllerStatus.text = name == "No controller" ? "Controller: not connected" :
            "Controller: " + name
    }
    @objc private func library() { switchTab(1) }
    @objc private func graphics() { switchTab(2) }
    @objc private func controls() { switchTab(3) }
    @objc private func engine() { openEngineReport() }
    @objc private func logs() { GTAReference.exportLogs(from: self) }
}