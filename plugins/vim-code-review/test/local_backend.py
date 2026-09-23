"""Local backend contract and real Vim integration, entirely in temp directories."""
import concurrent.futures
import copy
import errno
import importlib.util
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("revue_local", ROOT / "python/revue_local.py")
local = importlib.util.module_from_spec(spec)
spec.loader.exec_module(local)


class LocalBackendTest(unittest.TestCase):
    def test_targeted_lookup_cost_and_complete_reply_after_restart(self):
        root = self.mutate(self.draft())['id']
        self.mutate(self.draft(kind='reply', thread=root, body='Complete reply'))
        data = json.loads(self.backend.db.execute('SELECT data FROM reviews WHERE id=?', (self.review,)).fetchone()[0])
        template = data['snapshot']['threads'][0]
        data['snapshot']['threads'] = []
        for n in range(501):
            thread = copy.deepcopy(template)
            thread['id'] = 'thread-' + str(n)
            thread['comments'][0]['id'] = thread['id']
            thread['comments'][1]['id'] = 'reply-' + str(n)
            for message in thread['comments']:
                message['created'] = f'2026-09-14T00:{n // 60:02d}:{n % 60:02d}Z'
            data['snapshot']['threads'].append(thread)
        with self.backend.db:
            self.backend.db.execute('UPDATE reviews SET data=? WHERE id=?', (local.encode(data), self.review))
        initial = self.backend.request({'op': 'open', 'review': self.review})['snapshot']
        reference = {k: initial[k] for k in ('snapshot', 'base', 'head', 'base_tip')}
        cursor, loaded, pages = initial['feedback']['cursor'], list(initial['threads']), 0
        while not any(t['id'] == 'thread-500' for t in loaded):
            page = self.backend.request({'op': 'feedback_page', 'review': self.review, 'reference': reference, 'cursor': cursor})
            loaded.extend(page['threads'])
            cursor = page['next_cursor']
            pages += 1
        self.assertEqual(10, pages)
        self.assertEqual(501, len(loaded))
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        request = {'op': 'feedback_lookup', 'review': self.review, 'reference': reference,
                   'target': {'kind': 'thread', 'thread': 'thread-500', 'message': 'reply-500', 'message_kind': 'reply'}}
        before = self.backend.db.execute('SELECT data FROM reviews WHERE id=?', (self.review,)).fetchone()[0]
        result = self.backend.request(request)
        self.assertEqual(['thread-500', 'reply-500'], [m['id'] for m in result['thread']['comments']])
        self.assertEqual(reference, result['reference'])
        self.assertEqual(request['target'], result['target'])
        self.assertEqual(initial['key'], result['key'])
        self.assertNotIn('inventory', result)
        self.assertEqual(before, self.backend.db.execute('SELECT data FROM reviews WHERE id=?', (self.review,)).fetchone()[0])
        for target in [dict(request['target'], thread='foreign'), dict(request['target'], message_kind='comment'), dict(request['target'], message='foreign')]:
            with self.assertRaises(ValueError):
                self.backend.request(dict(request, target=target))
        for invalid in [None, {}, dict(reference, head='foreign')]:
            with self.assertRaises(ValueError):
                self.backend.request(dict(request, reference=invalid))
        lookup_dir = self.root / 'lookup-vim'
        lookup_dir.mkdir()
        (lookup_dir / 'config.json').write_text(json.dumps(self.backend.request({'op': 'open', 'review': self.review})))
        for _ in range(2):
            proc = subprocess.run(['vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-S', str(ROOT / 'test/feedback_lookup_local.vim')],
                                  env=dict(os.environ, REVUE_LOCAL_STORE=str(self.store), REVUE_LOOKUP_DIR=str(lookup_dir)),
                                  capture_output=True, timeout=30)
            self.assertEqual(0, proc.returncode, (lookup_dir / 'errors').read_text() if (lookup_dir / 'errors').exists() else proc.stderr.decode())
        if os.environ.get('REVUE_LOOKUP_EVIDENCE'):
            Path(os.environ['REVUE_LOOKUP_EVIDENCE']).write_text(json.dumps({
                'fixture_threads': 501, 'initial_threads': 50, 'paging_actions_after_open': pages,
                'lookup_actions_after_open': 1, 'paging_total_threads_loaded': len(loaded),
                'lookup_total_threads_loaded': len(initial['threads']) + 1,
                'scope': 'Real local backend requests against a disposable store; action/payload cost, not latency. Local lookup still projects the review in memory.'}, indent=2) + '\n')

    def test_message_history_paging_identity_and_restart(self):
        root = self.mutate(self.draft())['id']
        reply = self.mutate(self.draft(kind='reply', thread=root, body='Original reply'))['id']
        for number in range(52):
            message = self.snapshot_now()['threads'][0]['comments'][1]
            self.mutate(self.draft(kind='edit', message=reply, message_kind='reply', thread=root,
                                  expected_version=message['version'], original_body=message['body'], body='Revision ' + str(number)))
        message = self.snapshot_now()['threads'][0]['comments'][1]
        target = {'message': reply, 'message_kind': 'reply', 'thread': root, 'expected_version': message['version'], 'body': message['body']}
        request = {'op': 'message_history', 'review': self.review, 'target': target, 'cursor': ''}
        first = self.backend.request(request)
        self.assertEqual(50, len(first['items']))
        self.assertEqual(52, first['total'])
        self.assertIn('+Revision 51', first['items'][-1]['body'])
        self.assertFalse(first['complete'])
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        older = self.backend.request(dict(request, cursor=first['next_cursor']))
        self.assertTrue(older['complete'])
        self.assertEqual(2, len(older['items']))
        self.assertIn('-Original reply', older['items'][0]['body'])
        for override in ({'thread': 'foreign'}, {'message_kind': 'comment'}, {'expected_version': 'old'}):
            with self.assertRaises(ValueError): self.backend.request(dict(request, target=dict(target, **override)))
        invalid = json.loads(first['next_cursor']); invalid['review'] = 'other'
        with self.assertRaises(ValueError): self.backend.request(dict(request, cursor=json.dumps(invalid)))
        root_message = self.snapshot_now()['threads'][0]['comments'][0]
        root_target = dict(target, message=root, message_kind='comment', body=root_message['body'], expected_version=root_message['version'])
        self.assertEqual([], self.backend.request(dict(request, target=root_target))['items'])
        self.mutate(self.draft(kind='edit', message=reply, message_kind='reply', thread=root,
                              expected_version=message['version'], original_body=message['body'], body='A newer edit'))
        with self.assertRaises(ValueError): self.backend.request(dict(request, cursor=first['next_cursor']))

    def test_message_history_through_real_vim_and_restart(self):
        root = self.mutate(self.draft())['id']
        reply = self.mutate(self.draft(kind='reply', thread=root, body='Original reply'))['id']
        message = self.snapshot_now()['threads'][0]['comments'][1]
        self.mutate(self.draft(kind='edit', message=reply, message_kind='reply', thread=root,
                              expected_version=message['version'], original_body=message['body'], body='Revised reply'))
        config = self.backend.request({'op': 'open', 'review': self.review})
        config['message'] = reply
        path = self.root / 'history-config.json'; path.write_text(json.dumps(config))
        errors = self.root / 'history-errors'
        count = self.backend.db.execute('SELECT COUNT(*) FROM receipts').fetchone()[0]
        for _ in range(2):
            result = subprocess.run(['vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-S', str(ROOT / 'test/message_history_local.vim')],
                                    env=dict(os.environ, REVUE_LOCAL_STORE=str(self.store), REVUE_HISTORY_CONFIG=str(path),
                                             REVUE_HISTORY_ERRORS=str(errors), REVUE_HISTORY_DRAFTS=str(self.root / 'history-drafts')),
                                    capture_output=True, timeout=25)
            self.assertEqual(0, result.returncode, errors.read_text() if errors.exists() else result.stderr.decode())
        self.assertEqual(count, self.backend.db.execute('SELECT COUNT(*) FROM receipts').fetchone()[0])

    def test_reviewed_comparison_survives_capture_receipt_migration_and_restart(self):
        receipt = self.mutate(self.draft(kind='review', event='COMMENT', body='Reviewed original capture'))
        original = {k: self.snapshot[k] for k in ('snapshot', 'base', 'head', 'base_tip')}
        (self.repo / 'code.py').write_text('a different capture\n')
        self.mutate(self.draft(kind='capture', body='', untracked=False))
        def event():
            items = self.backend.request({'op': 'timeline', 'review': self.review, 'cursor': ''})['items']
            return next(e for e in items if e.get('target', {}).get('message') == receipt['id'])
        self.assertEqual(original, event()['reviewed_comparison'])
        self.assertNotEqual(self.snapshot_now()['head'], event()['reviewed_head'])
        data = json.loads(self.backend.db.execute('SELECT data FROM reviews WHERE id=?', (self.review,)).fetchone()[0])
        data['snapshot']['conversation'][0]['reviewed_comparison']['base'] = 'unverified-base'
        with self.backend.db:
            self.backend.db.execute('UPDATE reviews SET data=? WHERE id=?', (local.encode(data), self.review))
        self.assertNotIn('reviewed_comparison', event())
        data['snapshot']['conversation'][0].pop('reviewed_comparison')
        with self.backend.db:
            self.backend.db.execute('UPDATE reviews SET data=? WHERE id=?', (local.encode(data), self.review))
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        self.assertEqual(original, event()['reviewed_comparison'])
        self.assertIn('receipt', event()['comparison_provenance'])
        with self.backend.db:
            self.backend.db.execute('DELETE FROM receipts WHERE review=?', (self.review,))
        self.assertNotIn('reviewed_comparison', event())
        self.assertIn('unavailable', ' '.join(event()['details']))

    def test_reviewed_comparison_through_real_vim_and_restart(self):
        receipt = self.mutate(self.draft(kind='review', event='COMMENT', body='Reviewed before further edits'))
        (self.repo / 'code.py').write_text('later source\n')
        self.mutate(self.draft(kind='capture', body='', untracked=False))
        config = self.backend.request({'op': 'open', 'review': self.review})
        config.update(review_message=receipt['id'], original=self.snapshot)
        config_path = self.root / 'event-comparison.json'
        config_path.write_text(json.dumps(config))
        errors = self.root / 'event-comparison-errors'
        before = self.backend.db.execute('SELECT COUNT(*) FROM receipts').fetchone()[0]
        for _ in range(2):
            result = subprocess.run(['vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-S', str(ROOT / 'test/event_comparison_local.vim')],
                                    env=dict(os.environ, REVUE_LOCAL_STORE=str(self.store), REVUE_EVENT_CONFIG=str(config_path),
                                             REVUE_EVENT_ERRORS=str(errors), REVUE_EVENT_DRAFTS=str(self.root / 'event-drafts')),
                                    capture_output=True, timeout=25)
            self.assertEqual(0, result.returncode, errors.read_text() if errors.exists() else result.stderr.decode())
            self.assertEqual('', errors.read_text())
        self.assertEqual(before, self.backend.db.execute('SELECT COUNT(*) FROM receipts').fetchone()[0])

    def test_feedback_pages_through_real_vim_local_transport(self):
        for n in range(51):
            self.mutate(self.draft(kind='conversation', body='Loaded feedback ' + str(n)))
        opened = self.backend.request({'op': 'open', 'review': self.review})
        config = self.root / 'feedback.json'
        config.write_text(json.dumps(opened))
        errors = self.root / 'feedback-errors'
        script = self.root / 'feedback.vim'
        script.write_text('''set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(''' + repr(str(ROOT)) + ''')
let g:revue_local_dir = ''' + repr(str(self.store)) + '''
let g:revue_draft_dir = ''' + repr(str(self.root / 'vim-drafts')) + '''
let g:config = json_decode(join(readfile(''' + repr(str(config)) + '''), "\\n"))
function! WaitFor(Check) abort
  let start = reltime()
  while !a:Check() && reltimefloat(reltime(start)) < 10
    sleep 10m
  endwhile
  call assert_true(a:Check(), 'Backend callback timed out')
endfunction
try
  let g:id = revue#backend#Open({'id': 'local', 'connection': g:config.connection, 'review': g:config.review,
        \\ 'snapshot': g:config.snapshot, 'Request': function('revue#backends#local#Request', [g:config.review])}, 0)
  call WaitFor({-> !empty(revue#session#Inspect(g:id).loaded)})
  call assert_equal(50, len(revue#session#Inspect(g:id).snapshot.conversation))
  ReviewDiscussions Loaded feedback 50
  call assert_match('No discussions match in loaded feedback', join(getline(1, '$'), "\\n"))
  ReviewLoadMoreFeedback
  call WaitFor({-> !revue#session#Inspect(g:id).feedback_read.loading})
  call assert_equal('', revue#session#Inspect(g:id).feedback_read.error)
  call assert_equal(51, len(revue#session#Inspect(g:id).snapshot.conversation))
  call assert_match('Loaded feedback 50', join(getline(1, '$'), "\\n"))
  call assert_equal([], revue#activity#Unread(revue#session#Inspect(g:id)))
  ReviewRefresh
  call WaitFor({-> !revue#session#Inspect(g:id).busy})
  call assert_equal('partial refresh', revue#session#Inspect(g:id).refresh_state.status)
  call assert_equal(51, len(revue#session#Inspect(g:id).snapshot.conversation))
  ReviewContinueRefresh
  call WaitFor({-> !revue#session#Inspect(g:id).busy})
  call assert_equal('succeeded', revue#session#Inspect(g:id).refresh_state.status)
  call assert_equal(51, len(revue#session#Inspect(g:id).snapshot.conversation))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, ''' + repr(str(errors)) + ''')
if !empty(v:errors) | cquit | endif
qa!
''')
        result = subprocess.run(['vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-S', str(script)], capture_output=True, timeout=20)
        self.assertEqual(0, result.returncode, errors.read_text() if errors.exists() else result.stderr.decode())
        self.assertEqual('', errors.read_text())

    def test_feedback_continuation_keeps_whole_threads_and_survives_restart(self):
        roots = []
        for n in range(52):
            root = self.mutate(self.draft(body='Thread ' + str(n)))['id']
            roots.append(root)
            self.mutate(self.draft(kind='reply', thread=root, body='Complete reply ' + str(n)))
        self.mutate(self.draft(kind='conversation', body='Review-wide message'))
        snapshot = self.backend.request({'op': 'open', 'review': self.review})['snapshot']
        self.assertEqual(50, len(snapshot['threads']))
        self.assertTrue(all(len(t['comments']) == 2 for t in snapshot['threads']))
        self.assertEqual('partial', snapshot['inventory']['threads']['state'])
        self.assertEqual(52, snapshot['inventory']['threads']['total'])
        cursor = snapshot['feedback']['cursor']
        ref = {k: snapshot[k] for k in ('snapshot', 'base', 'head')}
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        page = self.backend.request({'op': 'feedback_page', 'review': self.review, 'reference': ref, 'cursor': cursor})
        self.assertTrue(page['complete'])
        self.assertEqual(roots, [t['id'] for t in snapshot['threads'] + page['threads']])
        self.assertTrue(all(len(t['comments']) == 2 for t in page['threads']))
        self.assertEqual('Review-wide message', page['conversation'][0]['body'])
        self.assertEqual('', page['next_cursor'])
        refreshed = self.backend.request({'op': 'refresh', 'review': self.review, 'incremental': True})
        self.assertEqual(50, len(refreshed['threads']))
        self.assertTrue(refreshed['feedback']['cursor'])
        self.assertTrue(refreshed['capabilities']['feedback_refresh']['enabled'])
        # Legacy callers retain complete replacement reads.
        self.assertEqual(52, len(self.snapshot_now()['threads']))

    def test_feedback_continuation_rejects_changed_or_foreign_inventories(self):
        for n in range(51):
            self.mutate(self.draft(kind='conversation', body='Message ' + str(n)))
        snapshot = self.backend.request({'op': 'open', 'review': self.review})['snapshot']
        self.assertEqual(50, len(snapshot['conversation']))
        cursor = snapshot['feedback']['cursor']
        request = {'op': 'feedback_page', 'review': self.review, 'reference': {'snapshot': snapshot['snapshot']}, 'cursor': cursor}
        for field in ('snapshot', 'review', 'version', 'offset'):
            foreign = json.loads(cursor)
            foreign[field] = 'wrong'
            with self.assertRaises(ValueError):
                self.backend.request(dict(request, cursor=json.dumps(foreign)))
        for invalid in (None, [], '{}', '[]', 'null'):
            with self.assertRaises(ValueError):
                self.backend.request(dict(request, cursor=invalid))
        self.mutate(self.draft(kind='conversation', body='New feedback'))
        with self.assertRaisesRegex(ValueError, 'Feedback changed'):
            self.backend.request(request)

    def test_timeline_pages_have_exact_targets_and_survive_restart(self):
        root = self.mutate(self.draft())['id']
        reply = self.mutate(self.draft(kind='reply', thread=root, body='Timeline reply'))['id']
        for n in range(51):
            self.mutate(self.draft(kind='conversation', body='History message ' + str(n)))
        read = lambda cursor='': self.backend.request({'op': 'timeline', 'review': self.review, 'cursor': cursor})
        first = read()
        self.assertEqual(50, len(first['items']))
        self.assertFalse(first['complete'])
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        older = read(first['next_cursor'])
        self.assertTrue(older['complete'])
        self.assertEqual('', older['next_cursor'])
        events = older['items'] + first['items']
        self.assertEqual(first['total'], len(events))
        self.assertEqual(len(events), len({e['id'] for e in events}))
        target = next(e['target'] for e in events if e['body'] == 'Timeline reply')
        self.assertEqual({'kind': 'thread', 'thread': root, 'message': reply, 'message_kind': 'reply'}, target)
        self.assertEqual(1, sum(e['kind'] == 'Capture' for e in events))
        self.assertTrue(all(e['title'] == 'Commented' for e in events if e['body'].startswith('History message ')))
        self.assertIn('edit/lifecycle events are not recorded', older['scope'])

    def test_timeline_rejects_changed_inventory_and_foreign_cursor(self):
        for n in range(51):
            self.mutate(self.draft(kind='conversation', body=str(n)))
        first = self.backend.request({'op': 'timeline', 'review': self.review})
        foreign = json.loads(first['next_cursor'])
        foreign['review'] = 'another-review'
        for cursor in [[], '[]', 'null', json.dumps(foreign)]:
            with self.assertRaises(ValueError):
                self.backend.request({'op': 'timeline', 'review': self.review, 'cursor': cursor})
        self.mutate(self.draft(kind='conversation', body='New arrival'))
        with self.assertRaisesRegex(ValueError, 'history changed'):
            self.backend.request({'op': 'timeline', 'review': self.review, 'cursor': first['next_cursor']})

    def test_timeline_does_not_invent_capture_events_for_derived_ranges(self):
        source = self.snapshot_now()
        ref = {k: source[k] for k in ('snapshot', 'base', 'head')}
        self.backend.request({'op': 'comparison_range', 'review': self.review,
                              'selection': {'from': {'reference': ref, 'side': 'base'},
                                            'to': {'reference': ref, 'side': 'head'}}})
        page = self.backend.request({'op': 'timeline', 'review': self.review})
        self.assertEqual(['Capture'], [e['kind'] for e in page['items']])

    def test_inventory_tracks_current_shared_feedback_on_retained_source(self):
        before = self.snapshot_now()
        root = self.mutate(self.draft())['id']
        self.mutate(self.draft(kind='reply', thread=root, body='Inline response'))
        current = self.snapshot_now()
        reference = {k: before[k] for k in ('snapshot', 'base', 'head', 'base_tip')}
        retained = self.backend.request({'op': 'comparison', 'review': self.review, 'reference': reference})
        for snapshot in (current, retained):
            for name in ('files', 'threads', 'conversation'):
                self.assertEqual({'state': 'complete', 'total': len(snapshot[name])},
                                 {k: snapshot['inventory'][name][k] for k in ('state', 'total')})
            self.assertEqual(1, snapshot['inventory']['thread_state']['total'])
            self.assertEqual(2, len(snapshot['threads'][0]['comments']))

    def test_ranges_compare_retained_trees_and_keep_shared_conversation(self):
        root = self.mutate(self.draft())['id']
        first = self.snapshot_now()
        # A file restored to baseline disappears from the second capture's delta.
        (self.repo / 'code.py').write_text('one\nold\nthree\n')
        (self.repo / 'untracked.py').write_bytes(b'extra\r\n')
        self.mutate(self.draft(kind='capture', body='', untracked=True))
        second = self.snapshot_now()
        refs = lambda s: {k: s[k] for k in ('snapshot', 'base', 'head', 'base_tip')}
        selection = {'from': {'reference': refs(first), 'side': 'head'},
                     'to': {'reference': refs(second), 'side': 'head'}}
        # Deliberately remove Git/workspace access: the range uses retained data.
        from unittest.mock import patch
        with patch.object(local, 'git', side_effect=AssertionError('Range must not read Git')):
            result = self.backend.request({'op': 'comparison_range', 'review': self.review, 'selection': selection})
        paths = {f['path']: f for f in result['files']}
        self.assertEqual({'code.py', 'untracked.py'}, set(paths))
        read = lambda f: self.backend.request({'op': 'file', 'review': self.review, 'snapshot': result, 'file': f})
        code = read(paths['code.py'])
        self.assertEqual(['one', 'new', 'three'], code['base']['lines'])
        self.assertEqual(['one', 'old', 'three'], code['head']['lines'])
        self.assertEqual('absent', read(paths['untracked.py'])['base']['kind'])
        self.assertEqual(first['head'], result['base'])
        self.assertEqual(second['head'], result['head'])
        self.assertEqual(second['snapshot'], self.snapshot_now()['snapshot'])
        self.assertFalse(result['capabilities']['comment']['enabled'])
        self.assertEqual(root, result['threads'][0]['id'])
        # Replies made while inspecting the range still belong to the same thread.
        reply = self.draft(kind='reply', thread=root, body='Reply from selected range',
                           **{k: result[k] for k in ('snapshot', 'head', 'base_tip')})
        self.mutate(reply)
        self.assertEqual(reply['body'], self.snapshot_now()['threads'][0]['comments'][-1]['body'])
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        self.addCleanup(self.backend.close)
        restored = self.backend.request({'op': 'comparison', 'review': self.review, 'reference': refs(result)})
        self.assertEqual(selection, restored['range'])
        self.assertEqual(code, read(paths['code.py']))
        repeated = self.backend.request({'op': 'comparison_range', 'review': self.review, 'selection': selection})
        self.assertEqual(result['snapshot'], repeated['snapshot'])

    def test_ranges_cover_base_reverse_rename_binary_newlines_and_empty(self):
        first = self.snapshot_now()
        (self.repo / 'code.py').write_bytes(b'one\nnew\nthree')
        (self.repo / 'binary').write_bytes(b'\0data')
        self.git('mv', 'renamed.py', 'rename.py')
        self.mutate(self.draft(kind='capture', body='', untracked=True))
        second = self.snapshot_now()
        endpoint = lambda s, side: {'reference': {k: s[k] for k in ('snapshot', 'base', 'head')}, 'side': side}
        def compare(a, aside, b, bside):
            return self.backend.request({'op': 'comparison_range', 'review': self.review,
                'selection': {'from': endpoint(a, aside), 'to': endpoint(b, bside)}})
        result = compare(first, 'head', second, 'head')
        paths = {f['path']: f for f in result['files']}
        self.assertEqual('D', paths['renamed.py']['status'])
        self.assertEqual('A', paths['rename.py']['status'])
        for path in ('code.py', 'binary'):
            data = self.backend.request({'op': 'file', 'review': self.review, 'snapshot': result, 'file': paths[path]})
            if path == 'code.py':
                self.assertNotEqual(data['base']['hash'], data['head']['hash'])
                self.assertFalse(data['head']['final_newline'])
            else:
                self.assertEqual('binary', data['head']['kind'])
        self.assertEqual([], compare(first, 'head', first, 'head')['files'])
        baseline = compare(first, 'base', second, 'base')
        self.assertEqual([], baseline['files'])
        reverse = compare(second, 'head', first, 'head')
        self.assertEqual('A', next(f for f in reverse['files'] if f['path'] == 'renamed.py')['status'])
        self.assertEqual(first['base'], compare(first, 'base', second, 'head')['base'])
        malformed = endpoint(first, 'head')
        malformed['reference']['head'] = 'different'
        with self.assertRaisesRegex(ValueError, 'identify original captures'):
            self.backend.request({'op': 'comparison_range', 'review': self.review, 'selection': {'from': malformed, 'to': endpoint(second, 'head')}})
        with self.assertRaisesRegex(ValueError, 'original captures'):
            compare(result, 'head', second, 'head')

    def test_reaction_membership_counts_receipts_and_edit_independence(self):
        root = self.mutate(self.draft())['id']
        reply = self.mutate(self.draft(kind='reply', thread=root, body='Reply'))['id']
        target = {'message': reply, 'message_kind': 'reply', 'thread': root}
        before = self.snapshot_now()['threads'][0]['comments'][1]
        data = self.backend.load(self.review)
        data['snapshot']['threads'][0]['comments'][1]['reaction_members'] = [{'id': 'other-reaction', 'actor': 'local:other', 'content': 'heart'}]
        with self.backend.db:
            self.backend.db.execute('UPDATE reviews SET data=? WHERE id=?', (local.encode(data), self.review))
        read = lambda: self.backend.request({'op': 'reactions', 'review': self.review, 'target': target})
        groups = read()
        heart = next(r for r in groups['items'] if r['id'] == 'heart')
        self.assertEqual((1, False), (heart['count'], heart['mine']))
        self.assertEqual({'items': [{'id': 'local:other', 'label': 'other'}], 'unavailable': 0}, heart['members'])
        self.assertNotIn('members', self.snapshot_now()['threads'][0]['comments'][1]['reactions']['items'][0])
        add = self.draft(kind='reaction', body='', reaction='heart', present=True, actor=groups['actor'], **target)
        self.mutate(add)
        self.mutate(add)
        self.assertEqual((2, True), tuple(next(r for r in read()['items'] if r['id'] == 'heart')[k] for k in ('count', 'mine')))
        self.assertEqual(before['version'], self.snapshot_now()['threads'][0]['comments'][1]['version'])
        remove = dict(add, id=local.identity(), present=False)
        self.mutate(remove)
        self.assertEqual((1, False), tuple(next(r for r in read()['items'] if r['id'] == 'heart')[k] for k in ('count', 'mine')))
        self.assertTrue(self.mutate(add, reconcile=True)['recovered'])
        self.assertFalse(next(r for r in read()['items'] if r['id'] == 'heart')['mine'], 'old receipt never reapplies a reaction')
        self.assertFalse(self.snapshot_now()['threads'][0]['resolved'])
        self.assertEqual(before['body'], self.snapshot_now()['threads'][0]['comments'][1]['body'])
        with self.assertRaisesRegex(ValueError, 'actor changed'):
            self.mutate(dict(add, id=local.identity(), actor='local:other', present=False))
        with self.assertRaisesRegex(ValueError, 'does not belong'):
            self.mutate(dict(add, id=local.identity(), thread='wrong-thread'))
        with self.assertRaisesRegex(ValueError, 'No saved receipt'):
            self.mutate(dict(add, id=local.identity()), reconcile=True)
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        self.addCleanup(self.backend.close)
        self.assertTrue(self.mutate(remove, reconcile=True)['recovered'])
        self.assertEqual(1, next(r for r in read()['items'] if r['id'] == 'heart')['count'])

    def test_edit_exact_message_conflict_history_and_receipts(self):
        root = self.mutate(self.draft())['id']
        reply = self.mutate(self.draft(kind='reply', thread=root, body='Original reply'))['id']
        original = self.snapshot_now()['threads'][0]['comments'][1]
        edit = self.draft(kind='edit', message=reply, message_kind='reply', thread=root,
                          expected_version=original['version'], original_body=original['body'], body='  Exact replacement 日本語\n')
        wrong = dict(edit, id=local.identity(), message=root)
        with self.assertRaisesRegex(ValueError, 'Message does not belong'):
            self.mutate(wrong)
        receipt = self.mutate(edit)
        messages = self.snapshot_now()['threads'][0]['comments']
        self.assertEqual('Explain this change', messages[0]['body'])
        self.assertEqual(edit['body'], messages[1]['body'])
        self.assertTrue(messages[1]['edited'])
        self.assertEqual(reply, receipt['message'])
        self.assertEqual(root, receipt['thread'])
        with self.assertRaisesRegex(ValueError, 'Message changed'):
            self.mutate(dict(edit, id=local.identity(), body='Concurrent overwrite'))
        # An ABA change still has a new version, even if text returns to original.
        second = dict(edit, id=local.identity(), expected_version=messages[1]['version'], original_body=messages[1]['body'], body=original['body'])
        self.mutate(second)
        with self.assertRaisesRegex(ValueError, 'Message changed'):
            self.mutate(dict(edit, id=local.identity()))
        self.assertTrue(self.mutate(edit, reconcile=True)['recovered'])
        self.assertEqual(original['body'], self.snapshot_now()['threads'][0]['comments'][1]['body'])
        with self.assertRaisesRegex(ValueError, 'different feedback'):
            self.mutate(dict(edit, body='Changed frozen payload'), reconcile=True)
        before = self.snapshot_now()
        with self.assertRaisesRegex(ValueError, 'No saved receipt'):
            self.mutate(dict(edit, id=local.identity()), reconcile=True)
        self.assertEqual(before, self.snapshot_now())
        rows = self.backend.db.execute("SELECT data FROM events WHERE kind='comment.edited'").fetchall()
        self.assertEqual(2, len(rows))
        self.assertEqual(original['body'], json.loads(rows[0][0])['before']['body'])
        self.assertEqual(edit['body'], json.loads(rows[0][0])['after']['body'])
        self.backend.close()
        self.backend = local.LocalBackend(self.store)
        self.addCleanup(self.backend.close)
        self.assertTrue(self.mutate(edit, reconcile=True)['recovered'])
        (self.repo / 'code.py').write_text('new revision\n')
        self.mutate(self.draft(kind='capture', body='', untracked=False))
        historical = self.backend.request({'op': 'comparison', 'review': self.review, 'reference': self.snapshot})
        current = historical['threads'][0]['comments'][1]
        third = dict(edit, id=local.identity(), expected_version=current['version'], original_body=current['body'], body='Edited from retained comparison')
        self.mutate(third)
        self.assertEqual(third['body'], self.snapshot_now()['threads'][0]['comments'][1]['body'])

    def test_edit_conversation_permissions_and_transactional_race(self):
        mid = self.mutate(self.draft(kind='conversation', body='Discussion'))['id']
        message = self.snapshot_now()['conversation'][0]
        edit = self.draft(kind='edit', message=mid, message_kind='conversation', thread='',
                          expected_version=message['version'], original_body=message['body'], body='First')
        def attempt(body):
            backend = local.LocalBackend(self.store)
            try:
                return backend.request({'op': 'mutate', 'review': self.review, 'draft': dict(edit, id=local.identity(), body=body)})
            except ValueError as error:
                return str(error)
            finally:
                backend.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, ['First concurrent edit', 'Second concurrent edit']))
        self.assertEqual(1, sum(isinstance(r, dict) for r in results))
        self.assertEqual(1, sum(isinstance(r, str) and 'Message changed' in r for r in results))
        data = self.backend.load(self.review)
        data['snapshot']['conversation'][0]['author'] = 'Another participant'
        with self.backend.db:
            self.backend.db.execute('UPDATE reviews SET data=? WHERE id=?', (local.encode(data), self.review))
        latest = self.snapshot_now()['conversation'][0]
        self.assertFalse(latest['capabilities']['edit']['enabled'])
        with self.assertRaisesRegex(ValueError, 'not permitted'):
            self.mutate(dict(edit, expected_version=latest['version'], original_body=latest['body']))

    def test_revision_capture_preserves_conversation_and_original_source(self):
        first = self.snapshot
        head = self.mutate(self.draft())['id']
        base = self.mutate(self.draft(side='base'))['id']
        whole = self.draft(kind='file_comment')
        for key in ('side', 'start', 'end'):
            whole.pop(key)
        file_root = self.mutate(whole)['id']
        (self.repo / 'code.py').write_text('one\nnewer\nthree\n')
        advance = self.draft(kind='capture', body='', untracked=False)
        receipt = self.mutate(advance)
        second = self.snapshot_now()
        self.assertTrue(receipt['changed'])
        self.assertEqual(first['snapshot'], receipt['previous_snapshot'])
        self.assertEqual(second['snapshot'], receipt['snapshot'])
        self.assertEqual(first['key'], second['key'])
        self.assertEqual(first['base'], second['base'])
        threads = {t['id']: t for t in second['threads']}
        self.assertTrue(threads[head]['outdated'])
        self.assertEqual(['2 │ new'], threads[head]['original_context'])
        self.assertFalse(threads[base]['outdated'])
        self.assertFalse(threads[file_root]['outdated'])
        self.assertFalse(any(t['resolved'] for t in threads.values()))
        self.assertTrue(self.mutate(advance, reconcile=True)['recovered'])
        # Replies and explicit thread state refer to the shared conversation.
        self.mutate(self.draft(kind='reply', thread=head, body='Reply from the original comparison'))
        self.mutate(self.draft(kind='thread_state', thread=head, body='', resolved=True, expected_resolved=False))
        with self.assertRaisesRegex(ValueError, 'newer local comparison'):
            self.mutate(self.draft())
        historical = self.backend.request({'op': 'comparison', 'review': self.review, 'reference': first})
        self.assertFalse(historical['capabilities']['comment']['enabled'])
        self.assertTrue(historical['capabilities']['reply']['enabled'])
        historical_thread = next(t for t in historical['threads'] if t['id'] == head)
        self.assertFalse(historical_thread['outdated'])
        self.assertTrue(historical_thread['resolved'])
        self.assertEqual(2, len(historical_thread['comments']))
        file = next(f for f in first['files'] if f['path'] == 'code.py')
        old_content = self.backend.request({'op': 'file', 'review': self.review, 'snapshot': first, 'file': file})
        self.assertEqual(['one', 'new', 'three'], old_content['head']['lines'])
        other = local.LocalBackend(self.store)
        try:
            history = other.request({'op': 'comparisons', 'review': self.review})
            self.assertEqual(2, len(history['items']))
            self.assertEqual([first['snapshot'], second['snapshot']], [r['snapshot'] for r in history['items']])
            self.assertEqual(historical, other.request({'op': 'comparison', 'review': self.review, 'reference': first}))
        finally:
            other.close()
        self.snapshot = second
        same = self.mutate(self.draft(kind='capture', body='', untracked=False))
        self.assertFalse(same['changed'])
        self.assertEqual(2, len(self.backend.request({'op': 'comparisons', 'review': self.review})['items']))
        # An empty diff is a valid subsequent revision; it does not erase feedback.
        self.git('restore', '--source=' + first['base'], '--staged', '--worktree', '.')
        empty = self.mutate(self.draft(kind='capture', body='', untracked=False))
        self.assertTrue(empty['changed'])
        latest = self.snapshot_now()
        self.assertEqual([], latest['files'])
        self.assertEqual(3, len(latest['threads']))
        self.assertTrue(all(t['outdated'] for t in latest['threads']))
        self.assertEqual(3, len(self.backend.request({'op': 'comparisons', 'review': self.review})['items']))

    def test_capture_receipt_validation_legacy_settings_and_stale_race(self):
        # Legacy records retain source/replies and explicitly default capture to tracked files.
        data = self.backend.load(self.review)
        data.pop('capture_options')
        data.pop('vcs')
        data.pop('revisions')
        with self.backend.db:
            self.backend.db.execute('UPDATE reviews SET data=? WHERE id=?', (local.encode(data), self.review))
        self.assertFalse(self.snapshot_now()['capture_context']['options_known'])
        original = self.snapshot['snapshot']
        for fields in ({'untracked': 1}, {'body': 'accidental comment'}, {'snapshot': 'missing'}):
            draft = self.draft(kind='capture', body='', untracked=False)
            draft.update(fields)
            with self.assertRaises(ValueError):
                self.mutate(draft)
            self.assertEqual(original, self.snapshot_now()['snapshot'])
        with self.assertRaisesRegex(ValueError, 'No saved receipt'):
            self.mutate(self.draft(kind='capture', body='', untracked=True), reconcile=True)
        def attempt(draft):
            backend = local.LocalBackend(self.store)
            try:
                return backend.request({'op': 'mutate', 'review': self.review, 'draft': draft})
            except ValueError as error:
                return str(error)
            finally:
                backend.close()
        drafts = [self.draft(kind='capture', body='', untracked=True) for _ in range(2)]
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(attempt, drafts))
        self.assertEqual(1, sum(isinstance(r, dict) for r in results))
        self.assertTrue(any(isinstance(r, str) and 'newer local comparison' in r for r in results))
        self.assertIn('untracked.py', [f['path'] for f in self.snapshot_now()['files']])
        self.assertTrue(self.snapshot_now()['capture_context']['options_known'])
        self.assertTrue(self.snapshot_now()['capture_context']['untracked'])
        self.assertEqual(2, len(self.backend.request({'op': 'comparisons', 'review': self.review})['items']))

    def test_unchanged_line_anchors_use_captured_source_not_patch_membership(self):
        original = [f'unchanged source {n}' for n in range(1, 81)]
        (self.repo / 'long.txt').write_text('\n'.join(original) + '\n')
        self.git('add', 'long.txt')
        self.git('commit', '-qm', 'Long source for anchor fixture')
        self.git('mv', 'long.txt', 'renamed-long.txt')
        changed = original.copy()
        changed[4] = 'changed source 5'
        (self.repo / 'renamed-long.txt').write_text('\n'.join(changed) + '\n')
        opened = self.backend.request({'op': 'create', 'cwd': str(self.repo), 'base': 'HEAD'})
        self.review, self.snapshot = opened['review'], opened['snapshot']
        self.assertEqual('changed_file', self.snapshot['capabilities']['comment']['anchors']['scope'])
        file = next(f for f in self.snapshot['files'] if f['path'] == 'renamed-long.txt')
        self.assertEqual('long.txt', file['old_path'])
        self.assertNotIn('unchanged source 48', file['patch'])
        first = self.draft(path=file['path'], old_path=file['old_path'], start=48, end=50)
        second = self.draft(path=file['path'], old_path=file['old_path'], side='base', start=48, end=50)
        proposal = self.draft(path=file['path'], old_path=file['old_path'], start=70, end=71,
                              suggestion=True, body='```suggestion\nreplacement beyond the hunk\n```')
        batch = self.draft(kind='batch', body='', items=[first, second, proposal])
        self.mutate(batch)
        self.assertTrue(self.mutate(batch, reconcile=True)['recovered'])
        threads = self.snapshot_now()['threads']
        self.assertEqual([original[47:50], original[47:50], original[69:71]], [t['anchor']['selected'] for t in threads])
        self.assertEqual(['head', 'base', 'head'], [t['side'] for t in threads])
        self.assertTrue(all(t['anchor']['snapshot'] == self.snapshot['snapshot'] for t in threads))
        self.mutate(self.draft(kind='reply', thread=threads[0]['id'], body='Exact root reply'))
        self.assertEqual(2, len(self.snapshot_now()['threads'][0]['comments']))
        before = (self.repo / file['path']).read_bytes()
        for fields in ({'start': 0}, {'end': 81}, {'start': True}, {'side': 'unknown'}, {'path': 'unchanged-file.txt'}, {'old_path': 'wrong'}):
            with self.assertRaises(ValueError):
                self.mutate(dict(first, id=local.identity(), **fields))
        self.assertEqual(before, (self.repo / file['path']).read_bytes())
        (self.repo / file['path']).write_text('Different workspace revision\n')
        self.mutate(dict(first, id=local.identity()))
        self.assertEqual(original[47:50], self.snapshot_now()['threads'][-1]['anchor']['selected'])

    def test_file_comments_preserve_targets_replies_and_batch_receipts(self):
        def file_draft(file):
            draft = self.draft(kind='file_comment', path=file['path'], old_path=file['old_path'])
            for key in ('side', 'start', 'end'):
                draft.pop(key)
            return draft
        self.assertTrue(self.snapshot['capabilities']['file_comment']['enabled'])
        for file in self.snapshot['files']:
            draft = file_draft(file)
            receipt = self.mutate(draft)
            self.mutate(self.draft(kind='reply', thread=receipt['id'], body='File reply'))
            thread = self.snapshot_now()['threads'][-1]
            self.assertEqual(('file', file['path'], '', 0, 0),
                             (thread['subject_type'], thread['path'], thread['side'], thread['start'], thread['line']))
            self.assertEqual(2, len(thread['comments']))
            self.assertEqual(file['old_path'], thread['anchor']['old_path'])
            self.assertNotIn('selected', thread['anchor'])
            self.assertTrue(self.mutate(draft, reconcile=True)['recovered'])
        total = len(self.snapshot['files'])
        draft = file_draft(self.snapshot['files'][0])
        batch = self.draft(kind='batch', body='', items=[draft, self.draft()])
        self.mutate(batch)
        self.assertTrue(self.mutate(batch, reconcile=True)['recovered'])
        self.assertEqual(total + 2, len(self.snapshot_now()['threads']))
        for fields in ({'path': 'missing'}, {'old_path': 'wrong'}, {'start': 1}, {'side': 'head'}, {'suggestion': True}):
            invalid = dict(file_draft(self.snapshot['files'][0]), **fields)
            with self.assertRaises(ValueError):
                self.mutate(invalid)
        invalid = dict(file_draft(self.snapshot['files'][0]), path='missing')
        with self.assertRaises(ValueError):
            self.mutate(self.draft(kind='batch', body='', items=[file_draft(self.snapshot['files'][0]), invalid]))
        self.assertEqual(total + 2, len(self.snapshot_now()['threads']))

    def test_suggestions_are_comments_and_never_modify_source(self):
        before = (self.repo / 'code.py').read_bytes()
        self.assertEqual(['head'], self.snapshot['capabilities']['suggestion']['sides'])
        body = 'Reason\n\n````suggestion\n```literal\nnew text\n````'
        draft = self.draft(suggestion=True, body=body)
        self.mutate(draft)
        self.assertEqual(body, self.snapshot_now()['threads'][0]['comments'][0]['body'])
        self.assertEqual(before, (self.repo / 'code.py').read_bytes())
        self.assertTrue(self.mutate(draft, reconcile=True)['recovered'])
        deletion = self.draft(suggestion=True, body='```suggestion\n```')
        batch = self.draft(kind='batch', body='', items=[deletion])
        self.mutate(batch)
        self.assertEqual(2, len(self.snapshot_now()['threads']))
        for fields in [{'side': 'base'}, {'body': '```suggestion\nunterminated'},
                       {'body': '> ```suggestion\n> quoted\n> ```'}, {'suggestion': 1}]:
            invalid = self.draft(suggestion=True)
            invalid.update(fields)
            with self.assertRaises(ValueError):
                self.mutate(invalid)
        self.assertEqual(2, len(self.snapshot_now()['threads']))
        self.assertEqual(before, (self.repo / 'code.py').read_bytes())
        bad_batch = self.draft(kind='batch', body='', items=[self.draft(), self.draft(suggestion=True, body='malformed')])
        with self.assertRaises(ValueError):
            self.mutate(bad_batch)
        self.assertEqual(2, len(self.snapshot_now()['threads']), 'invalid suggestion rolls back the entire batch')

    def test_frozen_comparison_inventory_and_lookup(self):
        self.mutate(self.draft())
        listing = self.backend.request({'op': 'comparisons', 'review': self.review})
        self.assertTrue(listing['complete'])
        self.assertEqual(1, len(listing['items']))
        reference = listing['items'][0]
        self.assertEqual(self.snapshot['snapshot'], reference['snapshot'])
        restored = self.backend.request({'op': 'comparison', 'review': self.review, 'reference': reference})
        self.assertEqual(self.snapshot_now(), restored)
        self.assertEqual(1, len(restored['threads']))
        for changed in ({'snapshot': 'another-review'}, {'head': 'wrong-source'}):
            with self.assertRaisesRegex(ValueError, 'does not belong'):
                self.backend.request({'op': 'comparison', 'review': self.review, 'reference': dict(reference, **changed)})

    def test_thread_resolution_receipts_and_history(self):
        root = self.mutate(self.draft())['id']
        draft = self.draft(kind='thread_state', thread=root, body='', resolved=True, expected_resolved=False)
        original = self.snapshot_now()['threads'][0]
        self.assertEqual('local', original['comments'][0]['publication'])
        self.assertFalse(original['resolved'])
        self.assertTrue(original['capabilities']['resolve']['enabled'])
        receipt = self.mutate(draft)
        self.assertTrue(receipt['resolved'])
        resolved = self.snapshot_now()['threads'][0]
        self.assertEqual(original['comments'], resolved['comments'])
        self.assertTrue(resolved['capabilities']['reopen']['enabled'])
        self.assertFalse(resolved['capabilities']['resolve']['enabled'])
        self.assertTrue(self.mutate(dict(draft, state='unknown'), reconcile=True)['recovered'])
        reopen = self.draft(kind='thread_state', thread=root, body='', resolved=False, expected_resolved=True)
        self.mutate(reopen)
        self.assertFalse(self.snapshot_now()['threads'][0]['resolved'])
        # Recovery confirms the original operation, even after later state changes.
        self.assertTrue(self.mutate(draft, reconcile=True)['resolved'])
        self.assertFalse(self.snapshot_now()['threads'][0]['resolved'])
        count = self.backend.db.execute("SELECT COUNT(*) FROM events WHERE kind='thread.state'").fetchone()[0]
        self.assertEqual(2, count)
        with self.assertRaisesRegex(ValueError, 'different feedback'):
            self.mutate(dict(draft, resolved=False))
        with self.assertRaisesRegex(ValueError, 'No saved receipt'):
            self.mutate(dict(draft, id='unknown-operation'), reconcile=True)

    def test_thread_resolution_rejects_invalid_targets_and_booleans(self):
        root = self.mutate(self.draft())['id']
        for fields in [{'thread': 'absent'}, {'resolved': 1}, {'expected_resolved': 'false'}]:
            draft = self.draft(kind='thread_state', thread=root, body='', resolved=True, expected_resolved=False)
            draft.update(fields)
            with self.assertRaises(ValueError):
                self.mutate(draft)
            self.assertFalse(self.snapshot_now()['threads'][0]['resolved'])

    def test_atomic_batch_receipts_and_rollback(self):
        first = self.draft(id='batch-comment')
        second = self.draft(id='batch-summary', kind='review', event='COMMENT', body='Review summary')
        batch = self.draft(id='batch-operation', kind='batch', body='', items=[first, second])
        receipt = self.mutate(batch)
        self.assertEqual(['batch-comment', 'batch-summary'], [r['draft'] for r in receipt['items']])
        batch.update(state='unknown', error='transport interruption')
        self.assertTrue(self.mutate(batch, reconcile=True)['recovered'])
        self.assertEqual(1, len(self.snapshot_now()['threads']))
        self.assertEqual(1, len(self.snapshot_now()['conversation']))
        batch['items'][0]['body'] = 'changed after acceptance'
        with self.assertRaisesRegex(ValueError, 'different feedback'):
            self.mutate(batch)

        bad = self.draft(id='atomic-invalid', kind='batch', body='', items=[
            self.draft(id='would-be-valid'), self.draft(id='invalid-range', end=999)])
        with self.assertRaises(ValueError):
            self.mutate(bad)
        self.assertEqual(1, len(self.snapshot_now()['threads']))
        self.assertIsNone(self.backend.db.execute('SELECT 1 FROM receipts WHERE operation=?', ('would-be-valid',)).fetchone())
        with self.assertRaisesRegex(ValueError, 'No batch receipt'):
            self.mutate(bad, reconcile=True)
        self.assertEqual(1, len(self.snapshot_now()['threads']))

    def test_reanchor_through_vim_and_local_backend_restart(self):
        config = self.backend.request({'op': 'open', 'review': self.review})
        self.git('mv', 'code.py', 'moved.py')
        (self.repo / 'moved.py').write_text('first moved line\nsecond moved line\nthird\n')
        self.mutate(self.draft(kind='capture', body='', untracked=False))
        config['latest'] = self.snapshot_now()
        path = self.root / 'reanchor-config.json'
        path.write_text(json.dumps(config))
        code = "from pathlib import Path; from vim_pty import run; run(Path('test/reanchor_local.vim').resolve(), repeat=2)"
        result = subprocess.run(['python3', '-c', code], cwd=ROOT, capture_output=True, text=True, timeout=50,
                                env=dict(os.environ, PYTHONPATH=str(ROOT / 'test'), REVUE_LOCAL_STORE=str(self.store), REVUE_REANCHOR_CONFIG=str(path)))
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        threads = self.snapshot_now()['threads']
        self.assertEqual(1, len(threads))
        self.assertEqual('moved.py', threads[0]['path'])
        self.assertEqual('Draft moved deliberately.', threads[0]['comments'][0]['body'])
        self.assertEqual(1, self.backend.db.execute("SELECT COUNT(*) FROM events WHERE kind='comment.created'").fetchone()[0])

    def test_published_deletion_through_vim_and_restart(self):
        root = self.mutate(self.draft(body='Root remains'))['id']
        thread = self.snapshot_now()['threads'][0]['id']
        reply = self.mutate(self.draft(kind='reply', thread=thread, body='Remove this reply'))['id']
        config = self.backend.request({'op': 'open', 'review': self.review})
        config.update(root=root, thread=thread, message=reply)
        path = self.root / 'delete-config.json'
        path.write_text(json.dumps(config))
        code = "from pathlib import Path; from vim_pty import run; run(Path('test/published_delete_local.vim').resolve(), repeat=2)"
        result = subprocess.run(['python3', '-c', code], cwd=ROOT, capture_output=True, text=True, timeout=50,
                                env=dict(os.environ, PYTHONPATH=str(ROOT / 'test'), REVUE_LOCAL_STORE=str(self.store), REVUE_DELETE_CONFIG=str(path)))
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)
        self.assertEqual([root], [m['id'] for m in self.snapshot_now()['threads'][0]['comments']])
        self.assertEqual(1, self.backend.db.execute("SELECT COUNT(*) FROM events WHERE kind='comment.deleted'").fetchone()[0])

    def test_published_deletion_scope_atomic_receipts_and_restart(self):
        root = self.mutate(self.draft(body='Root'))['id']
        thread = self.snapshot_now()['threads'][0]['id']
        reply = self.mutate(self.draft(kind='reply', thread=thread, body='Reply stays'))['id']
        def deletion(message, thread_id=thread):
            snapshot = self.snapshot_now()
            messages = snapshot['conversation'] + [m for t in snapshot['threads'] for m in t['comments']]
            current = next(m for m in messages if m['id'] == message)
            return self.draft(kind='delete_message', message=message, message_kind=current['kind'], thread=thread_id,
                              actor=current['capabilities']['delete_message']['actor'], delete_scope='message', body='',
                              original_body=current['body'], expected_version=current['version'])
        draft = deletion(root)
        for fields in ({'actor': 'another'}, {'delete_scope': 'thread'}, {'message_kind': 'review'}, {'thread': 'foreign'}, {'expected_version': 'old'}, {'original_body': 'wrong'}, {'body': 'replacement'}):
            with self.assertRaises(ValueError): self.mutate(dict(draft, **fields))
        receipt = self.mutate(draft)
        self.assertTrue(receipt['deleted'])
        remaining = self.snapshot_now()['threads'][0]
        self.assertEqual(thread, remaining['id'])
        self.assertEqual([reply], [m['id'] for m in remaining['comments']])
        restarted = local.LocalBackend(self.store)
        try:
            recovered = restarted.request({'op': 'mutate', 'review': self.review, 'draft': draft, 'reconcile': True})
            self.assertTrue(recovered['recovered'])
            self.assertEqual(receipt['message'], recovered['message'])
        finally:
            restarted.close()
        with self.assertRaises(ValueError): self.mutate(dict(draft, actor='changed'), reconcile=True)
        self.mutate(deletion(reply))
        self.assertEqual([], self.snapshot_now()['threads'])
        general = self.mutate(self.draft(kind='conversation', body='General comment'))['id']
        self.mutate(deletion(general, ''))
        self.assertEqual([], self.snapshot_now()['conversation'])
        self.assertEqual(3, self.backend.db.execute("SELECT COUNT(*) FROM events WHERE kind='comment.deleted'").fetchone()[0])

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo with spaces"
        self.repo.mkdir()
        self.store = self.root / "store"
        self.git("init", "-q")
        self.git("config", "user.name", "Local reviewer")
        self.git("config", "user.email", "local@example.invalid")
        (self.repo / "code.py").write_text("one\nold\nthree\n")
        (self.repo / "deleted.py").write_text("deleted\n")
        (self.repo / "rename.py").write_text("same\n" * 20)
        self.git("add", ".")
        self.git("commit", "-qm", "base")
        (self.repo / "code.py").write_text("one\nnew\nthree\n")
        (self.repo / "deleted.py").unlink()
        self.git("mv", "rename.py", "renamed.py")
        (self.repo / "untracked.py").write_text("extra\n")
        self.backend = local.LocalBackend(self.store)
        self.addCleanup(self.backend.close)
        self.opened = self.backend.request({"op": "create", "cwd": str(self.repo), "base": "HEAD"})
        self.review = self.opened["review"]
        self.snapshot = self.opened["snapshot"]

    def git(self, *args):
        return local.git(self.repo, *args)

    def draft(self, **overrides):
        draft = {"id": local.identity(), "kind": "comment", "path": "code.py", "old_path": "code.py",
                 "side": "head", "start": 2, "end": 2, "body": "Explain this change", "state": "draft",
                 **{key: self.snapshot[key] for key in ("head", "base_tip", "snapshot")}}
        draft.update(overrides)
        return draft

    def mutate(self, draft, **kwargs):
        return self.backend.request({"op": "mutate", "review": self.review, "draft": draft, **kwargs})

    def snapshot_now(self):
        return self.backend.request({"op": "refresh", "review": self.review})

    def test_frozen_content_and_reopen(self):
        receipt = self.mutate(self.draft())
        self.mutate(self.draft(kind="reply", thread=receipt["id"], body="> Explain\n\nHere is why."))
        (self.repo / "code.py").write_text("entirely different\n")
        code = next(f for f in self.snapshot["files"] if f["path"] == "code.py")
        other = local.LocalBackend(self.store)
        try:
            opened = other.request({"op": "open", "review": self.review})
            self.assertEqual(self.opened["connection"], opened["connection"])
            self.assertEqual(2, len(opened["snapshot"]["threads"][0]["comments"]))
            file = other.request({"op": "file", "review": self.review, "snapshot": self.snapshot, "file": code})
            self.assertEqual(["one", "new", "three"], file["head"]["lines"])
            self.assertEqual(["one", "old", "three"], file["base"]["lines"])
        finally:
            other.close()

    def test_receipts_and_validation(self):
        draft = self.draft()
        receipt = self.mutate(draft)
        recovered = self.mutate(dict(draft, state="unknown"), reconcile=True)
        self.assertEqual(receipt["id"], recovered["id"])
        self.assertTrue(recovered["recovered"])
        for bad in [dict(draft, body="Changed"), self.draft(start=0), self.draft(end=900),
                    self.draft(snapshot="other"), self.draft(side="bad"), self.draft(body=" "),
                    self.draft(kind="reply", thread="unknown"), self.draft(kind="review", event="APPROVE")]:
            with self.assertRaises(ValueError):
                self.mutate(bad)
        with self.assertRaisesRegex(ValueError, "reconciliation did not create"):
            self.mutate(self.draft(), reconcile=True)
        self.assertEqual(1, len(self.snapshot_now()["threads"]))
        self.assertEqual(1, self.backend.db.execute("SELECT count(*) FROM receipts").fetchone()[0])

    def test_concurrent_writes_and_duplicate_retry(self):
        drafts = [self.draft(body="Reviewer " + str(n)) for n in range(6)]
        def write(draft):
            backend = local.LocalBackend(self.store)
            try:
                return backend.request({"op": "mutate", "review": self.review, "draft": draft})
            finally:
                backend.close()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(write, drafts + drafts))
        self.assertEqual(6, len(self.snapshot_now()["threads"]))
        self.assertEqual(6, self.backend.db.execute("SELECT count(*) FROM events").fetchone()[0])

    def test_paths_absent_binary_and_opt_in_untracked(self):
        files = {f["path"]: f for f in self.snapshot["files"]}
        self.assertNotIn("untracked.py", files)
        self.assertEqual("rename.py", files["renamed.py"]["old_path"])
        deleted = self.backend.request({"op": "file", "review": self.review, "snapshot": self.snapshot,
                                        "file": files["deleted.py"]})
        self.assertEqual("absent", deleted["head"]["kind"])
        (self.repo / "odd\t'quote.py").write_text("日本語\n")
        (self.repo / "binary.dat").write_bytes(b"hello\0world")
        new = self.backend.request({"op": "create", "cwd": str(self.repo), "base": "HEAD", "untracked": True})
        files = {f["path"]: f for f in new["snapshot"]["files"]}
        self.assertIn("odd\t'quote.py", files)
        binary = self.backend.request({"op": "file", "review": new["review"], "snapshot": new["snapshot"],
                                       "file": files["binary.dat"]})
        self.assertEqual("binary", binary["head"]["kind"])
        file_draft = {key: new['snapshot'][key] for key in ('head', 'base_tip', 'snapshot')}
        file_draft.update(id=local.identity(), kind='file_comment', path='binary.dat', old_path='binary.dat', body='Binary file feedback')
        self.backend.request({'op': 'mutate', 'review': new['review'], 'draft': file_draft})
        self.assertEqual('file', self.backend.request({'op': 'refresh', 'review': new['review']})['threads'][0]['subject_type'])
        self.assertEqual(b'hello\0world', (self.repo / 'binary.dat').read_bytes())
        with self.assertRaises(ValueError):
            self.backend.request({"op": "file", "review": new["review"], "snapshot": self.snapshot,
                                  "file": files["binary.dat"]})

    def test_capture_does_not_change_index(self):
        before = self.git("diff", "--cached", "--binary").stdout
        self.backend.request({"op": "create", "cwd": str(self.repo), "base": "HEAD", "untracked": True})
        self.assertEqual(before, self.git("diff", "--cached", "--binary").stdout)
        with self.assertRaises(ValueError):
            self.backend.request({"op": "create", "cwd": str(self.repo), "base": "--invalid"})
        self.assertEqual(2, len(self.backend.request({"op": "list"})))

    def test_staged_removal_with_untracked_replacement(self):
        self.git("rm", "--cached", "code.py")
        for include in (False, True):
            opened = self.backend.request({"op": "create", "cwd": str(self.repo), "base": "HEAD", "untracked": include})
            files = [f for f in opened["snapshot"]["files"] if f["path"] == "code.py"]
            self.assertEqual(1, len(files))
            captured = self.backend.request({"op": "file", "review": opened["review"],
                                             "snapshot": opened["snapshot"], "file": files[0]})
            self.assertEqual("text" if include else "absent", captured["head"]["kind"])

    def test_submodule_and_symlink_parent(self):
        commit = self.git("rev-parse", "HEAD").stdout.decode().strip()
        self.git("update-index", "--add", "--cacheinfo", "160000," + commit + ",submodule")
        self.git("commit", "-qm", "submodule pointer")
        self.git("rm", "--cached", "submodule")
        opened = self.backend.request({"op": "create", "cwd": str(self.repo), "base": "HEAD"})
        file = next(f for f in opened["snapshot"]["files"] if f["path"] == "submodule")
        captured = self.backend.request({"op": "file", "review": opened["review"], "snapshot": opened["snapshot"], "file": file})
        self.assertEqual("unavailable", captured["base"]["kind"])
        file_draft = {key: opened['snapshot'][key] for key in ('head', 'base_tip', 'snapshot')}
        file_draft.update(id=local.identity(), kind='file_comment', path=file['path'], old_path=file['old_path'], body='Review the dependency removal')
        self.backend.request({'op': 'mutate', 'review': opened['review'], 'draft': file_draft})
        self.assertEqual('file', self.backend.request({'op': 'refresh', 'review': opened['review']})['threads'][0]['subject_type'])
        outside = self.root / "outside"
        outside.mkdir()
        (outside / "private.txt").write_text("not part of the workspace")
        (self.repo / "link").symlink_to(outside, target_is_directory=True)
        with self.assertRaisesRegex(ValueError, "escapes workspace"):
            local.working_content(self.repo, "link/private.txt")

    def test_real_vim_async_backend_and_cards(self):
        self.mutate(self.draft())
        script = self.root / "integration.vim"
        output = self.root / "errors.txt"
        config = {"root": str(ROOT), "store": str(self.store), "review": self.review,
                  "repo": str(self.repo), "drafts": str(self.root / "drafts"), "errors": str(output)}
        fixture = self.root / "config.json"
        fixture.write_text(json.dumps(config))
        script.write_text("let g:config = json_decode(readfile(" + repr(str(fixture)) + ")[0])\n" + r'''
set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(g:config.root)
runtime plugin/revue.vim
let g:revue_local_dir = g:config.store
let g:revue_draft_dir = g:config.drafts
function! WaitFor(Check) abort
  let deadline = reltime()
  while !a:Check() && reltimefloat(reltime(deadline)) < 10
    sleep 10m
  endwhile
  call assert_true(a:Check(), 'Timed out waiting for local backend')
endfunction
try
  call revue#backends#local#Resume(g:config.review)
  call WaitFor({-> exists('t:revue_session')})
  let g:id = t:revue_session
  call WaitFor({-> !empty(revue#session#Inspect(g:id).loaded)})
  let session = revue#session#Inspect(g:id)
  call assert_equal('local', session.snapshot.backend.id)
  call assert_equal(['one', 'new', 'three'], getbufline(session.head, 1, '$'))
  call assert_equal(0, getbufvar(session.head, '&modifiable'))
  call win_gotoid(session.headwin)
  call cursor(2, 1)
  call assert_true(len(prop_list(2)) > 1)
  call revue#session#Reply()
  let draft = revue#session#Inspect(g:id).drafts[-1]
  call assert_equal(session.snapshot.threads[0].id, draft.thread)
  call setline(1, 'Reply from Vim')
  call revue#session#SaveDraft()
  " The PTY driver answers Save only for this isolated local fixture.
  call revue#session#Send()
  call WaitFor({-> empty(revue#session#Inspect(g:id).drafts) && !revue#session#Inspect(g:id).busy})
  call assert_equal(2, len(revue#session#Inspect(g:id).snapshot.threads[0].comments))
  call win_gotoid(session.headwin)
  " A settings change must not redirect an existing backend binding.
  let g:revue_local_dir = g:config.store . '-other'
  call revue#session#Refresh()
  call WaitFor({-> !revue#session#Inspect(g:id).busy})
  call assert_equal(2, len(revue#session#Inspect(g:id).snapshot.threads[0].comments))
  call assert_equal(session.snapshot.key, revue#session#Inspect(g:id).snapshot.key)
  call assert_false(isdirectory(g:revue_local_dir))
  call assert_true(len(prop_list(2)) > 1)
  let g:original = session.snapshot.snapshot
  call writefile(['one', 'next version', 'three'], g:config.repo . '/code.py')
  ReviewCapture tracked
  call assert_false(&modifiable)
  call assert_match('Exclude untracked', join(getline(1, '$'), "\n"))
  ReviewSend
  call WaitFor({-> empty(revue#session#Inspect(g:id).drafts) && !revue#session#Inspect(g:id).busy})
  call assert_equal(g:original, revue#session#Inspect(g:id).snapshot.snapshot)
  let g:next = revue#session#Inspect(g:id).latest_comparison
  call assert_notequal(g:original, g:next)
  ReviewLatest
  call WaitFor({-> revue#session#Inspect(g:id).snapshot.snapshot ==# g:next && !empty(revue#session#Inspect(g:id).loaded)})
  call assert_equal(['one', 'next version', 'three'], getbufline(session.head, 1, '$'))
  call assert_true(revue#session#Inspect(g:id).snapshot.threads[0].outdated)
  ReviewThreads
  call assert_match('Original source:', join(getline(1, '$'), "\n"))
  ReviewThreadComparison
  call WaitFor({-> revue#session#Inspect(g:id).snapshot.snapshot ==# g:original && !empty(revue#session#Inspect(g:id).loaded)})
  call assert_equal(['one', 'new', 'three'], getbufline(session.head, 1, '$'))
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(2, 1)
  ReviewReply
  call setline(1, 'Reply after recapture from original source')
  " Exercise accepted-reply storage explicitly; ReviewSend now saves pending.
  call revue#session#Send()
  call WaitFor({-> empty(revue#session#Inspect(g:id).drafts) && !revue#session#Inspect(g:id).busy})
  call revue#session#OpenComparison(g:original)
  call WaitFor({-> len(revue#session#Inspect(g:id).snapshot.threads[0].comments) == 3})
  call revue#session#Threads()
  call cursor(1, 1)
  ReviewNextMessage
  ReviewNextMessage
  let g:edit_target = deepcopy(revue#discussion#Selected(revue#session#Inspect(g:id), line('.')))
  ReviewEditMessage
  call assert_equal(g:edit_target.comment, revue#session#Inspect(g:id).drafts[-1].message)
  call setline(1, ['Updated existing reply through the local backend'])
  if line('$') > 1 | 2,$delete _ | endif
  ReviewSend
  call WaitFor({-> empty(revue#session#Inspect(g:id).drafts) && !revue#session#Inspect(g:id).busy})
  call revue#session#OpenComparison(g:original)
  call WaitFor({-> revue#session#Inspect(g:id).snapshot.threads[0].comments[1].body ==# 'Updated existing reply through the local backend'})
  call assert_equal(g:edit_target.comment, revue#session#Inspect(g:id).snapshot.threads[0].comments[1].id)
  call revue#session#Threads()
  call cursor(1, 1)
  ReviewNextMessage
  ReviewReactions
  call WaitFor({-> !empty(get(revue#session#Inspect(g:id), 'reactionrows', {}))})
  for [row, item] in items(revue#session#Inspect(g:id).reactionrows)
    if item.id ==# 'heart' | call cursor(str2nr(row), 1) | break | endif
  endfor
  ReviewReact
  call WaitFor({-> empty(revue#session#Inspect(g:id).drafts) && !revue#session#Inspect(g:id).busy && !empty(get(revue#session#Inspect(g:id), 'reactionrows', {}))})
  call assert_true(filter(copy(revue#session#Inspect(g:id).reaction_data.items), {_, r -> r.id ==# 'heart'})[0].mine)
  call assert_false(isdirectory(g:revue_local_dir))
  call revue#session#Close()
  let g:revue_local_dir = g:config.store
  ReviewSaved
  call WaitFor({-> exists('b:revue_local_reviews')})
  call assert_equal(g:config.review, b:revue_local_reviews[0].id)
  call cursor(3, 1)
  call revue#backends#local#Select()
  call WaitFor({-> exists('t:revue_session')})
  call assert_equal(g:config.review, revue#session#Inspect(t:revue_session).snapshot.backend.review)
  call revue#session#Close()
  execute 'cd ' . fnameescape(g:config.repo)
  Review! HEAD
  call WaitFor({-> exists('t:revue_session')})
  call assert_equal(4, len(revue#session#Inspect(t:revue_session).snapshot.files))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, g:config.errors)
if !empty(v:errors) | cquit | endif
qa!
''')
        master, slave = pty.openpty()
        proc = subprocess.Popen(["vim", "-Nu", "NONE", "-i", "NONE", "-n", "-S", str(script)],
                                stdin=slave, stdout=slave, stderr=slave, env=dict(os.environ, TERM="xterm"))
        os.close(slave)
        transcript = pending = b""
        deadline = time.monotonic() + 40
        try:
            while proc.poll() is None and time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    transcript += chunk
                    pending += chunk
                    if b"(S)ave, [K]eep draft:" in pending:
                        os.write(master, b"s\r")
                        pending = b""
        finally:
            if proc.poll() is None:
                proc.terminate()
            proc.wait(timeout=5)
            os.close(master)
        errors = (output.read_text() if output.exists() else "")
        if proc.returncode:
            errors += transcript.decode("utf-8", "replace")[-10000:]
        self.assertEqual(0, proc.returncode, errors)
        self.assertEqual("", errors)


if __name__ == "__main__":
    unittest.main()
