from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('history: PASS (backend inventory, persisted references/views, restart retrieval, identity, failed/stale async results)')
