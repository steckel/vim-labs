from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), dimensions=(200, 50))
print('diff rendering: PASS (visible +/- signs, line colors, intraline emphasis, cards, moves, loading/failure cleanup, immutable source)')
