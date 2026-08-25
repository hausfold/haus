// haus-github-receiver — the machine's GitHub webhook endpoint.
//
// GitHub → cloudflared (the tunnel this room also runs) → 127.0.0.1:<port> →
// here. One job, and deliberately only one: prove the delivery is real, write
// down that it happened, and hand the RAW bytes on to whoever wants them.
//
// ── what it will never do ────────────────────────────────────────────────────
// It does not interpret the payload. `repository.full_name` and
// `organization.login` are the only two fields it reads, both top-level, both
// only ever used as a scope name — and that is the whole extent of GitHub's
// schema this repo knows. Mapping a delivery into something with MEANING (a
// review request, a red run, a mention) is an app's job, and trill already
// quarantines those payload shapes inside one file of its own. A second mapper
// here would be a copy that drifts, in a nix-darwin module, where the only
// symptom of drift is a notification that silently stopped arriving.
//
// So the fan-out is bytes, not events:
//
//   --forward host:port   the delivery again, verbatim, signature header and
//                         all, so the receiver on the other end verifies it
//                         itself and trusts nothing about us. That is what
//                         lets trill's own bridge keep working UNCHANGED with
//                         this process in front of it.
//   --subscribers DIR     every executable in DIR, run detached with the four
//                         facts as environment. This is how a room learns that
//                         GitHub said something, without either room knowing
//                         the other exists.
//
// ── the response is not a receipt for the fan-out ────────────────────────────
// GitHub gives a delivery ~10s and marks the hook unhealthy when responses stop
// arriving; a subscriber that hangs must not be able to cost us that. So the
// 200 goes out the moment the signature verifies and the state file is written,
// and forwarding and subscribers are both fire-and-forget behind it. A
// subscriber that fails fails alone and silently — check the delivery log and
// run it by hand.
//
// ── trust ────────────────────────────────────────────────────────────────────
// The tunnel hostname is public, so unsigned traffic reaching this socket is
// expected background noise rather than an incident. The HMAC secret is the
// entire auth story: no token, no GitHub API call, nothing here can change
// anything on GitHub. The socket binds 127.0.0.1 only — the public leg is
// cloudflared's, which is a process with a much better claim to that job.
import CryptoKit
import Foundation

// MARK: - Options

struct Options {
    var port: UInt16 = 42786
    var secretFile: String = ""
    var stateDir: String = ""
    var subscribersDir: String?
    var forwards: [(host: String, port: UInt16)] = []
}

func parseArguments(_ argv: [String]) -> Result<Options, Failure> {
    var options = Options()
    var index = 0
    func value(_ flag: String) -> String? {
        index += 1
        return index < argv.count ? argv[index] : nil
    }
    while index < argv.count {
        let flag = argv[index]
        switch flag {
        case "--port":
            guard let raw = value(flag), let port = UInt16(raw), port > 0 else {
                return .failure(Failure("--port wants a number 1-65535"))
            }
            options.port = port
        case "--secret-file":
            guard let path = value(flag) else { return .failure(Failure("--secret-file wants a path")) }
            options.secretFile = path
        case "--state":
            guard let path = value(flag) else { return .failure(Failure("--state wants a directory")) }
            options.stateDir = path
        case "--subscribers":
            guard let path = value(flag) else { return .failure(Failure("--subscribers wants a directory")) }
            options.subscribersDir = path
        case "--forward":
            guard let raw = value(flag) else { return .failure(Failure("--forward wants host:port")) }
            let parts = raw.split(separator: ":")
            guard parts.count == 2, let port = UInt16(parts[1]) else {
                return .failure(Failure("--forward wants host:port, got '\(raw)'"))
            }
            options.forwards.append((String(parts[0]), port))
        default:
            return .failure(Failure("unknown flag '\(flag)'"))
        }
        index += 1
    }
    guard !options.secretFile.isEmpty else { return .failure(Failure("--secret-file is required")) }
    guard !options.stateDir.isEmpty else { return .failure(Failure("--state is required")) }
    return .success(options)
}

