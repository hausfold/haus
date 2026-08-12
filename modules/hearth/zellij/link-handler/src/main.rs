// link-handler — zellij's built-in `link` plugin (default-plugins/link at
// v0.44.3, MIT), forked to change what a click DOES. Upstream opens files in
// $EDITOR (floating pane) and directories in the filepicker; this fork opens
// both in a new tab cwd'd at the path's directory, auto-named after its git
// repo — the same behavior as peek-run.sh. Everything else (path regex, hover
// underline/italic, cwd tracking, dir-entry highlights, ~/$VAR expansion) is
// upstream, kept verbatim so the fork stays diffable against new zellij
// releases.
//
// Deltas from upstream, in full:
//   - request_permission + Event::PermissionRequestResult handling: built-in
//     plugins are implicitly trusted, user plugins must ask. Loaded as a
//     background plugin there is no pane to show the grant prompt in, so
//     hearth pre-seeds zellij's permission cache (see modules/hearth).
//   - handle_highlight_clicked: new-tab-with-cwd instead of $EDITOR/filepicker,
//     and an existence-first dispatch — a click is opened as a file/dir if the
//     path resolves on disk, otherwise it falls through to the URL kinds. This
//     is what lets a bare token be a path OR a schemeless site without the
//     regex having to tell them apart up front.
//   - FILE_PATH_REGEX: on top of the upstream ./ ../ / ~/ $VAR anchors, a bare
//     relative branch matches slash-bearing paths that DON'T start with a
//     leading `.`/`/` (e.g. `src/main.rs`, `modules/hearth/foo.rs`). Safe to
//     highlight liberally because the click validates existence before acting.
//   - URL_REGEX + WEB_DOMAIN_REGEX + open_target: http(s) URLs are highlighted
//     and open in the default browser via `open` (hence RunCommands), and so
//     are schemeless well-known-TLD domains (`github.com/x`, `nebelhaus.com`) —
//     https:// is prepended on click. open_target is the dispatch point for any
//     future per-kind click behavior.
//   - image files open a near-fullscreen floating pane running
//     ~/.config/zellij/image-preview.sh (chafa render + copy/open hotkeys)
//     instead of a new tab.
//   - a FILE opens in the rice editor, at its `:line` when the reference
//     carried one (editor-open-pane.sh, the same script EditorOpen.app uses);
//     only a DIRECTORY opens as a new tab cwd'd at itself.
//   - tooltip says where the click goes.
//   - OSC 8 hyperlinks arrive here as clicks too, with `pattern` set to
//     LINK_ANCHOR_PATTERN and `matched_string` already resolved to the real
//     URI (see below).
//
// This plugin can only MATCH visible text: the zellij 0.44 plugin API
// (set_pane_regex_highlights + HighlightClicked) hands back the matched
// *visible* string and nothing else — there is no API surfacing the hidden URI
// or the raw cell buffer (checked against zellij-tile 0.44.3). That is fatal
// for exactly the links an agent prints: an OSC 8 hyperlink whose visible text
// is a word, and a URL the application hard-wrapped across two rows (the
// visible text is then two unrelated strings, and clicking either used to open
// half a URL). So the rice patches zellij itself to read the destination off
// the CELLS — where OSC 8 and zellij's own URL tracker both record it — and to
// send it here as a click under LINK_ANCHOR_PATTERN, which this plugin trusts
// whole. See modules/hearth/zellij/patches/naked-click-links.patch.
//
// The gesture is a bare click, in every pane, whether or not the program
// running there captures the mouse — LINKS in every pane, and additionally
// paths/images in panes no application is tracking the mouse in (there, its
// own clicks land on path-shaped text and are left alone). There is no ⌥+Click any more (it opened
// the visible-text version of the same thing, wrongly, and cost a modifier)
// and there never could be a ⌘+Click inside the terminal: the SGR mouse
// encoding has bits for shift, alt and ctrl and none for super, so ⌘ never
// crosses the wire. ⌘⇧+Click still bypasses the multiplexer entirely into
// ghostty (⇧ frees the mouse from the program capturing it, ⌘ is what makes
// ghostty read a link there) — the escape hatch for a target we get wrong.

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::{Path, PathBuf};
use zellij_tile::prelude::*;

// Path branches, in order: an anchored path (./ ../ / ~/ $VAR/…), then a bare
// relative path that merely CONTAINS a slash and starts with an alnum/_/@ —
// e.g. `src/main.rs`, `modules/hearth/foo.rs`, `github.com/org/repo`. The last
// branch is deliberately loose; the click's std::fs existence check (and the
// URL fallback) is what keeps a false-positive highlight from doing anything.
const FILE_PATH_REGEX: &str = r#"(?:^|\s)((?:(?:\./|\.\./|/)[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+|~/[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+|\$\{?[A-Za-z_][A-Za-z0-9_]*\}?/[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+|[A-Za-z0-9_@][A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]*/[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]+)(?::\d+(?::\d+)?)?)(?::|\s|$)"#;

// Ends at whitespace or a quote/angle delimiter; trailing sentence
// punctuation the character class can't exclude (a URL inside parens or at
// the end of a sentence) is trimmed on click by parse_url.
const URL_REGEX: &str = r#"\b(https?://[^\s"'<>]+)"#;

