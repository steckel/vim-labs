from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('links: PASS (body URLs, copy/open, cancellation, stale targets, view retention)')
