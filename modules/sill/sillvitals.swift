// sillvitals — one sample of what this Mac is busy with, for the cpu and memory
// pills. Prints a few TSV lines and exits; everything the two pills draw (the
// number, the graph point, the hover breakdown, the dropdown's per-app rows)
// comes out of ONE run of this, so the pill and the dropdown it explains can
// never disagree about what 41% was made of.
//
// ── why a binary at all ───────────────────────────────────────────────────────
// The shell versions of these pills were both WRONG, in the same way, and no
// amount of awk fixes it:
//
//   * `ps -A -o %cpu` sums each process's average over its ENTIRE LIFETIME.
//     A machine that has been up for a week reads ~4% while a compile pins
//     every core, because a burst is a rounding error against seven days of
//     idle. The pill moved so little it may as well have been a static label —
//     which is exactly what it looked like, and the reason nobody ever clicked
//     it.
//   * `memory_pressure`'s "System-wide memory free percentage" counts the file
//     cache as USED. macOS deliberately fills unused RAM with cache, so that
//     number sits near 90% on a machine with nothing running and never comes
//     down: a readout with no dynamic range, reported as a percentage.
//
// Both real answers are a DELTA against the previous sample (CPU) or a specific
// sum of vm_statistics64 fields (memory), so the sampler has to keep state and
// speak Mach. `top -l 2` knows all this and costs a full second of wall clock
// per sample — a second of `top` every two seconds, to draw a CPU meter, is a
// joke the meter would be telling about itself. This reads the same kernel
// counters top does, in ~8 ms, and leaves its previous reading in a state file.
//
// Compiled with the system Swift via xcrun, exactly like sillpop (see
// sillvitals.nix).
//
// ── usage ─────────────────────────────────────────────────────────────────────
//     sillvitals sample --state PATH [--top cpu|mem|none] [--rows N]
//
// --state is per-CALLER, not per-machine: the two pills tick at different
// frequencies and each one's percentages are "since MY last look". Sharing one
// file would have the 5-second memory tick silently reset the 2-second CPU
// tick's baseline, and the CPU number would then be an average over whichever
// of the two happened to run last.
//
// ── output ────────────────────────────────────────────────────────────────────
// Tab-separated, first field names the record. Absent records mean "couldn't
// read that" — never a zero, which a bar would draw as a confident 0%.
//
//     cpu <total%> <user%> <sys%> <load1> <ncpu>
//     mem <used%> <usedGB> <totalGB> <swapGB> <pressure> <cachedGB> <compressedGB>
//     top <value> <pid> <name>          (repeated, biggest first)
//     rest <value>                       (everything the printed rows don't cover)
//
// `top`'s value is percent-of-machine in cpu mode and gigabytes in mem mode.
// The FIRST sample after a state file appears has no previous reading to
// subtract, so it prints no `cpu` record at all rather than a made-up one; the
// pill keeps its last label and picks the number up 2 seconds later.

import Darwin
import Foundation

// ── little helpers ────────────────────────────────────────────────────────────

func sysctlUInt64(_ name: String) -> UInt64? {
  var value: UInt64 = 0
  var size = MemoryLayout<UInt64>.size
  guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
  return value
}

func sysctlInt32(_ name: String) -> Int32? {
  var value: Int32 = 0
  var size = MemoryLayout<Int32>.size
  guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
  return value
}

/// One decimal place, and never `-0.0`, which is what a delta of exactly zero
/// prints as often enough to matter in a bar.
func f1(_ v: Double) -> String { String(format: "%.1f", v == 0 ? 0 : v) }

// ── CPU: whole-machine ticks ──────────────────────────────────────────────────
// host_statistics(HOST_CPU_LOAD_INFO) returns MONOTONIC tick counters summed
// over every core — user, system, idle, nice since boot. Busy-ness is the ratio
// of non-idle ticks GAINED since the last sample, which is the definition `top`
// and Activity Monitor use and the one `ps %cpu` does not.

struct CPUTicks {
  var user: UInt64 = 0
  var system: UInt64 = 0
  var idle: UInt64 = 0
  var nice: UInt64 = 0

  var total: UInt64 { user &+ system &+ idle &+ nice }
}

