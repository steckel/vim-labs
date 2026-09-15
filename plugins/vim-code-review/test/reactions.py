from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
print('reactions: PASS (counts/actor, exact targets, add/remove, delayed reads, frozen restart)')
