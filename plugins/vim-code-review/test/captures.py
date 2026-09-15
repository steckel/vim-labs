from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('captures: PASS (settings, preview, frozen recovery, original drafts/source, live history)')
