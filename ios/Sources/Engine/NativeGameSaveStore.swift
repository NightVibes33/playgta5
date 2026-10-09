import Foundation

/// Durable native save storage with atomic writes and strict slot validation.
/// GTA engine save calls are NOT connected yet; this is the host file service
/// that can be bound once their actual signatures and serialization are known.
final class NativeGameSaveStore {
    static let shared = NativeGameSaveStore()
    enum SaveError: LocalizedError {
        case invalidSlot
        case oversized
        var errorDescription: String? {
            switch self {
            case .invalidSlot: return "Invalid save slot identifier"
            case .oversized: return "Save record exceeds the 32 MiB safety bound"
            }
        }
    }

    private let queue = DispatchQueue(label: "gtaios.native.save", qos: .utility)
    private let directory: URL
    private init() {
        directory = FileManager.default.urls(for: .documentDirectory,
            in: .userDomainMask)[0].appendingPathComponent("GTAiOS-Saves", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func url(for slot: String) throws -> URL {
        guard slot.range(of: "^[A-Za-z0-9_-]{1,40}$", options: .regularExpression) != nil else {
            throw SaveError.invalidSlot
        }
        return directory.appendingPathComponent(slot).appendingPathExtension("sav")
    }

    func write(_ data: Data, slot: String, completion: @escaping (Result<Void, Error>) -> Void) {
        queue.async {
            let result: Result<Void, Error>
            do {
                guard data.count <= 32 * 1024 * 1024 else { throw SaveError.oversized }
                try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
                let file = try self.url(for: slot)
                try data.write(to: file, options: [.atomic, .completeFileProtectionUnlessOpen])
                result = .success(())
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func read(slot: String, completion: @escaping (Result<Data?, Error>) -> Void) {
        queue.async {
            let result: Result<Data?, Error>
            do {
                let file = try self.url(for: slot)
                if FileManager.default.fileExists(atPath: file.path) {
                    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
                    let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
                    guard size >= 0 && size <= 32 * 1024 * 1024 else { throw SaveError.oversized }
                    result = .success(try Data(contentsOf: file, options: .mappedIfSafe))
                } else { result = .success(nil) }
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    func slots() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return files.filter { $0.pathExtension == "sav" }.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }
}
