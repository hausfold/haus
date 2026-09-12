// hausdisp — read and set a display's scaled resolution ("looks like N×M"), by
// INTENT rather than by pixel count.
//
//   hausdisp list
//   hausdisp resolve <selector> <intent>    # print the target mode, change nothing
//   hausdisp apply   <selector> <intent>    # set it, permanently, idempotently
//   hausdisp arrange <selector> <side> <of> <align> [--dry-run]
//                                          # move it beside another panel,
//                                          # permanently, idempotently
//
// `arrange` is the write half of arrangement. The READ half (`list`'s `at x,y`)
// shipped first: arrangement is a RELATION between two panels, not a fact about
// one, so the option states the relation (side, `of`, align) and the origins
// are COMPUTED here from each panel's current point size — the same
// derived-not-tabulated taste as the mode ladder. Because origins are in
// points, a uiScale change MOVES every origin; the room applies every uiScale
// entry before any arrange entry, so a profile never computes against a stale
// point size. `of` names a selector this file already resolves (internal | main
// | <uuid>), and a display is placed BESIDE `of` — never re-anchored to the
// origin. One consequence is load-bearing: macOS makes a display MAIN by
// putting it at (0, 0), and a relation can put one there, so main is part of
// what an arrangement asserts. `--dry-run` prints the computed origin and
// touches nothing — a mis-arranged desk is felt instantly and cannot be undone
// blind, so the dry run is the way a value is chosen, not a garnish.
//
// `list` also reports the two facts this room shipped a vocabulary for and could
// not previously answer: what macOS CALLS each panel, and WHERE each one sits in
// the global point space. Both are read-only and both are here rather than in a
// second tool because `internal | main | <uuid>` — the selector this file already
// resolves — is the vocabulary the question is asked in.
//
// The name is the load-bearing one. Two other rooms answer "is this the built-in
// panel?" with the literal string "Built-in Retina Display" — windows, in the
// per-monitor gap rows of the generated aerospace.toml, and terminal, in
// float-term.sh's popup geometry — neither going through this room. That literal
// is `NSScreen.localizedName`, which is a PRODUCT NAME: it is what this Mac's
// panel happens to be called, not a property of being built in. AeroSpace 0.21.3
// offers no keyword for it either (its monitor patterns are `main`, `secondary`,
// a regex or an id — there is no `built-in`), so the literal cannot simply be
// replaced. What it CAN be is checkable, on any Mac, with no second display
// attached: `hausdisp list` now prints the name each room is matching against.
//
// selector : internal | main | <persistent display UUID>
// intent   : more-space | default | slightly-larger-text | larger-text | largest-text
//
// Why this exists: display scaling is the ONLY working "make everything bigger"
// lever on macOS 26 — its text-size setting writes a value no running app
// re-reads, while the working accessibility scalars affect contrast or motion,
// not system-wide size (see `docs/macos-settings.md`). It is
// public CoreGraphics, so haus ships ~150 lines of Swift instead of taking a
// Homebrew dependency on displayplacer (which isn't in nixpkgs anyway).
//
// The one interesting part is picking the mode. A 14" MacBook Pro panel reports
// 132 modes; the five System Settings actually offers are the HiDPI modes whose
// POINT aspect ratio matches the panel default's (1.540 on a notched panel, where
// the plain 16:10 modes are 1.600) — the rest are duplicates across refresh rate
// and colour depth, or letterboxed shapes. So the ladder is derived here rather
// than hardcoded: aspect-match the default, dedupe by point size keeping the
// highest refresh, sort largest-points-first. On the machine the spike ran on that
// yields exactly [1800x1169, 1512x982*, 1352x878, 1147x745, 1024x665], and the
// intent mapping below reproduces the table that spike wrote out by hand — but it
// now also works on a panel nobody has measured, which a hardcoded table cannot.
import AppKit
import ColorSync
import CoreGraphics
import Foundation

