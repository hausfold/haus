// haustabs — the machine half of the Zen tab bridge.
//
// Spawned BY the browser (Firefox's native-messaging protocol: the browser execs
// this and talks 4-byte-little-endian-length-prefixed JSON over stdin/stdout),
// so its lifetime is the browser's. No launchd job, no port, nothing to reap:
// no Zen, no bridge, and the state files go with it.
//
// It is a pipe with two ends and deliberately no logic:
//
//   browser → here   the full tab list, whenever it changes  → tabs.json
//   here → browser   "focus <tabId>"                         ← cmd
//
// ── WHY THE COMMAND CHANNEL IS A PLAIN APPEND-ONLY FILE ──────────────────────
//
// The obvious shapes are a unix socket or a FIFO, and both can WEDGE THE CALLER.
// The caller here is a SketchyBar click_script: a FIFO write blocks until
// something reads, so a host that died without cleaning up (Zen crashed, the
// laptop slept badly) turns the next ⌘-click into a bar thread that never
// returns. A socket is the same story with more code. An append to a regular
// file cannot block, cannot fail on a missing reader, and needs no accept loop —
// so that is what this reads, watching it with a vnode source and picking up
// from its own offset. `cmd` is truncated once here at startup and then only
// ever appended to; a stale one from a previous run is therefore never replayed.
//
// The pid file is the other half of not-wedging: a leftover tabs.json is
// indistinguishable from a live one (a browser sitting still publishes nothing
// new for hours, so mtime says nothing), and the bar needs to know whether to
// use this route at all before it commits to it. So it checks the pid, which is
// the one question with a real answer.
import Foundation

let fm = FileManager.default
let stateDir = ("~/.local/state/nebelhaus/zen-tabs" as NSString).expandingTildeInPath
let tabsPath = stateDir + "/tabs.json"
let cmdPath = stateDir + "/cmd"
let pidPath = stateDir + "/pid"

try? fm.createDirectory(
    atPath: stateDir, withIntermediateDirectories: true,
    attributes: [.posixPermissions: 0o700])

// ── stdout ───────────────────────────────────────────────────────────────────
// Written from the vnode queue as well as the main thread, hence the lock. A
// short write is a real possibility on a pipe, so the loop is not decoration.
let outLock = NSLock()
func send(_ obj: [String: Any]) {
    guard let body = try? JSONSerialization.data(withJSONObject: obj) else { return }
    var length = UInt32(body.count).littleEndian
    var frame = Data(bytes: &length, count: 4)
    frame.append(body)
    outLock.lock()
    defer { outLock.unlock() }
    frame.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
        var off = 0
        while off < raw.count {
            let n = write(1, raw.baseAddress!.advanced(by: off), raw.count - off)
            if n <= 0 { return }
            off += n
        }
    }
}

// ── teardown ─────────────────────────────────────────────────────────────────
// Reached on stdin EOF (the browser quit or disabled the extension) and on the
// signals that skip it. tabs.json goes FIRST: it is the file the bar trusts, and
// the window where it exists without a pid to back it is the window where a
// ⌘-click silently does nothing instead of falling back.
func teardown() -> Never {
    try? fm.removeItem(atPath: tabsPath)
    try? fm.removeItem(atPath: pidPath)
    try? fm.removeItem(atPath: cmdPath)
    exit(0)
}

// Held in a global on purpose. A DispatchSource is cancelled when its last
// reference goes, so a `let` inside the loop below — or inside the `if` further
// down — creates a source that is deallocated, and therefore silently disarmed,
// the instant the block ends. Both of these were written that way first, and
// both went quiet in exactly the way that produces no error anywhere.
var sources: [any DispatchSourceProtocol] = []

for sig in [SIGTERM, SIGINT, SIGHUP] {
    signal(sig, SIG_IGN)
    let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
    src.setEventHandler { teardown() }
    src.resume()
    sources.append(src)
}

// ── the command file ─────────────────────────────────────────────────────────
try? Data().write(to: URL(fileURLWithPath: cmdPath))
try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cmdPath)
let cmdFD = open(cmdPath, O_RDONLY | O_NONBLOCK)
var cmdBuf = Data()

func drainCommands() {
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(cmdFD, &chunk, chunk.count)
        if n <= 0 { break }
        cmdBuf.append(contentsOf: chunk[0..<n])
    }
    while let nl = cmdBuf.firstIndex(of: UInt8(ascii: "\n")) {
        let line = String(decoding: cmdBuf[cmdBuf.startIndex..<nl], as: UTF8.self)
        cmdBuf.removeSubrange(cmdBuf.startIndex...nl)
        let parts = line.split(separator: " ")
        if parts.count == 2, parts[0] == "focus", let id = Int(parts[1]) {
            send(["cmd": "focus", "tabId": id])
        }
    }
}

if cmdFD >= 0 {
    let watch = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: cmdFD, eventMask: [.write, .extend], queue: .global())
    watch.setEventHandler { drainCommands() }
    watch.resume()
    sources.append(watch)
}

// ── stdin ────────────────────────────────────────────────────────────────────
func readExact(_ count: Int) -> Data? {
    var out = Data()
    var buf = [UInt8](repeating: 0, count: min(count, 1 << 16))
    while out.count < count {
        let want = min(count - out.count, buf.count)
        let n = buf.withUnsafeMutableBytes { read(0, $0.baseAddress, want) }
        if n <= 0 { return nil }
        out.append(contentsOf: buf[0..<n])
    }
    return out
}

// rename(2) rather than FileManager.replaceItemAt: the latter needs the
// destination to already exist, and this writes the FIRST tabs.json too.
func publish(_ data: Data) {
    let tmp = tabsPath + ".tmp"
    guard (try? data.write(to: URL(fileURLWithPath: tmp))) != nil else { return }
    try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp)
    rename(tmp, tabsPath)
}

try? "\(getpid())\n".write(toFile: pidPath, atomically: true, encoding: .utf8)

while true {
    guard let header = readExact(4) else { teardown() }
    let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian })
    // The protocol caps a browser→host message at 1 MiB. Anything claiming more
    // is a desynced stream, and reading it would hang on a pipe that will never
    // deliver — so treat it as the end rather than trying to resynchronise.
    guard length > 0, length <= 1 << 20, let body = readExact(length) else { teardown() }
    publish(body)
}
