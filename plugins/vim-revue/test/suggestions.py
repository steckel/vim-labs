from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('suggestions: PASS (selection, seed, reuse, validation, preview, permission/staleness, receipt restart)')