func readCPUTicks() -> CPUTicks? {
  var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)
  var info = host_cpu_load_info_data_t()
  let result = withUnsafeMutablePointer(to: &info) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPointer in
      host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, reboundPointer, &size)
    }
  }
  guard result == KERN_SUCCESS else { return nil }
  return CPUTicks(
    user: UInt64(info.cpu_ticks.0),
    system: UInt64(info.cpu_ticks.1),
    idle: UInt64(info.cpu_ticks.2),
    nice: UInt64(info.cpu_ticks.3))
}

// ── memory: the fields Activity Monitor actually adds up ──────────────────────
// "Memory Used" in Activity Monitor is app memory + wired + compressed, where
// app memory is the internal (anonymous) pages minus the purgeable ones. What
// it is NOT is "everything that isn't free": the external pages are the file
// cache, which macOS grows into idle RAM on purpose and hands straight back
// under pressure. Counting those is what pinned the old pill near 90% forever.
//
// `pressure` is the kernel's own verdict rather than a number we derive:
// kern.memorystatus_vm_pressure_level is 1 normal / 2 warning / 4 critical, and
// it is the thing that decides whether your machine is about to start swapping.
// A percentage says how full the glass is; this says whether the kernel minds.

struct MemorySample {
  var usedBytes: UInt64
  var totalBytes: UInt64
  var cachedBytes: UInt64
  var compressedBytes: UInt64
  var swapBytes: UInt64
  var pressure: Int32

  var usedPercent: Double { totalBytes == 0 ? 0 : Double(usedBytes) / Double(totalBytes) * 100 }
}

func readMemory() -> MemorySample? {
  var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
  var stats = vm_statistics64_data_t()
  let result = withUnsafeMutablePointer(to: &stats) { pointer in
    pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { reboundPointer in
      host_statistics64(mach_host_self(), HOST_VM_INFO64, reboundPointer, &size)
    }
  }
  guard result == KERN_SUCCESS, let total = sysctlUInt64("hw.memsize") else { return nil }

  let page = UInt64(vm_kernel_page_size)
  let app = UInt64(stats.internal_page_count &- stats.purgeable_count) &* page
  let wired = UInt64(stats.wire_count) &* page
  let compressed = UInt64(stats.compressor_page_count) &* page
  let cached = (UInt64(stats.external_page_count) &+ UInt64(stats.purgeable_count)) &* page

  // vm.swapusage is a struct, not a scalar: xsu_used is the byte count worth
  // reporting — swap that exists but is untouched costs nothing and alarms
  // people who look at swap totals.
  var swap = xsw_usage()
  var swapSize = MemoryLayout<xsw_usage>.size
  let swapUsed = sysctlbyname("vm.swapusage", &swap, &swapSize, nil, 0) == 0 ? swap.xsu_used : 0

  return MemorySample(
    usedBytes: app &+ wired &+ compressed,
    totalBytes: total,
    cachedBytes: cached,
    compressedBytes: compressed,
    swapBytes: swapUsed,
    pressure: sysctlInt32("kern.memorystatus_vm_pressure_level") ?? 1)
}

// ── per-process ───────────────────────────────────────────────────────────────
// proc_pid_rusage gives cumulative CPU nanoseconds and the phys_footprint —
// the same footprint Activity Monitor's Memory column shows, which is why a
// row here and a row there agree to the tenth of a gigabyte.
//
// It answers only for processes we OWN. A root daemon (kernel_task,
// WindowServer, mds) returns EPERM and is skipped rather than guessed at — so
// the rows are "your apps", and the whole-machine total above is not. That gap
// is not swept under the rug: whatever the rows don't account for is printed as
// `rest`, and a big `rest` is the popup telling you the answer is a system
// process and belongs in Activity Monitor.

/// rusage's CPU fields are named `ri_user_time` / `ri_system_time` and are NOT
/// nanoseconds: they are mach absolute-time units, which on Apple Silicon tick
/// at 24 MHz — so a process burning a whole core for two seconds reports about
/// 48 million of them. Taken at face value that reads as 48 ms of work, i.e. a
/// pegged core rendered as 2.4%, which is a wrong number that looks entirely
/// reasonable and is why this cost an hour. The timebase is 1:1 on Intel, which
/// is why code that never ran on Apple Silicon can carry the bug undisturbed.
let machTimebase: (numerator: UInt64, denominator: UInt64) = {
  var info = mach_timebase_info_data_t()
  guard mach_timebase_info(&info) == KERN_SUCCESS, info.denom != 0 else { return (1, 1) }
  return (UInt64(info.numer), UInt64(info.denom))
}()

