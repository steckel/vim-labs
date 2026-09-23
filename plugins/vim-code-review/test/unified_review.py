"""The public :Review command must use durable cards for Git and jj alike."""
from contextlib import closing
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('review_capture', ROOT / 'python/revue_local.py')
local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local)


class UnifiedReviewTest(unittest.TestCase):
    def exercise(self, backend):
        if backend != 'git' and not shutil.which('jj'):
            self.skipTest('jj is not installed')
        with tempfile.TemporaryDirectory(prefix='review-unified-') as tmp:
            root = Path(tmp)
            repo = root / 'repo'
            repo.mkdir()
            def run(*args):
                return subprocess.run(args, cwd=repo, capture_output=True, text=True, check=True).stdout
            if backend == 'jj':
                run('jj', 'git', 'init')
            else:
                run('git', 'init', '-q', '-b', 'main')
                run('git', 'config', 'user.name', 'Review Test')
                run('git', 'config', 'user.email', 'review@example.invalid')
            original = ['old one', 'old two', 'old three', 'old four', 'old five']
            changed = ['new one', 'new two', 'new three', 'new four', 'new five']
            (repo / 'example.py').write_text('\n'.join(original) + '\n')
            if backend == 'jj':
                run('jj', 'new')
            else:
                run('git', 'add', '.')
                run('git', 'commit', '-qm', 'base')
                if backend == 'colocated':
                    run('jj', 'git', 'init', '--colocate')
            (repo / 'example.py').write_text('\n'.join(changed) + '\n')
            (repo / 'nested').mkdir()
            config = {'original': original, 'changed': changed}
            (root / 'config.json').write_text(json.dumps(config))
            for phase in ['create', 'resume', 'saved']:
                result = subprocess.run(['vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-S', str(ROOT / 'test/unified_review.vim')],
                                        cwd=repo / 'nested', env=dict(os.environ, REVIEW_UNIFIED_DIR=tmp, REVIEW_UNIFIED_PHASE=phase),
                                        capture_output=True, text=True, timeout=30)
                errors = (root / 'errors').read_text() if (root / 'errors').exists() else result.stdout + result.stderr
                self.assertEqual(0, result.returncode, errors)
                self.assertEqual([], errors.splitlines())
                self.assertEqual('\n'.join(changed) + '\n', (repo / 'example.py').read_text())
            # Retained content can be reopened without rereading the changed workspace.
            review = (root / 'review').read_text().strip()
            with closing(local.LocalBackend(root / 'store')) as store:
                data = store.load(review)
                self.assertEqual('git' if backend == 'git' else 'jj', data['vcs'])
                self.assertEqual(original, data['contents'][data['snapshot']['files'][0]['id']]['base']['lines'])
                (repo / 'example.py').write_text('changed after review\n')
                reopened = store.request({'op': 'open', 'review': review})
                self.assertEqual(data['snapshot']['snapshot'], reopened['snapshot']['snapshot'])
                # A recapture stays in the same VCS and keeps the original baseline.
                draft = {'id': local.identity(), 'kind': 'capture', 'body': '', 'untracked': False,
                         **{k: data['snapshot'][k] for k in ('head', 'base_tip', 'snapshot')}}
                receipt = store.request({'op': 'mutate', 'review': review, 'draft': draft})
                self.assertTrue(receipt['changed'])
                captured = store.load(review)
                self.assertEqual(data['vcs'], captured['vcs'])
                self.assertEqual(data['snapshot']['base'], captured['snapshot']['base'])
                self.assertNotEqual(data['snapshot']['snapshot'], captured['snapshot']['snapshot'])
                retained = store.request({'op': 'file', 'review': review, 'snapshot': data['snapshot'],
                                          'file': data['snapshot']['files'][0]})
                self.assertEqual(changed, retained['head']['lines'])

    def test_git(self):
        self.exercise('git')

    def test_jj(self):
        self.exercise('jj')

    def test_colocated_prefers_jj(self):
        self.exercise('colocated')

    @unittest.skipUnless(shutil.which('jj'), 'jj is not installed')
    def test_jj_capture_types_paths_and_pinned_content(self):
        with tempfile.TemporaryDirectory(prefix='review-jj-types-') as tmp:
            root = Path(tmp)
            def run(*args):
                return subprocess.run(['jj', *args], cwd=root, capture_output=True, text=True, check=True).stdout
            run('git', 'init')
            names = ['braces {x} and space.py', 'glob[1]*.py', 'pipe|name.py', 'quote"name.py', 'unicode雪.py', 'newline\nname.py']
            for name in names:
                (root / name).write_text('original content\n')
            (root / 'link').symlink_to('original-target')
            run('new')
            for name in names:
                (root / name).write_text('changed content\n')
            (root / 'link').unlink()
            (root / 'link').symlink_to('new-target')
            (root / 'binary').write_bytes(b'\0binary')
            captured = local.capture({'cwd': tmp})
            self.assertEqual(set(names + ['link', 'binary']), {f['path'] for f in captured['snapshot']['files']})
            by_path = {f['path']: captured['contents'][f['id']] for f in captured['snapshot']['files']}
            for name in names:
                self.assertEqual(['original content'], by_path[name]['base']['lines'])
                self.assertEqual(['changed content'], by_path[name]['head']['lines'])
            self.assertEqual('unavailable', by_path['link']['head']['kind'])
            self.assertIn('symlink', by_path['link']['head']['message'])
            self.assertEqual('binary', by_path['binary']['head']['kind'])
            self.assertEqual('absent', by_path['binary']['base']['kind'])
            with self.assertRaisesRegex(ValueError, 'exactly one'):
                local.capture({'cwd': tmp, 'base': '@ | @-'})
            with self.assertRaises(ValueError):
                local.capture({'cwd': tmp, 'base': 'missing-revision'})


if __name__ == '__main__':
    unittest.main()
