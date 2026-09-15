from pathlib import Path
from vim_pty import run
run(Path(__file__).with_suffix('.vim'), repeat=2)
run(Path(__file__).with_name('reanchor_edges.vim'))
print('reanchor: PASS (explicit target, unchanged text, frozen/private guards, refresh, persistence rollback, restart)')
