import Foundation
import UIKit

final class LogStore {
    static let shared = LogStore()
    private let queue = DispatchQueue(label: "gtaios.logs", qos: .utility)
    private let directory: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        directory = documents.appendingPathComponent("GTAiOS-Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ channel: String, _ message: String) {
        let safe = channel.range(of: "^[a-zA-Z0-9-]+$", options: .regularExpression) != nil ? channel : "engine"
        let file = directory.appendingPathComponent(safe + ".txt")
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        queue.async {
            guard let bytes = line.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: file.path) {
                if let handle = try? FileHandle(forWritingTo: file) {
                    defer { try? handle.close() }
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: bytes)
                }
            } else {
                try? bytes.write(to: file)
            }
        }
    }

    func exportURL() -> URL {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("GTAiOS-diagnostics.txt")
        queue.sync {}
        var collected = "GTAiOS diagnostics\n"
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) where file.pathExtension == "txt" {
                collected += "\n===== \(file.lastPathComponent) =====\n"
                collected += (try? String(contentsOf: file, encoding: .utf8)) ?? "(unreadable)"
            }
        }
        try? collected.write(to: output, atomically: true, encoding: .utf8)
        return output
    }

    func diagnosticsDirectory() -> URL { directory }
}
