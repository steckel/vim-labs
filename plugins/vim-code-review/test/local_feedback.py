from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('local feedback: PASS (pending cards, edit/save/restart, selected/full Markdown, saved comments, non-destructive export)')
