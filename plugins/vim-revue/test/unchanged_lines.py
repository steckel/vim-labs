from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('unchanged lines: PASS (policies, exact ranges, received threads, native folds, drafts, restart)')