// MARK: - The secret

/// Re-read when the file changes rather than at startup only. Rotating the
/// secret is a two-sided move (GitHub's hook, then this file) and the window
/// between them is already awkward; making it also require `launchctl kickstart`
/// would turn a rotation into an outage nobody remembers the fix for.
final class Secret {
    private let path: String
    private var cached = Data()
    private var stamp: Date?
    private let lock = NSLock()

    init(path: String) { self.path = path }

    var bytes: Data {
        lock.lock()
        defer { lock.unlock() }
        let modified = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate])
            .flatMap { $0 as? Date }
        if modified != stamp || cached.isEmpty {
            stamp = modified
            let raw = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
            cached = Data(raw.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        }
        return cached
    }
}

/// `sha256=<hex>` over the raw body. Constant-time compare: a webhook
/// endpoint's rejection timing shouldn't narrate how close a forgery got.
func signatureMatches(header: String?, body: Data, secret: Data) -> Bool {
    guard let header, !secret.isEmpty else { return false }
    let mac = HMAC<SHA256>.authenticationCode(for: body, using: SymmetricKey(data: secret))
    let expected = "sha256=" + mac.map { String(format: "%02x", $0) }.joined()
    let a = Array(expected.utf8), b = Array(header.lowercased().utf8)
    guard a.count == b.count else { return false }
    return zip(a, b).reduce(UInt8(0)) { $0 | ($1.0 ^ $1.1) } == 0
}

// MARK: - HTTP

struct HTTPRequest {
    var method: String
    var headers: [String: String]   // keys lowercased; cloudflared exercises that freedom
    var body: Data

    /// GitHub caps deliveries at 25 MB. Nothing this room forwards is close, and
    /// a receiver that will buffer 25 MB per connection is a receiver that can be
    /// made to eat memory by anyone who knows the hostname.
    static let bodyLimit = 2 * 1024 * 1024
    static let headLimit = 64 * 1024

    enum ParseResult {
        case incomplete
        case invalid
        /// Well-formed HTTP this receiver deliberately does not implement.
        case unsupported
        case complete(HTTPRequest)
    }

    static func parse(_ buffer: Data) -> ParseResult {
        guard let headEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else {
            return buffer.count > headLimit ? .invalid : .incomplete
        }
        guard let head = String(data: buffer[buffer.startIndex..<headEnd.lowerBound], encoding: .utf8)
        else { return .invalid }

        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return .invalid }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].lowercased()] =
                line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        // A chunked body has no Content-Length, so the naive read would take the
        // body as EMPTY, fail the HMAC, and log "bad or missing signature" —
        // pointing whoever is debugging it at the secret, which is the one thing
        // that is fine. GitHub always sends Content-Length and cloudflared
        // propagates it (measured against live deliveries), so this is a
        // shouldn't-happen; `.unsupported` exists so that if it ever does, the
        // log says what is actually wrong.
        if headers["transfer-encoding"] != nil { return .unsupported }

        let length = headers["content-length"].flatMap(Int.init) ?? 0
        guard length >= 0, length <= bodyLimit else { return .invalid }
        let bodyStart = headEnd.upperBound
        guard buffer.distance(from: bodyStart, to: buffer.endIndex) >= length else { return .incomplete }

        return .complete(HTTPRequest(
            method: String(requestLine[0]),
            headers: headers,
            body: Data(buffer[bodyStart..<buffer.index(bodyStart, offsetBy: length)])
        ))
    }
}

/// Minimal HTTP/1.1 receiver: one request per connection, a status-only answer,
/// then close. POSIX sockets on one serial queue — every fd owned by one thread,
/// no third-party networking, nothing to keep in step with a dependency.
final class Server {
    typealias Handler = (HTTPRequest) -> Int

