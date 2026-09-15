from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
print('feedback lookup: PASS (exact target, whole thread, paging overlap/cycles, coverage, cancellation, focus, stale responses)')