// Schemeless web links: a well-known-TLD domain (or any `www.` host) with an
// optional port and path. Kept to a curated TLD set so ordinary `name.ext`
// file references aren't mistaken for sites; https:// is prepended on click,
// and — like paths — a click only reaches the browser after the on-disk
// existence check has failed, so a real file named `foo.io` still opens as a
// file.
const WEB_DOMAIN_REGEX: &str = r#"\b((?:www\.)?[A-Za-z0-9][A-Za-z0-9\-]*(?:\.[A-Za-z0-9\-]+)*\.(?:com|org|net|io|dev|ai|app|gov|edu|co|xyz|info|cloud|tv|gg|so|me|page|blog)(?::\d+)?(?:/[^\s"'<>]*)?)"#;

// TLDs the schemeless-domain matcher trusts, plus the WEB_DOMAIN_REGEX list
// above (keep the two in sync). `www.`-prefixed hosts bypass this check.
const COMMON_TLDS: &[&str] = &[
    "com", "org", "net", "io", "dev", "ai", "app", "gov", "edu", "co", "xyz", "info", "cloud",
    "tv", "gg", "so", "me", "page", "blog",
];

const CWD_CONTEXT_KEY: &str = "cwd";

/// The pattern zellij reports when the click landed on a link ANCHOR rather
/// than one of the regexes above — an OSC 8 hyperlink, or a URL zellij's own
/// HyperlinkTracker found in printed text. Must stay identical to
/// `LINK_ANCHOR_PATTERN` in the rice's zellij patch
/// (modules/hearth/zellij/patches/naked-click-links.patch); it is the whole
/// contract between the two halves.
const LINK_ANCHOR_PATTERN: &str = "<link-anchor>";

const IMAGE_EXTENSIONS: &[&str] = &["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "ico", "tiff"];

fn is_image_file(path: &Path) -> bool {
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        IMAGE_EXTENSIONS.contains(&ext.to_lowercase().as_str())
    } else {
        false
    }
}

#[derive(Default)]
struct State {
    known_terminal_panes: HashSet<PaneId>,
    /// Tracks the current CWD for each terminal pane.
    pane_cwds: HashMap<PaneId, PathBuf>,
    /// Tracks the directory entry names highlighted for each pane,
    /// so they can be removed when the CWD changes.
    pane_dir_entries: HashMap<PaneId, Vec<String>>,
    /// Session environment variables, fetched once permissions are granted.
    /// Used for `~` and `$VAR` expansion in clicked paths.
    env_vars: BTreeMap<String, String>,
}

register_plugin!(State);

impl ZellijPlugin for State {
    fn load(&mut self, _configuration: BTreeMap<String, String>) {
        // Everything below PermissionRequestResult is gated on the grant:
        // host-folder access, pane cwds and tab-opening are all
        // permissioned for non-builtin plugins.
        request_permission(&[
            PermissionType::ReadApplicationState,
            PermissionType::ChangeApplicationState,
            PermissionType::FullHdAccess,
            PermissionType::RunCommands,
            PermissionType::ReadSessionEnvironmentVariables,
        ]);
        subscribe(&[
            EventType::PermissionRequestResult,
            EventType::PaneUpdate,
            EventType::HighlightClicked,
            EventType::CwdChanged,
        ]);
    }

    fn update(&mut self, event: Event) -> bool {
        match event {
            Event::PermissionRequestResult(PermissionStatus::Granted) => {
                // Set host folder to "/" so that /host maps to the real
                // filesystem root, allowing std::fs operations on
                // /host/<absolute_path>.
                change_host_folder(PathBuf::from("/"));
                self.env_vars = get_session_environment_variables();
            },
            Event::PaneUpdate(pane_manifest) => {
                self.handle_pane_update(pane_manifest);
            },
            Event::HighlightClicked {
                pane_id: _,
                pattern,
                matched_string,
                context,
            } => {
                self.handle_highlight_clicked(&pattern, matched_string, context);
            },
            Event::CwdChanged(pane_id, new_cwd, _focused_client_ids) => {
                self.handle_cwd_changed(pane_id, new_cwd);
            },
            _ => {},
        }
        false // never render — background-only plugin
    }

    fn render(&mut self, _rows: usize, _cols: usize) {
        // Background-only plugin. Never rendered. Intentionally empty.
    }
}

impl State {
    fn handle_pane_update(&mut self, pane_manifest: PaneManifest) {
        let mut current_panes: HashSet<PaneId> = HashSet::new();

        for (_tab_index, panes) in &pane_manifest.panes {
            for pane_info in panes {
                if !pane_info.is_plugin {
                    let pane_id = PaneId::Terminal(pane_info.id);
                    current_panes.insert(pane_id);
                }
            }
        }

        // Set highlights on newly appeared terminal panes
        for &pane_id in &current_panes {
            if !self.known_terminal_panes.contains(&pane_id) {
                // Fetch the pane's current CWD and scan its directory
                if let Ok(cwd) = get_pane_cwd(pane_id) {
                    self.scan_and_store_dir_entries(pane_id, &cwd);
                    self.pane_cwds.insert(pane_id, cwd);
                }
                self.set_all_highlights_for_pane(pane_id);
            }
        }

        // Clean up tracking state for panes that no longer exist
        for &pane_id in &self.known_terminal_panes {
            if !current_panes.contains(&pane_id) {
                self.pane_cwds.remove(&pane_id);
                self.pane_dir_entries.remove(&pane_id);
            }
        }

        self.known_terminal_panes = current_panes;
    }