    private let port: UInt16
    private let handler: Handler
    private let queue = DispatchQueue(label: "co.hausfold.haus.github-receiver")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private final class Connection {
        let source: DispatchSourceRead
        let openedAt: Date
        var buffer = Data()
        init(source: DispatchSourceRead, openedAt: Date) {
            self.source = source
            self.openedAt = openedAt
        }
    }
    private var connections: [Int32: Connection] = [:]
    private var reaper: DispatchSourceTimer?

    /// How long a connection may go without producing a complete request, and
    /// how many unfinished ones may exist at once.
    ///
    /// Both are load-bearing rather than tidiness. The body cap bounds BYTES per
    /// connection and nothing bounded connection count or age: measured against
    /// this binary, 400 peers that each sent a request line and then went quiet
    /// held 401 file descriptors for as long as they stayed alive. The socket is
    /// loopback, but cloudflared streams a request body through to the origin,
    /// so anyone who knows the (public) hostname can pin them. At the fd limit
    /// `accept` starts failing, every real delivery is refused, GitHub marks the
    /// hook unhealthy — and the log says nothing at all.
    ///
    /// 15 s is generous for the 2 MB cap over a tunnel; 64 is far above the
    /// handful GitHub opens in a burst. Eviction is OLDEST-FIRST on purpose: the
    /// stuck connections are the old ones, so a flood must never be able to lock
    /// a live delivery out of the table.
    private static let requestDeadline: TimeInterval = 15
    private static let maxConnections = 64

    init(port: UInt16, handler: @escaping Handler) {
        self.port = port
        self.handler = handler
    }

    private static func loopback(port: UInt16) -> sockaddr_in {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr.s_addr = INADDR_LOOPBACK.bigEndian
        return addr
    }

    /// Throws a message fit for a log line a person will read at 2am.
    func start() throws {
        try queue.sync {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { throw Failure("socket: \(String(cString: strerror(errno)))") }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, socklen_t(MemoryLayout<Int32>.size))

            var addr = Self.loopback(port: port)
            let size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let bound = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
            }
            guard bound == 0 else {
                let why = String(cString: strerror(errno))
                close(fd)
                throw Failure("bind 127.0.0.1:\(port): \(why) — is another receiver running?")
            }
            guard listen(fd, 16) == 0 else {
                let why = String(cString: strerror(errno))
                close(fd)
                throw Failure("listen: \(why)")
            }

