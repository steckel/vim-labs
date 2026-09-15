from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
from vim_pty import run

run(Path(__file__).with_suffix('.vim'), repeat=2)
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='revue-range-backend-') as directory:
    tmp = Path(directory)
    repo = tmp / 'repo'
    repo.mkdir()
    def git(*args):
        subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True)
    def backend(request):
        result = subprocess.run([sys.executable, str(root / 'python/revue_local.py'), '--store', str(tmp / 'store')],
                                input=json.dumps(request), text=True, capture_output=True, check=True)
        response = json.loads(result.stdout)
        assert response['ok'], response
        return response['data']
    git('init', '-q')
    git('config', 'user.name', 'Range fixture')
    git('config', 'user.email', 'range@example.invalid')
    (repo / 'code.py').write_text('one\nbase\nthree\n')
    git('add', '.')
    git('commit', '-qm', 'Base')
    (repo / 'code.py').write_text('one\nfirst\nthree\n')
    first = backend({'op': 'create', 'cwd': str(repo), 'base': 'HEAD'})
    (repo / 'code.py').write_text('one\nsecond\nthree\n')
    backend({'op': 'mutate', 'review': first['review'], 'draft': {'id': 'capture-second', 'kind': 'capture', 'body': '',
             'untracked': False, **{k: first['snapshot'][k] for k in ('snapshot', 'head', 'base_tip')}}})
    second = backend({'op': 'refresh', 'review': first['review']})
    fixture = tmp / 'fixture.json'
    fixture.write_text(json.dumps({'first': first['snapshot'], 'second': second, 'review': first['review'],
                                   'connection': first['connection'], 'store': str(tmp / 'store')}))
    os.environ['REVUE_RANGE_FIXTURE'] = str(fixture)
    run(Path(__file__).with_name('ranges_local.vim'), repeat=2)
print('ranges: PASS (endpoint selection, backend identity, original drafts/replies, late responses, cancellation, restart)')
