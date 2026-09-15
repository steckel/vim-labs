from pathlib import Path
import json
import os
import fcntl
import sys
import subprocess
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'python'))
import revue_apply as apply
import local_backend as fixtures
local = fixtures.local


class ApplicationTest(unittest.TestCase):
    setUp = fixtures.LocalBackendTest.setUp
    git = fixtures.LocalBackendTest.git
    draft = fixtures.LocalBackendTest.draft
    mutate = fixtures.LocalBackendTest.mutate
    snapshot_now = fixtures.LocalBackendTest.snapshot_now

    def proposal(self, body='```suggestion\nbetter λ\n```'):
        thread = self.mutate(self.draft(body=body))['id']
        snapshot = self.snapshot_now()
        message = next(t for t in snapshot['threads'] if t['id'] == thread)['comments'][0]
        request = {'op': 'suggestion_plan', 'review': self.review,
                   'reference': {k: snapshot[k] for k in ('snapshot', 'base', 'head', 'base_tip')},
                   'target': {'thread': thread, 'message': message['id'], 'message_kind': 'comment', 'expected_version': message['version']}}
        return dict(self.backend.request(request), id=local.identity(), state='draft'), request

    def test_apply_capture_receipt_restart_and_no_commit(self):
        before_head = self.git('rev-parse', 'HEAD').stdout
        before_index = self.git('diff', '--cached', '--raw').stdout
        draft, _ = self.proposal()
        result = self.mutate(draft)
        self.assertTrue(result['applied'])
        self.assertFalse(result['observed'])
        self.assertEqual('one\nbetter λ\nthree\n', (self.repo / 'code.py').read_text())
        self.assertEqual(before_head, self.git('rev-parse', 'HEAD').stdout)
        self.assertEqual(before_index, self.git('diff', '--cached', '--raw').stdout)
        snapshot = self.snapshot_now()
        self.assertEqual(result['result_snapshot'], snapshot['snapshot'])
        self.assertFalse(snapshot['threads'][0]['resolved'])
        self.assertTrue(snapshot['threads'][0]['outdated'])
        self.assertEqual('Applied to workspace', snapshot['threads'][0]['comments'][0]['suggestion_application']['label'])
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        self.addCleanup(self.backend.close)
        (self.repo / 'code.py').write_text('later human edit\n')
        self.assertTrue(self.mutate(draft, reconcile=True)['recovered'])
        self.assertEqual('later human edit\n', (self.repo / 'code.py').read_text())
        with self.assertRaisesRegex(ValueError, 'different preview'):
            self.mutate(dict(draft, replacement=['different']))

    def test_stale_message_file_path_and_preview_make_no_edits(self):
        draft, request = self.proposal()
        original = (self.repo / 'code.py').read_bytes()
        for key, value in [('path', '../escape'), ('workspace', str(self.root)), ('replacement', ['forged']), ('start', 1), ('before_hash', 'bad')]:
            with self.assertRaises(ValueError):
                self.mutate(dict(draft, id=local.identity(), **{key: value}))
            self.assertEqual(original, (self.repo / 'code.py').read_bytes())
        (self.repo / 'code.py').write_text('changed outside selected line\nnew\nthree\n')
        with self.assertRaisesRegex(ValueError, 'differs from'):
            self.mutate(draft)
        (self.repo / 'code.py').write_bytes(original)
        self.mutate(self.draft(kind='edit', message=draft['message'], message_kind='comment', thread=draft['thread'], expected_version=draft['expected_version'], original_body=draft['original_body'], body='```suggestion\nchanged\n```'))
        with self.assertRaisesRegex(ValueError, 'message changed'):
            self.backend.request(request)
        self.assertEqual(original, (self.repo / 'code.py').read_bytes())

    def test_crash_before_and_after_replace_never_reapplies(self):
        draft, _ = self.proposal()
        with patch.object(apply.LocalApplications, 'install', side_effect=OSError('before replace')):
            with self.assertRaises(apply.ApplicationUnknown):
                self.mutate(draft)
        with patch.object(apply.LocalApplications, 'install', side_effect=AssertionError('must not write')):
            receipt = self.mutate(draft, reconcile=True)
        self.assertFalse(receipt['applied'])
        self.assertTrue(receipt['observed'])
        original_install = apply.LocalApplications.install
        def installed_then_crash(*args):
            original_install(*args)
            raise OSError('after replace')
        draft['id'] = local.identity()
        with patch.object(apply.LocalApplications, 'install', side_effect=installed_then_crash):
            with self.assertRaises(apply.ApplicationUnknown):
                self.mutate(draft)
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        self.addCleanup(self.backend.close)
        with patch.object(apply.LocalApplications, 'install', side_effect=AssertionError('must not write')):
            receipt = self.mutate(draft, reconcile=True)
        self.assertTrue(receipt['applied'])
        self.assertTrue(receipt['observed'])
        self.assertTrue(receipt['result_snapshot'])

    def test_symlink_hardlink_and_changed_during_install_rejected(self):
        draft, _ = self.proposal()
        file = self.repo / 'code.py'
        original = file.read_bytes()
        outside = self.root / 'outside'
        outside.write_bytes(original)
        file.unlink()
        file.symlink_to(outside)
        with self.assertRaises(OSError):
            self.mutate(draft)
        file.unlink()
        os.link(outside, file)
        with self.assertRaises(ValueError):
            self.mutate(draft)
        file.unlink()
        file.write_bytes(original)
        real_read = apply.read_file
        def changed(directory, name):
            if list(self.repo.glob('.revue-suggestion-*')):
                file.write_text('concurrent human edit\n')
            return real_read(directory, name)
        with patch.object(apply, 'read_file', side_effect=changed):
            with self.assertRaises(apply.ApplicationUnknown):
                self.mutate(draft)
        self.assertEqual('concurrent human edit\n', file.read_text())
        self.assertEqual(original, outside.read_bytes())
        with self.assertRaises(apply.ApplicationUnknown):
            self.mutate(draft, reconcile=True)
        self.assertFalse(list(self.repo.glob('.revue-suggestion-*')))

    def test_newline_deletion_quotes_and_mode(self):
        for raw, start, end, lines, expected in [
            (b'a\r\nb\r\nc\r\n', 2, 2, ['x', 'y'], b'a\r\nx\r\ny\r\nc\r\n'),
            (b'a\nb', 2, 2, ['x'], b'a\nx'),
            (b'a\nb\n', 2, 2, [], b'a\n'),
            (b'a\n', 1, 1, [], b''),
            (b'a', 1, 1, [''], b''),
        ]:
            self.assertEqual(expected, apply.replace_lines(raw, start, end, lines)[0])
        for body in ['> ```suggestion\n> no\n> ```', '````\n```suggestion\nquoted\n```\n````', '```suggestion\nnot closed', '```suggestion\nx\n```\n```suggestion\ny\n```']:
            with self.assertRaises(ValueError):
                apply.replacement(body)
        (self.repo / 'code.py').chmod(0o755)
        if sys.platform == 'darwin':
            subprocess.run(['xattr', '-w', 'com.revue.test', 'retained', str(self.repo / 'code.py')], check=True)
        elif hasattr(os, 'setxattr'):
            os.setxattr(self.repo / 'code.py', 'user.revue.test', b'retained')
        draft, _ = self.proposal()
        self.mutate(draft)
        self.assertEqual(0o755, (self.repo / 'code.py').stat().st_mode & 0o777)
        if sys.platform == 'darwin':
            self.assertEqual(b'retained', subprocess.check_output(['xattr', '-p', 'com.revue.test', str(self.repo / 'code.py')]).strip())
        elif hasattr(os, 'getxattr'):
            self.assertEqual(b'retained', os.getxattr(self.repo / 'code.py', 'user.revue.test'))

    def test_vim_preview_unsaved_guard_and_receipt_restart(self):
        from vim_pty import run
        draft, _ = self.proposal()
        config = self.backend.request({'op': 'open', 'review': self.review})
        config.update(store=str(self.store), workspace=str(self.repo), thread=draft['thread'])
        path = self.root / 'application-config.json'
        path.write_text(json.dumps(config))
        before_head = self.git('rev-parse', 'HEAD').stdout
        with patch.dict(os.environ, REVUE_APPLY_CONFIG=str(path)):
            run(Path(__file__).with_name('apply_suggestion.vim'), repeat=2)
        self.assertEqual('one\nbetter λ\nthree\n', (self.repo / 'code.py').read_text())
        self.assertEqual(before_head, self.git('rev-parse', 'HEAD').stdout)

    def test_receipt_transaction_failure_after_write_is_recoverable(self):
        draft, _ = self.proposal()
        self.backend.db.execute("CREATE TRIGGER fail_application BEFORE INSERT ON receipts WHEN NEW.operation = '" + draft['id'] + "' BEGIN SELECT RAISE(ABORT, 'receipt storage failed'); END")
        with self.assertRaises(apply.ApplicationUnknown):
            self.mutate(draft)
        self.assertEqual('one\nbetter λ\nthree\n', (self.repo / 'code.py').read_text())
        self.assertEqual(draft['snapshot'], self.snapshot_now()['snapshot'])
        self.backend.db.execute('DROP TRIGGER fail_application')
        receipt = self.mutate(draft, reconcile=True)
        self.assertTrue(receipt['applied'])
        self.assertTrue(receipt['observed'])
        self.assertNotEqual(draft['snapshot'], receipt['result_snapshot'])

    def test_capture_failure_does_not_hide_successful_file_application(self):
        draft, _ = self.proposal()
        with patch.object(self.backend, '_mutate', side_effect=OSError('capture unavailable')):
            receipt = self.mutate(draft)
        self.assertTrue(receipt['applied'])
        self.assertEqual('', receipt['result_snapshot'])
        self.assertEqual('capture unavailable', receipt['capture_error'])
        self.assertEqual('one\nbetter λ\nthree\n', (self.repo / 'code.py').read_text())
        self.assertEqual(draft['snapshot'], self.snapshot_now()['snapshot'])
        self.assertTrue(self.mutate(draft, reconcile=True)['recovered'])

    def test_busy_application_and_no_intent_recovery_do_not_write(self):
        draft, _ = self.proposal()
        with open(self.store / '.suggestion-application.lock', 'w') as handle:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(apply.ApplicationUnknown, 'in progress'):
                self.mutate(draft)
        receipt = self.mutate(draft, reconcile=True)
        self.assertFalse(receipt['applied'])
        self.assertTrue(receipt['observed'])
        self.assertEqual('one\nnew\nthree\n', (self.repo / 'code.py').read_text())
        self.assertFalse(self.mutate(draft)['applied'], 'A settled no-write operation cannot later mutate')


if __name__ == '__main__':
    unittest.main()
