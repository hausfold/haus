// hausrect — where a window actually IS on screen, in points, by window id.
//
//   hausrect [<window-id>...]     one `id x y width height` line per window,
//                                 tab separated; every on-screen ordinary
//                                 window when given no ids
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
let wanted = Set(CommandLine.arguments.dropFirst().compactMap(Int.init))

let info =
    CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

for window in info {
    guard let id = window[kCGWindowNumber as String] as? Int else { continue }
    if !wanted.isEmpty && !wanted.contains(id) { continue }
    // Layer 0 is an ordinary application window. Only filtered when listing
    // everything: an id the caller named is one it already decided it wants,
    // and second-guessing that would make the tool lie about a window it can
    // see perfectly well.
    if wanted.isEmpty && (window[kCGWindowLayer as String] as? Int ?? -1) != 0 { continue }
    guard let bounds = window[kCGWindowBounds as String] as? [String: Any],
        let x = bounds["X"] as? Double, let y = bounds["Y"] as? Double,
        let w = bounds["Width"] as? Double, let h = bounds["Height"] as? Double
    else { continue }
    print("\(id)\t\(Int(x))\t\(Int(y))\t\(Int(w))\t\(Int(h))")
}
