
import UIKit
import CoreGraphics

/// Restrained launcher palette, inspired by the game's city-at-dusk setting.
/// No runtime asset downloads, shaders, animation loops or artwork IO.
enum GTATheme {
    static let night = UIColor(red: 0.025, green: 0.031, blue: 0.056, alpha: 1)
    static let raised = UIColor(red: 0.075, green: 0.085, blue: 0.135, alpha: 1)
    static let inset = UIColor(red: 0.145, green: 0.158, blue: 0.181, alpha: 1)
    static let coral = UIColor(red: 0.98, green: 0.34, blue: 0.67, alpha: 1)
    static let neonPink = UIColor(red: 0.98, green: 0.30, blue: 0.70, alpha: 1)
    static let neonBlue = UIColor(red: 0.27, green: 0.71, blue: 1, alpha: 1)
    static let mint = UIColor(red: 0.27, green: 0.95, blue: 0.68, alpha: 1)
    static let cream = UIColor(red: 0.97, green: 0.97, blue: 0.965, alpha: 1)
    static let subdued = UIColor(red: 0.70, green: 0.73, blue: 0.84, alpha: 1)
    static let success = UIColor(red: 0.54, green: 0.82, blue: 0.63, alpha: 1)

    static func caption(_ text: String) -> UILabel {
        let l = UILabel()
        l.text = text
        l.textColor = subdued
        l.font = .systemFont(ofSize: 12, weight: .medium)
        l.adjustsFontForContentSizeCategory = true
        return l
    }

    static func section(_ title: String) -> UILabel {
        let l = UILabel()
        l.text = title
        l.textColor = cream
        l.font = .systemFont(ofSize: 20, weight: .bold)
        l.adjustsFontForContentSizeCategory = true
        return l
    }

    static func card(_ view: UIView) {
        view.backgroundColor = raised
        view.layer.cornerRadius = 18
        view.layer.cornerCurve = .continuous
        view.layer.borderWidth = 1
        view.layer.borderColor = UIColor.white.withAlphaComponent(0.16).cgColor
    }
}

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
            UIColor(red: 0.08, green: 0.08, blue: 0.22, alpha: 1).cgColor,
            UIColor(red: 0.39, green: 0.16, blue: 0.40, alpha: 1).cgColor,
            UIColor(red: 0.97, green: 0.43, blue: 0.37, alpha: 1).cgColor
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


/// Compact, fixed-height cinematic artwork. Fixed text widths and line
/// breaking prevent "GRAND THEFT..." truncation on a 393pt iPhone.
final class LosSantosHeroView: UIView {
    private let skyline = SunsetSkylineView()
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        layer.cornerRadius = 18
        layer.cornerCurve = .continuous
        layer.borderWidth = 1
        layer.borderColor = UIColor.white.withAlphaComponent(0.10).cgColor

        skyline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(skyline)
        NSLayoutConstraint.activate([
            skyline.topAnchor.constraint(equalTo: topAnchor),
            skyline.bottomAnchor.constraint(equalTo: bottomAnchor),
            skyline.leadingAnchor.constraint(equalTo: leadingAnchor),
            skyline.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // Bundled, locally generated GTA V hero art. No network access, no
        // external storage reads and no synthetic gameplay/UI data involved.
        if let imageURL = Bundle.main.url(forResource: "gtaios-reference-hero", withExtension: "jpg"),
           let image = UIImage(contentsOfFile: imageURL.path) {
            let artwork = UIImageView(image: image)
            artwork.translatesAutoresizingMaskIntoConstraints = false
            artwork.contentMode = .scaleAspectFill
            artwork.clipsToBounds = true
            addSubview(artwork)
            NSLayoutConstraint.activate([
                artwork.topAnchor.constraint(equalTo: topAnchor),
                artwork.bottomAnchor.constraint(equalTo: bottomAnchor),
                artwork.leadingAnchor.constraint(equalTo: leadingAnchor),
                artwork.trailingAnchor.constraint(equalTo: trailingAnchor)
            ])
        }

        let isReferenceArtwork = Bundle.main.url(forResource: "gtaios-reference-hero", withExtension: "jpg") != nil
        let eyebrow = UILabel()
        eyebrow.text = "LOS SANTOS  /  GTA V"
        eyebrow.isHidden = isReferenceArtwork
        eyebrow.textColor = GTATheme.cream.withAlphaComponent(0.90)
        eyebrow.font = .systemFont(ofSize: 10, weight: .heavy)
        eyebrow.letterSpacingIfAvailable()
        eyebrow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(eyebrow)

        let title = UILabel()
        title.text = "GRAND THEFT\nAUTO V"
        title.isHidden = isReferenceArtwork
        title.font = .systemFont(ofSize: 43, weight: .black, width: .condensed)
        title.textColor = .white
        title.numberOfLines = 2
        title.lineBreakMode = .byWordWrapping
        title.adjustsFontSizeToFitWidth = true
        title.minimumScaleFactor = 0.72
        title.setContentCompressionResistancePriority(.required, for: .vertical)
        title.translatesAutoresizingMaskIntoConstraints = false
        addSubview(title)

        let tagline = UILabel()
        tagline.text = "GTA V  ·  LOCAL USB-C GAME LIBRARY"
        tagline.isHidden = isReferenceArtwork
        tagline.textColor = GTATheme.cream.withAlphaComponent(0.82)
        tagline.font = .systemFont(ofSize: 10, weight: .semibold)
        tagline.numberOfLines = 1
        tagline.adjustsFontSizeToFitWidth = true
        tagline.minimumScaleFactor = 0.7
        tagline.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tagline)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 180),
            eyebrow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            eyebrow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            eyebrow.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            title.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 2),
            tagline.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            tagline.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            tagline.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -18)
        ])
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityLabel = "Grand Theft Auto V, Los Santos game library"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

private extension UILabel {
    func letterSpacingIfAvailable() {
        guard let text = text else { return }
        let fontAttributes: [NSAttributedString.Key: Any] = [
            .kern: 1.4, .foregroundColor: textColor as Any,
            .font: font as Any
        ]
        attributedText = NSAttributedString(string: text, attributes: fontAttributes)
    }
}
