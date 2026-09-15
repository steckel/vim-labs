from pathlib import Path
from vim_pty import run
for dimensions in [(80, 24), (120, 40)]:
    run(Path(__file__).with_suffix('.vim'), repeat=2, dimensions=dimensions)
print('service progress: PASS (read/mark/unmark, local independence, exact source return, lost response/restart, stale data)')
