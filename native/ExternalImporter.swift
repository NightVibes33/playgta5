@_silgen_name("muguet_mount_external")
func muguet_mount_external(_ path: UnsafePointer<CChar>) -> Bool
@_silgen_name("muguet_import_error")
func muguet_import_error() -> UnsafePointer<CChar>?
@_silgen_name("muguet_game_ready")
func muguet_game_ready() -> Bool
@_silgen_name("muguet_has_game_code")
func muguet_has_game_code() -> Bool

/// UI state and the lifetime of the file-provider grant belong to the main actor.
/// The serial worker validates external files without blocking SwiftUI rendering.
@MainActor
final class Importer: ObservableObject {
    static let shared = Importer()
    @Published var ready = false
    @Published var progress: Double?
    @Published var error: String?
    private var scopedURL: URL?
    private let worker = DispatchQueue(label: "gtaios.external-game", qos: .userInitiated)
    private static let bookmarkKey = "gtaios.native.external-folder"

    init() {
        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        worker.async {
            do {
                var stale = false
                let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
                DispatchQueue.main.async { self.run(url) }
            } catch {
                let message = "Reconnect your game drive and select the folder again: \(error.localizedDescription)"
                DispatchQueue.main.async { self.error = message }
            }
        }
    }

    func run(_ url: URL) {
        guard progress == nil else { return }
        error = nil
        progress = 0
        worker.async {
            let scoped = url.startAccessingSecurityScopedResource()
            let ok = url.path.withCString { muguet_mount_external($0) }
            let ready = ok && muguet_game_ready()
            let message = ok ? nil : muguet_import_error().map { String(cString: $0) } ?? "Game folder could not be read."
            let bookmark = ok ? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)) : nil
            if !ok && scoped { url.stopAccessingSecurityScopedResource() }
            DispatchQueue.main.async {
                self.progress = nil
                guard ok else {
                    self.error = message
                    return
                }
                // Keep the grant open for the entire engine lifetime, including its I/O workers.
                if let previous = self.scopedURL { previous.stopAccessingSecurityScopedResource() }
                self.scopedURL = scoped ? url : nil
                if let bookmark { UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey) }
                self.ready = ready
                if !self.ready { self.error = "The selected library is incomplete or the drive was disconnected." }
            }
        }
    }
}
