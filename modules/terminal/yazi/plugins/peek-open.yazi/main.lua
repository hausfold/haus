--- @since 26.1.22
--- @sync entry

-- peek-open — bound to Enter in the main yazi keymap, but only CHANGES anything
-- inside the "peek" overlay (Super y, see zellij/peek-run.sh, which exports
-- PEEK=1). There it branches on the hovered entry:
--   • directory → write its path to ~/.cache/peek.cwd and quit yazi, so
--     peek-run.sh spawns a new zellij tab cwd'd there (the old Super-Shift-t
--     browse-and-pick flow, folded into peek). Descend to browse with l/→.
--   • file → fall through to `open`, paging it fullscreen — peek stays a reader.
-- Outside peek (a normal `yy` session, PEEK unset) it is a plain passthrough to
-- `open`, i.e. exactly yazi's default Enter — so regular yazi is unaffected.
--
-- Runs as a SYNC entry (the `--- @sync entry` annotation above) — this matters:
-- an async plugin is itself an "ongoing task" while it runs, so emitting `quit`
-- from inside one makes yazi flash its "tasks are still running?" confirm popup
-- for a frame before exiting (yazi#993/#1059). A sync entry runs on the main
-- thread, counts as no task, so `quit` exits cleanly with no popup — and it can
-- read `cx` directly, so the old ya.sync() wrapper is gone too.

return {
	entry = function()
		local h = cx.active.current.hovered
		local dir = os.getenv("PEEK") == "1" and h and h.cha.is_dir and tostring(h.url)
		if not dir then
			-- Not in peek, or hovering a file: yazi's default Enter (open/page).
			ya.emit("open", {})
			return
		end

		-- Hand the picked directory to peek-run.sh via a fixed drop file, then
		-- quit so it can spawn the tab. HOME is always set in the peek instance.
		local out = (os.getenv("HOME") or "") .. "/.cache/peek.cwd"
		local f = io.open(out, "w")
		if f then
			f:write(dir)
			f:close()
		end
		ya.emit("quit", {})
	end,
}
