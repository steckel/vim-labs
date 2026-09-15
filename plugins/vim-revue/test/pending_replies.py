from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('pending replies: PASS (private/public intent, quote preservation, permissions, exact receipts, restart recovery)')
