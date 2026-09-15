from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
print('reader resize: PASS (deferred hidden layout, exact return, native tab return, data refresh)')
