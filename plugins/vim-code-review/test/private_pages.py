import json
import os
from pathlib import Path
import tempfile
from private_pages_provider import profile
from vim_pty import run
with tempfile.TemporaryDirectory(prefix='revue-private-page-fixture-') as directory:
    fixture = Path(directory) / 'private.json'
    fixture.write_text(json.dumps(profile()))
    os.environ['REVUE_PRIVATE_FIXTURE'] = str(fixture)
    run(Path(__file__).with_suffix('.vim'))
    run(Path(__file__).with_name('private_pages_bridge.vim'))
    run(Path(__file__).with_name('private_pages_restart.vim'), repeat=2)
print('private pages: PASS (actual adapter projection, complete threads, coverage, full-review gates, verification/cancel/stale reads, exact targets, bridge)')
