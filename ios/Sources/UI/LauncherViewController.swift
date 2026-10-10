import UIKit
import UniformTypeIdentifiers

/// Game-first dashboard: cinematic library cover, one meaningful action,
/// two practical setup destinations and diagnostics tucked into overflow.
/// This deliberately avoids test-world menus, fake playable modes and
/// a home-screen-sized engineering status panel.
final class LauncherViewController: UIViewController, UIDocumentPickerDelegate {
    private let background = CAGradientLayer()
    private let scrollView = UIScrollView()
    private var scrollBottomConstraint: NSLayoutConstraint?
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
    private let usbStatusLabel = UILabel()
    private let hardwareStatusLabel = UILabel()
    private let assetBadge = UILabel()
    private let engineBadge = UILabel()
    private let continueLabel = UILabel()
    private let fpsBadge = UILabel()
    private let playGradient = CAGradientLayer()
    private let validateButton = UIButton(type: .system)
    private let updateButton = UIButton(type: .system)
    private let runtimeButton = UIButton(type: .system)
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
            UIColor(red: 0.071, green: 0.059, blue: 0.135, alpha: 1).cgColor,
            GTATheme.night.cgColor
        ]
        background.locations = [0, 0.44, 1]
        background.startPoint = CGPoint(x: 0, y: 0)
        background.endPoint = CGPoint(x: 1, y: 1)
        view.layer.insertSublayer(background, at: 0)

        // Persistent bottom dock matches the reference, avoiding fake
        // Store/Social views that are not provided by this native app.
        let dock = UIView()
        dock.translatesAutoresizingMaskIntoConstraints = false
        dock.backgroundColor = GTATheme.night
        dock.layer.borderWidth = 0.5
        dock.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        view.addSubview(dock)
        let dockItems = UIStackView()
        dockItems.axis = .horizontal
        dockItems.distribution = .fillEqually
        dockItems.translatesAutoresizingMaskIntoConstraints = false
        dock.addSubview(dockItems)
        for (index, item) in [
            ("Home", "house.fill", #selector(goHome)),
            ("Settings", "gearshape", #selector(openSettings)),
            ("Performance", "chart.bar", #selector(openRuntimeChecks)),
            ("More", "ellipsis", #selector(showMore))
        ].enumerated() {
            let button = UIButton(type: .system)
            var c = UIButton.Configuration.plain()
            c.title = item.0
            c.image = UIImage(systemName: item.1)
            c.imagePlacement = .top
            c.imagePadding = 5
            c.baseForegroundColor = index == 0 ? GTATheme.neonPink : GTATheme.subdued
            c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
                var attrs = incoming
                attrs.font = UIFont.systemFont(ofSize: 10, weight: index == 0 ? .bold : .medium)
                return attrs
            }
            button.configuration = c
            button.accessibilityLabel = item.0
            button.addTarget(self, action: item.2, for: .touchUpInside)
            dockItems.addArrangedSubview(button)
        }

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)
        content.axis = .vertical
        content.spacing = 13
        content.alignment = .fill
        content.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(content)
        scrollBottomConstraint = scrollView.bottomAnchor.constraint(equalTo: dock.topAnchor)
        NSLayoutConstraint.activate([
            dock.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            dock.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            dock.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            dock.heightAnchor.constraint(equalToConstant: 66),
            dockItems.topAnchor.constraint(equalTo: dock.topAnchor, constant: 4),
            dockItems.bottomAnchor.constraint(equalTo: dock.bottomAnchor, constant: -3),
            dockItems.leadingAnchor.constraint(equalTo: dock.leadingAnchor, constant: 6),
            dockItems.trailingAnchor.constraint(equalTo: dock.trailingAnchor, constant: -6),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollBottomConstraint!,
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 9),
            content.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -20),
            content.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 17),
            content.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -17),
            content.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -34)
        ])

        let header = UIStackView()
        header.axis = .horizontal
        header.alignment = .center
        let heading = UIStackView()
        heading.axis = .vertical
        heading.spacing = 1
        let wordmark = UILabel()
        let brandText = NSMutableAttributedString(string: "GTA", attributes: [
            .font: UIFont.systemFont(ofSize: 27, weight: .black, width: .expanded),
            .foregroundColor: GTATheme.cream])
        brandText.append(NSAttributedString(string: "iOS", attributes: [
            .font: UIFont.systemFont(ofSize: 27, weight: .black, width: .expanded),
            .foregroundColor: GTATheme.neonPink]))
        wordmark.attributedText = brandText
        let subtitle = GTATheme.caption("MOBILE LAUNCHER  ·  GRAND THEFT AUTO V")
        subtitle.font = UIFont.systemFont(ofSize: 9, weight: .semibold)
        heading.addArrangedSubview(wordmark)
        heading.addArrangedSubview(subtitle)
        header.addArrangedSubview(heading)
        header.addArrangedSubview(UIView())
        moreButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        moreButton.tintColor = GTATheme.cream
        moreButton.backgroundColor = GTATheme.raised
        moreButton.layer.cornerRadius = 20
        moreButton.accessibilityLabel = "More options and diagnostics"
        moreButton.heightAnchor.constraint(equalToConstant: 40).isActive = true
        moreButton.widthAnchor.constraint(equalToConstant: 40).isActive = true
        moreButton.addTarget(self, action: #selector(showMore), for: .touchUpInside)
        header.addArrangedSubview(moreButton)
        content.addArrangedSubview(header)
        content.setCustomSpacing(6, after: header)

        // Exact GTA V artwork derived from the user's reference screenshot.
        // This is a static banner, not a bitmap of fake application controls.
        content.addArrangedSubview(LosSantosHeroView())
        content.setCustomSpacing(10, after: content.arrangedSubviews.last!)

        // Real action state: choose USB files, inspect engine, or play only
        // when an actual ARM64 GTA V engine becomes available.
        let launchRow = UIStackView()
        launchRow.axis = .horizontal
        launchRow.spacing = 8
        launchRow.distribution = .fill
        launchRow.alignment = .fill
        configureMainAction()
        playButton.addTarget(self, action: #selector(launch), for: .touchUpInside)
        playButton.heightAnchor.constraint(equalToConstant: 66).isActive = true
        launchRow.addArrangedSubview(playButton)
        playButton.widthAnchor.constraint(equalTo: launchRow.widthAnchor, multiplier: 0.48).isActive = true
        launchRow.addArrangedSubview(statusTile("GAME FILES", icon: "checkmark.shield.fill",
                                                output: assetBadge, accent: GTATheme.mint))
        launchRow.addArrangedSubview(statusTile("NATIVE ENGINE", icon: "cpu.fill",
                                                output: engineBadge, accent: GTATheme.neonBlue))
        content.addArrangedSubview(launchRow)
        statusLine.textColor = GTATheme.subdued
        statusLine.font = .systemFont(ofSize: 11, weight: .medium)
        statusLine.numberOfLines = 2
        statusLine.textAlignment = .center
        content.addArrangedSubview(statusLine)
        content.setCustomSpacing(13, after: statusLine)

        let quickRow = UIStackView()
        quickRow.axis = .horizontal
        quickRow.spacing = 10
        quickRow.distribution = .fillEqually
        setupSecondary(controllerButton, title: "Controller", symbol: "gamecontroller.fill",
                       action: #selector(openControllerSetup))
        setupSecondary(settingsButton, title: "Graphics", symbol: "gearshape.2.fill",
                       action: #selector(openSettings))
        quickRow.addArrangedSubview(controllerButton)
        quickRow.addArrangedSubview(settingsButton)
        content.addArrangedSubview(quickRow)

        content.setCustomSpacing(17, after: quickRow)
        content.addArrangedSubview(dashboardHeading("Continue Playing", detail: "GTA V ONLY"))
        let continueCard = UIStackView()
        continueCard.axis = .horizontal
        continueCard.spacing = 11
        continueCard.alignment = .center
        continueCard.isLayoutMarginsRelativeArrangement = true
        continueCard.directionalLayoutMargins = .init(top: 9, leading: 10, bottom: 9, trailing: 12)
        GTATheme.card(continueCard)
        let preview = UIImageView()
        if let artURL = Bundle.main.url(forResource: "gtaios-hero", withExtension: "jpg") {
            preview.image = UIImage(contentsOfFile: artURL.path)
        }
        preview.contentMode = .scaleAspectFill
        preview.clipsToBounds = true
        preview.layer.cornerRadius = 10
        preview.heightAnchor.constraint(equalToConstant: 86).isActive = true
        continueCard.addArrangedSubview(preview)
        preview.widthAnchor.constraint(equalTo: continueCard.widthAnchor, multiplier: 0.39).isActive = true
        let resumeCopy = UIStackView()
        resumeCopy.axis = .vertical
        resumeCopy.spacing = 5
        let resumeTitle = UILabel()
        resumeTitle.text = "Grand Theft Auto V"
        resumeTitle.textColor = GTATheme.cream
        resumeTitle.font = .systemFont(ofSize: 14, weight: .bold)
        resumeCopy.addArrangedSubview(resumeTitle)
        continueLabel.font = .systemFont(ofSize: 11, weight: .medium)
        continueLabel.textColor = GTATheme.subdued
        continueLabel.numberOfLines = 3
        resumeCopy.addArrangedSubview(continueLabel)
        let inspect = GTATheme.caption("View engine readiness  ›")
        inspect.font = .systemFont(ofSize: 11, weight: .semibold)
        inspect.textColor = GTATheme.neonBlue
        resumeCopy.addArrangedSubview(inspect)
        continueCard.addArrangedSubview(resumeCopy)
        let inspectButton = UIButton(type: .system)
        inspectButton.translatesAutoresizingMaskIntoConstraints = false
        inspectButton.accessibilityLabel = "View native GTA V runtime checks"
        inspectButton.addTarget(self, action: #selector(openRuntimeChecks), for: .touchUpInside)
        continueCard.addSubview(inspectButton)
        NSLayoutConstraint.activate([
            inspectButton.leadingAnchor.constraint(equalTo: continueCard.leadingAnchor),
            inspectButton.trailingAnchor.constraint(equalTo: continueCard.trailingAnchor),
            inspectButton.topAnchor.constraint(equalTo: continueCard.topAnchor),
            inspectButton.bottomAnchor.constraint(equalTo: continueCard.bottomAnchor)
        ])
        content.addArrangedSubview(continueCard)

        content.setCustomSpacing(17, after: continueCard)
        content.addArrangedSubview(dashboardHeading("Game Files", detail: "USB-C  ·  READ ONLY"))
        let library = UIStackView()
        library.axis = .horizontal
        library.spacing = 12
        library.alignment = .center
        library.isLayoutMarginsRelativeArrangement = true
        library.directionalLayoutMargins = .init(top: 14, leading: 13, bottom: 14, trailing: 13)
        GTATheme.card(library)
        let driveSymbol = UIImageView(image: UIImage(systemName: "externaldrive.fill"))
        driveSymbol.tintColor = GTATheme.neonBlue
        driveSymbol.contentMode = .scaleAspectFit
        driveSymbol.widthAnchor.constraint(equalToConstant: 34).isActive = true
        library.addArrangedSubview(driveSymbol)
        let details = UIStackView()
        details.axis = .vertical
        details.spacing = 5
        storageTitle.font = .systemFont(ofSize: 15, weight: .bold)
        storageTitle.textColor = GTATheme.cream
        storageDetails.font = .systemFont(ofSize: 12)
        storageDetails.textColor = GTATheme.subdued
        storageDetails.lineBreakMode = .byTruncatingMiddle
        details.addArrangedSubview(storageTitle)
        details.addArrangedSubview(storageDetails)
        library.addArrangedSubview(details)
        fileIndicator.layer.cornerRadius = 5
        fileIndicator.widthAnchor.constraint(equalToConstant: 10).isActive = true
        fileIndicator.heightAnchor.constraint(equalToConstant: 10).isActive = true
        library.addArrangedSubview(fileIndicator)
        let arrow = UIImageView(image: UIImage(systemName: "chevron.right"))
        arrow.tintColor = GTATheme.subdued
        arrow.widthAnchor.constraint(equalToConstant: 9).isActive = true
        library.addArrangedSubview(arrow)
        folderButton.translatesAutoresizingMaskIntoConstraints = false
        folderButton.accessibilityLabel = "Choose or change GTA V game folder"
        folderButton.addTarget(self, action: #selector(chooseFolder), for: .touchUpInside)
        library.addSubview(folderButton)
        NSLayoutConstraint.activate([
            folderButton.leadingAnchor.constraint(equalTo: library.leadingAnchor),
            folderButton.trailingAnchor.constraint(equalTo: library.trailingAnchor),
            folderButton.topAnchor.constraint(equalTo: library.topAnchor),
            folderButton.bottomAnchor.constraint(equalTo: library.bottomAnchor)
        ])
        content.addArrangedSubview(library)

        content.setCustomSpacing(18, after: library)
        content.addArrangedSubview(dashboardHeading("Launcher Tools", detail: "SEE ALL  ›"))
        let tools = UIStackView()
        tools.axis = .horizontal
        tools.spacing = 7
        tools.distribution = .fillEqually
        setupTool(validateButton, title: "Validate Files", icon: "checkmark.square.fill",
                  action: #selector(validateFiles))
        setupTool(runtimeButton, title: "Engine Checks", icon: "cpu.fill",
                  action: #selector(openRuntimeChecks))
        setupTool(logsButton, title: "Export Logs", icon: "doc.text",
                  action: #selector(exportLogs))
        setupTool(updateButton, title: "App Details", icon: "info.circle.fill",
                  action: #selector(showAppDetails))
        for tool in [validateButton, runtimeButton, logsButton, updateButton] {
            tools.addArrangedSubview(tool)
        }
        content.addArrangedSubview(tools)

        content.setCustomSpacing(17, after: tools)
        content.addArrangedSubview(dashboardHeading("Build Status", detail: "LIVE DATA"))
        let buildBox = UIStackView()
        buildBox.axis = .vertical
        buildBox.spacing = 10
        buildBox.isLayoutMarginsRelativeArrangement = true
        buildBox.directionalLayoutMargins = .init(top: 12, leading: 14, bottom: 12, trailing: 14)
        GTATheme.card(buildBox)
        buildBox.addArrangedSubview(statusLineRow("Game Files", icon: "externaldrive.fill",
                                                output: usbStatusLabel))
        let rule = UIView()
        rule.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        rule.heightAnchor.constraint(equalToConstant: 1).isActive = true
        buildBox.addArrangedSubview(rule)
        buildBox.addArrangedSubview(statusLineRow("Controller", icon: "gamecontroller.fill",
                                                output: hardwareStatusLabel))
        let ruleTwo = UIView()
        ruleTwo.backgroundColor = UIColor.white.withAlphaComponent(0.09)
        ruleTwo.heightAnchor.constraint(equalToConstant: 1).isActive = true
        buildBox.addArrangedSubview(ruleTwo)
        let nativeStatus = GTATheme.caption(NativeEngineStatus.nativeEngineLinked
            ? "ARM64 game runtime linked" : "ARM64 game runtime not yet linked")
        nativeStatus.textColor = NativeEngineStatus.nativeEngineLinked ?
            GTATheme.mint : GTATheme.neonPink
        nativeStatus.font = .systemFont(ofSize: 12, weight: .semibold)
        buildBox.addArrangedSubview(nativeStatus)
        content.addArrangedSubview(buildBox)

        content.setCustomSpacing(17, after: buildBox)
        content.addArrangedSubview(dashboardHeading("Latest Update", detail: "APP CHANGELOG"))
        let update = UIStackView()
        update.axis = .vertical
        update.spacing = 5
        update.isLayoutMarginsRelativeArrangement = true
        update.directionalLayoutMargins = .init(top: 15, leading: 16, bottom: 15, trailing: 16)
        GTATheme.card(update)
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let versionTitle = UILabel()
        versionTitle.text = "GTAiOS v" + version
        versionTitle.font = .systemFont(ofSize: 16, weight: .bold)
        versionTitle.textColor = GTATheme.cream
        update.addArrangedSubview(versionTitle)
        let releaseText = GTATheme.caption(
            "GTA V-only launcher · cinematic artwork · USB file tools · native diagnostics")
        releaseText.numberOfLines = 2
        update.addArrangedSubview(releaseText)
        content.addArrangedSubview(update)

        let footer = GTATheme.caption(
            "GTA V native gameplay is not available yet. No FPS, save progress, " +
            "shader counts, or storage usage is invented.")
        footer.numberOfLines = 0
        footer.font = .systemFont(ofSize: 10)
        content.addArrangedSubview(footer)

        NotificationCenter.default.addObserver(self, selector: #selector(storageChanged),
            name: USBStorageManager.changedNotification, object: nil)
        refresh()
    }

    private func dashboardHeading(_ title: String, detail: String) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        let heading = GTATheme.section(title)
        heading.font = .systemFont(ofSize: 19, weight: .bold)
        row.addArrangedSubview(heading)
        row.addArrangedSubview(UIView())
        let label = GTATheme.caption(detail)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = GTATheme.neonBlue
        row.addArrangedSubview(label)
        return row
    }

    private func statusTile(_ title: String, icon: String,
                            output: UILabel, accent: UIColor) -> UIView {
        let wrapper = UIStackView()
        wrapper.axis = .vertical
        wrapper.spacing = 5
        wrapper.isLayoutMarginsRelativeArrangement = true
        wrapper.directionalLayoutMargins = .init(top: 10, leading: 9, bottom: 10, trailing: 9)
        GTATheme.card(wrapper)
        let heading = UIStackView()
        heading.axis = .horizontal
        heading.spacing = 4
        let pictogram = UIImageView(image: UIImage(systemName: icon))
        pictogram.tintColor = accent
        pictogram.contentMode = .scaleAspectFit
        pictogram.widthAnchor.constraint(equalToConstant: 14).isActive = true
        heading.addArrangedSubview(pictogram)
        let titleLabel = GTATheme.caption(title)
        titleLabel.font = .systemFont(ofSize: 8, weight: .semibold)
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.7
        heading.addArrangedSubview(titleLabel)
        wrapper.addArrangedSubview(heading)
        output.font = .systemFont(ofSize: 10, weight: .bold)
        output.textColor = accent
        output.numberOfLines = 2
        output.adjustsFontSizeToFitWidth = true
        output.minimumScaleFactor = 0.8
        wrapper.addArrangedSubview(output)
        return wrapper
    }

    private func statusLineRow(_ title: String, icon: String, output: UILabel) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        let graphic = UIImageView(image: UIImage(systemName: icon))
        graphic.tintColor = GTATheme.neonBlue
        graphic.widthAnchor.constraint(equalToConstant: 22).isActive = true
        graphic.contentMode = .scaleAspectFit
        row.addArrangedSubview(graphic)
        let titleLabel = UILabel()
        titleLabel.text = title
        titleLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        titleLabel.textColor = GTATheme.cream
        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(UIView())
        output.numberOfLines = 2
        output.textAlignment = .right
        output.font = .systemFont(ofSize: 11, weight: .medium)
        output.textColor = GTATheme.mint
        output.setContentCompressionResistancePriority(.required, for: .horizontal)
        row.addArrangedSubview(output)
        return row
    }

    private func setupTool(_ button: UIButton, title: String, icon: String, action: Selector) {
        var c = UIButton.Configuration.filled()
        c.title = title
        c.image = UIImage(systemName: icon)
        c.imagePlacement = .top
        c.imagePadding = 9
        c.baseForegroundColor = GTATheme.cream
        c.baseBackgroundColor = GTATheme.raised
        c.cornerStyle = .large
        c.contentInsets = .init(top: 13, leading: 4, bottom: 13, trailing: 4)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attrs = incoming
            attrs.font = .systemFont(ofSize: 10, weight: .medium)
            return attrs
        }
        button.configuration = c
        button.heightAnchor.constraint(equalToConstant: 88).isActive = true
        button.titleLabel?.numberOfLines = 2
        button.titleLabel?.textAlignment = .center
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    @objc private func validateFiles() {
        guard USBStorageManager.shared.root != nil else { chooseFolder(); return }
        NativeEngineStatus.inspect { [weak self] result in
            guard let self else { return }
            let alert: UIAlertController
            switch result {
            case .success(let inspection):
                let bytes = ByteCountFormatter.string(fromByteCount: inspection.byteCount,
                                                      countStyle: .file)
                alert = UIAlertController(title: "GTA V files inspected",
                    message: "Readable WebAssembly engine: " + bytes +
                        "\nUSB game data and shader index were located." +
                        "\n\nThis validates files, not native GTA V gameplay.",
                    preferredStyle: .alert)
            case .failure(let error):
                alert = UIAlertController(title: "File inspection failed",
                    message: error.localizedDescription, preferredStyle: .alert)
            }
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            self.present(alert, animated: true)
        }
    }

    @objc private func showAppDetails() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let sheet = UIAlertController(title: "GTAiOS " + version,
            message: "Build " + build +
                "\n\nNative UIKit GTA V launcher\nUSB-C game files" +
                "\nController setup\nMetal preview and runtime diagnostics" +
                "\n\nGTA V gameplay is still in development.",
            preferredStyle: .alert)
        sheet.addAction(UIAlertAction(title: "OK", style: .default))
        present(sheet, animated: true)
    }

    private func configureMainAction() {
        var c = UIButton.Configuration.plain()
        c.title = "Choose Game Folder"
        c.image = UIImage(systemName: "play.fill")
        c.imagePlacement = .leading
        c.imagePadding = 7
        c.baseForegroundColor = .white
        c.cornerStyle = .large
        c.contentInsets = .init(top: 13, leading: 9, bottom: 13, trailing: 9)
        c.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var attrs = incoming
            attrs.font = .systemFont(ofSize: 14, weight: .bold)
            return attrs
        }
        playButton.configuration = c
        playGradient.colors = [GTATheme.neonBlue.cgColor,
            UIColor(red: 0.36, green: 0.32, blue: 0.95, alpha: 1).cgColor,
            GTATheme.neonPink.cgColor]
        playGradient.locations = [0, 0.53, 1]
        playGradient.startPoint = CGPoint(x: 0, y: 0.35)
        playGradient.endPoint = CGPoint(x: 1, y: 0.7)
        playButton.layer.insertSublayer(playGradient, at: 0)
        playButton.layer.cornerRadius = 15
        playButton.layer.masksToBounds = true
        playButton.layer.borderColor = UIColor.white.withAlphaComponent(0.38).cgColor
        playButton.layer.borderWidth = 1
        playButton.accessibilityIdentifier = "real-launch-action"
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
        let hasUSB = USBStorageManager.shared.root != nil
        let engine = NativeEngineStatus.nativeEngineLinked
        if let root = USBStorageManager.shared.root {
            storageTitle.text = "Grand Theft Auto V"
            storageDetails.text = "Connected · " + root.lastPathComponent
            fileIndicator.backgroundColor = GTATheme.mint
            playButton.configuration?.title = NativeEngineStatus.nativeEngineLinked ? "Play GTA V" : "Engine Checks"
            playButton.configuration?.image = UIImage(systemName: engine ? "play.fill" : "cpu.fill")
            playButton.isEnabled = true
            playButton.alpha = 1
            playButton.accessibilityLabel = engine ? "Play Grand Theft Auto V" : "Inspect GTA V native engine status"
            statusLine.text = engine ? "GTA V files connected · gameplay ready" :
                "USB game files detected · Native game engine integration is still in progress"
        } else {
            storageTitle.text = "Connect game files"
            storageDetails.text = "Select your GTA V folder on USB-C"
            fileIndicator.backgroundColor = GTATheme.neonPink
            playButton.configuration?.title = "Choose Game Folder"
            playButton.configuration?.image = UIImage(systemName: "folder.fill.badge.plus")
            playButton.isEnabled = true
            playButton.alpha = 1
            playButton.accessibilityLabel = "Choose game folder"
            statusLine.text = "Select your GTA V game library · files remain on your USB drive"
        }
        let missing = hasUSB ? USBStorageManager.shared.missingStartupAssets() : []
        usbStatusLabel.text = !hasUSB ? "Not connected" :
            (missing.isEmpty ? "Startup assets readable" : "Missing startup assets")
        usbStatusLabel.textColor = !hasUSB ? GTATheme.subdued :
            (missing.isEmpty ? GTATheme.mint : GTATheme.neonPink)
        assetBadge.text = !hasUSB ? "Not selected" : (missing.isEmpty ? "Readable" : "Check files")
        assetBadge.textColor = hasUSB && missing.isEmpty ? GTATheme.mint : GTATheme.neonPink
        engineBadge.text = engine ? "Ready" : "Pending"
        engineBadge.textColor = engine ? GTATheme.mint : GTATheme.neonPink
        continueLabel.text = engine ? "Game engine ready · Select Play to load GTA V" :
            "Native GTA V engine not linked.\nContinue will become available after gameplay integration."
        updateDevice(ControllerManager.shared.currentName)
        highlightFocus()
    }

    @objc private func storageChanged() { refresh() }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        background.frame = view.bounds
        playGradient.frame = playButton.bounds
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
        hardwareStatusLabel.text = name == "No controller" ? "Not connected" : name
    }

    private var focusTargets: [UIButton] {
        [playButton, folderButton, controllerButton, settingsButton, validateButton, runtimeButton, logsButton, updateButton, moreButton]
    }
    private func highlightFocus() {
        let connected = ControllerManager.shared.currentName != "No controller"
        for (i, button) in focusTargets.enumerated() {
            let focused = connected && focusIndex == i
            button.layer.borderColor = focused ? GTATheme.neonPink.cgColor : UIColor.clear.cgColor
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

    @objc private func goHome() { scrollView.setContentOffset(.zero, animated: true) }
    @objc private func openRuntimeChecks() { openGame() }

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
            openGame() // Engine Checks is explicitly not a gameplay launch.
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
