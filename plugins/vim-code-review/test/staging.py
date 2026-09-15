from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=4)
print('private staging: PASS (new/existing reviews, mixed items, partial saves, exact receipts, safe unpack, four-process recovery, disk failure, publication isolation)')
