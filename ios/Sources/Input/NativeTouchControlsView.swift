import UIKit

/// A normalized native input state with identical fields for GameController
/// and the on-screen pad. This is a staging ABI, not a connected GTA game ABI.
final class NativeInputState {
    static let shared = NativeInputState()
    private(set) var hardware: [String: Double] = [:]
    private(set) var touch: [String: Double] = [:]
    private init() {}

    func updateHardware(_ values: [String: Double]) {
        assert(Thread.isMainThread)
        hardware = values
    }

    func updateTouch(_ values: [String: Double]) {
        assert(Thread.isMainThread)
        touch = values
    }

    func clearTouch() { touch = [:] }
    func clearHardware() { hardware = [:] }

    /// Touch overrides a hardware input only while it is nonzero. Hardware
    /// values stay analog; do not convert thumbsticks to keyboard presses.
    var snapshot: [String: Double] {
        var merged = hardware
        for (key, value) in touch where abs(value) > 0.0001 {
            merged[key] = value
        }
        merged["touchActive"] = touch.values.contains { abs($0) > 0.0001 } ? 1 : 0
        return merged
    }
}

private final class NativeTouchStick: UIControl {
    let axis: String
    var onAxes: ((Double, Double) -> Void)?
    private let base = UIView()
    private let thumb = UIView()
    private var dx: CGFloat = 0
    private var dy: CGFloat = 0
    private var thumbX: NSLayoutConstraint!
    private var thumbY: NSLayoutConstraint!

    init(axis: String) {
        self.axis = axis
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isMultipleTouchEnabled = false
        isAccessibilityElement = true
        accessibilityLabel = axis == "move" ? "Move analog stick" : "Camera analog stick"
        accessibilityHint = "Drag to control the analog input"
        backgroundColor = UIColor.black.withAlphaComponent(0.24)
        layer.cornerRadius = 55
        layer.borderColor = UIColor.white.withAlphaComponent(0.28).cgColor
        layer.borderWidth = 1
        base.translatesAutoresizingMaskIntoConstraints = false
        base.layer.cornerRadius = 50
        base.layer.borderWidth = 1
        base.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        base.isUserInteractionEnabled = false
        thumb.translatesAutoresizingMaskIntoConstraints = false
        thumb.layer.cornerRadius = 22
        thumb.backgroundColor = UIColor.white.withAlphaComponent(0.45)
        thumb.layer.borderColor = UIColor.white.withAlphaComponent(0.55).cgColor
        thumb.layer.borderWidth = 1
        thumb.isUserInteractionEnabled = false
        addSubview(base)
        addSubview(thumb)
        thumbX = thumb.centerXAnchor.constraint(equalTo: centerXAnchor)
        thumbY = thumb.centerYAnchor.constraint(equalTo: centerYAnchor)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 110),
            heightAnchor.constraint(equalToConstant: 110),
            base.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
            base.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5),
            base.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            base.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            thumb.widthAnchor.constraint(equalToConstant: 44),
            thumb.heightAnchor.constraint(equalToConstant: 44),
            thumbX, thumbY
        ])
    }
    required init?(coder: NSCoder) { fatalError("Use init(axis:)") }

    private func move(_ point: CGPoint) {
        let limit: CGFloat = 34
        let rawX = point.x - bounds.midX, rawY = point.y - bounds.midY
        let scale = min(1.0, limit / max(0.001, hypot(rawX, rawY)))
        dx = rawX * scale
        dy = rawY * scale
        thumbX.constant = dx
        thumbY.constant = dy
        onAxes?(Double(dx / limit), Double(-dy / limit))
    }
    private func release() {
        dx = 0
        dy = 0
        thumbX.constant = 0
        thumbY.constant = 0
        onAxes?(0, 0)
    }
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        move(touch.location(in: self))
        return true
    }
    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        move(touch.location(in: self))
        return true
    }
    override func endTracking(_ touch: UITouch?, with event: UIEvent?) { release() }
    override func cancelTracking(with event: UIEvent?) { release() }
}

