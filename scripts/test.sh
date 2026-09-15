#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
component="${1:-all}"

# Retain the original test aliases for existing development scripts.
case "$component" in
  revue) component=review ;;
  reviewhub) component=github ;;
esac

case "$component" in
  all|install|review|github|mcp) ;;
  *) echo 'Usage: scripts/test.sh [all|install|review|github|mcp]' >&2; exit 2 ;;
esac

if [ "$component" = all ] || [ "$component" = install ]; then
  (cd "$root" && python3 -m unittest discover -s test -p 'test_*.py')
fi
if [ "$component" = all ] || [ "$component" = review ]; then
  (cd "$root/plugins/vim-code-review" && sh test/run.sh && python3 test/regressions.py)
fi
if [ "$component" = all ] || [ "$component" = github ]; then
  (cd "$root/plugins/vim-code-review-github" && python3 -m unittest discover -s test -p 'test_*.py' && python3 test/run_integration.py)
fi
if [ "$component" = all ] || [ "$component" = mcp ]; then
  (cd "$root/plugins/vim9-mcp" && npm run check && npm test)
fi
