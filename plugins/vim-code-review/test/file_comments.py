from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('file comments: PASS (file targets, cards, binary/deleted/unavailable, replies, preview, restart)')
