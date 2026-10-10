import Foundation
import MetalKit

/// Native USB I/O and WASM binary inspection. This is NOT a WASM executor:
/// the Emscripten memory64/pthread module still requires a verified AOT
/// conversion and replacement of its platform imports.
enum NativeEngineStatus {
    struct MemoryImport {
        let minimumPages: UInt64
        let maximumPages: UInt64?
        let shared: Bool
        let memory64: Bool
    }
    struct Inspection {
        let byteCount: Int64
        let memory: MemoryImport
        let shaderIndex: URL
        let gameFile: URL
    }
    enum Failure: LocalizedError {
        case notConnected
        case missing(String)
        case invalidWasm(String)
        case nativeEngineUnavailable
        case io(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Select the USB game folder first."
            case .missing(let p): return "Required USB game file is unavailable: " + p
            case .invalidWasm(let m): return "Engine WASM validation failed: " + m
            case .nativeEngineUnavailable:
                return "The native ARM64 GTA V engine has not been compiled or linked. The 63 MB game.wasm cannot run directly as an ARM64 executable. This is a native runtime readiness check, not gameplay."
            case .io(let m): return "USB I/O failed: " + m
            }
        }
    }

    static let queue = DispatchQueue(label: "gtaios.native.game-io", qos: .userInitiated)
    static let nativeEngineLinked = false

    /// Stage 1: verify real archives and inspect the module's imported shared
    /// memory *without* allocating any of the engine's multi-GB linear heap.
    static func inspect(completion: @escaping (Result<Inspection, Error>) -> Void) {
        queue.async {
            let result: Result<Inspection, Error>
            do { result = .success(try inspectSync()) }
            catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }

    /* Native Emscripten openat guest paths become coordinated reads of the
     * user's selected data/ or b/ files. C already rejects writes and paths
     * outside these prefixes; USBStorageManager independently blocks escapes. */
    private static let nativeArchiveOpen: @convention(c) (UnsafePointer<CChar>?) -> Int32 = { rawPath in
        guard let rawPath, let relative = String(validatingCString: rawPath),
              relative.hasPrefix("data/") || relative.hasPrefix("b/"),
              let file = USBStorageManager.shared.file(relative) else { return -2 }
        var coordinationError: NSError?
        var result: Int32 = -5
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: file, options: [], error: &coordinationError
        ) { coordinated in
            do {
                let handle = try FileHandle(forReadingFrom: coordinated)
                result = gta_wasi_register_readonly_fd(handle.fileDescriptor)
                try handle.close()
                if result < 3 { result = -24 } // EMFILE: guest fd table exhausted
            } catch {
                LogStore.shared.write("native", "Archive open denied: \(relative): \(error.localizedDescription)")
            }
        }
        return coordinationError == nil ? result : -5
    }

    private static func inspectSync() throws -> Inspection {
        guard USBStorageManager.shared.root != nil else { throw Failure.notConnected }
        gta_wasi_set_openat_provider(nativeArchiveOpen)
        guard let wasm = USBStorageManager.shared.file("b/8b0b5899ed/game.wasm") else {
            throw Failure.missing("b/8b0b5899ed/game.wasm")
        }
        guard let shader = USBStorageManager.shared.file("b/8b0b5899ed/shaders/index.json") else {
            throw Failure.missing("b/8b0b5899ed/shaders/index.json")
        }
        guard let data = USBStorageManager.shared.file("data") else {
            throw Failure.missing("data/")
        }
        guard (try? data.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            throw Failure.missing("data/ is not a directory")
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: wasm.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        guard size > 8 else { throw Failure.invalidWasm("empty or truncated module") }
        let memory = try inspectWasmMemory(wasm)
        // Stage the actual data/manifest.json into the native HTTPFS
        // import provider before any future AOT game instantiation.
        // Only this small manifest is copied; archives remain on USB.
        do {
            let staged = try stageHTTPFSManifest()
            LogStore.shared.write("native",
                "Native HTTPFS manifest staged from USB: \(staged) bytes")
        } catch {
            gta_httpfs_manifest_clear()
            LogStore.shared.write("native",
                "Native HTTPFS manifest unavailable: \(error.localizedDescription)")
        }
        // Exercise actual bytes from the user-approved USB folder through
        // the same memory64 WASI descriptor functions that an AOT guest uses.
        // This is a host I/O check, not game engine execution.
        do {
            let bytes = try verifyWASIUSBRead()
            LogStore.shared.write("native",
                "WASI virtual FD read verified against USB data/manifest.json: \(bytes) bytes; no GTA execution")
        } catch {
            LogStore.shared.write("native",
                "WASI USB virtual FD read FAILED: \(error.localizedDescription)")
        }
        let result = Inspection(byteCount: size, memory: memory, shaderIndex: shader, gameFile: wasm)
        LogStore.shared.write("native", "WASM inspected: bytes=\(size), shared=\(memory.shared), memory64=\(memory.memory64), minimumPages=\(memory.minimumPages), maximumPages=\(String(describing: memory.maximumPages))")
        LogStore.shared.write("native", "USB shader index accessible: \(shader.lastPathComponent). Native shader translation has NOT been implemented.")
        return result
    }

    private static func stageHTTPFSManifest() throws -> Int {
        guard let url = USBStorageManager.shared.file("data/manifest.json") else {
            throw Failure.missing("data/manifest.json")
        }
        var coordinationError: NSError?
        var readError: Error?
        var stagedSize: Int?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: [], error: &coordinationError) { granted in
                do {
                    let attrs = try FileManager.default.attributesOfItem(atPath: granted.path)
                    let count = (attrs[.size] as? NSNumber)?.int64Value ?? -1
                    guard count > 0 && count <= Int64(GTA_HTTPFS_MAX_MANIFEST) else {
                        throw Failure.io("HTTPFS manifest exceeds native 32 MiB safety limit")
                    }
                    let data = try Data(contentsOf: granted)
                    guard data.count > 0 && data.count <= GTA_HTTPFS_MAX_MANIFEST else {
                        throw Failure.io("Native HTTPFS manifest data is invalid")
                    }
                    let rc = data.withUnsafeBytes { bytes -> Int32 in
                        gta_httpfs_manifest_stage(bytes.baseAddress, data.count)
                    }
                    guard rc == 0 else {
                        throw Failure.io("Native HTTPFS manifest stage error \(rc)")
                    }
                    stagedSize = data.count
                } catch {
                    readError = error
                }
            }
        if let coordinationError { throw coordinationError }
        if let readError { throw readError }
        guard let stagedSize else { throw Failure.io("File provider returned no manifest") }
        return stagedSize
    }


    /// Coordinates a real USB manifest file, duplicates its provider-approved
    /// descriptor into a guest-only fd, then verifies memory64 pread and read
    /// return precisely the bytes in the selected original file.
    /// Never copies a game archive or claims the actual WASM was executed.
    private static func verifyWASIUSBRead() throws -> Int {
        guard let url = USBStorageManager.shared.file("data/manifest.json") else {
            throw Failure.missing("data/manifest.json")
        }
        var coordinationError: NSError?
        var testError: Error?
        var result: Int?
        NSFileCoordinator(filePresenter: nil).coordinate(
            readingItemAt: url, options: [], error: &coordinationError) { granted in
                do {
                    let source = try FileHandle(forReadingFrom: granted)
                    defer { try? source.close() }
                    let expected = try source.read(upToCount: 32) ?? Data()
                    guard !expected.isEmpty else {
                        throw Failure.io("empty USB manifest sample")
                    }
                    let fd = gta_wasi_register_readonly_fd(source.fileDescriptor)
                    guard fd >= 3 else {
                        throw Failure.io("WASI refused external regular-file descriptor")
                    }
                    defer { _ = gta_wasi_fd_close(UInt32(fd)) }
                    var guest = [UInt8](repeating: 0, count: 128)
                    let good = guest.withUnsafeMutableBytes { bytes -> Bool in
                        guard let pointer = bytes.baseAddress else { return false }
                        func put64(_ index: Int, _ value: UInt64) {
                            for i in 0..<8 { bytes[index + i] = UInt8(truncatingIfNeeded: value >> (UInt64(i) * 8)) }
                        }
                        func get64(_ index: Int) -> UInt64 {
                            var value: UInt64 = 0
                            for i in 0..<8 { value |= UInt64(bytes[index + i]) << (UInt64(i) * 8) }
                            return value
                        }
                        put64(80, 0)  // memory64 iovec -> destination at 0
                        put64(88, UInt64(expected.count))
                        gta_wasi_bind_memory(pointer, UInt64(bytes.count))
                        defer { gta_wasi_unbind_memory() }
                        let guestFD = UInt32(fd)
                        guard gta_wasi_fd_pread(guestFD, 80, 1, 0, 104) == 0,
                              get64(104) == UInt64(expected.count),
                              Array(bytes.prefix(expected.count)) == Array(expected) else {
                            return false
                        }
                        for i in 0..<expected.count { bytes[i] = 0 }
                        guard gta_wasi_fd_read(guestFD, 80, 1, 104) == 0,
                              get64(104) == UInt64(expected.count),
                              Array(bytes.prefix(expected.count)) == Array(expected),
                              gta_wasi_fd_seek(guestFD, 0, 1, 112) == 0,
                              get64(112) == UInt64(expected.count) else {
                            return false
                        }
                        return true
                    }
                    guard good else {
                        throw Failure.io("WASI memory64 USB bytes mismatch, seek or read error")
                    }
                    result = expected.count
                } catch { testError = error }
            }
        if let coordinationError { throw coordinationError }
        if let testError { throw testError }
        guard let result else { throw Failure.io("file provider did not return WASI test bytes") }
        return result
    }

    /// Read only the initial import section; the proprietary game binary
    /// remains on the selected external drive. A module's memory limits are
    /// encoded in the import section, not safely inferred from game.js.
    private static func inspectWasmMemory(_ file: URL) throws -> MemoryImport {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        let magic = try handle.read(upToCount: 8) ?? Data()
        guard magic == Data([0, 97, 115, 109, 1, 0, 0, 0]) else {
            throw Failure.invalidWasm("missing WebAssembly version 1 header")
        }
        while true {
            guard let idData = try handle.read(upToCount: 1), let id = idData.first else {
                throw Failure.invalidWasm("no imported memory was found")
            }
            let payloadSize = try readULEBFromHandle(handle)
            let start = try handle.offset()
            guard payloadSize < 80_000_000 else {
                throw Failure.invalidWasm("section exceeds safety bound")
            }
            if id == 2 {
                guard payloadSize <= 1_048_576 else {
                    throw Failure.invalidWasm("unusually large import section")
                }
                let bytes = try handle.read(upToCount: Int(payloadSize)) ?? Data()
                guard bytes.count == Int(payloadSize) else { throw Failure.invalidWasm("truncated imports") }
                var reader = ImportReader(data: bytes)
                let count = try reader.number()
                guard count <= 100_000 else { throw Failure.invalidWasm("import count exceeds bound") }
                for _ in 0..<count {
                    let module = try reader.name()
                    let symbol = try reader.name()
                    let kind = try reader.byte()
                    if kind == 2 {
                        let flags = try reader.number()
                        let minimum = try reader.number()
                        let maximum = flags & 1 != 0 ? try reader.number() : nil
                        if module == "env" && symbol == "memory" {
                            return MemoryImport(minimumPages: minimum, maximumPages: maximum,
                                                shared: flags & 2 != 0, memory64: flags & 4 != 0)
                        }
                    } else if kind == 0 {
                        _ = try reader.number() // type index
                    } else if kind == 1 {
                        _ = try reader.byte() // reference type
                        let flags = try reader.number()
                        _ = try reader.number()
                        if flags & 1 != 0 { _ = try reader.number() }
                    } else if kind == 3 {
                        _ = try reader.byte() // value type
                        _ = try reader.byte() // mutable flag
                    } else if kind == 4 {
                        _ = try reader.number() // tag attribute
                        _ = try reader.number() // signature index
                    } else {
                        throw Failure.invalidWasm("unsupported import kind \(kind)")
                    }
                }
                throw Failure.invalidWasm("env.memory import not found")
            }
            guard payloadSize <= UInt64.max - start else { throw Failure.invalidWasm("section size overflow") }
            try handle.seek(toOffset: start + payloadSize)
        }
    }

    private static func readULEBFromHandle(_ handle: FileHandle) throws -> UInt64 {
        var result: UInt64 = 0
        for i in 0..<10 {
            guard let raw = try handle.read(upToCount: 1)?.first else {
                throw Failure.invalidWasm("truncated section length")
            }
            let part = UInt64(raw & 0x7f)
            if i == 9 && part > 1 { throw Failure.invalidWasm("ULEB128 overflow") }
            result |= part << UInt64(i * 7)
            if raw & 0x80 == 0 { return result }
        }
        throw Failure.invalidWasm("overlong ULEB128")
    }

    private struct ImportReader {
        let data: Data
        var cursor = 0
        mutating func byte() throws -> UInt8 {
            guard cursor < data.count else { throw Failure.invalidWasm("truncated import") }
            defer { cursor += 1 }
            return data[cursor]
        }
        mutating func number() throws -> UInt64 {
            var value: UInt64 = 0
            for i in 0..<10 {
                let b = try byte()
                let part = UInt64(b & 0x7f)
                if i == 9 && part > 1 { throw Failure.invalidWasm("import ULEB overflow") }
                value |= part << UInt64(i * 7)
                if b & 0x80 == 0 { return value }
            }
            throw Failure.invalidWasm("import ULEB too long")
        }
        mutating func name() throws -> String {
            let n = try number()
            guard n <= 4096, n <= UInt64(data.count - cursor) else {
                throw Failure.invalidWasm("invalid import name length")
            }
            let end = cursor + Int(n)
            let name = String(decoding: data[cursor..<end], as: UTF8.self)
            cursor = end
            return name
        }
    }
}

