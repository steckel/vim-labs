"""Move recognition and rendering, including real Git/jj working-copy diffs."""
import difflib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
BLOCK = ['def relocated_function(value):', '    return value + important_constant', '']
STAY = [f'unchanged_statement_{i} = {i}' for i in range(15)]


def file(path, before, after, old_path=None):
    return {'id': path, 'path': path, 'old_path': old_path or path,
            'status': 'modified', 'patch': '\n'.join(difflib.unified_diff(before, after, n=3, lineterm='')),
            'before': before, 'after': after}


def run_vim(fixture, mode='', cwd=None):
    with tempfile.TemporaryDirectory() as tmp:
        fixture_path = Path(tmp) / 'fixture.json'
        fixture_path.write_text(json.dumps(fixture))
        errors = Path(tmp) / 'errors'
        env = dict(os.environ, REVIEW_MOVES_FIXTURE=str(fixture_path), REVIEW_MOVES_ERRORS=str(errors),
                   REVIEW_MOVES_MODE=mode, REVIEW_MOVES_TMP=tmp)
        result = subprocess.run(['vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-S', str(ROOT / 'test/moves.vim')],
                                cwd=cwd, env=env, capture_output=True, text=True, timeout=45)
        assert result.returncode == 0, (errors.read_text() if errors.exists() else result.stdout + result.stderr)


same = file('same.py', BLOCK + STAY, STAY + BLOCK)
source = file('source.py', BLOCK + STAY, STAY)
target = file('target.py', STAY, STAY + BLOCK)
# No source deletion => a copy must remain an addition.
copy = file('copy.py', BLOCK + STAY, BLOCK + STAY + BLOCK)
edit = file('edit.py', BLOCK + STAY, ['def different_function(value):', '    return something_else', ''] + STAY)
tiny = file('tiny.py', ['}', ''] + STAY, STAY + ['}', ''])
cases = [
    {'files': [same], 'count': 1, 'base': ['same.py', 1], 'head': ['same.py', 16]},
    {'files': [source, target], 'count': 1, 'base': ['source.py', 1], 'head': ['target.py', 16]},
    {'files': [copy], 'count': 0}, {'files': [edit], 'count': 0}, {'files': [tiny], 'count': 0},
    # Two identical removed blocks and one added block provide no unique seed.
    {'files': [source, dict(source, id='second.py', path='second.py', old_path='second.py'), target], 'count': 0},
    {'files': [], 'count': 0},
    {'files': [dict(source, patch='@@ -1 +1 @@\n-' + BLOCK[0] + '\n+' + BLOCK[0])], 'count': 0},
    # Optional hunk counts and no-final-newline records preserve coordinates.
    {'files': [dict(source, patch='@@ -1 +0,0 @@\n-' + BLOCK[0] + '\n\\ No newline at end of file'),
               dict(target, patch='@@ -0,0 +1 @@\n+' + BLOCK[0] + '\n\\ No newline at end of file')],
     'count': 1, 'base': ['source.py', 1], 'head': ['target.py', 1]},
]
run_vim({'cases': cases, 'files': [source, target]})

for backend in ['git', 'jj']:
    if not shutil.which(backend):
        print(f'moves: {backend} integration skipped (not installed)')
        continue
    with tempfile.TemporaryDirectory(prefix='review-moves-') as tmp:
        repo = Path(tmp)
        def command(*args):
            subprocess.run(args, cwd=repo, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        command('git', 'init', '-q')
        command('git', 'config', 'color.ui', 'always')
        command('git', 'config', 'user.name', 'Move Test')
        command('git', 'config', 'user.email', 'moves@example.invalid')
        for f in [source, target]:
            (repo / f['path']).write_text('\n'.join(f['before']) + '\n')
        command('git', 'add', '.')
        command('git', 'commit', '-qm', 'base')
        if backend == 'jj':
            command('jj', 'git', 'init', '--colocate')
        for f in [source, target]:
            (repo / f['path']).write_text('\n'.join(f['after']) + '\n')
        (repo / 'nested').mkdir()
        run_vim({'base': 'HEAD' if backend == 'git' else '@-', 'files': [source, target]}, backend, repo / 'nested')
print('moves: PASS (matching, cross-file labels, cards, source integrity, cleanup, Git/jj from subdirectory)')

# jj's human summary compresses rename paths with {old => new}. Review
# must use real source/target paths, including with spaces and braces.
if shutil.which('jj'):
    for edited in [False, True]:
        with tempfile.TemporaryDirectory(prefix='review-jj-rename-') as tmp:
            repo = Path(tmp)
            def command(*args):
                return subprocess.run(args, cwd=repo, check=True, capture_output=True, text=True).stdout
            command('git', 'init', '-q', '-b', 'main')
            command('git', 'config', 'user.name', 'Move Test')
            command('git', 'config', 'user.email', 'moves@example.invalid')
            old = "nested/old {source} 'name'.py"
            new = "nested/new {target} 'name'.py"
            (repo / 'nested').mkdir()
            before = BLOCK + STAY
            after = before.copy()
            if edited:
                after[1] = '    return value + changed_constant'
            (repo / old).write_text('\n'.join(before) + '\n')
            (repo / 'removed.py').write_text('this_file_will_be_removed = True\n')
            command('git', 'add', '.')
            command('git', 'commit', '-qm', 'base')
            command('jj', 'git', 'init', '--colocate')
            (repo / old).rename(repo / new)
            (repo / new).write_text('\n'.join(after) + '\n')
            summary = command('jj', 'diff', '--from', 'main', '--summary')
            if not summary.startswith('R '):
                print('moves: jj rename integration skipped (jj did not detect rename)')
                continue
            run_vim({'old': old, 'new': new, 'before': before, 'after': after,
                     'edited': edited}, 'jj_rename', repo / 'nested')
            (repo / 'removed.py').unlink()
            (repo / 'added.py').write_text('this_file_is_new = True\n')
            run_vim({'new': new, 'old': old}, 'jj_inventory', repo / 'nested')
    print('moves: PASS (jj rename paths, paired buffers, edits, default :Review from subdirectory)')
