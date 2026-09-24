// hausrect — where a window actually IS on screen, in points, by window id.
//
//   hausrect [<window-id>...]     one `id x y width height` line per window,
//                                 tab separated; every on-screen ordinary
//                                 window when given no ids
//   hausrect --visible <id>...    one `id percent` line per named window: how
//                                 much of it is NOT covered by an ordinary
//                                 window stacked in front of it, 0-100
//
// It exists because AeroSpace can't answer this. `aerospace list-windows
// --format` has no rect placeholder (`--format` rejects `monitor-width` and
// every geometry spelling of it on 0.21.3), `aerospace config --get` only
// reaches the binding tree, and `list-monitors --json` carries an id and a
// name and nothing else. So the ONE number scripts/tiling-mode.sh needs to lay
// out a grid — how wide the tiled area on this monitor is, in the same points
// `aerospace resize width ±N` counts in — has no source inside the tiler.
//
// The tiled row spans the usable rect exactly, so measuring the windows
// measures the rect: `max(x+w) - min(x)` over a workspace's tiled windows IS
// the width AeroSpace laid them into, gaps, notch, bar insets and per-monitor
// gap overrides all already subtracted. That is why this reads WINDOWS rather
// than displays — a CGDisplayBounds route would then have to re-derive haus's
// own outer gaps and the menu bar's inset and would be wrong on the monitor
// nobody tested.
//
// Geometry comes from CGWindowListCopyWindowInfo, the same TCC-free source
// modules/terminal/floatring.swift uses and for the same reason: the window
// list hands out bounds, owner and layer with no grant at all, while the
// Accessibility route would need a grant keyed to this binary's /nix/store
// path — which changes on every rebuild, so the grant would silently orphan
// itself. (Only window TITLES are withheld without Screen Recording, and
// nothing here wants one.)
import CoreGraphics
import Foundation

// Window ids are CGWindowIDs — the same numbers AeroSpace prints for
// `%{window-id}`, which is what makes the join in tiling-mode.sh possible at
// all. A non-numeric argument is dropped rather than fatal: the caller is a
// shell loop over ids it got from aerospace, and one unparseable word should
// cost that window's line, not the whole answer.
var argv = Array(CommandLine.arguments.dropFirst())
let visibleMode = argv.first == "--visible"
if visibleMode { argv.removeFirst() }
let wanted = Set(argv.compactMap(Int.init))

let info =
    CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

func rect(_ window: [String: Any]) -> CGRect? {
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
        let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double
    else { return nil }
    return CGRect(x: x, y: y, width: w, height: h)
}

// ── --visible: how much of a window you can actually see ────────────────────
// The bar's question, not tiling-mode's: AeroSpace's `floating` is a LAYOUT
// rather than a stacking order, so a floating window sinks behind the first
// tiled window you click and nothing on screen says it is still there
// (modules/terminal/floatpin.swift measures why haus can only PIN the popups
// it spawns itself). What haus CAN do is notice — and the stacking order is
// exactly what this list already hands out: CGWindowListCopyWindowInfo returns
// on-screen windows FRONT TO BACK, so everything before a window in the list
// is in front of it.
//
// Only layer-0 windows count as cover. The bar itself is a full-width window
// at a higher level and is almost entirely transparent, floatring's outline is
// a hollow frame, and a pinned popup (floatpin) is a window haus put there on
// purpose — none of them is what buries a window you lost. A fully transparent
// window (alpha 0) covers nothing either.
//
// The area is SAMPLED rather than unioned: a 24 × 16 grid of points over the
// window, each one covered or not. Exact rectangle-union arithmetic buys
// nothing at a threshold the bar reads in quarters, and the grid is a few
// thousand comparisons.
//
// A named id that is not on screen (minimised, a hidden app, another
// workspace AeroSpace parked in the corner) prints nothing, which the caller
// reads as "not buried" — there is nothing in front of a window that is not
// there.
if visibleMode {
    var cover: [CGRect] = []
    for window in info {
        guard let id = window[kCGWindowNumber as String] as? Int else { continue }
        let layer = window[kCGWindowLayer as String] as? Int ?? -1
        let alpha = window[kCGWindowAlpha as String] as? Double ?? 1
        guard let r = rect(window) else { continue }
        if wanted.contains(id) && r.width > 0 && r.height > 0 {
            let cols = 24, rows = 16
            var seen = 0
            for i in 0..<cols {
                for j in 0..<rows {
                    let p = CGPoint(
                        x: r.minX + (Double(i) + 0.5) * r.width / Double(cols),
                        y: r.minY + (Double(j) + 0.5) * r.height / Double(rows))
                    if !cover.contains(where: { $0.contains(p) }) { seen += 1 }
                }
            }
            print("\(id)\t\(seen * 100 / (cols * rows))")
        }
        if layer == 0 && alpha > 0 { cover.append(r) }
    }
    exit(0)
}

for window in info {
    guard let id = window[kCGWindowNumber as String] as? Int else { continue }
    if !wanted.isEmpty && !wanted.contains(id) { continue }
    // Layer 0 is an ordinary application window. Only filtered when listing
    // everything: an id the caller named is one it already decided it wants,
    // and second-guessing that would make the tool lie about a window it can
    // see perfectly well.
    if wanted.isEmpty && (window[kCGWindowLayer as String] as? Int ?? -1) != 0 { continue }
    guard let r = rect(window) else { continue }
    print("\(id)\t\(Int(r.minX))\t\(Int(r.minY))\t\(Int(r.width))\t\(Int(r.height))")
}
