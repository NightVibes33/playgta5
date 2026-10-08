import Foundation
import Network

/// Minimal loopback service for WebKit. Game data is read on demand from USB.
final class AssetHTTPServer {
    static let shared = AssetHTTPServer()
    private let queue = DispatchQueue(label: "gtaios.local-http", qos: .userInitiated)
    private var listener: NWListener?
    private(set) var port: UInt16?

    func start(_ completed: @escaping (Result<UInt16, Error>) -> Void) {
        if let port { completed(.success(port)); return }
        do {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: .any)
            let server = try NWListener(using: parameters)
            listener = server
            server.stateUpdateHandler = { [weak self] status in
                switch status {
                case .ready:
                    if let port = server.port?.rawValue {
                        self?.port = port
                        DispatchQueue.main.async { completed(.success(port)) }
                    }
                case .failed(let error):
                    DispatchQueue.main.async { completed(.failure(error)) }
                default: break
                }
            }
            server.newConnectionHandler = { [weak self] connection in
                connection.start(queue: self?.queue ?? .global())
                self?.read(connection, Data())
            }
            server.start(queue: queue)
        } catch { completed(.failure(error)) }
    }

    private func read(_ connection: NWConnection, _ received: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] chunk, _, closed, error in
            guard let self, error == nil else { connection.cancel(); return }
            var bytes = received
            if let chunk { bytes.append(chunk) }
            guard bytes.count < 1_100_000 else { self.respond(connection, status: 413); return }
            guard let boundary = bytes.range(of: Data("\r\n\r\n".utf8)) else {
                if closed { connection.cancel() } else { self.read(connection, bytes) }
                return
            }
            let request = String(decoding: bytes[..<boundary.lowerBound], as: UTF8.self)
            let lines = request.components(separatedBy: "\r\n")
            let fields = (lines.first ?? "").split(separator: " ").map(String.init)
            guard fields.count >= 2 else { self.respond(connection, status: 400); return }
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 { headers[parts[0].lowercased()] = parts[1].trimmingCharacters(in: .whitespaces) }
            }
            let needed = Int(headers["content-length"] ?? "0") ?? 0
            guard needed >= 0, needed <= 1_000_000 else { self.respond(connection, status: 413); return }
            if bytes.count - boundary.upperBound < needed {
                if closed { connection.cancel() } else { self.read(connection, bytes) }
                return
            }
            let body = bytes.subdata(in: boundary.upperBound..<(boundary.upperBound + needed))
            self.route(connection, method: fields[0], path: fields[1], headers: headers, body: body)
        }
    }

    private func route(_ conn: NWConnection, method: String, path: String, headers: [String: String], body: Data) {
        let decoded = URLComponents(string: "http://localhost" + path)?.percentEncodedPath.removingPercentEncoding ?? ""
        if method == "POST" && decoded == "/log" {
            LogStore.shared.write("engine", String(decoding: body, as: UTF8.self))
            respond(conn, status: 200)
            return
        }
        if method == "POST" && decoded == "/data/batch" { batch(conn, body); return }
        guard method == "GET" || method == "HEAD" else { respond(conn, status: 405); return }
        guard let file = fileURL(decoded) else {
            LogStore.shared.write("usb-storage", "Missing asset: " + decoded)
            respond(conn, status: 404); return
        }
        sendFile(conn, file, range: headers["range"], head: method == "HEAD")
    }

    private func fileURL(_ path: String) -> URL? {
        let prefix = "/b/8b0b5899ed/"
        let bundled = Bundle.main.resourceURL?.appendingPathComponent("WebRuntime")
        if path == "/" || path == "/index.html" { return bundled?.appendingPathComponent("index.html") }
        if path == "/ios/preflight.html" { return bundled?.appendingPathComponent("preflight.html") }
        // The repository's data-manifest.json is the exact input for io_worker.js.
        // On USB, /data/manifest.json takes precedence; bundled manifest is fallback.
        if path == "/data/manifest.json" {
            return USBStorageManager.shared.file("data/manifest.json") ??
                bundled?.appendingPathComponent("data-manifest.json")
        }
        if path.hasPrefix(prefix) {
            let name = String(path.dropFirst(prefix.count))
            if name == "ios_controller.js" { return bundled?.appendingPathComponent("controller-bridge.js") }
            if ["loader.js", "game.js", "wgpu_worker.js", "io_worker.js"].contains(name) {
                return bundled?.appendingPathComponent(name)
            }
            if name == "shaders/index.json" {
                return USBStorageManager.shared.file("b/8b0b5899ed/shaders/index.json") ??
                    bundled?.appendingPathComponent("shader-index.json")
            }
        }
        guard path.hasPrefix("/data/") || path.hasPrefix(prefix) else { return nil }
        return USBStorageManager.shared.file(String(path.dropFirst()))
    }

    private func sendFile(_ conn: NWConnection, _ url: URL, range: String?, head: Bool) {
        do {
            let h = try FileHandle(forReadingFrom: url)
            let total = try h.seekToEnd()
            var begin: UInt64 = 0
            var end: UInt64 = total == 0 ? 0 : total - 1
            var code = 200
            if let range {
                let pieces = range.hasPrefix("bytes=") ? range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false) : []
                guard pieces.count == 2, total > 0 else { try? h.close(); respond(conn, status: 416); return }
                if pieces[0].isEmpty, let suffix = UInt64(pieces[1]), suffix > 0 {
                    begin = total > suffix ? total - suffix : 0
                } else if let n = UInt64(pieces[0]) { begin = n }
                else { try? h.close(); respond(conn, status: 416); return }
                if !pieces[1].isEmpty && !pieces[0].isEmpty {
                    guard let n = UInt64(pieces[1]) else { try? h.close(); respond(conn, status: 416); return }
                    end = min(end, n)
                }
                guard begin < total && begin <= end else { try? h.close(); respond(conn, status: 416); return }
                code = 206
            }
            let length = total == 0 ? 0 : end - begin + 1
            var extra = "Accept-Ranges: bytes\r\n"
            if code == 206 { extra += "Content-Range: bytes \(begin)-\(end)/\(total)\r\n" }
            let header = response(code, length, mime(url.pathExtension), extra)
            conn.send(content: Data(header.utf8), completion: .contentProcessed { error in
                if error != nil || head || length == 0 { try? h.close(); conn.cancel(); return }
                do { try h.seek(toOffset: begin) } catch { try? h.close(); conn.cancel(); return }
                self.stream(conn, handle: h, remaining: length)
            })
        } catch { respond(conn, status: 500) }
    }

    private func stream(_ conn: NWConnection, handle: FileHandle, remaining: UInt64) {
        if remaining == 0 { try? handle.close(); conn.cancel(); return }
        guard let chunk = try? handle.read(upToCount: Int(min(remaining, 131072))), !chunk.isEmpty else {
            try? handle.close(); conn.cancel(); return
        }
        conn.send(content: chunk, completion: .contentProcessed { error in
            if error != nil { try? handle.close(); conn.cancel() }
            else { self.stream(conn, handle: handle, remaining: remaining - UInt64(chunk.count)) }
        })
    }

    private func batch(_ conn: NWConnection, _ body: Data) {
        guard let rows = (try? JSONSerialization.jsonObject(with: body)) as? [[Any]], rows.count <= 1000 else {
            respond(conn, status: 400); return
        }
        var payload = Data()
        var lengths = [Int]()
        for row in rows {
            guard row.count == 3, let name = row[0] as? String,
                  let start = row[1] as? NSNumber, let end = row[2] as? NSNumber,
                  start.int64Value >= 0, end.int64Value >= start.int64Value,
                  let file = USBStorageManager.shared.file("data/" + name) else {
                respond(conn, status: 400); return
            }
            do {
                let h = try FileHandle(forReadingFrom: file)
                defer { try? h.close() }
                let size = try h.seekToEnd()
                let offset = UInt64(start.int64Value)
                let count = offset >= size ? UInt64(0) : min(size - offset, UInt64(end.int64Value) - offset + 1)
                guard count <= 64 * 1024 * 1024, payload.count + Int(count) <= 64 * 1024 * 1024 else {
                    respond(conn, status: 413); return
                }
                try h.seek(toOffset: min(offset, size))
                let data = try h.read(upToCount: Int(count)) ?? Data()
                payload.append(data)
                lengths.append(data.count)
            } catch { respond(conn, status: 400); return }
        }
        respond(conn, status: 200, bytes: payload, type: "application/octet-stream",
                extra: "X-Run-Lengths: " + lengths.map(String.init).joined(separator: ",") + "\r\n")
    }

    private func mime(_ ext: String) -> String {
        switch ext.lowercased() {
        case "js": return "text/javascript"
        case "json": return "application/json"
        case "wasm": return "application/wasm"
        case "html": return "text/html; charset=utf-8"
        case "png": return "image/png"
        case "webp": return "image/webp"
        case "woff": return "font/woff"
        default: return "application/octet-stream"
        }
    }

    private func response(_ code: Int, _ size: UInt64, _ type: String, _ extra: String = "") -> String {
        return "HTTP/1.1 \(code) OK\r\nContent-Type: \(type)\r\nContent-Length: \(size)\r\n" +
            "Cross-Origin-Opener-Policy: same-origin\r\nCross-Origin-Embedder-Policy: require-corp\r\n" +
            "Cross-Origin-Resource-Policy: same-origin\r\nConnection: close\r\n" + extra + "\r\n"
    }

    private func respond(_ conn: NWConnection, status: Int, bytes: Data = Data(),
                         type: String = "text/plain", extra: String = "") {
        let header = Data(response(status, UInt64(bytes.count), type, extra).utf8)
        conn.send(content: header + bytes, completion: .contentProcessed { _ in conn.cancel() })
    }
}
