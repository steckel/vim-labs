from pathlib import Path
from vim_pty import run
run(Path(__file__).with_suffix('.vim'))
run(Path(__file__).with_name('refresh_restart.vim'), repeat=2)
print('bounded refresh: PASS (page budget, retained inventory/typing/selection, cancellation, stale and malformed reads, retry, removals, new comparison)')