    fn handle_cwd_changed(&mut self, pane_id: PaneId, new_cwd: PathBuf) {
        let old_cwd = self.pane_cwds.get(&pane_id);
        if old_cwd == Some(&new_cwd) {
            return;
        }

        self.pane_cwds.insert(pane_id, new_cwd.clone());
        self.scan_and_store_dir_entries(pane_id, &new_cwd);

        // clear_pane_highlights removes all highlights, then re-set everything
        // (file-path regex + directory entry patterns)
        clear_pane_highlights(pane_id);
        self.set_all_highlights_for_pane(pane_id);
    }

    /// Dispatch a click by what was matched, existence-first: an explicit
    /// http(s) URL goes to the browser; otherwise we try to open it as a real
    /// file/dir; only if that path doesn't exist do we treat it as a schemeless
    /// web link. This ordering is what lets one bare token (`github.com/x` vs
    /// `src/main.rs`) resolve correctly without the regex disambiguating up front.
    ///
    /// `pattern` is `LINK_ANCHOR_PATTERN` when the click landed on a link
    /// ANCHOR rather than one of our regexes — an OSC 8 hyperlink, or a URL
    /// zellij's own tracker found in printed text. Then `matched_string` is a
    /// finished URI resolved from the cells themselves (see the header), so it
    /// is trusted whole instead of being re-derived from visible text: that is
    /// the entire point of the anchor path, and re-parsing would put back the
    /// hard-wrap bug it exists to fix.
    fn handle_highlight_clicked(
        &self,
        pattern: &str,
        matched_string: String,
        context: BTreeMap<String, String>,
    ) {
        let clicked = matched_string.trim();

        if pattern == LINK_ANCHOR_PATTERN {
            self.open_anchor_uri(clicked);
            return;
        }

        // 1. Explicit http(s) URL → browser.
        if let Some(url) = parse_url(clicked) {
            open_in_browser(url);
            return;
        }

        // 2. A real file or directory on disk → open it (tab or image preview).
        if self.try_open_as_path(&matched_string, &context) {
            return;
        }

        // 3. Not a real path — a schemeless web link (github.com/x, nebelhaus.com)?
        if let Some(url) = parse_bare_url(clicked) {
            open_in_browser(&url);
        }
        // 4. Otherwise: not a link we recognize — ignore.
    }

    /// Open a URI that came from a link anchor. `file:` URIs are turned back
    /// into paths so they open in the editor (with the line, if the producer
    /// put one in the fragment) instead of bouncing through the browser;
    /// everything else — http(s), mailto:, and whatever scheme an application
    /// decides to emit — is handed to the system opener, which is the one thing
    /// that knows what this machine has registered for it.
    fn open_anchor_uri(&self, uri: &str) {
        if let Some((path, line)) = parse_file_uri(uri) {
            self.open_in_editor(Path::new(&path), line);
            return;
        }
        open_in_browser(uri);
    }

    /// Resolve `matched_string` against the pane CWD and, if it names an
    /// existing file or directory, open it. Returns `true` when the path
    /// resolved (and was acted on), `false` when it doesn't exist on disk — the
    /// caller uses that to fall through to the URL kinds.
    fn try_open_as_path(&self, matched_string: &str, context: &BTreeMap<String, String>) -> bool {
        let (path_str, line_number) = parse_path_and_line(matched_string);
        let path_str = path_str.trim();
        let expanded = expand_path(path_str, &self.env_vars);
        let path_str = expanded.as_str();

        // Resolve to a fully qualified path: if relative, join with the
        // pane CWD stored in the highlight context.
        let absolute_path = if path_str.starts_with('/') {
            PathBuf::from(path_str)
        } else if let Some(cwd) = context.get(CWD_CONTEXT_KEY) {
            PathBuf::from(cwd).join(path_str)
        } else {
            PathBuf::from(path_str)
        };

        // Validate the path exists via the /host/ filesystem mapping
        // established after the permission grant. This guards against regex
        // false positives that match non-path text in terminal output.
        let metadata = match std::fs::metadata(host_path(&absolute_path)) {
            Ok(m) => m,
            Err(_) => return false, // not a real path — let the caller try URL kinds
        };

        if metadata.is_file() && is_image_file(&absolute_path) {
            if let Some(home) = self.env_vars.get("HOME") {
                let preview_script = PathBuf::from(home)
                    .join(".config/zellij/image-preview.sh");
                let cmd = CommandToRun {
                    path: preview_script,
                    args: vec![absolute_path.to_string_lossy().into_owned()],
                    cwd: None,
                };
                // Near-fullscreen: the default floating size is a small
                // centered window; a preview wants all the cells it can get
                // since the image renders as character art.
                let coords = FloatingPaneCoordinates::new(
                    Some("2%".to_owned()),
                    Some("2%".to_owned()),
                    Some("96%".to_owned()),
                    Some("96%".to_owned()),
                    None,
                    None,
                );
                open_command_pane_floating(cmd, coords, BTreeMap::new());
            }
            return true;
        }

        // A file opens IN the editor, at its line when the reference carried
        // one. It used to open a tab cwd'd at the file's parent instead, which
        // dropped the `:26` an agent puts on every path it prints and left you
        // to find the file again by hand — the single most-clicked link in the
        // whole rice, landing one step short every time.
        if metadata.is_file() {
            self.open_in_editor(&absolute_path, line_number);
            return true;
        }

        // A directory still opens as a tab cwd'd at itself. Anything that is
        // neither file nor directory (a fifo, a socket) is not something to
        // open: fall through as if the path hadn't resolved.
        if !metadata.is_dir() {
            return false;
        }
        let dir = absolute_path;
        let name = tab_name_for(&dir);
        match self.layout_with_cwd(&dir, &name) {
            Some(layout) => {
                new_tabs_with_layout(&layout);
            },
            None => {
                // Layout missing/reformatted: at least name the tab; cwd may
                // land in $HOME (`new-tab --cwd` is ignored under a
                // default_tab_template) — same fallback as peek-run.sh.
                new_tab(Some(name.as_str()), Some(dir.to_string_lossy().as_ref()));
            },
        }
        true
    }

