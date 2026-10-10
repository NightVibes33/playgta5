import UIKit

/// Legacy browser-port switches preserved for future native engine ABI mapping.
/// Only the native Metal frame rate is currently active; other values are
/// saved presets, NOT functional rendering controls without the ARM64 engine.
final class SettingsViewController: UITableViewController {
    private let ink = GTATheme.night
    private let panel = GTATheme.raised
    private let accent = GTATheme.neonPink

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Graphics & Controls"
        view.backgroundColor = ink
        tableView.backgroundColor = ink
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.11)
        tableView.sectionHeaderTopPadding = 13
        tableView.estimatedRowHeight = 78
        tableView.rowHeight = UITableView.automaticDimension

        // The graphics page shares the same cinematic GTA V identity as Home,
        // but leaves the choices wired directly to EngineOptions.
        let header = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 368))
        header.backgroundColor = GTATheme.night
        let art = LosSantosHeroView()
        art.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(art)
        let heading = GTATheme.section("Graphics & Controls")
        heading.font = .systemFont(ofSize: 27, weight: .heavy)
        heading.translatesAutoresizingMaskIntoConstraints = false
        heading.adjustsFontSizeToFitWidth = true
        heading.minimumScaleFactor = 0.8
        let description = GTATheme.caption("GTA V · native Metal frame target and saved engine presets")
        description.numberOfLines = 2
        description.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(heading)
        header.addSubview(description)
        NSLayoutConstraint.activate([
            art.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            art.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 18),
            art.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18),
            heading.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 21),
            heading.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -18),
            heading.topAnchor.constraint(equalTo: art.bottomAnchor, constant: 13),
            description.leadingAnchor.constraint(equalTo: heading.leadingAnchor),
            description.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -21),
            description.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 3)
        ])
        tableView.tableHeaderView = header

        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 393, height: 154))
        let note = UILabel()
        note.text = "Only the Metal frame-rate setting currently applies to the native preview. Other preferences are saved for later integration. This screen does not enable GTA V gameplay."
        note.numberOfLines = 0
        note.textColor = GTATheme.subdued
        note.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(
            for: .systemFont(ofSize: 13))
        note.adjustsFontForContentSizeCategory = true
        note.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(note)
        NSLayoutConstraint.activate([
            note.topAnchor.constraint(equalTo: footer.topAnchor, constant: 14),
            note.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 25),
            note.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -25),
            note.bottomAnchor.constraint(lessThanOrEqualTo: footer.bottomAnchor, constant: -16)
        ])
        tableView.tableFooterView = footer
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Reset", style: .plain,
                                                            target: self, action: #selector(resetPressed))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.tintColor = accent
        navigationController?.navigationBar.barStyle = .black
        navigationController?.navigationBar.titleTextAttributes = [
            .foregroundColor: UIColor.white,
            .font: UIFont.systemFont(ofSize: 15, weight: .bold)
        ]
    }

    override func numberOfSections(in tableView: UITableView) -> Int { EngineOptions.sections.count }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        EngineOptions.sections[section].options.count
    }
    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        EngineOptions.sections[section].title
    }
    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        EngineOptions.sections[section].subtitle
    }

    override func tableView(_ tableView: UITableView,
                            cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let spec = EngineOptions.sections[indexPath.section].options[indexPath.row]
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.backgroundColor = panel
        cell.layer.borderColor = UIColor.white.withAlphaComponent(0.07).cgColor
        cell.selectionStyle = .default
        cell.tintColor = accent
        cell.accessibilityHint = "Double-tap to change the preset"
        cell.textLabel?.text = spec.title
        cell.textLabel?.textColor = GTATheme.cream
        cell.textLabel?.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .systemFont(ofSize: 16, weight: .semibold))
        cell.textLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.text = spec.subtitle
        cell.detailTextLabel?.font = UIFontMetrics(forTextStyle: .caption1).scaledFont(
            for: .systemFont(ofSize: 12))
        cell.detailTextLabel?.adjustsFontForContentSizeCategory = true
        cell.detailTextLabel?.textColor = GTATheme.subdued
        cell.detailTextLabel?.numberOfLines = 2
        let value = UILabel()
        value.text = EngineOptions.display(spec.id)
        value.textColor = accent
        value.font = UIFontMetrics(forTextStyle: .callout).scaledFont(
            for: .systemFont(ofSize: 13, weight: .bold))
        value.adjustsFontForContentSizeCategory = true
        value.textAlignment = .right
        value.numberOfLines = 2
        value.lineBreakMode = .byWordWrapping
        value.frame = CGRect(x: 0, y: 0, width: 103, height: 51)
        cell.accessoryView = value
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let spec = EngineOptions.sections[indexPath.section].options[indexPath.row]
        let sheet = UIAlertController(title: spec.title, message: spec.subtitle, preferredStyle: .actionSheet)
        for (name, key) in spec.choices {
            let selected = EngineOptions.value(spec.id) == key
            sheet.addAction(UIAlertAction(title: selected ? "✓  " + name : name, style: .default) { _ in
                EngineOptions.set(spec.id, value: key)
                tableView.reloadRows(at: [indexPath], with: .none)
                UISelectionFeedbackGenerator().selectionChanged()
            })
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let pop = sheet.popoverPresentationController,
           let cell = tableView.cellForRow(at: indexPath) {
            pop.sourceView = cell
            pop.sourceRect = cell.bounds
        }
        present(sheet, animated: true)
    }

    @objc private func resetPressed() {
        let alert = UIAlertController(title: "Reset engine configuration?",
                                      message: "Reset staged game settings and native Metal frame-rate preference.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Reset", style: .destructive) { [weak self] _ in
            EngineOptions.resetAll()
            self?.tableView.reloadData()
        })
        present(alert, animated: true)
    }
}
