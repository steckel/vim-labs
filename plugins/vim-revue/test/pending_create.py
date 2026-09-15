from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=3)
print('pending creation: PASS (start/first comment, private line/file saves, publication exclusion, restart recovery)')