// IOGraphicsTypes.h — not exported to Swift, and the only way to ask "which mode
// does this panel consider its default?" without reimplementing System Settings'
// heuristics. Falls back to the current mode if no mode is flagged.
let kDisplayModeDefaultFlag: UInt32 = 0x0000_0004

enum Intent: String, CaseIterable {
    case moreSpace = "more-space"
    case `default` = "default"
    // Declared in ladder order: `describe` labels a rung with the FIRST intent
    // that lands on it, and on a short ladder slightly-larger and larger-text
    // collapse onto the same rung — the gentler name is the honest label there.
    case slightlyLargerText = "slightly-larger-text"
    case largerText = "larger-text"
    case largestText = "largest-text"
}

func die(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data("hausdisp: \(message)\n".utf8))
    exit(code)
}

// sides and the aligns each one accepts, as one table so the validation and
// the error message cannot disagree. `top`/`bottom`/`left`/`right` pin the
// shared edges; `center` centres on the other axis.
let SIDE_ALIGNS: [String: [String]] = [
    "right-of": ["top", "center", "bottom"],
    "left-of": ["top", "center", "bottom"],
    "above": ["left", "center", "right"],
    "below": ["left", "center", "right"],
]

/// The origin that puts `moved` beside `target` — by relation, in the global
/// point space both bounds already share. Points, not modes: this is what a
/// uiScale applied FIRST buys.
func arrangeOrigin(moved: CGRect, target: CGRect, side: String, align: String) -> (x: Int, y: Int) {
    let mw = Int(moved.width.rounded()), mh = Int(moved.height.rounded())
    let tx = Int(target.origin.x.rounded()), ty = Int(target.origin.y.rounded())
    let tw = Int(target.width.rounded()), th = Int(target.height.rounded())
    var x: Int, y: Int
    switch side {
    case "right-of":
        (x, y) = (tx + tw, 0)
    case "left-of":
        (x, y) = (tx - mw, 0)
    case "above":
        (x, y) = (0, ty - mh)
    case "below":
        (x, y) = (0, ty + th)
    default:
        fatalError("unvalidated side")
    }
    switch (side, align) {
    case ("right-of", "top"), ("left-of", "top"):
        y = ty
    case ("right-of", "center"), ("left-of", "center"):
        y = ty + (th - mh) / 2
    case ("right-of", "bottom"), ("left-of", "bottom"):
        y = ty + th - mh
    case ("above", "left"), ("below", "left"):
        x = tx
    case ("above", "center"), ("below", "center"):
        x = tx + (tw - mw) / 2
    case ("above", "right"), ("below", "right"):
        x = tx + tw - mw
    default:
        break
    }
    return (x, y)
}

func activeDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    return Array(ids.prefix(Int(count)))
}

func uuid(of id: CGDirectDisplayID) -> String? {
    guard let ref = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, ref) as String?
}

/// What macOS calls this panel — `NSScreen.localizedName`, the same string
/// AeroSpace reports as `monitor-name` and matches its per-monitor config rows
/// against, and the same one float-term.sh compares to.
///
/// Optional on purpose. NSScreen needs a window-server connection, so this is
/// nil from a launchd daemon in another session, and a name is decoration here
/// while the UUID is the identity — `list` prints what it got and the mode
/// ladder is unaffected either way. AppKit is imported for this one call and
/// nothing else: no NSApplication, so nothing is activated and no Dock tile
/// appears.
func localizedName(of id: CGDirectDisplayID) -> String? {
    for screen in NSScreen.screens {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let number = screen.deviceDescription[key] as? NSNumber else { continue }
        if CGDirectDisplayID(number.uint32Value) == id { return screen.localizedName }
    }
    return nil
}

/// Where this display sits in the global point space, which is what
/// "arrangement" means: the origin is the top-left corner relative to the main
/// display's own (0, 0), with y growing DOWNWARD (CoreGraphics' orientation, not
/// AppKit's). A monitor to the left of the main one therefore has a negative x.
/// Read-only — moving a display is `CGConfigureDisplayOrigin`, and nothing here
/// calls it.
func arrangement(of id: CGDirectDisplayID) -> String {
    let b = CGDisplayBounds(id)
    let x = Int(b.origin.x.rounded())
    let y = Int(b.origin.y.rounded())
    return "at \(x),\(y)  \(Int(b.width.rounded()))x\(Int(b.height.rounded()))pt"
}

