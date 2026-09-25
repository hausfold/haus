#!/usr/bin/env bash
# not-a-suite: the runner that finds and runs every other file in test/
#
# How CI decides what to run and what to lint, so neither is a list somebody
# has to remember to extend. Three verbs:
#
#   bash test/ci.sh run <job>   run every suite whose header names <job>
#   bash test/ci.sh census      fail on a suite no job runs
#   bash test/ci.sh lint        shellcheck every tracked *.sh but the
#                               exclusions below
#
# ── the header ───────────────────────────────────────────────────────────────
#
# Every test/*.bats, and every test/*.sh, carries ONE of these in its first
# five lines:
#
#   # suite: job=<job> [needs=<need>[,<need>]]
#   # not-a-suite: <why this file is here>
#
# <job> is a job in .github/workflows/check.yml that has a
# `bash test/ci.sh run <job>` step. A `.bats` file runs under bats and a `.sh`
# under bash, in name order. The needs are what a suite goes quietly green
# without, so the runner checks each one before it starts the suite and fails
# it rather than letting its cases skip:
#
#   painter   HAUS_UI_SH points at a readable snug ui.sh. Without it the
#             colour cases SKIP, and a skip reads as a pass (AGENTS.md, "A
#             suite that RUNS haus.sh"). The job fetches it in a step before
#             the runner.
#   nix       a real `nix` on PATH, for suites that drive a consumer flake.
#
# There is no bash5 need. The three suites that want bash 4+ re-exec
# themselves under one (test/haus-settings.sh's header says why), and
# ubuntu-latest's bash is 5 anyway.
#
# Why a header and not a list in check.yml: that list was hand-written, and
# test/workspace-pills.bats (#780) and test/lane-name-ceiling.bats (#692) both
# landed green without being in it. Neither had ever run in CI. The census
# walks test/ itself, the way `checks-platform-split` in flake.nix walks the
# flake's own checks, so a new suite is a red lint job until it names a job.
#
# The jobs themselves stay fixed and hand-written, and that part is on
# purpose. Each one has its own setup (a Nix install, a store restore, the
# painter fetch), and the banners in check.yml measure each job against the
# pole. A matrix built from the headers would need a discovery job in front
# of every other job, adding about 10s to the gate, and would break the
# per-job arithmetic those banners record. So a new job is still a decision
# made in check.yml, while a new suite is only a header line.
set -euo pipefail

cd "$(dirname "$0")/.."
export LC_ALL=C

WORKFLOW=.github/workflows/check.yml
KNOWN_NEEDS=" painter nix "

# ── shellcheck exclusions ────────────────────────────────────────────────────
#
# Everything tracked as *.sh is linted at --severity=warning unless one of two
# RULES or a NAMED line below takes it out. The rules:
#
#   a zsh shebang    shellcheck has no zsh dialect (SC1071).
#   a `# widget:`    a barlib framework widget. fetch() emits state that
#     header         render() reads as variables, so SC2154 fires on every
#                    widget by design (ops/todo/bar-framework.md).
#
# A named line is `<path><TAB><reason>`. A line naming a file that is no
# longer tracked, or a file that now passes, FAILS the lint, so this list can
# only get shorter. Fixing a file means deleting its line in the same commit.
# A "not triaged" reason means nobody has decided yet whether the warning is a
# bug or a false positive.
EXCLUDE=$(
    cat <<'EOF'
modules/windows/scripts/resort-windows.sh	@placeholder@ template: @RESORT_CASES@ stands where case arms go, so the unsubstituted file does not parse (SC1073)
modules/terminal/scripts/launch.sh	@placeholder@ template: `[ "@restore@" = 1 ]` is a constant until substituted (SC2050)
modules/bar/sketchybar/plugins/ai-provider.sh	sourced library: its P_* variables are read by the plugin that sources it (SC2034)
modules/bar/sketchybar/plugins/media_lib.sh	sourced library: its BAR_MEDIA_* variables are read by the plugin that sources it (SC2034)
modules/bar/sketchybar/plugins/vitals_lib.sh	sourced library: its CPU_*/MEM_* variables are read by the plugin that sources it (SC2034)
modules/bar/sketchybar/plugins/logo.sh	barlib shape with no `# widget:` header: BAR_ITEM is read by barlib.sh (SC2034), `armed` by the popup runtime (SC2154)
modules/bar/sketchybar/plugins/media_art.sh	barlib shape with no `# widget:` header: BAR_ITEM is read by barlib.sh (SC2034)
modules/bar/sketchybar/plugins/page.sh	barlib shape with no `# widget:` header: BAR_ITEM is read by barlib.sh (SC2034)
modules/bar/sketchybar/plugins/media_stream.sh	barlib shape (BAR_ITEM, SC2034); not triaged: SC2207 at :125
test/bar-widget-glued.sh	fixture for the glued-header mistake: its `widget:` line deliberately fails to parse as a header, so the widget rule cannot see it
modules/bar/sketchybar/plugins/aerospace_watcher.sh	not triaged: SC2207 at :79 and :80
modules/launcher/commands/add-app.sh	not triaged: SC1111 (unicode quotes) at :378 and :458
modules/launcher/commands/links.sh	not triaged: SC2046 at :113
modules/launcher/commands/spawn-agent.sh	not triaged: SC2088 at :256, SC1111 at :415
modules/terminal/scripts/float-term.sh	not triaged: SC2034 (`i` unused) at :768
EOF
)

