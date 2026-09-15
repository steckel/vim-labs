from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
print('readiness: PASS (read-only routes, paging, cancellation, stale/malformed reads, exact return, custom maps, draft retention)')