    /// Open a file in the rice editor, at `line` when the reference carried
    /// one. Delegates to ~/.config/zellij/editor-open-pane.sh — the same script
    /// the file-association handler (EditorOpen.app) and the "Nix Config"
    /// palette command call — so a clicked path lands in exactly the same place
    /// a double-clicked file does: a new tab at the file's repo root, editor
    /// open on the file. The editor command itself is baked into that script
    /// from haus.hearth.editor at build time, which is why the plugin (built
    /// on its own, without the rice's config) doesn't need to know it.
    fn open_in_editor(&self, path: &Path, line: Option<usize>) {
        let Some(home) = self.env_vars.get("HOME") else {
            return;
        };
        let script = PathBuf::from(home).join(".config/zellij/editor-open-pane.sh");
        let script = script.to_string_lossy().into_owned();
        let path_arg = path.to_string_lossy().into_owned();
        // The empty argument is the script's cwd override, which only
        // nix-config-open.sh uses; the line goes after it.
        let line_arg = line.map(|line| line.to_string()).unwrap_or_default();
        run_command(
            &[
                script.as_str(),
                path_arg.as_str(),
                "",
                line_arg.as_str(),
            ],
            BTreeMap::new(),
        );
    }

    /// Clone the live layout file and inject cwd + name onto its content tab —
    /// the same trick as peek-run.sh: `new-tab --cwd` is silently ignored when a
    /// default_tab_template is active (zellij 0.44), but a tab-level cwd in a
    /// layout IS honored, and reusing custom.kdl verbatim keeps the
    /// tab-bar/status-bar and the spiral/columns/grid swap layouts intact.
    fn layout_with_cwd(&self, dir: &Path, name: &str) -> Option<String> {
        let home = self.env_vars.get("HOME")?;
        let layout_src = Path::new(home).join(".config/zellij/layouts/custom.kdl");
        let src = std::fs::read_to_string(host_path(&layout_src)).ok()?;

        // KDL-escape (backslash then double-quote), mirroring peek-run.sh.
        let cwd_escaped = kdl_escape(&dir.to_string_lossy());
        let name_escaped = kdl_escape(name);

        let mut done = false;
        let out: Vec<String> = src
            .lines()
            .map(|line| {
                if !done && line == "    tab name=\"~\" {" {
                    done = true;
                    format!("    tab cwd=\"{}\" name=\"{}\" {{", cwd_escaped, name_escaped)
                } else {
                    line.to_string()
                }
            })
            .collect();
        done.then(|| out.join("\n"))
    }

    /// (Re-)set all regex highlights for a pane: the general file-path regex
    /// plus any directory-entry patterns derived from the pane's CWD.
    fn set_all_highlights_for_pane(&self, pane_id: PaneId) {
        let mut highlights = Vec::new();

        // Build context map containing the pane CWD (echoed back on click)
        let context = self.cwd_context_for_pane(pane_id);

        // General file-path regex (always present)
        highlights.push(RegexHighlight {
            pattern: FILE_PATH_REGEX.to_owned(),
            style: HighlightStyle::None,
            layer: HighlightLayer::Hint,
            context: context.clone(),
            on_hover: true,
            bold: false,
            italic: true,
            underline: true,
            tooltip_text: Some("Open in editor · dir opens a tab".to_string()),
        });

        // http(s) URLs (always present)
        highlights.push(RegexHighlight {
            pattern: URL_REGEX.to_owned(),
            style: HighlightStyle::None,
            layer: HighlightLayer::Hint,
            context: context.clone(),
            on_hover: true,
            bold: false,
            italic: true,
            underline: true,
            tooltip_text: Some("Open in browser".to_string()),
        });

        // Schemeless well-known-TLD domains (always present) — https:// is
        // prepended on click.
        highlights.push(RegexHighlight {
            pattern: WEB_DOMAIN_REGEX.to_owned(),
            style: HighlightStyle::None,
            layer: HighlightLayer::Hint,
            context: context.clone(),
            on_hover: true,
            bold: false,
            italic: true,
            underline: true,
            tooltip_text: Some("Open in browser".to_string()),
        });

        // Directory-entry patterns for the pane's current CWD
        if let Some(entries) = self.pane_dir_entries.get(&pane_id) {
            for entry_name in entries {
                let path_chars = r#"[A-Za-z0-9_./\-+@%,#=~!\$\{\}\[\]]"#;
                let pattern = format!(
                    "(?:^|\\s)({}(?:/{path_chars}+)?(?::\\d+(?::\\d+)?)?)(?::|\\s|$)",
                    regex_escape(entry_name),
                );
                highlights.push(RegexHighlight {
                    pattern,
                    style: HighlightStyle::None,
                    layer: HighlightLayer::Hint,
                    context: context.clone(),
                    on_hover: true,
                    bold: false,
                    italic: true,
                    underline: true,
                    tooltip_text: Some("Open in editor · dir opens a tab".to_string()),
                });
            }
        }

        set_pane_regex_highlights(pane_id, highlights);
    }