/// Native analog touch input with a customizable display toggle and explicit
/// held-button semantics. It captures controls but does NOT claim to drive
/// the proprietary GTA engine until a real host ABI consumes the snapshot.
final class NativeTouchControlsView: UIView {
    private var held: [String: Double] = [:]
    var onState: (([String: Double]) -> Void)?
    private let leftStick = NativeTouchStick(axis: "move")
    private let rightStick = NativeTouchStick(axis: "camera")
    private let labels = ["lt": "AIM", "rt": "FIRE", "a": "JUMP",
                          "b": "COVER", "x": "RELOAD", "y": "ENTER"]
    private var mode = "onFoot"

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
        isMultipleTouchEnabled = true

        let centerControls = UIStackView()
        centerControls.axis = .vertical
        centerControls.alignment = .center
        centerControls.spacing = 7
        centerControls.translatesAutoresizingMaskIntoConstraints = false

        let modeButton = UIButton(type: .system)
        var modeConfig = UIButton.Configuration.tinted()
        modeConfig.title = "ON FOOT"
        modeConfig.baseForegroundColor = .white
        modeConfig.background.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        modeButton.configuration = modeConfig
        modeButton.accessibilityLabel = "Switch between on-foot and driving controls"
        modeButton.addTarget(self, action: #selector(changeMode(_:)), for: .touchUpInside)
        centerControls.addArrangedSubview(modeButton)

        let buttons = UIStackView()
        buttons.axis = .horizontal
        buttons.spacing = 5
        buttons.distribution = .fillEqually
        let pairs = [("lt", "AIM"), ("rt", "FIRE"),
                     ("a", "JUMP"), ("b", "COVER"), ("x", "RELOAD"), ("y", "ENTER")]
        for (key, title) in pairs {
            let b = UIButton(type: .custom)
            b.accessibilityLabel = title
            b.accessibilityHint = "Press and hold"
            b.setTitle(title, for: .normal)
            b.titleLabel?.font = .systemFont(ofSize: 9, weight: .bold)
            b.backgroundColor = UIColor.black.withAlphaComponent(0.58)
            b.layer.cornerRadius = 8
            b.layer.borderWidth = 1
            b.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
            b.widthAnchor.constraint(equalToConstant: 48).isActive = true
            b.heightAnchor.constraint(equalToConstant: 34).isActive = true
            b.addAction(UIAction { [weak self] _ in self?.press(key) }, for: .touchDown)
            b.addAction(UIAction { [weak self] _ in self?.release(key) },
                        for: [.touchUpInside, .touchUpOutside, .touchCancel])
            buttons.addArrangedSubview(b)
        }
        centerControls.addArrangedSubview(buttons)

        addSubview(leftStick)
        addSubview(centerControls)
        addSubview(rightStick)
        NSLayoutConstraint.activate([
            leftStick.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 22),
            leftStick.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            rightStick.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -22),
            rightStick.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12),
            centerControls.centerXAnchor.constraint(equalTo: centerXAnchor),
            centerControls.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12)
        ])

        leftStick.onAxes = { [weak self] x,y in
            self?.held["lx"] = x
            self?.held["ly"] = y
            self?.publish()
        }
        rightStick.onAxes = { [weak self] x,y in
            self?.held["rx"] = x
            self?.held["ry"] = y
            self?.publish()
        }
        accessibilityIdentifier = "native-touch-controls"
    }
    required init?(coder: NSCoder) { fatalError("Use init(frame:)") }

    // Let the overlay pass through touches away from actual control surfaces.
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        for item in subviews where !item.isHidden {
            let translated = convert(point, to: item)
            if item.point(inside: translated, with: event) { return true }
        }
        return false
    }
    private func press(_ key: String) { held[key] = 1; publish() }
    private func release(_ key: String) { held[key] = 0; publish() }
    private func publish() { onState?(held) }
    func reset() { held.removeAll(); onState?([:]) }

    @objc private func changeMode(_ sender: UIButton) {
        mode = mode == "onFoot" ? "driving" : "onFoot"
        var config = sender.configuration
        config?.title = mode == "driving" ? "DRIVING" : "ON FOOT"
        sender.configuration = config
        // The profile is recorded for native game ABI integration later.
        held["drivingProfile"] = mode == "driving" ? 1 : 0
        UISelectionFeedbackGenerator().selectionChanged()
        publish()
    }
}