ci() { [ "${GITHUB_ACTIONS:-}" = true ]; }

# `error <file> <message>`: one line, and a GitHub annotation on CI.
error() {
    if ci; then
        printf '::error file=%s::%s\n' "$1" "$2"
    else
        printf 'error: %s: %s\n' "$1" "$2" >&2
    fi
}

# Every file the census is about, in the order `run` runs them.
candidates() {
    local f
    for f in test/*.bats test/*.sh; do
        [ -e "$f" ] && printf '%s\n' "$f"
    done | sort
}

# `parse <file>` sets KIND (suite | not-a-suite), JOB and NEEDS (space
# separated), or sets PARSE_ERR to why it cannot and returns 1. Globals, not
# stdout: a `$( )` would parse in a subshell and lose all four.
parse() {
    local f=$1 all top body tok need
    KIND='' JOB='' NEEDS='' PARSE_ERR=''
    all=$(grep -cE '^# (suite|not-a-suite):' "$f" || true)
    top=$(head -n 5 "$f" | grep -E '^# (suite|not-a-suite):' || true)
    if [ "$all" -eq 0 ]; then
        PARSE_ERR="no header: add '# suite: job=<job>' (or '# not-a-suite: <why>') in its first five lines"
        return 1
    fi
    if [ "$all" -gt 1 ]; then
        PARSE_ERR="$all headers: a file has exactly one"
        return 1
    fi
    if [ -z "$top" ]; then
        PARSE_ERR="its header is below line five, where nothing reads it as a header"
        return 1
    fi
    case $top in
    '# not-a-suite:'*)
        body=${top#'# not-a-suite:'}
        [ -n "${body// /}" ] || {
            PARSE_ERR="'# not-a-suite:' needs a reason after the colon"
            return 1
        }
        case $f in
        *.bats)
            PARSE_ERR="a .bats file is always a suite"
            return 1
            ;;
        esac
        KIND=not-a-suite
        return 0
        ;;
    esac
    KIND=suite
    body=${top#'# suite:'}
    for tok in $body; do
        case $tok in
        job=*) JOB=${tok#job=} ;;
        needs=*)
            for need in $(printf '%s' "${tok#needs=}" | tr ',' ' '); do
                case $KNOWN_NEEDS in
                *" $need "*) NEEDS="$NEEDS $need" ;;
                *)
                    PARSE_ERR="unknown need '$need' (known:$KNOWN_NEEDS)"
                    return 1
                    ;;
                esac
            done
            ;;
        *)
            PARSE_ERR="unknown field '$tok' in its header (fields: job=, needs=)"
            return 1
            ;;
        esac
    done
    if ! printf '%s' "$JOB" | grep -qE '^[a-z][a-z0-9_-]*$'; then
        PARSE_ERR="its header names no job (job=<job>)"
        return 1
    fi
}

# `<job><TAB><job it runs>` for every runner step in the workflow: which job
# the step sits in, and which job's suites it asks for. Comment lines are
# skipped, so prose that quotes the command is not a step.
runner_steps() {
    awk '
        /^jobs:/ { in_jobs = 1; next }
        in_jobs && /^  [a-z][a-z0-9_-]*:[[:space:]]*$/ {
            job = $1; sub(/:$/, "", job)
        }
        /^[[:space:]]*#/ { next }
        match($0, /test\/ci\.sh run [a-z0-9_-]+/) {
            s = substr($0, RSTART, RLENGTH); sub(/.* run /, "", s)
            print job "\t" s
        }
    ' "$WORKFLOW"
}

cmd_census() {
    local f bad=0 steps suites=0 skipped=0 job step_job
    local jobs_used=''
    steps=$(runner_steps)
    while IFS= read -r f; do
        if ! parse "$f"; then
            error "$f" "$PARSE_ERR"
            bad=1
            continue
        fi
        if [ "$KIND" = not-a-suite ]; then
            skipped=$((skipped + 1))
            continue
        fi
        suites=$((suites + 1))
        jobs_used="$jobs_used $JOB"
        if ! printf '%s\n' "$steps" | grep -qx "$JOB	$JOB"; then
            error "$f" "names job '$JOB', and no job of that name in $WORKFLOW has a 'bash test/ci.sh run $JOB' step, so nothing would ever run it"
            bad=1
        fi
    done < <(candidates)

    # A .bats anywhere else is a suite the glob above cannot see.
    while IFS= read -r f; do
        case $f in
        test/*/*) ;;
        test/*) continue ;;
        esac
        error "$f" "a suite outside test/'s top level, where test/ci.sh never looks"
        bad=1
    done < <(git ls-files '*.bats' 2>/dev/null || find . -name '*.bats' -not -path './.git/*' | sed 's|^\./||')

    while IFS='	' read -r step_job job; do
        [ -n "$job" ] || continue
        if [ "$step_job" != "$job" ]; then
            error "$WORKFLOW" "the '$step_job' job runs 'test/ci.sh run $job'; a job runs its own suites, so rename one or the other"
            bad=1
        fi
        case " $jobs_used " in
        *" $job "*) ;;
        *)
            error "$WORKFLOW" "'test/ci.sh run $job' runs nothing: no suite in test/ names job=$job"
            bad=1
            ;;
        esac
    done <<<"$steps"

    [ "$bad" -eq 0 ] || return 1
    printf 'census: %d suites, each run by a job; %d helpers marked not-a-suite\n' "$suites" "$skipped"
}

cmd_run() {
    local want=${1:?usage: test/ci.sh run <job>} f need start secs rc
    local failed='' ran=0 rows='' problem
    while IFS= read -r f; do
        # A file the census would refuse is the lint job's to report; this
        # job only runs what it can read.
        parse "$f" || continue
        [ "$KIND" = suite ] && [ "$JOB" = "$want" ] || continue
        ran=$((ran + 1))

        problem=''
        for need in $NEEDS; do
            case $need in
            painter)
                if [ -z "${HAUS_UI_SH:-}" ]; then
                    problem="needs=painter, but HAUS_UI_SH is unset"
                elif [ ! -r "$HAUS_UI_SH" ]; then
                    problem="needs=painter, but HAUS_UI_SH ($HAUS_UI_SH) is unreadable"
                fi
                [ -z "$problem" ] ||
                    problem="$problem; put \"snug's painter, at the pinned rev\" in the '$want' job ahead of the runner"
                ;;
            nix)
                command -v nix >/dev/null 2>&1 ||
                    problem="needs=nix, but no nix is on PATH in the '$want' job"
                ;;
            esac
            [ -z "$problem" ] || break
        done

        if ci; then printf '::group::%s\n' "$f"; else printf '── %s\n' "$f"; fi
        start=$SECONDS
        if [ -n "$problem" ]; then
            rc=1
            echo "$problem"
        else
            rc=0
            case $f in
            *.bats) bats "$f" || rc=$? ;;
            *) bash "$f" || rc=$? ;;
            esac
        fi
        secs=$((SECONDS - start))
        if ci; then printf '::endgroup::\n'; fi

        if [ "$rc" -eq 0 ]; then
            rows="$rows$(printf 'ok      %4ss  %s' "$secs" "$f")"$'\n'
        else
            rows="$rows$(printf 'FAILED  %4ss  %s' "$secs" "$f")"$'\n'
            failed="$failed $f"
            error "$f" "${problem:-exited $rc}"
        fi
    done < <(candidates)

    if [ "$ran" -eq 0 ]; then
        error "$WORKFLOW" "no suite in test/ names job=$want"
        return 1
    fi
    printf '\n%s' "$rows"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
        {
            printf '### suites in `%s`\n\n```\n%s```\n' "$want" "$rows"
        } >>"$GITHUB_STEP_SUMMARY"
    fi
    if [ -n "$failed" ]; then
        printf '\n%d of %d failed:%s\n' "$(printf '%s' "$failed" | wc -w | tr -d ' ')" "$ran" "$failed"
        return 1
    fi
    printf '\nall %d suites in %s passed\n' "$ran" "$want"
}

cmd_lint() {
    local sc=${SHELLCHECK:-shellcheck} f reason tracked bad=0
    local lint=() by_zsh=0 by_widget=0 by_name=0
    "$sc" --version | sed -n 2p
    tracked=$(git ls-files '*.sh' | sort)

    while IFS='	' read -r f reason; do
        [ -n "$f" ] || continue
        if ! printf '%s\n' "$tracked" | grep -qxF "$f"; then
            error "$f" "is excluded from the lint by name but is not a tracked file; delete its line in test/ci.sh"
            bad=1
        elif "$sc" --severity=warning "$f" >/dev/null 2>&1; then
            error "$f" "passes shellcheck now, so its exclusion ($reason) is stale; delete its line in test/ci.sh"
            bad=1
        fi
    done <<<"$EXCLUDE"

    while IFS= read -r f; do
        if printf '%s\n' "$EXCLUDE" | cut -f1 | grep -qxF "$f"; then
            by_name=$((by_name + 1))
        elif head -n 1 "$f" | grep -q 'zsh'; then
            by_zsh=$((by_zsh + 1))
        elif grep -q '^# widget:' "$f"; then
            by_widget=$((by_widget + 1))
        else
            lint+=("$f")
        fi
    done <<<"$tracked"

    printf 'lint: %d files; excluded %d zsh, %d widgets, %d by name\n' \
        "${#lint[@]}" "$by_zsh" "$by_widget" "$by_name"
    "$sc" --severity=warning "${lint[@]}" || bad=1
    [ "$bad" -eq 0 ]
}

case ${1:-} in
run)
    shift
    cmd_run "$@"
    ;;
census) cmd_census ;;
lint) cmd_lint ;;
*)
    echo "usage: test/ci.sh run <job> | census | lint" >&2
    exit 2
    ;;
esac