/// internal | main | <persistent UUID>. Returns nil when nothing matches, which is
/// a normal outcome (a docked monitor is not always plugged in) rather than an error.
func resolveDisplay(_ selector: String) -> CGDirectDisplayID? {
    let wanted = selector.lowercased()
    for id in activeDisplays() {
        switch wanted {
        case "internal" where CGDisplayIsBuiltin(id) == 1: return id
        case "main" where CGDisplayIsMain(id) == 1: return id
        default:
            if let u = uuid(of: id), u.lowercased() == wanted { return id }
        }
    }
    return nil
}

struct Rung {
    let mode: CGDisplayMode
    var points: String { "\(mode.width)x\(mode.height)" }
}

/// The scaled-resolution ladder System Settings would show, largest points first,
/// plus the index of the panel's default rung.
func ladder(for id: CGDirectDisplayID) -> (rungs: [Rung], defaultIndex: Int)? {
    let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
    guard let all = CGDisplayCopyAllDisplayModes(id, options) as? [CGDisplayMode],
        let current = CGDisplayCopyDisplayMode(id)
    else { return nil }

    let usable = all.filter { $0.isUsableForDesktopGUI() }
    let flagged = usable.first { $0.ioFlags & kDisplayModeDefaultFlag != 0 }
    let reference = flagged ?? current

    // Retina panels expose both HiDPI ("looks like") and 1:1 modes; a 1080p
    // external exposes only 1:1. Follow whichever family the default is in, so
    // this never quietly hands a Retina panel a non-HiDPI mode.
    let referenceIsHiDPI = reference.pixelWidth > reference.width
    let family = usable.filter { ($0.pixelWidth > $0.width) == referenceIsHiDPI }

    // Same point-shape as the default. Notched panels report a taller aspect
    // (1.540) than their 16:10 modes (1.600), and mixing the two makes the ladder
    // jump shape mid-step.
    let referenceAspect = Double(reference.width) / Double(reference.height)
    let sameShape = family.filter {
        abs(Double($0.width) / Double($0.height) - referenceAspect) < 0.01
    }

    // Modes repeat ~6× across refresh rate × colour depth. Dedupe by point size,
    // keeping the highest refresh (then the highest pixel count, so a mode with a
    // real HiDPI backing store wins over a stretched one at the same refresh).
    var best: [String: CGDisplayMode] = [:]
    for mode in sameShape {
        let key = "\(mode.width)x\(mode.height)"
        guard let held = best[key] else {
            best[key] = mode
            continue
        }
        let better =
            (mode.refreshRate, mode.pixelWidth * mode.pixelHeight)
            > (held.refreshRate, held.pixelWidth * held.pixelHeight)
        if better { best[key] = mode }
    }

    let rungs = best.values.sorted { $0.width > $1.width }.map(Rung.init)
    guard !rungs.isEmpty else { return nil }
    // The default's own point size may have been deduped away to a different
    // refresh rate, so match on point size rather than object identity.
    let defaultIndex =
        rungs.firstIndex { $0.mode.width == reference.width && $0.mode.height == reference.height }
        ?? 0
    return (rungs, defaultIndex)
}