            listenFD = fd
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.acceptOne() }
            source.resume()
            acceptSource = source

            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.schedule(deadline: .now() + 5, repeating: 5)
            timer.setEventHandler { [weak self] in self?.reapExpired() }
            timer.resume()
            reaper = timer
        }
    }

    /// Close anything that has not produced a complete request in time. Runs on
    /// the same serial queue as everything else, so it cannot race a read.
    private func reapExpired() {
        let cutoff = Date().addingTimeInterval(-Self.requestDeadline)
        for (fd, connection) in connections where connection.openedAt < cutoff {
            drop(fd)
        }
    }

    private func acceptOne() {
        let fd = accept(listenFD, nil, nil)
        guard fd >= 0 else { return }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)

        reapExpired()
        while connections.count >= Self.maxConnections {
            guard let oldest = connections.min(by: { $0.value.openedAt < $1.value.openedAt })?.key
            else { break }
            drop(oldest)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        connections[fd] = Connection(source: source, openedAt: Date())
        source.setEventHandler { [weak self] in self?.readAvailable(fd) }
        source.setCancelHandler { close(fd) }
        source.resume()
    }

    private func readAvailable(_ fd: Int32) {
        guard let connection = connections[fd] else { return }
        var chunk = [UInt8](repeating: 0, count: 16 * 1024)
        var peerFinished = false
        while true {
            let n = read(fd, &chunk, chunk.count)
            if n > 0 {
                connection.buffer.append(contentsOf: chunk[0..<n])
                // Body cap plus head headroom; past that it is not a delivery,
                // it is a hose.
                if connection.buffer.count > HTTPRequest.bodyLimit + HTTPRequest.headLimit {
                    return drop(fd)
                }
            } else if n == 0 {
                // EOF, which for a half-closing client (`… | nc host port`, and
                // anything else someone debugging a dead bridge reaches for)
                // arrives WITH a complete request already in the buffer. Dropping
                // here — as this did — swallowed the delivery whole: no response,
                // no state, no log line. So note it and parse first; only an
                // incomplete request dies of an EOF.
                peerFinished = true
                break
            } else {
                break   // EAGAIN — wait for the next readability event
            }
        }

        switch HTTPRequest.parse(connection.buffer) {
        case .incomplete: if peerFinished { drop(fd) }
        case .invalid: respond(400, to: fd)
        case .unsupported:
            print("rejected: Transfer-Encoding is not supported (GitHub sends Content-Length)")
            respond(400, to: fd)
        case .complete(let request): respond(handler(request), to: fd)
        }
    }

    private func respond(_ status: Int, to fd: Int32) {
        let reasons = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 405: "Method Not Allowed"]
        let head = "HTTP/1.1 \(status) \(reasons[status] ?? "")\r\n"
            + "Content-Length: 0\r\nConnection: close\r\n\r\n"
        // The fd is O_NONBLOCK, so a short write is possible in principle even
        // for sixty bytes. The loop used to `break` on any n <= 0 and close,
        // which READS as a retry and is not one — EINTR and EAGAIN both meant
        // "send a truncated response and hang up".
        Data(head.utf8).withUnsafeBytes { raw in
            var offset = 0
            var attempts = 0
            while offset < raw.count && attempts < 100 {
                let n = Foundation.write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n > 0 {
                    offset += n
                } else if errno == EINTR {
                    continue
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    attempts += 1
                    usleep(1000)
                } else {
                    break
                }
            }
        }
        drop(fd)
    }

    private func drop(_ fd: Int32) {
        connections.removeValue(forKey: fd)?.source.cancel()
    }
}

struct Failure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

// MARK: - The signal

/// What this room writes down, and the whole contract every consumer reads.
/// Two files, because consumers ask two different questions and one of them is
/// asked on a render path:
///
///   last            the most recent accepted delivery, `<epoch> <event> <scope>`.
///                   Its MTIME is the answer to "has anything happened since my
///                   cache was written", which a consumer answers with one
///                   `stat` and no fork.
///   deliveries.tsv  the last few hundred, for `haus doctor` and for a person
///                   asking why a pill did or didn't move.
///
/// Neither ever holds payload text: a delivery body can carry the contents of a
/// private comment, and a log is a thing people paste. The directory is 0700 and
/// the secret beside it 0600 (the launchd wrapper sets both), so this is a
/// belt-and-braces rule rather than the only thing standing between a comment
/// and a stranger — but it is the one that survives someone `cat`ing the log.
final class Signal {
    private let directory: URL
    private let queue = DispatchQueue(label: "co.hausfold.haus.github-receiver.signal")
    private static let logKeep = 200

    init(directory: String) {
        self.directory = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }

    func started() {
        write("up", "\(Int(Date().timeIntervalSince1970))\n")
    }

    func record(event: String, scope: String, delivery: String) {
        let at = Int(Date().timeIntervalSince1970)
        let row = "\(at)\t\(event)\t\(scope)\t\(delivery)\n"
        queue.sync {
            write("last", row)
            let log = directory.appendingPathComponent("deliveries.tsv")
            let existing = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
            var lines = existing.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            lines.append(row.trimmingCharacters(in: .newlines))
            if lines.count > Self.logKeep { lines.removeFirst(lines.count - Self.logKeep) }
            try? (lines.joined(separator: "\n") + "\n").write(to: log, atomically: true, encoding: .utf8)
        }
    }

    private func write(_ name: String, _ text: String) {
        try? text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }
}

