import UIKit
import CoreGraphics

/// GTAiOS visual language: warm Los Santos sunset, editorial condensed display,
/// native iOS controls, and explicit native-engine readiness. Entirely drawn
/// in UIKit/CoreGraphics; no bitmap downloads or runtime web content.
enum GTATheme {
    static let night = UIColor(red: 0.055, green: 0.066, blue: 0.080, alpha: 1)
    static let raised = UIColor(red: 0.108, green: 0.123, blue: 0.145, alpha: 1)
    static let inset = UIColor(red: 0.138, green: 0.152, blue: 0.177, alpha: 1)
    static let coral = UIColor(red: 1.0, green: 0.717, blue: 0.509, alpha: 1)
    static let cream = UIColor(red: 0.995, green: 0.973, blue: 0.932, alpha: 1)
    static let subdued = UIColor(red: 0.725, green: 0.749, blue: 0.762, alpha: 1)
    static let success = UIColor(red: 0.622, green: 0.890, blue: 0.726, alpha: 1)

    static func caption(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = subdued
        label.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12, weight: .semibold))
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func section(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.textColor = cream
        label.font = UIFontMetrics(forTextStyle: .title3).scaledFont(
            for: .systemFont(ofSize: 20, weight: .bold))
        label.adjustsFontForContentSizeCategory = true
        return label
    }

    static func card(_ view: UIView) {
        view.backgroundColor = raised
        view.layer.cornerRadius = 17
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.075).cgColor
    }
}

/// Static custom-drawn local skyline. Drawing is triggered by bounds changes;
/// it never performs USB reads, animations, allocation spikes or web requests.
private final class SunsetSkylineView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = true
        contentMode = .redraw
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), rect.width > 0,
              rect.height > 0 else { return }
        let w = rect.width, h = rect.height
        let rgb = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(colorsSpace: rgb, colors: [
            UIColor(red: 0.13, green: 0.14, blue: 0.25, alpha: 1).cgColor,
            UIColor(red: 0.42, green: 0.25, blue: 0.34, alpha: 1).cgColor,
            UIColor(red: 0.92, green: 0.51, blue: 0.40, alpha: 1).cgColor
        ] as CFArray, locations: [0, 0.54, 1])!
        ctx.drawLinearGradient(gradient, start: .zero,
            end: CGPoint(x: 0, y: h), options: [])

        // Late-afternoon glow behind the city, built entirely from paths.
        let sun = CGPoint(x: w * 0.81, y: h * 0.45)
        ctx.setFillColor(UIColor(red: 1, green: 0.78, blue: 0.58, alpha: 0.76).cgColor)
        ctx.fillEllipse(in: CGRect(x: sun.x - 43, y: sun.y - 43, width: 86, height: 86))
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.11).cgColor)
        for fraction in [0.32, 0.40, 0.48] {
            let line = h * CGFloat(fraction)
            ctx.move(to: CGPoint(x: 0, y: line))
            ctx.addLine(to: CGPoint(x: w, y: line))
        }
        ctx.strokePath()

        // Distant towers, muted atmospheric depth.
        ctx.setFillColor(UIColor(red: 0.21, green: 0.19, blue: 0.28, alpha: 0.75).cgColor)
        let towers: [(CGFloat, CGFloat, CGFloat)] = [
            (0.04, 0.19, 0.62), (0.16, 0.10, 0.48),
            (0.25, 0.08, 0.66), (0.37, 0.14, 0.49),
            (0.52, 0.12, 0.62), (0.67, 0.10, 0.42),
            (0.77, 0.13, 0.54), (0.91, 0.09, 0.61)
        ]
        for (x, width, top) in towers {
            ctx.fill(CGRect(x: w*x, y: h*top, width: w*width,
                            height: h*(1-top)))
        }
        // Foreground urban silhouette with slender spires.
        ctx.setFillColor(UIColor(red: 0.086, green: 0.102, blue: 0.151, alpha: 0.98).cgColor)
        let fronts: [(CGFloat, CGFloat, CGFloat)] = [
            (0.0, 0.12, 0.80), (0.12, 0.17, 0.70), (0.29, 0.08, 0.83),
            (0.37, 0.13, 0.62), (0.50, 0.14, 0.78), (0.64, 0.13, 0.72),
            (0.77, 0.10, 0.84), (0.87, 0.13, 0.71)
        ]
        for (x, width, top) in fronts {
            ctx.fill(CGRect(x: w*x, y: h*top, width: w*width,
                            height: h*(1-top)))
        }
        ctx.fill(CGRect(x: w*0.425, y: h*0.54, width: w*0.011, height: h*0.1))
        ctx.fill(CGRect(x: 0, y: h*0.91, width: w, height: h*0.09))

        // A single palm silhouette marks the city without stock art.
        ctx.setStrokeColor(UIColor(red: 0.078, green: 0.090, blue: 0.128, alpha: 1).cgColor)
        ctx.setLineCap(.round)
        ctx.setLineWidth(5)
        let root = CGPoint(x: w*0.89, y: h)
        let crown = CGPoint(x: w*0.845, y: h*0.44)
        ctx.move(to: root)
        ctx.addQuadCurve(to: crown, control: CGPoint(x: w*0.84, y: h*0.73))
        ctx.strokePath()
        ctx.setLineWidth(2.4)
        for angle in [-2.85, -2.3, -1.72, -1.08, -0.50, 0.13, 0.77] {
            let a = CGFloat(angle)
            let tip = CGPoint(x: crown.x + cos(a)*w*0.12,
                              y: crown.y + sin(a)*h*0.22 + h*0.055)
            ctx.move(to: crown)
            ctx.addQuadCurve(to: tip, control: CGPoint(
                x: crown.x + cos(a)*w*0.09,
                y: crown.y + sin(a)*h*0.11 - h*0.045))
            ctx.strokePath()
        }

        // Text-protection vignette: deep on the left, transparent near sunset.
        let mask = CGGradient(colorsSpace: rgb, colors: [
            UIColor(red: 0.045, green: 0.060, blue: 0.089, alpha: 0.90).cgColor,
            UIColor(red: 0.055, green: 0.064, blue: 0.105, alpha: 0.57).cgColor,
            UIColor(red: 0.08, green: 0.09, blue: 0.15, alpha: 0.04).cgColor
        ] as CFArray, locations: [0, 0.48, 1])!
        ctx.drawLinearGradient(mask, start: .zero,
            end: CGPoint(x: w, y: 0), options: [])
    }
}