    fn scan_and_store_dir_entries(&mut self, pane_id: PaneId, cwd: &Path) {
        let dir_entries = scan_directory(&host_path(cwd));
        self.pane_dir_entries.insert(pane_id, dir_entries);
    }

    fn cwd_context_for_pane(&self, pane_id: PaneId) -> BTreeMap<String, String> {
        let mut context = BTreeMap::new();
        if let Some(cwd) = self.pane_cwds.get(&pane_id) {
            context.insert(CWD_CONTEXT_KEY.to_owned(), cwd.display().to_string());
        }
        context
    }
}

/// Map a real absolute path onto the plugin's /host mount (host folder is "/").
fn host_path(path: &Path) -> PathBuf {
    Path::new("/host").join(path.strip_prefix("/").unwrap_or(path))
}

/// The tab name for a directory: its git-root's basename, or its own basename
/// outside a repo — the same naming as peek-run.sh. `.git` is checked with
/// metadata (not is_dir) because linked worktrees and submodules have a
/// `.git` FILE.
fn tab_name_for(dir: &Path) -> String {
    let mut git_root = None;
    let mut current = Some(dir.to_path_buf());
    while let Some(candidate) = current {
        if std::fs::metadata(host_path(&candidate.join(".git"))).is_ok() {
            git_root = Some(candidate);
            break;
        }
        current = candidate.parent().map(Path::to_path_buf);
    }
    git_root
        .as_deref()
        .unwrap_or(dir)
        .file_name()
        .map(|name| name.to_string_lossy().into_owned())
        .unwrap_or_else(|| "new".to_string())
}

/// Open a URL in the default browser.
fn open_in_browser(url: &str) {
    run_command(&["/usr/bin/open", url], BTreeMap::new());
}

/// Split a `file:` URI into a path and an optional line number, or None when
/// it isn't one. Both spellings a producer might use for the line are read: a
/// `#L26` fragment (how a forge spells it) and a trailing `:26` (how a compiler
/// does). Percent-escapes are decoded — a path that arrived as a URI has them,
/// a path that arrived as terminal text does not.
fn parse_file_uri(uri: &str) -> Option<(String, Option<usize>)> {
    let rest = uri.strip_prefix("file://")?;
    // An authority component (`file://localhost/etc/hosts`) sits between the
    // slashes; the common `file:///etc/hosts` leaves `rest` already absolute.
    let path_and_fragment = match rest.strip_prefix('/') {
        Some(_) => rest,
        None => &rest[rest.find('/')?..],
    };

    let (path_part, line) = match path_and_fragment.split_once('#') {
        Some((path, fragment)) => {
            let line = fragment
                .trim_start_matches(['L', 'l'])
                .split(['-', ':'])
                .next()
                .and_then(|n| n.parse::<usize>().ok());
            (path, line)
        },
        None => {
            let (path, line) = parse_path_and_line(path_and_fragment);
            (path, line)
        },
    };

    Some((percent_decode(path_part), line))
}

