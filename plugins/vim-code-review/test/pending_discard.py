from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('pending discard: PASS (full preview, conflicts, explicit deletion, isolation, restart recovery)')