/// Intent → rung index. Relative to the panel's own default, so a panel with
/// three scaled modes and one with nine both behave sensibly.
func rungIndex(for intent: Intent, count: Int, defaultIndex: Int) -> Int {
    let last = count - 1
    switch intent {
    case .moreSpace: return 0
    case .default: return defaultIndex
    case .largestText: return last
    case .largerText:
        // Halfway between default and smallest-points, rounded away from the
        // default, and never a no-op while a smaller rung exists.
        let mid = Int((Double(defaultIndex + last) / 2).rounded())
        return min(max(mid, min(defaultIndex + 1, last)), last)
    case .slightlyLargerText:
        // Halfway again, between default and larger-text, rounded TOWARD the
        // default — "slightly" is the whole promise. A 27" 5K reports nine
        // rungs and larger-text jumps four of them at once, which is a wall of
        // pixels rather than a step; this is the rung a person actually wants
        // when they dock a laptop. Never a no-op, and never past larger-text,
        // so on a short ladder (where larger-text is already the next rung
        // down) the two names simply agree.
        let larger = rungIndex(for: .largerText, count: count, defaultIndex: defaultIndex)
        let mid = Int((Double(defaultIndex + larger) / 2).rounded(.down))
        return min(max(mid, min(defaultIndex + 1, last)), larger)
    }
}

func rung(for intent: Intent, rungs: [Rung], defaultIndex: Int) -> Rung {
    rungs[rungIndex(for: intent, count: rungs.count, defaultIndex: defaultIndex)]
}

func describe(_ id: CGDirectDisplayID) {
    let kind = CGDisplayIsBuiltin(id) == 1 ? "internal" : "external"
    let main = CGDisplayIsMain(id) == 1 ? " main" : ""
    let name = localizedName(of: id).map { " name=\"\($0)\"" } ?? ""
    print("— \(kind)\(main)  uuid=\(uuid(of: id) ?? "unknown")\(name)  \(arrangement(of: id))")
    guard let (rungs, defaultIndex) = ladder(for: id) else {
        print("  no usable modes reported")
        return
    }
    let current = CGDisplayCopyDisplayMode(id)
    for (i, r) in rungs.enumerated() {
        let marks =
            [
                i == defaultIndex ? "default" : nil,
                r.mode.width == current?.width && r.mode.height == current?.height ? "current" : nil,
                // `.default` is skipped: the rung it lands on is already marked
                // "default" above, and printing both reads like a bug.
                Intent.allCases.filter { $0 != .default }.first {
                    rung(for: $0, rungs: rungs, defaultIndex: defaultIndex).points == r.points
                }?.rawValue,
            ].compactMap { $0 }
        print(
            "  looks-like \(r.points)"
                + "  (native \(r.mode.pixelWidth)x\(r.mode.pixelHeight) @\(Int(r.mode.refreshRate.rounded()))Hz)"
                + (marks.isEmpty ? "" : "  [\(marks.joined(separator: " · "))]"))
    }
}

// ---- main -------------------------------------------------------------------

let args = Array(CommandLine.arguments.dropFirst())
let usage =
    "usage: hausdisp list | resolve <selector> <intent> | apply <selector> <intent> | "
    + "arrange <selector> <side> <of> <align> [--dry-run]"
guard let command = args.first else {
    die(usage, code: 64)
}

if command == "list" {
    let ids = activeDisplays()
    print("active displays: \(ids.count)")
    for id in ids { describe(id) }
    exit(0)
}

