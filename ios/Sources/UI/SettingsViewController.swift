import UIKit

/// Legacy browser-port switches preserved for future native engine ABI mapping.
/// Only the native Metal frame rate is currently active; other values are
/// saved presets, NOT functional rendering controls without the ARM64 engine.
final class SettingsViewController: UITableViewController {
    private let ink = UIColor(red: 0.035, green: 0.051, blue: 0.061, alpha: 1)
    private let panel = UIColor(red: 0.085, green: 0.106, blue: 0.12, alpha: 1)
    private let accent = UIColor(red: 0.58, green: 0.88, blue: 0.65, alpha: 1)

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "GAME SETTINGS"
        view.backgroundColor = ink
        tableView.backgroundColor = ink
        tableView.separatorColor = UIColor.white.withAlphaComponent(0.075)
        tableView.sectionHeaderTopPadding = 14
        tableView.estimatedRowHeight = 58
        tableView.rowHeight = UITableView.automaticDimension

        let header = UIView(frame: CGRect(x: 0, y: 0, width: 480, height: 76))
        let eyebrow = UILabel()
        eyebrow.text = "NATIVE METAL CONFIGURATION  /  ENGINE NOT LINKED"
        eyebrow.font = .monospacedSystemFont(ofSize: 10, weight: .semibold)
        eyebrow.textColor = accent
        eyebrow.translatesAutoresizingMaskIntoConstraints = false
        let title = UILabel()
        title.text = "REQUESTED ENGINE PRESETS"
        title.font = .systemFont(ofSize: 23, weight: .black)
        title.textColor = .white
        title.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(eyebrow); header.addSubview(title)
        NSLayoutConstraint.activate([
            eyebrow.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 22),
            eyebrow.topAnchor.constraint(equalTo: header.topAnchor, constant: 14),
            title.leadingAnchor.constraint(equalTo: eyebrow.leadingAnchor),
            title.topAnchor.constraint(equalTo: eyebrow.bottomAnchor, constant: 8)
        ])
        tableView.tableHeaderView = header

        let footer = UIView(frame: CGRect(x: 0, y: 0, width: 480, height: 118))
        let note = UILabel()
        note.text = "Only FPS currently adjusts the native Metal surface. The game engine, shaders and remaining gameplay options are NOT connected: settings here do not make GTA playable. Values are saved for a future verified ARM64 engine."
        note.numberOfLines = 0
        note.textColor = UIColor(white: 0.57, alpha: 1)
        note.font = .systemFont(ofSize: 11)
        note.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(note)
        NSLayoutConstraint.activate([
            note.topAnchor.constraint(equalTo: footer.topAnchor, constant: 14),
            note.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 25),
            note.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -25)
        ])
        tableView.tableFooterView = footer
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Reset", style: .plain,
                                                            target: self, action: #selector(resetPressed))
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
        navigationController?.navigationBar.tintColor = accent
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
        cell.selectionStyle = .default
        cell.textLabel?.text = spec.title
        cell.textLabel?.textColor = UIColor.white
        cell.textLabel?.font = UIFont.systemFont(ofSize: 15, weight: .semibold)
        cell.detailTextLabel?.text = spec.subtitle
        cell.detailTextLabel?.font = UIFont.systemFont(ofSize: 10)
        cell.detailTextLabel?.textColor = UIColor(white: 0.57, alpha: 1)
        cell.detailTextLabel?.numberOfLines = 2
        let value = UILabel()
        value.text = EngineOptions.display(spec.id)
        value.textColor = accent
        value.font = .systemFont(ofSize: 12, weight: .bold)
        value.textAlignment = .right
        value.numberOfLines = 2
        value.lineBreakMode = .byWordWrapping
        value.frame = CGRect(x: 0, y: 0, width: 130, height: 44)
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
