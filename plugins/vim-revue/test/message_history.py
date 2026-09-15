from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
print('message history: PASS (exact reply, paging, redaction, stale reads, cancellation, Help/return, retained drafts)')
