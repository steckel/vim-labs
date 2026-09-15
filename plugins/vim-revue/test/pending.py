from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('pending: PASS (private inventory, exact comments, publish preview, changed contents, restart recovery)')
