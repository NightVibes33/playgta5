import Foundation

/// Access to user-selected game files, with no requirement to copy the mirror to the app.
final class USBStorageManager {
    static let shared = USBStorageManager()
    private let bookmarkKey = "gtaios.usb.bookmark"
    private(set) var root: URL?
    private var accessURL: URL?
    private var hasScope = false

    private init() { restore() }

    /// Accept USB volume, mirror/, or playgta5.com/ as long as Files grants access.
    /// A selection is validated while the security-scope remains open.
    func choose(_ chosen: URL) throws {
        let scope = chosen.startAccessingSecurityScopedResource()
        LogStore.shared.write("usb-storage", "Folder access: \(chosen.path), scope=\(scope), provider=\(chosen.scheme ?? "?")")
        guard let resolved = locateMirror(chosen) else {
            if scope { chosen.stopAccessingSecurityScopedResource() }
            throw StorageError.invalidLayout(chosen.lastPathComponent)
        }
        if hasScope { accessURL?.stopAccessingSecurityScopedResource() }
        accessURL = chosen
        hasScope = scope
        root = resolved
        do {
            let bookmark = try chosen.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        } catch {
            LogStore.shared.write("usb-storage", "Folder selected, but bookmark persistence failed: \(error)")
        }
        LogStore.shared.write("usb-storage", "Resolved game root: \(resolved.path), scope=\(scope)")
    }

    func restore() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        do {
            let selected = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let scope = selected.startAccessingSecurityScopedResource()
            if let resolved = locateMirror(selected) {
                root = resolved
                accessURL = selected
                hasScope = scope
                LogStore.shared.write("usb-storage", "Restored USB folder: \(resolved.path), stale=\(stale)")
            } else {
                if scope { selected.stopAccessingSecurityScopedResource() }
                LogStore.shared.write("usb-storage", "Saved USB path no longer contains playgta5.com; select it again")
            }
        } catch {
            LogStore.shared.write("usb-storage", "USB access restoration failed: \(error)")
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if let dir = values?.isDirectory { return dir }
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    private func isGameRoot(_ url: URL) -> Bool {
        isDirectory(url.appendingPathComponent("data")) &&
        isDirectory(url.appendingPathComponent("b"))
    }

    private func locateMirror(_ chosen: URL) -> URL? {
        // Fast-path all documented layouts. A USB disk may be selected at its root.
        let candidates = [
            chosen,
            chosen.appendingPathComponent("playgta5.com"),
            chosen.appendingPathComponent("mirror/playgta5.com"),
            chosen.appendingPathComponent("mirror")
        ]
        for candidate in candidates where isGameRoot(candidate) {
            return candidate.standardizedFileURL
        }
        // Some users store the mirror under an extra folder on the external drive.
        // Traverse directories only, bounded to 3 levels, never inspect 20GB archives.
        var pending: [(URL, Int)] = [(chosen, 0)]
        var scanned = 0
        while !pending.isEmpty && scanned < 250 {
            let (folder, level) = pending.removeFirst()
            scanned += 1
            guard level < 3 else { continue }
            let children: [URL]
            do {
                children = try FileManager.default.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            } catch {
                LogStore.shared.write("usb-storage", "Cannot list \(folder.lastPathComponent): \(error.localizedDescription)")
                continue
            }
            for child in children where isDirectory(child) {
                if isGameRoot(child) { return child.standardizedFileURL }
                // Do not descend into huge game archive/shader subtrees.
                if ["data", "b", "title", "shaders"].contains(child.lastPathComponent.lowercased()) { continue }
                if level < 2 { pending.append((child, level + 1)) }
            }
        }
        LogStore.shared.write("usb-storage", "Game root not found within three directory levels of \(chosen.path)")
        return nil
    }

    /// Validate only startup-critical files. The full asset manifest is served separately.
    func missingStartupAssets() -> [String] {
        guard root != nil else { return ["USB game folder not selected"] }
        let required: [(String, String)] = [
            ("data", "data/ game archives"),
            ("b/8b0b5899ed/game.wasm", "b/8b0b5899ed/game.wasm"),
            ("b/8b0b5899ed/shaders/index.json", "b/8b0b5899ed/shaders/index.json"),
            ("b/8b0b5899ed/title", "b/8b0b5899ed/title/ artwork"),
            ("b/8b0b5899ed/audio-worklet.js", "b/8b0b5899ed/audio-worklet.js")
        ]
        let missing = required.compactMap { file($0.0) == nil ? $0.1 : nil }
        LogStore.shared.write("usb-storage", missing.isEmpty
            ? "All startup paths available"
            : "Missing game paths: " + missing.joined(separator: ", "))
        return missing
    }

    /// Prevent URL traversal, symlinks escaping selected root, and hidden file leaks.
    func file(_ relative: String) -> URL? {
        guard let root, !relative.isEmpty, !relative.hasPrefix("/") else { return nil }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = base.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/") && FileManager.default.fileExists(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    enum StorageError: LocalizedError {
        case invalidLayout(String)
        var errorDescription: String? {
            switch self {
            case .invalidLayout(let name):
                return "Selected '\(name)' but could not find folders data/ and b/ together. Open the USB drive → mirror → playgta5.com, select the playgta5.com folder and tap Open. You can also select the drive's containing folder."
            }
        }
    }
}
