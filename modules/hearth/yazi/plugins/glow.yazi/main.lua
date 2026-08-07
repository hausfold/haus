--- @since 26.1.22

-- Vendored + modernised copy of Reledia/glow.yazi. The upstream plugin (and the
-- nixpkgs `yaziPlugins.glow` snapshot) still target the pre-26 yazi Lua API and
-- crash on yazi 26.x with "attempt to call a nil value (method 'args')". The API
-- calls updated here, cross-checked against the bundled piper.yazi (@since
-- 26.1.22): Command :args -> :arg, ya.mgr_emit -> ya.emit, ya.preview_widgets ->
-- ya.preview_widget (singular), and require("code").peek -> :peek (method call).
-- rt.preview.tab_size is unchanged. Drop this vendor once upstream/nixpkgs ships
-- a 26-compatible glow plugin.

local M = {}

function M:peek(job)
	-- Render for the actual preview rectangle. The old fixed 55-column width
	-- only happened to fit one pane ratio and left stale wrapping behind as the
	-- terminal or manager columns changed.
	local preview_width = job.area.w

	-- @glowStyle@ is substituted by hearth with the Nebelung glamour port's
	-- store path. It must be passed with -s: glow ignores $GLAMOUR_STYLE in its
	-- default "auto" mode (glow 2.x). Upstream hardcoded "dark" here, which is
	-- what made previews ignore the theme.
	local child = Command("glow")
		:arg({
			"--style",
			"@glowStyle@",
			"--width",
			tostring(preview_width),
			tostring(job.file.url),
		})
		:env("CLICOLOR_FORCE", "1")
		:stdout(Command.PIPED)
		:stderr(Command.PIPED)
		:spawn()

	if not child then
		return require("code"):peek(job)
	end

	local limit = job.area.h
	local i, lines = 0, ""
	repeat
		local next, event = child:read_line()
		if event == 1 then
			return require("code"):peek(job)
		elseif event ~= 0 then
			break
		end

		i = i + 1
		if i > job.skip then
			lines = lines .. next
		end
	until i >= job.skip + limit

	child:start_kill()
	if job.skip > 0 and i < job.skip + limit then
		ya.emit("peek", {
			math.max(0, i - limit),
			only_if = job.file.url,
			upper_bound = true,
		})
	else
		lines = lines:gsub("\t", string.rep(" ", rt.preview.tab_size))
		ya.preview_widget(job, ui.Text.parse(lines):area(job.area))
	end
end

function M:seek(job) require("code"):seek(job) end

return M
