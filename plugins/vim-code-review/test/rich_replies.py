from pathlib import Path
from vim_pty import run
run(Path(__file__).with_suffix('.vim'))
print('rich replies: PASS (inline spans, semantic links, exact attributed quotes, raw copy, Unicode, widths)')
