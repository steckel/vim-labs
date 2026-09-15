from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('original context: PASS (verified target, exact return, failed/malformed/stale reads, draft retention, restart)')