/// Decode the percent-escapes in a URI path. Deliberately tiny: a file URI's
/// path is the only thing that reaches it, and an escape that isn't valid
/// UTF-8 hex is left alone rather than dropped, so a literal `%` in a filename
/// survives the round trip.
fn percent_decode(s: &str) -> String {
    let bytes = s.as_bytes();
    let mut out: Vec<u8> = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hex = std::str::from_utf8(&bytes[i + 1..i + 3]).ok();
            if let Some(byte) = hex.and_then(|h| u8::from_str_radix(h, 16).ok()) {
                out.push(byte);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8(out).unwrap_or_else(|_| s.to_owned())
}

/// Recognize an http(s) URL in a clicked highlight, with trailing sentence
/// punctuation trimmed (see `trim_url_trailing`).
fn parse_url(s: &str) -> Option<&str> {
    if !(s.starts_with("http://") || s.starts_with("https://")) {
        return None;
    }
    Some(trim_url_trailing(s))
}

/// Recognize a schemeless web link like `github.com/zellij-org/zellij` or
/// `nebelhaus.com` and return it with an `https://` scheme prepended. Only
/// hosts on a well-known TLD (or any `www.` host) qualify, so an ordinary
/// `name.ext` token isn't mistaken for a site. Called only after the on-disk
/// existence check has failed, so a real file named `foo.io` still opens as a
/// file rather than a website.
fn parse_bare_url(s: &str) -> Option<String> {
    let s = trim_url_trailing(s);
    if s.is_empty() || s.contains("://") {
        return None;
    }
    // The host is everything before the first `/`, minus any `:port`.
    let host = s.split('/').next().unwrap_or(s);
    let host = host.split(':').next().unwrap_or(host);
    if !is_web_host(host) {
        return None;
    }
    Some(format!("https://{s}"))
}

/// True if `host` looks like a browsable domain: at least two DNS labels, each
/// well-formed, and either a `www.` prefix or a trusted TLD (`COMMON_TLDS`).
fn is_web_host(host: &str) -> bool {
    let labels: Vec<&str> = host.split('.').collect();
    if labels.len() < 2 {
        return false;
    }
    let well_formed = labels.iter().all(|l| {
        !l.is_empty()
            && !l.starts_with('-')
            && !l.ends_with('-')
            && l.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
    });
    if !well_formed {
        return false;
    }
    let tld = labels.last().unwrap().to_ascii_lowercase();
    host.starts_with("www.") || COMMON_TLDS.contains(&tld.as_str())
}

/// Trim trailing punctuation a whitespace-terminated URL/domain match tends to
/// swallow — sentence punctuation, and closing brackets only when unbalanced
/// (so `…/Worm_(search_engine)` keeps its paren but `(…foo)` loses it).
fn trim_url_trailing(s: &str) -> &str {
    let mut trimmed = s;
    while !trimmed.is_empty() {
        let last_char = match trimmed.chars().next_back() {
            Some(c) => c,
            None => break,
        };
        if ".,;:!?\"'".contains(last_char) {
            trimmed = &trimmed[..trimmed.len() - last_char.len_utf8()];
        } else if last_char == ')' {
            // Trim trailing ')' ONLY if parentheses are unbalanced
            if trimmed.contains('(') {
                let open_count = trimmed.chars().filter(|&c| c == '(').count();
                let close_count = trimmed.chars().filter(|&c| c == ')').count();
                if close_count > open_count {
                    trimmed = &trimmed[..trimmed.len() - 1];
                } else {
                    break;
                }
            } else {
                trimmed = &trimmed[..trimmed.len() - 1];
            }
        } else if last_char == ']' {
            if trimmed.contains('[') {
                let open_count = trimmed.chars().filter(|&c| c == '[').count();
                let close_count = trimmed.chars().filter(|&c| c == ']').count();
                if close_count > open_count {
                    trimmed = &trimmed[..trimmed.len() - 1];
                } else {
                    break;
                }
            } else {
                trimmed = &trimmed[..trimmed.len() - 1];
            }
        } else if last_char == '}' {
            if trimmed.contains('{') {
                let open_count = trimmed.chars().filter(|&c| c == '{').count();
                let close_count = trimmed.chars().filter(|&c| c == '}').count();
                if close_count > open_count {
                    trimmed = &trimmed[..trimmed.len() - 1];
                } else {
                    break;
                }
            } else {
                trimmed = &trimmed[..trimmed.len() - 1];
            }
        } else {
            break;
        }
    }
    trimmed
}

fn kdl_escape(s: &str) -> String {
    s.replace('\\', "\\\\").replace('"', "\\\"")
}

/// Scan a directory for first-level file and folder names.
/// Returns an empty vec on any error.
/// Maximum number of directory entries to scan. Directories with more entries
/// than this are skipped entirely to avoid excessive regex pattern count.
const MAX_DIR_ENTRIES: usize = 500;

fn scan_directory(path: &Path) -> Vec<String> {
    let mut entries = Vec::new();
    let read_dir = match std::fs::read_dir(path) {
        Ok(rd) => rd,
        Err(_) => return entries,
    };
    for entry in read_dir {
        if let Ok(entry) = entry {
            if let Some(name) = entry.file_name().to_str() {
                entries.push(name.to_owned());
                if entries.len() > MAX_DIR_ENTRIES {
                    return Vec::new();
                }
            }
        }
    }
    entries
}

/// Escape a string so it is treated as a literal in a regex pattern.
fn regex_escape(s: &str) -> String {
    let mut escaped = String::with_capacity(s.len() + 8);
    for c in s.chars() {
        match c {
            '\\' | '.' | '+' | '*' | '?' | '(' | ')' | '|' | '[' | ']' | '{' | '}' | '^' | '$' => {
                escaped.push('\\');
                escaped.push(c);
            },
            _ => escaped.push(c),
        }
    }
    escaped
}

/// Expand `~` and `$VAR` / `${VAR}` references in a path string.
///
/// - `~` at the start (followed by `/` or at end-of-string) is replaced with
///   the value of `HOME` from `env_vars`.
/// - `$VARNAME` and `${VARNAME}` anywhere in the string are replaced with the
///   corresponding value from `env_vars`.
/// - Unrecognized variables and a missing `HOME` are left as-is.
fn expand_path(path: &str, env_vars: &BTreeMap<String, String>) -> String {
    // Step 1: tilde expansion (only leading ~)
    let after_tilde = if path == "~" {
        match env_vars.get("HOME") {
            Some(home) => home.clone(),
            None => path.to_owned(),
        }
    } else if let Some(rest) = path.strip_prefix("~/") {
        match env_vars.get("HOME") {
            Some(home) => format!("{}/{}", home, rest),
            None => path.to_owned(),
        }
    } else {
        path.to_owned()
    };

    // Step 2: environment variable expansion ($VAR and ${VAR})
    let bytes = after_tilde.as_bytes();
    let len = bytes.len();
    let mut result = String::with_capacity(len);
    let mut i = 0;

    while i < len {
        if bytes[i] == b'$' && i + 1 < len {
            let (var_name, end_idx) = if bytes[i + 1] == b'{' {
                // ${VAR} form
                if let Some(close) = after_tilde[i + 2..].find('}') {
                    let name = &after_tilde[i + 2..i + 2 + close];
                    (name, i + 2 + close + 1)
                } else {
                    // No closing brace — not a valid variable reference
                    result.push('$');
                    i += 1;
                    continue;
                }
            } else {
                // $VAR form — variable name is [A-Za-z_][A-Za-z0-9_]*
                let start = i + 1;
                if start < len && (bytes[start].is_ascii_alphabetic() || bytes[start] == b'_') {
                    let mut end = start + 1;
                    while end < len && (bytes[end].is_ascii_alphanumeric() || bytes[end] == b'_') {
                        end += 1;
                    }
                    (&after_tilde[start..end], end)
                } else {
                    result.push('$');
                    i += 1;
                    continue;
                }
            };

            if let Some(value) = env_vars.get(var_name) {
                result.push_str(value);
            } else {
                // Unknown variable — preserve the original text
                result.push_str(&after_tilde[i..end_idx]);
            }
            i = end_idx;
        } else {
            result.push(bytes[i] as char);
            i += 1;
        }
    }

    result
}

fn parse_path_and_line(matched_string: &str) -> (&str, Option<usize>) {
    let mut end = matched_string.len();
    let mut numeric_segments: Vec<(usize, &str)> = Vec::new();

    loop {
        if end == 0 {
            break;
        }
        let search_region = &matched_string[..end];
        if let Some(colon_pos) = search_region.rfind(':') {
            let segment = &matched_string[colon_pos + 1..end];
            if !segment.is_empty() && segment.chars().all(|c| c.is_ascii_digit()) {
                numeric_segments.push((colon_pos, segment));
                end = colon_pos;
            } else {
                break;
            }
        } else {
            break;
        }
    }

    numeric_segments.reverse();

    match numeric_segments.first() {
        None => (matched_string, None),
        Some(&(colon_pos, line_str)) => {
            let path = &matched_string[..colon_pos];
            (path, line_str.parse::<usize>().ok())
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // --- parse_path_and_line tests ---

    #[test]
    fn parse_path_and_line_simple_path() {
        let (path, line) = parse_path_and_line("src/main.rs");
        assert_eq!(path, "src/main.rs");
        assert_eq!(line, None);
    }

    #[test]
    fn parse_path_and_line_with_line_number() {
        let (path, line) = parse_path_and_line("src/main.rs:42");
        assert_eq!(path, "src/main.rs");
        assert_eq!(line, Some(42));
    }

    #[test]
    fn parse_path_and_line_with_line_and_col() {
        let (path, line) = parse_path_and_line("src/main.rs:42:10");
        assert_eq!(path, "src/main.rs");
        assert_eq!(line, Some(42));
    }

    #[test]
    fn parse_path_and_line_no_trailing_number() {
        let (path, line) = parse_path_and_line("src/main.rs:");
        assert_eq!(path, "src/main.rs:");
        assert_eq!(line, None);
    }

    // --- expand_path tests ---

    #[test]
    fn expand_path_tilde() {
        let mut env = BTreeMap::new();
        env.insert("HOME".into(), "/home/user".into());
        assert_eq!(expand_path("~/foo/bar", &env), "/home/user/foo/bar");
    }

    #[test]
    fn expand_path_env_var() {
        let mut env = BTreeMap::new();
        env.insert("HOME".into(), "/home/user".into());
        assert_eq!(expand_path("$HOME/foo", &env), "/home/user/foo");
    }

    #[test]
    fn expand_path_braced_var() {
        let mut env = BTreeMap::new();
        env.insert("HOME".into(), "/home/user".into());
        assert_eq!(expand_path("${HOME}/foo", &env), "/home/user/foo");
    }

    #[test]
    fn expand_path_unknown_var_preserved() {
        let env = BTreeMap::new();
        assert_eq!(expand_path("$UNKNOWN/foo", &env), "$UNKNOWN/foo");
    }

    #[test]
    fn expand_path_no_expansion_needed() {
        let env = BTreeMap::new();
        assert_eq!(expand_path("/absolute/path", &env), "/absolute/path");
    }

    // --- parse_url tests ---

    #[test]
    fn parse_url_plain() {
        assert_eq!(
            parse_url("https://github.com/zellij-org/zellij"),
            Some("https://github.com/zellij-org/zellij")
        );
        assert_eq!(parse_url("http://localhost:3000/path"), Some("http://localhost:3000/path"));
    }

    #[test]
    fn parse_url_trims_trailing_punctuation() {
        assert_eq!(parse_url("https://example.com/a)."), Some("https://example.com/a"));
        assert_eq!(parse_url("https://example.com/x,"), Some("https://example.com/x"));
        assert_eq!(parse_url("https://example.com/a)"), Some("https://example.com/a"));
    }

    #[test]
    fn parse_url_balanced_parentheses() {
        assert_eq!(
            parse_url("https://en.wikipedia.org/wiki/Worm_(search_engine)"),
            Some("https://en.wikipedia.org/wiki/Worm_(search_engine)")
        );
        assert_eq!(
            parse_url("https://en.wikipedia.org/wiki/Worm_(search_engine)."),
            Some("https://en.wikipedia.org/wiki/Worm_(search_engine)")
        );
        assert_eq!(
            parse_url("https://en.wikipedia.org/wiki/Worm_(search_engine))"),
            Some("https://en.wikipedia.org/wiki/Worm_(search_engine)")
        );
    }

    #[test]
    fn parse_url_rejects_non_urls() {
        assert_eq!(parse_url("/some/file/path"), None);
        assert_eq!(parse_url("~/code/workshop"), None);
        assert_eq!(parse_url("httpsish://nope"), None);
    }

    // --- parse_bare_url tests ---

    #[test]
    fn parse_bare_url_domain_with_path() {
        assert_eq!(
            parse_bare_url("github.com/zellij-org/zellij"),
            Some("https://github.com/zellij-org/zellij".to_string())
        );
    }

    #[test]
    fn parse_bare_url_bare_domain() {
        assert_eq!(parse_bare_url("nebelhaus.com"), Some("https://nebelhaus.com".to_string()));
        assert_eq!(
            parse_bare_url("www.anything.example"),
            Some("https://www.anything.example".to_string())
        );
    }

    #[test]
    fn parse_bare_url_trims_trailing_punctuation() {
        assert_eq!(
            parse_bare_url("github.com/zellij-org/zellij."),
            Some("https://github.com/zellij-org/zellij".to_string())
        );
        // Trailing `)` from a parenthetical (unbalanced within the match) is
        // trimmed; sentence punctuation too.
        assert_eq!(parse_bare_url("nebelhaus.com)."), Some("https://nebelhaus.com".to_string()));
        assert_eq!(parse_bare_url("nebelhaus.com,"), Some("https://nebelhaus.com".to_string()));
    }

    #[test]
    fn parse_bare_url_rejects_non_web() {
        // Already has a scheme — handled by parse_url, not here.
        assert_eq!(parse_bare_url("https://github.com"), None);
        // Relative file paths, not domains.
        assert_eq!(parse_bare_url("src/main.rs"), None);
        assert_eq!(parse_bare_url("modules/hearth/foo.rs"), None);
        // A dotted filename whose extension isn't a trusted TLD.
        assert_eq!(parse_bare_url("README.md"), None);
        assert_eq!(parse_bare_url("main.rs"), None);
        // Single label — not a domain.
        assert_eq!(parse_bare_url("localhost"), None);
    }

    // --- regex_escape tests ---

    #[test]
    fn regex_escape_special_chars() {
        assert_eq!(regex_escape("file.txt"), r"file\.txt");
        assert_eq!(regex_escape("a+b*c?"), r"a\+b\*c\?");
        assert_eq!(regex_escape("(foo)[bar]{baz}"), r"\(foo\)\[bar\]\{baz\}");
    }

    #[test]
    fn regex_escape_no_special_chars() {
        assert_eq!(regex_escape("foobar"), "foobar");
        assert_eq!(regex_escape("hello_world"), "hello_world");
    }

    // --- kdl_escape tests ---

    #[test]
    fn kdl_escape_quotes_and_backslashes() {
        assert_eq!(kdl_escape(r#"a"b\c"#), r#"a\"b\\c"#);
        assert_eq!(kdl_escape("/plain/path"), "/plain/path");
    }

    // --- parse_file_uri tests (the anchor path) ---

    #[test]
    fn parse_file_uri_plain() {
        assert_eq!(
            parse_file_uri("file:///Users/x/src/main.rs"),
            Some(("/Users/x/src/main.rs".to_string(), None))
        );
    }

    #[test]
    fn parse_file_uri_with_fragment_line() {
        assert_eq!(
            parse_file_uri("file:///Users/x/src/main.rs#L42"),
            Some(("/Users/x/src/main.rs".to_string(), Some(42)))
        );
    }

    #[test]
    fn parse_file_uri_with_trailing_colon_line() {
        assert_eq!(
            parse_file_uri("file:///Users/x/src/main.rs:42"),
            Some(("/Users/x/src/main.rs".to_string(), Some(42)))
        );
    }

    #[test]
    fn parse_file_uri_with_authority_and_escapes() {
        assert_eq!(
            parse_file_uri("file://localhost/Users/x/my%20file.rs#L7-L9"),
            Some(("/Users/x/my file.rs".to_string(), Some(7)))
        );
    }

    #[test]
    fn parse_file_uri_rejects_other_schemes() {
        assert_eq!(parse_file_uri("https://example.com/a"), None);
        assert_eq!(parse_file_uri("mailto:someone@example.com"), None);
    }

    #[test]
    fn percent_decode_leaves_a_lone_percent_alone() {
        assert_eq!(percent_decode("100%"), "100%");
        assert_eq!(percent_decode("a%zzb"), "a%zzb");
        assert_eq!(percent_decode("a%2Fb"), "a/b");
    }
}
