from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('edits: PASS (exact replies, before/current/proposed, conflicts, permissions, restart receipts)')
