from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('comparisons: PASS (explicit revision switch, immutable drafts, origin return, cache/generation isolation, restart)')
