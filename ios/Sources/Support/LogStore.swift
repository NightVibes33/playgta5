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

    /// Real log history, read from bounded file tails off the main thread.
    func recentEvents(limit: Int = 5, completion: @escaping ([(String, String)]) -> Void) {
        queue.async {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: self.directory, includingPropertiesForKeys: nil)) ?? []
            var events: [(stamp: String, detail: String)] = []
            for file in files where file.pathExtension == "txt" {
                guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
                defer { try? handle.close() }
                let size = (try? handle.seekToEnd()) ?? 0
                try? handle.seek(toOffset: size > 32768 ? size - 32768 : 0)
                guard let data = try? handle.readToEnd(),
                      let content = String(data: data, encoding: .utf8) else { continue }
                let channel = file.deletingPathExtension().lastPathComponent
                for line in content.split(separator: "\n").suffix(20) {
                    guard line.hasPrefix("["),
                          let close = line.firstIndex(of: "]") else { continue }
                    let stamp = String(line[line.index(after: line.startIndex)..<close])
                    let detail = String(line[line.index(after: close)...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !detail.isEmpty {
                        events.append((stamp, channel + " · " + detail))
                    }
                }
            }
            let rows = events.sorted { $0.stamp > $1.stamp }
                .prefix(max(0, min(20, limit)))
                .map { ($0.stamp, $0.detail) }
            DispatchQueue.main.async { completion(Array(rows)) }
        }
    }

    func diagnosticsDirectory() -> URL { directory }
}