/// File-backed on-demand native I/O. No HTTP, no WKWebView and no bulk copy.
/// The source URL is resolved through the existing security-scoped USB grant.
final class NativeUSBAssetReader {
    static let shared = NativeUSBAssetReader()
    private let io = DispatchQueue(label: "gtaios.native.asset-range", qos: .userInitiated)
    private init() {}

    func read(relativePath: String, offset: UInt64, length: Int,
              completion: @escaping (Result<Data, Error>) -> Void) {
        io.async {
            let result: Result<Data, Error>
            do {
                guard length > 0 && length <= 4 * 1024 * 1024 else {
                    throw NativeEngineStatus.Failure.io("range size must be 1–4 MiB")
                }
                guard let file = USBStorageManager.shared.file(relativePath) else {
                    throw NativeEngineStatus.Failure.missing(relativePath)
                }
                var coordinationError: NSError?
                var readResult: Result<Data, Error>?
                NSFileCoordinator(filePresenter: nil).coordinate(
                    readingItemAt: file, options: [], error: &coordinationError) { granted in
                    do {
                        let stream = try FileHandle(forReadingFrom: granted)
                        defer { try? stream.close() }
                        try stream.seek(toOffset: offset)
                        let data = try stream.read(upToCount: length) ?? Data()
                        readResult = .success(data)
                    } catch { readResult = .failure(error) }
                }
                if let error = coordinationError { throw error }
                guard let received = readResult else {
                    throw NativeEngineStatus.Failure.io("file provider returned no data")
                }
                result = received
            } catch { result = .failure(error) }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

/// This Metal surface draws no fake gameplay. It only verifies a native
/// GPU command queue and prepares a drawable for a future actual RAGE backend.
final class NativeMetalSurface: MTKView, MTKViewDelegate {
    private var commands: MTLCommandQueue?
    var gpuReady: Bool { commands != nil }

    init(frame: CGRect) {
        let gpu = MTLCreateSystemDefaultDevice()
        super.init(frame: frame, device: gpu)
        framebufferOnly = true
        colorPixelFormat = .bgra8Unorm
        // The only currently active native video setting. Other quality
        // settings remain pending until a real game renderer is linked.
        preferredFramesPerSecond = EngineOptions.value("fps") == "60" ? 60 : 30
        clearColor = MTLClearColor(red: 0.015, green: 0.020, blue: 0.028, alpha: 1)
        commands = gpu?.makeCommandQueue()
        delegate = self
        isPaused = false
        enableSetNeedsDisplay = false
        LogStore.shared.write("native", "Metal device: \(gpu?.name ?? "unavailable"), commandQueue=\(commands != nil)")
    }

    required init(coder: NSCoder) { fatalError("Use init(frame:)") }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        LogStore.shared.write("native", "Metal drawable size \(size.width)x\(size.height)")
    }
    func draw(in view: MTKView) {
        guard let drawable = currentDrawable, let pass = currentRenderPassDescriptor,
              let buffer = commands?.makeCommandBuffer(),
              let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }
}