/// The distinctive first viewport, with correct status copy that never claims
/// native gameplay is available simply because Metal/USB initialization works.
final class LosSantosHeroView: UIView {
    private let skyline = SunsetSkylineView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 20
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
        skyline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(skyline)
        NSLayoutConstraint.activate([
            skyline.topAnchor.constraint(equalTo: topAnchor),
            skyline.bottomAnchor.constraint(equalTo: bottomAnchor),
            skyline.leadingAnchor.constraint(equalTo: leadingAnchor),
            skyline.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        let top = UIStackView()
        top.axis = .horizontal
        top.spacing = 8
        top.alignment = .center
        top.translatesAutoresizingMaskIntoConstraints = false
        let mark = UILabel()
        mark.text = "V"
        mark.textAlignment = .center
        mark.textColor = GTATheme.night
        mark.backgroundColor = GTATheme.coral
        mark.layer.cornerRadius = 9
        mark.layer.cornerCurve = .continuous
        mark.clipsToBounds = true
        mark.font = .systemFont(ofSize: 20, weight: .black)
        mark.widthAnchor.constraint(equalToConstant: 34).isActive = true
        mark.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let section = UILabel()
        section.text = "LOS SANTOS"
        section.textColor = GTATheme.cream
        section.font = .systemFont(ofSize: 11, weight: .heavy)
        section.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = UIView()
        let state = UILabel()
        state.text = "PORT IN PROGRESS"
        state.font = .systemFont(ofSize: 9, weight: .heavy)
        state.textColor = GTATheme.cream
        state.textAlignment = .center
        state.backgroundColor = GTATheme.night.withAlphaComponent(0.68)
        state.layer.cornerRadius = 9
        state.layer.cornerCurve = .continuous
        state.clipsToBounds = true
        state.numberOfLines = 1
        state.widthAnchor.constraint(greaterThanOrEqualToConstant: 111).isActive = true
        state.heightAnchor.constraint(equalToConstant: 30).isActive = true
        top.addArrangedSubview(mark)
        top.addArrangedSubview(section)
        top.addArrangedSubview(spacer)
        top.addArrangedSubview(state)

        let title = UILabel()
        title.text = "GRAND THEFT\nAUTO V"
        title.font = UIFontMetrics(forTextStyle: .largeTitle).scaledFont(
            for: .systemFont(ofSize: 39, weight: .black))
        title.adjustsFontForContentSizeCategory = true
        title.textColor = GTATheme.cream
        title.numberOfLines = 2
        title.minimumScaleFactor = 0.7
        title.adjustsFontSizeToFitWidth = true
        title.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        let subtitle = UILabel()
        subtitle.text = "THE NATIVE iPHONE PROJECT"
        subtitle.textColor = GTATheme.cream.withAlphaComponent(0.88)
        subtitle.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12, weight: .bold))
        subtitle.adjustsFontForContentSizeCategory = true

        let copy = UIStackView(arrangedSubviews: [title, subtitle])
        copy.axis = .vertical
        copy.spacing = 5
        copy.alignment = .leading
        copy.translatesAutoresizingMaskIntoConstraints = false

        let footer = UILabel()
        footer.text = "A18 CPU     •     APPLE METAL     •     USB-C"
        footer.textColor = GTATheme.cream.withAlphaComponent(0.82)
        footer.font = UIFontMetrics(forTextStyle: .caption2).scaledFont(
            for: .monospacedSystemFont(ofSize: 10, weight: .semibold))
        footer.adjustsFontForContentSizeCategory = true
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(top)
        addSubview(copy)
        addSubview(footer)

        let constraints = [
            top.topAnchor.constraint(equalTo: topAnchor, constant: 17),
            top.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            top.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            copy.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            copy.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            copy.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 7),
            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -17),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 255)
        ]
        NSLayoutConstraint.activate(constraints)
        isAccessibilityElement = true
        accessibilityLabel = "Grand Theft Auto V native iPhone project. Port in progress. A18, Apple Metal, USB-C."
        accessibilityTraits = .staticText
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}
