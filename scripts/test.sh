#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
component="${1:-all}"

case "$component" in
  all|revue|reviewhub|mcp) ;;
  *) echo 'Usage: scripts/test.sh [all|revue|reviewhub|mcp]' >&2; exit 2 ;;
esac

if [ "$component" = all ] || [ "$component" = revue ]; then
  (cd "$root/plugins/vim-revue" && sh test/run.sh && python3 test/regressions.py)
fi
if [ "$component" = all ] || [ "$component" = reviewhub ]; then
  (cd "$root/plugins/vim-reviewhub" && python3 -m unittest discover -s test -p 'test_*.py' && python3 test/run_integration.py)
fi
if [ "$component" = all ] || [ "$component" = mcp ]; then
  (cd "$root/plugins/vim9-mcp" && npm run check && npm test)
fi
