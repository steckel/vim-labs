from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('private deletion: PASS (exact reply, preview, stale body, permissions, isolation, restart recovery)')
