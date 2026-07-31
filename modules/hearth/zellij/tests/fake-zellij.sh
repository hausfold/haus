#!/bin/bash
set -euo pipefail

case " $* " in
    *" action list-panes "*) exec /bin/cat "$ZRELOAD_TEST_PANES" ;;
    *" action dump-layout "*) exec /bin/cat "$ZRELOAD_TEST_LAYOUT" ;;
    *) printf 'unexpected fake zellij invocation: %s\n' "$*" >&2; exit 2 ;;
esac