func machToNanoseconds(_ ticks: UInt64) -> UInt64 {
  ticks / machTimebase.denominator &* machTimebase.numerator
    &+ (ticks % machTimebase.denominator) &* machTimebase.numerator / machTimebase.denominator
}

/// `PROC_PIDPATHINFO_MAXSIZE` (4 × MAXPATHLEN) spelled out, because Swift
/// declines to import that macro — proc_info.h marks it "structure not
/// supported" and the constant goes with it.
let processPathMax = 4 * 1024

struct ProcessSample {
  var pid: pid_t
  var name: String
  var cpuNanos: UInt64
  var footprint: UInt64
}

/// The name a human would use. Derived from the FIRST `.app` component of the
/// executable path, so `Google Chrome Helper (Renderer)` lands under `Google
/// Chrome` and a browser's twenty helpers add up to one row instead of filling
/// the dropdown with twenty identical names. Everything else is the executable's
/// own basename.
func displayName(forPath path: String) -> String {
  for component in path.split(separator: "/") where component.hasSuffix(".app") {
    return String(component.dropLast(4))
  }
  // A leading dot is a wrapper's, not a name: nix and Homebrew both install the
  // real binary as `.thing-wrapped` beside a shim, and a dropdown row reading
  // `.claude-wrapped` is naming an implementation detail at the user.
  let base = String(path.split(separator: "/").last ?? "?")
  return base.hasPrefix(".") ? String(base.dropFirst()) : base
}

func readProcesses() -> [ProcessSample] {
  let byteCount = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
  guard byteCount > 0 else { return [] }
  // Ask for more room than the kernel just quoted: processes are spawning while
  // we count, and a listing truncated to the old count would drop whatever
  // sorted last.
  let capacity = Int(byteCount) / MemoryLayout<pid_t>.size + 64
  var pids = [pid_t](repeating: 0, count: capacity)
  let filled = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(capacity * MemoryLayout<pid_t>.size))
  guard filled > 0 else { return [] }

  var samples: [ProcessSample] = []
  samples.reserveCapacity(capacity)
  var pathBuffer = [CChar](repeating: 0, count: processPathMax)

  for pid in pids[0..<(Int(filled) / MemoryLayout<pid_t>.size)] where pid > 0 {
    var usage = rusage_info_current()
    let ok = withUnsafeMutablePointer(to: &usage) { pointer -> Int32 in
      pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
        proc_pid_rusage(pid, RUSAGE_INFO_CURRENT, reboundPointer)
      }
    }
    guard ok == 0 else { continue }  // not ours — see the note above
    guard proc_pidpath(pid, &pathBuffer, UInt32(processPathMax)) > 0 else { continue }
    samples.append(
      ProcessSample(
        pid: pid,
        name: displayName(forPath: String(cString: pathBuffer)),
        cpuNanos: machToNanoseconds(usage.ri_user_time &+ usage.ri_system_time),
        footprint: usage.ri_phys_footprint))
  }
  return samples
}

// ── state file ────────────────────────────────────────────────────────────────
// Plain text, one record per line, rewritten whole every sample. Small enough
// (a few hundred processes) that parsing it costs less than the Mach calls
// above, and readable by eye when a pill is misbehaving.

struct PreviousState {
  var wall: Double
  var ticks: CPUTicks
  var cpuNanosByPID: [pid_t: UInt64]
  /// The last percentages this state file's owner actually reported. Kept so a
  /// sample taken moments after the previous one can repeat them instead of
  /// dividing by a window too short to mean anything — see `minimumWindow`.
  var last: (total: Double, user: Double, system: Double)?
}

/// Below this many seconds between samples, a tick delta is noise: the pointer
/// crossing the bar fires mouse.entered and mouse.exited milliseconds apart, and
/// each one would otherwise redraw the pill from whatever the machine happened
/// to be doing during those milliseconds — a hover that makes the number jump is
/// a hover that makes the number look made up. A window this short repeats the
/// last reported figures and leaves the baseline alone, so the next real tick
/// still measures from where it should.
let minimumWindow = 0.4

let stateVersion = "sillvitals1"

