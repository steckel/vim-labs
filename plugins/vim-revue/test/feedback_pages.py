from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
run(Path(__file__).with_name('github_feedback.vim'))
print('feedback pages: PASS (continuation, exact selection, cancellation, stale/malformed reads, deduplication, search, retained typing)')
