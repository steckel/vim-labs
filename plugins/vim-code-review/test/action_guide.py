from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
run(Path(__file__).with_name('navigation_guide.vim'))
print('action guide: PASS (delivery, permissions, exact messages, comparison/original navigation, local Viewed, unavailable source, refresh during menus, custom mappings)')
