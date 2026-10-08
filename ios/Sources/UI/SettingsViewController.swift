import UIKit

final class SettingsViewController: UITableViewController {
    private let fps = UISegmentedControl(items: ["30 FPS", "60 FPS"])
    private let scale = UISlider()
    private let lowMode = UISwitch()
    private let notes = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Graphics & Runtime"
        tableView.backgroundColor = UIColor(red: 0.055, green: 0.068, blue: 0.09, alpha: 1)
        tableView.separatorColor = .gray
        fps.selectedSegmentIndex = UserDefaults.standard.integer(forKey: "gtaios.fps") == 60 ? 1 : 0
        fps.addTarget(self, action: #selector(changed), for: .valueChanged)
        scale.minimumValue = 0.5
        scale.maximumValue = 1
        let stored = UserDefaults.standard.double(forKey: "gtaios.scale")
        scale.value = Float(stored == 0 ? 0.65 : stored)
        scale.addTarget(self, action: #selector(changed), for: .valueChanged)
        lowMode.isOn = true
        lowMode.isEnabled = false
        notes.text = "Low-memory mode is required for the first iPhone validation. Higher FPS is a requested limiter, not guaranteed performance. Shader compilation and rendering depend on WebKit features on the device."
        notes.textColor = .lightGray
        notes.font = .systemFont(ofSize: 12)
        notes.numberOfLines = 0
        notes.frame = CGRect(x: 16, y: 0, width: view.bounds.width - 32, height: 120)
        tableView.tableFooterView = notes
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 1 }
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { 3 }
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        cell.backgroundColor = .clear
        cell.textLabel?.textColor = .white
        switch indexPath.row {
        case 0: cell.textLabel?.text = "Frame cap"; cell.accessoryView = fps
        case 1: cell.textLabel?.text = "Render scale"; cell.accessoryView = scale
        default: cell.textLabel?.text = "Low-memory profile"; cell.accessoryView = lowMode
        }
        return cell
    }

    @objc private func changed() {
        UserDefaults.standard.set(fps.selectedSegmentIndex == 1 ? 60 : 30, forKey: "gtaios.fps")
        UserDefaults.standard.set(Double(scale.value), forKey: "gtaios.scale")
        LogStore.shared.write("boot", "Updated settings: fps=\(fps.selectedSegmentIndex == 1 ? 60 : 30) scale=\(scale.value)")
    }
}
