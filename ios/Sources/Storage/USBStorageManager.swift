import Foundation

final class USBStorageManager {
    static let shared = USBStorageManager()
    private let bookmarkKey = "gtaios.usb.bookmark"
    private(set) var root: URL?
    private var accessURL: URL?
    private var hasScope = false

    private init() { restore() }

    func choose(_ chosen: URL) throws {
        let scope = chosen.startAccessingSecurityScopedResource()
        guard let resolved = locateMirror(chosen) else {
            if scope { chosen.stopAccessingSecurityScopedResource() }
            throw StorageError.invalidLayout
        }
        if hasScope { accessURL?.stopAccessingSecurityScopedResource() }
        accessURL = chosen
        hasScope = scope
        root = resolved
        if let bookmark = try? chosen.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
        }
        LogStore.shared.write("usb-storage", "Selected \(resolved.path); security scope \(scope)")
    }

    func restore() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            let scope = url.startAccessingSecurityScopedResource()
            if let resolved = locateMirror(url) {
                root = resolved; accessURL = url; hasScope = scope
                LogStore.shared.write("usb-storage", "Restored selected directory; stale=\(stale)")
            } else if scope {
                url.stopAccessingSecurityScopedResource()
            }
        } catch {
            LogStore.shared.write("usb-storage", "Bookmark restore failed: \(error)")
        }
    }

    private func locateMirror(_ url: URL) -> URL? {
        let candidates = [url, url.appendingPathComponent("playgta5.com"),
                          url.appendingPathComponent("mirror/playgta5.com")]
        for candidate in candidates {
            var isDir: ObjCBool = false
            let data = candidate.appendingPathComponent("data")
            if FileManager.default.fileExists(atPath: data.path, isDirectory: &isDir) && isDir.boolValue {
                return candidate.standardizedFileURL
            }
        }
        return nil
    }

    func file(_ relative: String) -> URL? {
        guard let root = root else { return nil }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let path = base.appendingPathComponent(relative).resolvingSymlinksInPath().standardizedFileURL
        guard path.path.hasPrefix(base.path + "/"), FileManager.default.fileExists(atPath: path.path) else { return nil }
        return path
    }

    enum StorageError: LocalizedError {
        case invalidLayout
        var errorDescription: String? { "Choose the mirror/playgta5.com directory containing the data folder." }
    }
}