func readState(_ path: String) -> PreviousState? {
  guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
  var wall: Double?
  var ticks = CPUTicks()
  var haveTicks = false
  var byPID: [pid_t: UInt64] = [:]
  var versionSeen = false
  var last: (total: Double, user: Double, system: Double)?

  for line in text.split(separator: "\n") {
    let parts = line.split(separator: "\t")
    guard let kind = parts.first else { continue }
    switch kind {
    case Substring(stateVersion): versionSeen = true
    case "wall" where parts.count >= 2: wall = Double(parts[1])
    case "ticks" where parts.count >= 5:
      ticks = CPUTicks(
        user: UInt64(parts[1]) ?? 0, system: UInt64(parts[2]) ?? 0,
        idle: UInt64(parts[3]) ?? 0, nice: UInt64(parts[4]) ?? 0)
      haveTicks = true
    case "p" where parts.count >= 3:
      if let pid = pid_t(parts[1]), let nanos = UInt64(parts[2]) { byPID[pid] = nanos }
    case "last" where parts.count >= 4:
      if let total = Double(parts[1]), let user = Double(parts[2]), let system = Double(parts[3]) {
        last = (total, user, system)
      }
    default: continue
    }
  }
  // A file from an older layout is not a baseline, it's a different unit. Treat
  // it as no baseline at all and let the next sample be the first one.
  guard versionSeen, haveTicks, let wallValue = wall else { return nil }
  return PreviousState(wall: wallValue, ticks: ticks, cpuNanosByPID: byPID, last: last)
}

func writeState(
  _ path: String, wall: Double, ticks: CPUTicks, processes: [ProcessSample],
  last: (total: Double, user: Double, system: Double)?
) {
  var out = "\(stateVersion)\n"
  out += "wall\t\(wall)\n"
  out += "ticks\t\(ticks.user)\t\(ticks.system)\t\(ticks.idle)\t\(ticks.nice)\n"
  if let last = last { out += "last\t\(f1(last.total))\t\(f1(last.user))\t\(f1(last.system))\n" }
  for process in processes { out += "p\t\(process.pid)\t\(process.cpuNanos)\n" }
  // Write-then-rename: a pill reading the file while we truncate it would find
  // half a baseline and report a percentage computed against it.
  let temporary = path + ".tmp\(getpid())"
  guard (try? out.write(toFile: temporary, atomically: false, encoding: .utf8)) != nil else { return }
  if rename(temporary, path) != 0 { unlink(temporary) }
}

// ── the sample ────────────────────────────────────────────────────────────────

enum TopMode: String {
  case cpu, mem, none
}

var statePath = ""
var topMode = TopMode.none
var rowCount = 5

var arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.first == "sample" else {
  FileHandle.standardError.write(
    Data("usage: sillvitals sample --state PATH [--top cpu|mem|none] [--rows N]\n".utf8))
  exit(2)
}
arguments.removeFirst()
while let flag = arguments.first {
  arguments.removeFirst()
  let value = arguments.first
  switch flag {
  case "--state": statePath = value ?? ""; if value != nil { arguments.removeFirst() }
  case "--top": topMode = TopMode(rawValue: value ?? "") ?? .none; if value != nil { arguments.removeFirst() }
  case "--rows": rowCount = Int(value ?? "") ?? 5; if value != nil { arguments.removeFirst() }
  default: continue
  }
}
guard !statePath.isEmpty else {
  FileHandle.standardError.write(Data("sillvitals: --state is required\n".utf8))
  exit(2)
}

let now = Date().timeIntervalSince1970
let previous = readState(statePath)
let processes = topMode == .none ? [] : readProcesses()
var output = ""

// The whole-machine CPU line, and the per-process shares that have to add up to
// it. Both are deltas, so both are absent on the very first run.
var machineCPU: Double?
if let ticks = readCPUTicks() {
  var reported: (total: Double, user: Double, system: Double)?
  let window = previous.map { now - $0.wall } ?? 0

  if let previous = previous, window >= minimumWindow, ticks.total > previous.ticks.total {
    let span = Double(ticks.total &- previous.ticks.total)
    let user = Double((ticks.user &+ ticks.nice) &- (previous.ticks.user &+ previous.ticks.nice)) / span * 100
    let system = Double(ticks.system &- previous.ticks.system) / span * 100
    reported = (user + system, user, system)
  } else if let cached = previous?.last {
    // Too soon to measure again — repeat what we last said. See `minimumWindow`.
    reported = cached
  }

  if let reported = reported {
    machineCPU = reported.total
    var loads = [Double](repeating: 0, count: 3)
    getloadavg(&loads, 3)
    let cores = sysctlUInt64("hw.logicalcpu") ?? 1
    output += "cpu\t\(f1(reported.total))\t\(f1(reported.user))"
    output += "\t\(f1(reported.system))\t\(f1(loads[0]))\t\(cores)\n"
  }

  // The state file IS the baseline for the next run, so it is written on every
  // mode — but NOT when the window was too short to measure: rewriting it there
  // would move the baseline forward without ever having measured against it, and
  // a pointer swept across the bar could keep resetting it indefinitely.
  if window >= minimumWindow || previous == nil {
    writeState(statePath, wall: now, ticks: ticks, processes: processes, last: reported)
  }
}