if command == "arrange" {
    let dryRun = args.contains("--dry-run")
    let positional = args.filter { $0 != "--dry-run" }
    guard positional.count == 5 else {
        die(usage, code: 64)
    }
    let selector = positional[1], side = positional[2], ofSelector = positional[3], align = positional[4]
    guard let legal = SIDE_ALIGNS[side] else {
        die("unknown side '\(side)' (want: \(SIDE_ALIGNS.keys.sorted().joined(separator: " | ")))", code: 64)
    }
    guard legal.contains(align) else {
        die("align '\(align)' does not fit side '\(side)' (want: \(legal.joined(separator: " | ")))", code: 64)
    }

    // Exit 2 for EITHER display: an arrangement is about a desk, and an
    // undocked one has no such desk. Callers already treat 2 as a skip.
    guard let movedId = resolveDisplay(selector) else {
        die("no attached display matches '\(selector)'", code: 2)
    }
    guard let targetId = resolveDisplay(ofSelector) else {
        die("no attached display matches '\(ofSelector)' — the display '\(selector)' is to sit beside", code: 2)
    }

    let before = CGDisplayBounds(movedId)
    let target = CGDisplayBounds(targetId)
    let origin = arrangeOrigin(moved: before, target: target, side: side, align: align)
    let becomesMain = origin.x == 0 && origin.y == 0
    let detail = "\(side) \(ofSelector), aligned \(align)"

    if dryRun {
        print(
            "hausdisp: \(selector) → \(origin.x),\(origin.y)pt  (\(detail))"
            + (becomesMain ? "\nhausdisp: \(origin.x),\(origin.y) is the origin — \(selector) becomes main" : ""))
        exit(0)
    }

    // Re-applying an already-current arrangement is a no-op, so a rebuild
    // doesn't flash the screen — same contract as `apply`.
    let current = (Int(before.origin.x.rounded()), Int(before.origin.y.rounded()))
    if current == (origin.x, origin.y) {
        print("hausdisp: \(selector) already at \(origin.x),\(origin.y) (\(detail))")
        exit(0)
    }

    // Same transaction `apply` uses, completed `.permanently` so the
    // arrangement survives a reboot. CGConfigureDisplayOrigin is the one call
    // that moves a display — and, put at (0, 0), the one that makes it main.
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else {
        die("could not begin a display configuration", code: 1)
    }
    guard CGConfigureDisplayOrigin(config, movedId, Int32(origin.x), Int32(origin.y)) == .success else {
        CGCancelDisplayConfiguration(config)
        die("could not stage \(origin.x),\(origin.y) on '\(selector)'", code: 1)
    }
    let result = CGCompleteDisplayConfiguration(config, .permanently)
    guard result == .success else {
        die("could not move '\(selector)' to \(origin.x),\(origin.y) (CGError \(result.rawValue))", code: 1)
    }
    print("hausdisp: \(selector) → \(origin.x),\(origin.y)  (\(detail))")
    exit(0)
}

guard command == "resolve" || command == "apply", args.count == 3 else {
    die(usage, code: 64)
}
let selector = args[1]
guard let intent = Intent(rawValue: args[2]) else {
    die("unknown intent '\(args[2])' (want: \(Intent.allCases.map(\.rawValue).joined(separator: " | ")))", code: 64)
}

// Exit 2 = "that display isn't attached". Callers (haus's activation script)
// treat it as a skip, not a failure: a `displays.<uuid>` entry for a monitor at
// the office must not break a rebuild on the train.
guard let id = resolveDisplay(selector) else {
    die("no attached display matches '\(selector)'", code: 2)
}
guard let (rungs, defaultIndex) = ladder(for: id) else {
    die("display '\(selector)' reports no usable scaled modes", code: 3)
}

let target = rung(for: intent, rungs: rungs, defaultIndex: defaultIndex)
let current = CGDisplayCopyDisplayMode(id)

if command == "resolve" {
    print(target.points)
    exit(0)
}

if target.mode.width == current?.width && target.mode.height == current?.height {
    print("hausdisp: \(selector) already \(intent.rawValue) (\(target.points))")
    exit(0)
}

// A configuration transaction, completed `.permanently`, is what makes this
// survive a reboot — a bare CGDisplaySetDisplayMode is session-only, so haus
// would silently forget its own setting every restart.
var config: CGDisplayConfigRef?
guard CGBeginDisplayConfiguration(&config) == .success, let config else {
    die("could not begin a display configuration", code: 1)
}
guard CGConfigureDisplayWithDisplayMode(config, id, target.mode, nil) == .success else {
    CGCancelDisplayConfiguration(config)
    die("could not stage \(target.points) on '\(selector)'", code: 1)
}
let result = CGCompleteDisplayConfiguration(config, .permanently)
guard result == .success else {
    die("could not apply \(target.points) on '\(selector)' (CGError \(result.rawValue))", code: 1)
}
print("hausdisp: \(selector) → \(intent.rawValue) (looks like \(target.points))")
