from pathlib import Path
import json
import os
from vim_pty import run

for settings in [(80, 24, 1), (120, 40, 1), (120, 24, 1), (80, 24, 0)]:
    os.environ['REVUE_INITIAL_SETTINGS'] = json.dumps(settings)
    run(Path(__file__).with_suffix('.vim'), dimensions=settings[:2])
print('initial layout: PASS (single final-width render, delayed/error delivery, focus preference, restored panes)')
