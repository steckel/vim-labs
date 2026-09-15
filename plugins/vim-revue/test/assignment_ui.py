from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('assignment UI: PASS (selection, preview, stale targets, capability, exact receipt and restart recovery)')
