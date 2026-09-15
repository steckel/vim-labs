from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('published deletion: PASS (exact reply, scope, preview, permission/stale checks, frozen restart recovery)')