/// The only two fields of a GitHub payload this repo knows, both top-level, both
/// used as a name and nothing else. `organization.login` is the fallback because
/// an org-level hook's `ping` carries no repository at all, and "the hook is
/// alive" is exactly the delivery a person most wants to see recorded.
func scope(of body: Data) -> String {
    guard let root = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return "" }
    if let repository = root["repository"] as? [String: Any],
       let full = repository["full_name"] as? String { return full }
    if let organization = root["organization"] as? [String: Any],
       let login = organization["login"] as? String { return login }
    return ""
}

// MARK: - Fan-out

/// The delivery again, byte for byte, signature header included. The far end
/// verifies it exactly as if GitHub had called it directly — which is the point:
/// nothing downstream has to trust this process, and putting a receiver in front
/// of an app's own bridge changes nothing about that app.
func forward(_ request: HTTPRequest, to targets: [(host: String, port: UInt16)]) {
    for target in targets {
        guard let url = URL(string: "http://\(target.host):\(target.port)/") else { continue }
        var out = URLRequest(url: url)
        out.httpMethod = "POST"
        out.httpBody = request.body
        out.timeoutInterval = 5
        for name in ["x-github-event", "x-github-delivery", "x-hub-signature-256",
                     "x-hub-signature", "content-type", "user-agent"] {
            if let value = request.headers[name] { out.setValue(value, forHTTPHeaderField: name) }
        }
        URLSession.shared.dataTask(with: out).resume()
    }
}

/// Every executable in the directory, detached, with the four facts as
/// environment. No arguments, so a subscriber can never be confused by a scope
/// that starts with a dash, and no stdin, so it can never block on one.
func notify(subscribers directory: String?, event: String, scope: String, delivery: String) {
    guard let directory else { return }
    let root = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
    guard let entries = try? FileManager.default.contentsOfDirectory(
        at: root, includingPropertiesForKeys: nil
    ) else { return }

    for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        guard FileManager.default.isExecutableFile(atPath: entry.path) else { continue }
        let task = Process()
        task.executableURL = entry
        var environment = ProcessInfo.processInfo.environment
        environment["HAUS_GITHUB_EVENT"] = event
        environment["HAUS_GITHUB_SCOPE"] = scope
        environment["HAUS_GITHUB_DELIVERY"] = delivery
        environment["HAUS_GITHUB_AT"] = String(Int(Date().timeIntervalSince1970))
        task.environment = environment
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        task.standardInput = FileHandle.nullDevice
        try? task.run()
        // Deliberately not waited on. A subscriber that hangs must not be able
        // to cost us GitHub's delivery timeout — see the header.
    }
}

// MARK: - Main

setvbuf(stdout, nil, _IOLBF, 0)

let options: Options
switch parseArguments(Array(CommandLine.arguments.dropFirst())) {
case .success(let parsed): options = parsed
case .failure(let why):
    FileHandle.standardError.write(Data("haus-github-receiver: \(why)\n".utf8))
    exit(2)
}

let secret = Secret(path: (options.secretFile as NSString).expandingTildeInPath)
let signal = Signal(directory: options.stateDir)

let server = Server(port: options.port) { request in
    guard request.method == "POST" else { return 405 }
    guard signatureMatches(
        header: request.headers["x-hub-signature-256"],
        body: request.body,
        secret: secret.bytes
    ) else {
        // The hostname is public; unsigned traffic is weather, not an incident.
        print("rejected: bad or missing signature")
        return 401
    }
    guard let event = request.headers["x-github-event"],
          let delivery = request.headers["x-github-delivery"] else { return 400 }

    let name = scope(of: request.body)
    signal.record(event: event, scope: name, delivery: delivery)
    print("delivery \(delivery) (\(event)) \(name.isEmpty ? "-" : name)")

    forward(request, to: options.forwards)
    notify(subscribers: options.subscribersDir, event: event, scope: name, delivery: delivery)
    return 200
}

do {
    try server.start()
} catch {
    FileHandle.standardError.write(Data("haus-github-receiver: \(error)\n".utf8))
    exit(1)
}

signal.started()
print("listening on 127.0.0.1:\(options.port)")
dispatchMain()
