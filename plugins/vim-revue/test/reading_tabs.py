from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
print('reading tabs: PASS (whole-area views, exact return, actual Insert mode during hidden refresh, user splits and cleanup)')
