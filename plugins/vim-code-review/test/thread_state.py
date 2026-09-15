from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2,
    forbidden=(b'(R)esolve, [K]eep draft:', b'(R)eopen, [K]eep draft:'))
print('thread state: PASS (in-place actions, no confirmation, targeting, permissions, Insert mode, failure, restart recovery)')