let memory = readMemory()
if let memory = memory {
  let gigabytes = { (bytes: UInt64) in f1(Double(bytes) / 1_073_741_824) }
  output += "mem\t\(f1(memory.usedPercent))\t\(gigabytes(memory.usedBytes))"
  output += "\t\(gigabytes(memory.totalBytes))\t\(gigabytes(memory.swapBytes))"
  output += "\t\(memory.pressure)\t\(gigabytes(memory.cachedBytes))\t\(gigabytes(memory.compressedBytes))\n"
}

// ── the rows ──────────────────────────────────────────────────────────────────
// Aggregated BY NAME, not by pid: the question a dropdown answers is "what is
// eating this machine", and the answer is an app, not one of its nine helpers.
switch topMode {
case .none:
  break

case .cpu:
  // Percent of the WHOLE MACHINE, not of one core — deliberately unlike
  // Activity Monitor, where a four-thread build reads 400% and no column of
  // numbers can be compared with the pill above it. Here the rows and the `rest`
  // sum to the pill's own number, which is the only property that makes the
  // dropdown an explanation rather than a second opinion.
  if let previous = previous, now > previous.wall {
    let elapsedNanos = (now - previous.wall) * 1_000_000_000
    let cores = Double(sysctlUInt64("hw.logicalcpu") ?? 1)
    var byName: [String: (share: Double, pid: pid_t)] = [:]
    for process in processes {
      // A pid with no baseline was BORN inside this window, so all of its CPU
      // time was spent inside it — count the lot. Skipping those instead (the
      // obvious reading of "no previous sample, no delta") is what made the
      // rows useless for the case they exist to serve: a compile, an install, a
      // `nix build` are all processes that did not exist two seconds ago, and
      // the dropdown would credit their entire cost to `rest`.
      let before = previous.cpuNanosByPID[process.pid] ?? 0
      guard process.cpuNanos > before else { continue }
      let share = Double(process.cpuNanos &- before) / elapsedNanos / cores * 100
      let existing = byName[process.name]
      byName[process.name] = (
        share: (existing?.share ?? 0) + share,
        // Keep the pid of the biggest single process under this name — it is
        // what a row's click has to act on.
        pid: (existing.map { share > $0.share ? process.pid : $0.pid }) ?? process.pid
      )
    }
    var shown = 0.0
    for (name, entry) in byName.sorted(by: { $0.value.share > $1.value.share }).prefix(rowCount) {
      guard entry.share >= 0.1 else { continue }
      shown += entry.share
      output += "top\t\(f1(entry.share))\t\(entry.pid)\t\(name)\n"
    }
    if let total = machineCPU {
      output += "rest\t\(f1(max(0, total - shown)))\n"
    }
  }

case .mem:
  // No delta needed: a footprint is a quantity, not a rate.
  var byName: [String: (bytes: UInt64, pid: pid_t)] = [:]
  for process in processes {
    let existing = byName[process.name]
    byName[process.name] = (
      bytes: (existing?.bytes ?? 0) &+ process.footprint,
      pid: (existing.map { process.footprint > $0.bytes ? process.pid : $0.pid }) ?? process.pid
    )
  }
  var shown: UInt64 = 0
  for (name, entry) in byName.sorted(by: { $0.value.bytes > $1.value.bytes }).prefix(rowCount) {
    guard entry.bytes >= 64 * 1_048_576 else { continue }
    shown &+= entry.bytes
    output += "top\t\(f1(Double(entry.bytes) / 1_073_741_824))\t\(entry.pid)\t\(name)\n"
  }
  if let memory = memory {
    let rest = memory.usedBytes > shown ? memory.usedBytes - shown : 0
    output += "rest\t\(f1(Double(rest) / 1_073_741_824))\n"
  }
}

FileHandle.standardOutput.write(Data(output.utf8))
