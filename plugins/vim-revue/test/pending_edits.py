from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('pending edits: PASS (private summary/reply, preview, publication guard, conflicts, restart receipts)')
