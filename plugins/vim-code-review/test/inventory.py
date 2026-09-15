from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
print('inventory: PASS (coverage states, partial search, refresh failure/retry, exact selection, draft retention)')
