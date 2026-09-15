from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
print('thread entry: PASS (exact thread, quote/preview/return, custom keys, chooser refresh and navigation races)')
