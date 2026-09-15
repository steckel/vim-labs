from pathlib import Path
from vim_pty import run
run(Path(__file__).with_suffix('.vim'))
print('unchanged refresh: PASS (no rich-buffer rebuild, current status, changed body/permissions still repaint, draft retention)')
