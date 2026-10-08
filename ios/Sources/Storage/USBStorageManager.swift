import Foundation

/// The mirror is never copied to internal storage. Access is held by a picked
/// security-scoped directory, or by a file picked in the same provider if (and
/// only if) sibling reads are independently proven to work on that provider.
final class USBStorageManager {
    static let shared = USBStorageManager()
    static let changedNotification = Notification.Name("gtaios.usb-storage.changed")
    private let bookmarkKey = "gtaios.usb.bookmark"
    private let anchorKindKey = "gtaios.usb.bookmark-kind"

    private let worker = DispatchQueue(label: "gtaios.usb.files", qos: .userInitiated)
    private let stateLock = NSLock()
    private var storedRoot: URL?
    private var startupMissing: [String] = ["USB game folder not selected"]
    var root: URL? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return storedRoot
    }
    private(set) var selectionMethod: String = "none"
    private var accessURL: URL?
    private var hasScope = false

    // Bookmark resolution / disk probing must never block viewDidLoad or the
    // document-picker delegate. iOS USB providers can take arbitrary time.
    private init() {
        worker.async { [weak self] in self?.restore() }
    }

    func chooseAsync(_ chosen: URL, fromFile: Bool,
                     completion: @escaping (Result<URL, Error>) -> Void) {
        worker.async { [weak self] in
            guard let self else { return }
            let result: Result<URL, Error>
            do {
                if fromFile {
                    try self.chooseIndexFile(chosen)
                } else {
                    try self.choose(chosen)
                }
                result = .success(self.root ?? chosen)
            } catch {
                result = .failure(error)
            }
            DispatchQueue.main.async { completion(result) }
        }
    }

    private func saveRoot(_ url: URL, missing: [String]) {
        stateLock.lock()
        storedRoot = url
        startupMissing = missing
        stateLock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.changedNotification, object: nil)
        }
    }

    func choose(_ chosen: URL) throws {
        try select(chosen, fromFile: false)
    }

    /// USB-provider fallback when the Files folder picker doesn't complete.
    /// This is NOT a sandbox bypass: some providers only grant the picked file,
    /// in which case this function rejects the selection and explains why.
    func chooseIndexFile(_ chosen: URL) throws {
        guard chosen.lastPathComponent.lowercased() == "index.html" else {
            throw StorageError.invalidMarker(chosen.lastPathComponent)
        }
        try select(chosen, fromFile: true)
    }

    private func select(_ selected: URL, fromFile: Bool) throws {
        let scope = selected.startAccessingSecurityScopedResource()
        let kind = fromFile ? "index.html file" : "folder"
        LogStore.shared.write("usb-storage",
            "Selected \(kind): \(selected.path), securityScope=\(scope)")
        let candidate = fromFile ? selected.deletingLastPathComponent() : selected
        guard let gameRoot = locateMirror(candidate) else {
            if scope { selected.stopAccessingSecurityScopedResource() }
            throw StorageError.invalidLayout(candidate.lastPathComponent)
        }
        // A file-only security scope may not authorize sibling data/ and b/.
        // Check real file I/O before storing the URL or claiming readiness.
        do {
            try verifyReadable(gameRoot)
        } catch {
            if scope { selected.stopAccessingSecurityScopedResource() }
            LogStore.shared.write("usb-storage",
                "Denied \(kind) access: \(error.localizedDescription)")
            if fromFile { throw StorageError.fileProviderDeniedSiblingAccess(error.localizedDescription) }
            throw error
        }

        // Do not drop a working selection if the new bookmark cannot be made.
        if hasScope { accessURL?.stopAccessingSecurityScopedResource() }
        accessURL = selected
        hasScope = scope
        // Compute startup status once on the worker; UI refreshes must never
        // perform thousands of external Files-provider calls.
        let missing = scanStartupAssets(in: gameRoot)
        saveRoot(gameRoot, missing: missing)
        selectionMethod = kind

        do {
            let bookmark = try selected.bookmarkData(
                options: [.minimalBookmark],
                includingResourceValuesForKeys: nil,
                relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            UserDefaults.standard.set(fromFile, forKey: anchorKindKey)
        } catch {
            LogStore.shared.write("usb-storage",
                "Folder access is valid now, but bookmark could not be saved: \(error.localizedDescription)")
        }
        LogStore.shared.write("usb-storage",
            "READY: \(gameRoot.path), selectedVia=\(kind), scope=\(scope)")
    }

    func restore() {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var stale = false
        do {
            let selected = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
                bookmarkDataIsStale: &stale)
            let scope = selected.startAccessingSecurityScopedResource()
            let fileBased = UserDefaults.standard.bool(forKey: anchorKindKey)
            let candidate = fileBased ? selected.deletingLastPathComponent() : selected
            if let gameRoot = locateMirror(candidate) {
                do {
                    try verifyReadable(gameRoot)
                    let missing = scanStartupAssets(in: gameRoot)
                    saveRoot(gameRoot, missing: missing)
                    accessURL = selected
                    hasScope = scope
                    selectionMethod = fileBased ? "index.html file" : "folder"
                    LogStore.shared.write("usb-storage",
                        "Restored \(selectionMethod) selection: \(gameRoot.path), stale=\(stale)")
                } catch {
                    if scope { selected.stopAccessingSecurityScopedResource() }
                    LogStore.shared.write("usb-storage",
                        "USB bookmark restored but no longer readable: \(error.localizedDescription)")
                }
            } else {
                if scope { selected.stopAccessingSecurityScopedResource() }
                LogStore.shared.write("usb-storage",
                    "USB bookmark no longer resolves to playgta5.com (drive detached or permission revoked)")
            }
        } catch {
            LogStore.shared.write("usb-storage",
                "USB bookmark resolve failed: \(error.localizedDescription)")
        }
    }

    private func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        if let value = values?.isDirectory { return value }
        var flag: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &flag) && flag.boolValue
    }

    private func isGameRoot(_ url: URL) -> Bool {
        isDirectory(url.appendingPathComponent("data")) &&
        isDirectory(url.appendingPathComponent("b"))
    }

    private func locateMirror(_ chosen: URL) -> URL? {
        let candidates = [
            chosen,
            chosen.appendingPathComponent("playgta5.com"),
            chosen.appendingPathComponent("mirror/playgta5.com"),
            chosen.appendingPathComponent("mirror")
        ]
        for candidate in candidates where isGameRoot(candidate) {
            return candidate.standardizedFileURL
        }
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
                LogStore.shared.write("usb-storage",
                    "Directory access failed \(folder.path): \(error.localizedDescription)")
                continue
            }
            for child in children where isDirectory(child) {
                if isGameRoot(child) { return child.standardizedFileURL }
                if ["data", "b", "title", "shaders"].contains(child.lastPathComponent.lowercased()) {
                    continue
                }
                if level < 2 { pending.append((child, level + 1)) }
            }
        }
        return nil
    }

    /// Validate real USB I/O under the caller's selected scope. File coordination
    /// is required for externally provided content; fileExists alone isn't proof.
    /// The archive header check reads FOUR bytes, never copies 63MB of wasm.
    private func verifyReadable(_ root: URL) throws {
        let archive = root.appendingPathComponent("b/8b0b5899ed/game.wasm")
        guard isDirectory(root.appendingPathComponent("data")),
              isDirectory(root.appendingPathComponent("b")),
              FileManager.default.fileExists(atPath: archive.path) else {
            throw StorageError.missingEngine
        }
        var coordinationError: NSError?
        var readingError: Error?
        var didCoordinate = false
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: archive, options: [],
                               error: &coordinationError) { coordinatedURL in
            didCoordinate = true
            do {
                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? handle.close() }
                let magic = try handle.read(upToCount: 4) ?? Data()
                guard magic == Data([0, 97, 115, 109]) else {
                    throw StorageError.invalidEngine
                }
                // data/ directory existence was checked above. Never enumerate
                // its thousands of entries just to validate a picked folder.
            } catch {
                readingError = error
            }
        }
        if let error = coordinationError {
            throw StorageError.inaccessibleEngine("File coordination: " + error.localizedDescription)
        }
        guard didCoordinate else {
            throw StorageError.inaccessibleEngine("File provider did not coordinate game.wasm")
        }
        if let error = readingError {
            if error is StorageError { throw error }
            throw StorageError.inaccessibleEngine(error.localizedDescription)
        }
    }

    /// UI reads only a cached snapshot; no synchronous USB file I/O.
    func missingStartupAssets() -> [String] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return startupMissing
    }

    private func scanStartupAssets(in gameRoot: URL) -> [String] {
        let required: [(String, String)] = [
            ("data", "data/ game archives"),
            ("b/8b0b5899ed/game.wasm", "b/8b0b5899ed/game.wasm"),
            ("b/8b0b5899ed/shaders/index.json", "b/8b0b5899ed/shaders/index.json"),
            ("b/8b0b5899ed/title", "b/8b0b5899ed/title/ artwork"),
            ("b/8b0b5899ed/audio-worklet.js", "b/8b0b5899ed/audio-worklet.js")
        ]
        let missing = required.compactMap { item -> String? in
            let path = gameRoot.appendingPathComponent(item.0)
            return FileManager.default.fileExists(atPath: path.path) ? nil : item.1
        }
        LogStore.shared.write("usb-storage", missing.isEmpty ?
            "Required startup paths detected" :
            "Missing startup paths: " + missing.joined(separator: ", "))
        return missing
    }

    func file(_ relative: String) -> URL? {
        guard let root, !relative.isEmpty, !relative.hasPrefix("/") else { return nil }
        let base = root.resolvingSymlinksInPath().standardizedFileURL
        let candidate = base.appendingPathComponent(relative)
            .resolvingSymlinksInPath().standardizedFileURL
        guard candidate.path.hasPrefix(base.path + "/"),
              FileManager.default.fileExists(atPath: candidate.path) else { return nil }
        return candidate
    }

    enum StorageError: LocalizedError {
        case invalidLayout(String)
        case invalidMarker(String)
        case missingEngine
        case invalidEngine
        case inaccessibleEngine(String)
        case fileProviderDeniedSiblingAccess(String)

        var errorDescription: String? {
            switch self {
            case .invalidLayout(let folder):
                return "'\(folder)' has no accessible data/ and b/ game folders. Select mirror/playgta5.com."
            case .invalidMarker(let name):
                return "Selected \(name), but the USB fallback requires playgta5.com/index.html."
            case .missingEngine:
                return "Game root found, but b/8b0b5899ed/game.wasm cannot be found."
            case .invalidEngine:
                return "Found game.wasm but its WebAssembly file signature is invalid."
            case .inaccessibleEngine(let details):
                return "Cannot read game.wasm or the data directory: \(details)"
            case .fileProviderDeniedSiblingAccess(let reason):
                return "iOS accepted index.html, but this app could not read the other required game files. A file selection might not grant access to its siblings. Reason: \(reason). Try Select Folder, or check the USB layout."
            }
        }
    }
}
