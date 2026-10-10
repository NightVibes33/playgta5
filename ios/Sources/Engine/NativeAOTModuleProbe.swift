import Foundation
import CryptoKit

/// Checks an opt-in, privately compiled AOT engine alongside the USB game
/// files. Not a GTA game executor: it only calls Wasmtime's deserializer and
/// lists imports. In particular it never instantiates the 3 GiB shared heap,
/// passes the game a Metal device, or invokes gameplay exports.
enum NativeAOTModuleProbe {
    enum Outcome {
        case notSupplied
        case deserialized(UInt32, UInt32, String)
        case failed(String)
    }

    // GC-disabled Wasmtime 49.0.2 compiler output verified from
    // exact SHA256-matched game.wasm. This supersedes the old GC-enabled\n    // serialized module that iOS beta 4 rejected. Deserialization is UNSAFE for arbitrary
    // data: never remove this content allowlist.
    static let allowedSHA256 =
        "4ed6a1261747212cc3413319db55c20f9ee48be72d6572dd4513f4febb318fd9"
    static let expectedBytes: Int64 = 238_815_736
    private static let worker = DispatchQueue(label: "gtaios.native.aot-imports", qos: .userInitiated)

    static func inspect(completion: @escaping (Outcome) -> Void) {
        worker.async {
            let outcome: Outcome
            #if targetEnvironment(simulator)
            outcome = .failed("Compiled AOT module is device-only; iOS simulator uses a different architecture")
            #else
            do {
                outcome = try inspectOnWorker()
            } catch {
                outcome = .failed(error.localizedDescription)
            }
            #endif
            DispatchQueue.main.async { completion(outcome) }
        }
    }

    private static func inspectOnWorker() throws -> Outcome {
        guard USBStorageManager.shared.root != nil else {
            return .failed("USB game directory not connected")
        }
        let candidates = ["real-gta-ios.cwasm", "b/8b0b5899ed/real-gta-ios.cwasm"]
        guard let file = candidates.lazy.compactMap({ USBStorageManager.shared.file($0) }).first else {
            return .notSupplied
        }

        var coordinationError: NSError?
        var outcome: Outcome?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: file, options: [], error: &coordinationError
        ) { granted in
            do {
                let handle = try FileHandle(forReadingFrom: granted)
                defer { try? handle.close() }
                let values = try FileManager.default.attributesOfItem(atPath: granted.path)
                let size = (values[.size] as? NSNumber)?.int64Value ?? 0
                guard size == expectedBytes else {
                    outcome = .failed("Compiled AOT file size mismatch: \(size) bytes, expected \(expectedBytes)")
                    return
                }

                var checksum = SHA256()
                while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                    checksum.update(data: chunk)
                }
                let digest = checksum.finalize().map { String(format: "%02x", $0) }.joined()
                guard digest == allowedSHA256 else {
                    outcome = .failed("Compiled AOT SHA256 mismatch: refusing unsafe Wasmtime deserialization")
                    return
                }
                LogStore.shared.write("native", "Trusted 228 MiB AArch64 AOT module SHA256 verified. Deserialization beginning.")
                var count: UInt32 = 0
                var covered: UInt32 = 0
                var message = [CChar](repeating: 0, count: 16384)
                let result: Int32 = granted.withUnsafeFileSystemRepresentation { path in
                    guard let path else { return -10 }
                    return gta_ios_wasmtime_aot_probe(path, &count, &covered, &message, message.count)
                }
                let detail = String(cString: message)
                LogStore.shared.write("native", "Wasmtime real AOT deserialization result=\(result), imports=\(count), linked=\(covered), message=\(detail)")
                if result == 0 {
                    outcome = .deserialized(count, covered, detail)
                } else {
                    outcome = .failed("Wasmtime deserialization code \(result): \(detail)")
                }
            } catch {
                outcome = .failed("AOT file access failed: \(error.localizedDescription)")
            }
        }
        if let error = coordinationError { throw error }
        return outcome ?? .failed("File provider returned without an AOT read grant")
    }
}
