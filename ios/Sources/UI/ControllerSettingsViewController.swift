import UIKit
import GameController

/// Controller setup can be used without game assets or the WebAssembly engine.
final class ControllerSettingsViewController: UIViewController {
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let hardware = UILabel()
    private let live = UILabel()
    private let deadzone = UISlider()
    private let sensitivity = UISlider()
    private let invert = UISwitch()
    private var mappingButtons: [UIButton] = []
    private let inputs = ["a", "b", "x", "y", "lb", "rb", "l3", "r3", "menu"]
    private let labels = ["A / Cross", "B / Circle", "X / Square", "Y / Triangle",
                          "L1 / LB", "R1 / RB", "L3", "R3", "Menu / Options"]
    private var lastSampleTime: TimeInterval = 0

    static let bindingKey = "gtaios.controller.bindings"
    static let defaults: [String: String] = [
        "a": "ShiftLeft", "b": "KeyR", "x": "Space", "y": "KeyF",
        "lb": "Tab", "rb": "KeyQ", "l3": "ControlLeft", "r3": "KeyC", "menu": "Escape"
    ]
    private let choices: [(String, String)] = [
        ("Sprint", "ShiftLeft"), ("Jump / handbrake", "Space"),
        ("Reload", "KeyR"), ("Enter / exit vehicle", "KeyF"),
        ("Weapon wheel", "Tab"), ("Cover", "KeyQ"),
        ("Stealth", "ControlLeft"), ("Look behind", "KeyC"),
        ("Pause", "Escape"), ("Interaction menu", "KeyM"),
        ("Horn", "KeyE"), ("Confirm", "Enter"), ("Unassigned", "")
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Controller studio"
        view.backgroundColor = GTATheme.night
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 16
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -20)
        ])
        let top = UIStackView()
        top.axis = .horizontal
        top.alignment = .center
        top.spacing = 12
        let controllerIcon = UIImageView(image: UIImage(systemName: "gamecontroller.fill"))
        controllerIcon.tintColor = GTATheme.coral
        controllerIcon.contentMode = .scaleAspectFit
        controllerIcon.translatesAutoresizingMaskIntoConstraints = false
        controllerIcon.widthAnchor.constraint(equalToConstant: 48).isActive = true
        controllerIcon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        let titles = UIStackView()
        titles.axis = .vertical
        titles.spacing = 3
        titles.addArrangedSubview(GTATheme.section("Take control."))
        titles.addArrangedSubview(GTATheme.caption("Bluetooth · wired · touch"))
        top.addArrangedSubview(controllerIcon)
        top.addArrangedSubview(titles)
        stack.addArrangedSubview(top)

        hardware.font = UIFontMetrics(forTextStyle: .headline).scaledFont(
            for: .systemFont(ofSize: 17, weight: .bold))
        hardware.adjustsFontForContentSizeCategory = true
        hardware.textColor = GTATheme.coral
        hardware.numberOfLines = 0
        hardware.text = "Searching for controllers…"
        live.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .monospacedSystemFont(ofSize: 12, weight: .medium))
        live.adjustsFontForContentSizeCategory = true
        live.numberOfLines = 0
        live.textColor = GTATheme.subdued
        live.text = "Connect an Xbox, PlayStation, or iOS-supported controller."
        let signalCard = UIStackView(arrangedSubviews: [hardware, live])
        signalCard.axis = .vertical
        signalCard.spacing = 8
        signalCard.isLayoutMarginsRelativeArrangement = true
        signalCard.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 17, leading: 17, bottom: 17, trailing: 17)
        GTATheme.card(signalCard)
        stack.addArrangedSubview(signalCard)
        stack.addArrangedSubview(GTATheme.section("Analog tuning"))

        let store = UserDefaults.standard
        deadzone.minimumValue = 0.02
        deadzone.maximumValue = 0.45
        deadzone.value = store.object(forKey: ControllerManager.deadzoneKey) == nil
            ? 0.15 : Float(store.double(forKey: ControllerManager.deadzoneKey))
        deadzone.addTarget(self, action: #selector(save), for: .valueChanged)
        addSlider("Analog stick deadzone", slider: deadzone)
        sensitivity.minimumValue = 0.25
        sensitivity.maximumValue = 3
        sensitivity.value = store.object(forKey: ControllerManager.sensitivityKey) == nil
            ? 1 : Float(store.double(forKey: ControllerManager.sensitivityKey))
        sensitivity.addTarget(self, action: #selector(save), for: .valueChanged)
        addSlider("Camera sensitivity", slider: sensitivity)
        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 14, leading: 17, bottom: 14, trailing: 17)
        GTATheme.card(row)
        row.addArrangedSubview(label("Invert vertical camera"))
        row.addArrangedSubview(invert)
        invert.isOn = store.bool(forKey: ControllerManager.invertYKey)
        invert.addTarget(self, action: #selector(save), for: .valueChanged)
        stack.addArrangedSubview(row)
        invert.onTintColor = GTATheme.coral
        stack.addArrangedSubview(GTATheme.section("Button mapping"))
        stack.addArrangedSubview(GTATheme.caption("Customize your on-foot bindings"))
        for index in inputs.indices {
            let button = UIButton(type: .system)
            button.tag = index
            button.contentHorizontalAlignment = .left
            button.tintColor = GTATheme.cream
            button.backgroundColor = GTATheme.inset
            button.layer.cornerRadius = 11
            button.layer.cornerCurve = .continuous
            button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
            button.addTarget(self, action: #selector(remap), for: .touchUpInside)
            mappingButtons.append(button)
            stack.addArrangedSubview(button)
        }
        let rumble = UIButton(type: .system)
        rumble.setTitle("TEST CONTROLLER VIBRATION", for: .normal)
        rumble.tintColor = GTATheme.night
        rumble.backgroundColor = GTATheme.coral
        rumble.layer.cornerRadius = 13
        rumble.layer.cornerCurve = .continuous
        rumble.titleLabel?.font = .systemFont(ofSize: 13, weight: .bold)
        rumble.heightAnchor.constraint(greaterThanOrEqualToConstant: 50).isActive = true
        rumble.addTarget(self, action: #selector(testRumble), for: .touchUpInside)
        stack.addArrangedSubview(rumble)
        let limitation = label("Game analog sticks/triggers are captured correctly. The current game binary exposes only keyboard/mouse input, so true analog vehicle steering and throttle still require an engine-level gamepad interface.")
        limitation.numberOfLines = 0
        limitation.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13))
        limitation.adjustsFontForContentSizeCategory = true
        limitation.textColor = GTATheme.subdued
        stack.addArrangedSubview(limitation)
        updateBindings()
    }

    private func label(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.textColor = GTATheme.cream
        l.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 15, weight: .medium))
        l.adjustsFontForContentSizeCategory = true
        return l
    }
    private func addSlider(_ name: String, slider: UISlider) {
        slider.tintColor = GTATheme.coral
        slider.accessibilityLabel = name
        let group = UIStackView(arrangedSubviews: [label(name), slider])
        group.axis = .vertical
        group.spacing = 11
        group.isLayoutMarginsRelativeArrangement = true
        group.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 13, leading: 17, bottom: 13, trailing: 17)
        GTATheme.card(group)
        stack.addArrangedSubview(group)
    }
    private func bindings() -> [String: String] {
        var m = Self.defaults
        if let saved = UserDefaults.standard.dictionary(forKey: Self.bindingKey) as? [String: String] {
            for (key, value) in saved { if inputs.contains(key) { m[key] = value } }
        }
        return m
    }
    private func updateBindings() {
        let m = bindings()
        for i in inputs.indices {
            let code = m[inputs[i]] ?? ""
            let display = choices.first(where: { $0.1 == code })?.0 ?? "Unassigned"
            mappingButtons[i].setTitle("  \(labels[i]): \(display)", for: .normal)
        }
    }
    @objc private func remap(_ button: UIButton) {
        let input = inputs[button.tag]
        let sheet = UIAlertController(title: "Assign \(labels[button.tag])", message: nil, preferredStyle: .actionSheet)
        for (name, value) in choices {
            sheet.addAction(UIAlertAction(title: name, style: .default) { [weak self] _ in
                var m = self?.bindings() ?? Self.defaults
                m[input] = value
                UserDefaults.standard.set(m, forKey: Self.bindingKey)
                self?.updateBindings()
                LogStore.shared.write("controller", "Remapped \(input) to \(value)")
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = button
        sheet.popoverPresentationController?.sourceRect = button.bounds
        present(sheet, animated: true)
    }
    @objc private func save() {
        let db = UserDefaults.standard
        db.set(Double(deadzone.value), forKey: ControllerManager.deadzoneKey)
        db.set(Double(sensitivity.value), forKey: ControllerManager.sensitivityKey)
        db.set(invert.isOn, forKey: ControllerManager.invertYKey)
    }
    @objc private func testRumble() {
        let ok = ControllerManager.shared.testRumble()
        if !ok {
            let alert = UIAlertController(title: "No controller rumble", message: "This controller does not expose supported haptics to iOS, or a haptic engine could not start.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
        }
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        ControllerManager.shared.onConnection = { [weak self] name in
            self?.hardware.text = name == "No controller" ? "No controller connected" : "Connected: \(name)"
        }
        ControllerManager.shared.onState = { [weak self] state in
            guard let self else { return }
            let now = Date.timeIntervalSinceReferenceDate
            guard now - self.lastSampleTime > 0.10 else { return }
            self.lastSampleTime = now
            func f(_ key: String) -> String { String(format: "%.2f", state[key] ?? 0) }
            self.live.text = "LX \(f("lx"))  LY \(f("ly"))  RX \(f("rx"))  RY \(f("ry"))\nLT \(f("lt")) RT \(f("rt"))  L3 \(f("l3")) R3 \(f("r3"))\nA \(f("a")) B \(f("b")) X \(f("x")) Y \(f("y"))\nL1 \(f("lb")) R1 \(f("rb")) Menu \(f("menu")) Options \(f("options"))"
        }
        ControllerManager.shared.begin()
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        ControllerManager.shared.stop()
    }
}
