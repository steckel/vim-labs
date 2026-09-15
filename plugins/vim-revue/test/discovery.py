from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('discovery: PASS (filters, exact targets, refresh, drafts, Viewed revisions/restart, delayed reads)')
