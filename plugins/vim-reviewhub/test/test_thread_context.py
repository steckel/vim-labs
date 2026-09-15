"""Historical comment context uses verified immutable source, never guessed bases."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('context_hub', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


class ThreadContextTest(unittest.TestCase):
    def setUp(self):
        self.api = object.__new__(hub.GitHub)
        self.api.repo = 'owner/repo'
        self.head, self.parent = 'a' * 40, 'b' * 40
        self.thread = {'id': '101', 'path': 'code.py', 'side': 'head', 'line': 0, 'start': 0,
                       'original_path': 'code.py', 'original_side': 'head', 'original_start_side': 'head',
                       'original_commit_id': self.head, 'original_line': 2, 'original_start_line': 2,
                       'hunk': '@@ -1,3 +1,3 @@\n one\n-old\n+new\n three', 'outdated': True,
                       'comments': [{'id': '101', 'body': 'Root'}, {'id': '102', 'body': 'Reply'}], 'resolved': False}
        self.current = {'snapshot': 'current', 'base': 'c' * 40, 'head': 'd' * 40, 'base_tip': 'c' * 40,
                        'head_repo': 'fork/repo', 'files': [{'id': 'code.py', 'path': 'code.py', 'old_path': 'code.py', 'status': 'modified', 'patch': ''}],
                        'threads': [self.thread], 'capabilities': {'reply': {'enabled': True}}, 'conversation': []}
        self.commit = {'sha': self.head, 'parents': [{'sha': self.parent}], 'files': [{'filename': 'code.py', 'status': 'modified'}]}
        self.contents = {(self.head, 'code.py'): b'one\nnew\nthree\n', (self.parent, 'code.py'): b'one\nold\nthree\n'}
        self.paths = []
        self.api.open = lambda _, incremental=False: copy.deepcopy(self.current)
        self.api.api = self.read

    def read(self, path, **kwargs):
        self.paths.append(path)
        self.assertFalse('method' in kwargs or 'data' in kwargs)
        if '/commits/' in path:
            return copy.deepcopy(self.commit)
        self.assertTrue(kwargs.get('raw'))
        filename, ref = path.split('/contents/')[1].split('?ref=')
        if (ref, filename) not in self.contents:
            raise hub.Failure('Source unavailable', 'unavailable')
        return self.contents[(ref, filename)]

    def context(self, **target):
        token = hub.original_source(self.thread)['token']
        return self.api.thread_context({'number': 42, 'target': dict(thread='101', token=token, **target)})

    def test_original_head_is_verified_and_reopens_exactly(self):
        result = self.context()
        source = result['snapshot']
        self.assertEqual({'path': 'code.py', 'side': 'head', 'start': 2, 'line': 2}, result['location'])
        self.assertEqual('original-head', source['context']['kind'])
        self.assertIn('not the full original PR diff', source['comparison_note'])
        self.assertEqual(self.head, source['head'])
        self.assertEqual(self.parent, source['base'])
        self.assertFalse(source['capabilities']['comment']['enabled'])
        self.assertTrue(source['capabilities']['reply']['enabled'])
        self.assertEqual('Reply', source['threads'][0]['comments'][1]['body'])
        reference = self.api.comparison_reference(source)
        reopened = self.api.comparison({'number': 42, 'reference': reference})
        self.assertEqual(source, reopened)
        self.assertTrue(all('/fork/repo/' in path for path in self.paths))
        wrong = copy.deepcopy(reference)
        wrong['context']['path'] = 'other.py'
        with self.assertRaisesRegex(hub.Failure, 'identity changed'):
            self.api.comparison({'number': 42, 'reference': wrong})

    def test_base_excerpt_match_is_labeled_and_mismatch_is_unavailable(self):
        self.thread.update(side='base', original_side='base', original_start_side='base')
        result = self.context()
        self.assertEqual('matching-parent', result['snapshot']['context']['kind'])
        self.assertEqual('base', result['location']['side'])
        self.assertIn('not a verified original review base', result['snapshot']['comparison_note'])
        self.contents[(self.parent, 'code.py')] = b'one\nDIFFERENT BASE\nthree\n'
        with self.assertRaisesRegex(hub.Failure, 'does not match the commit parent'):
            self.context()

    def test_wrong_head_excerpt_or_cross_side_range_does_not_jump(self):
        self.contents[(self.head, 'code.py')] = b'one\nwrong historical path\nthree\n'
        with self.assertRaisesRegex(hub.Failure, 'could not be verified'):
            self.context()
        self.thread['original_start_side'] = 'base'
        with self.assertRaisesRegex(hub.Failure, 'unsupported sides'):
            self.context()

    def test_rename_recovers_explicit_old_path_and_parent_path(self):
        self.thread.update(path='current.py', original_path='current.py')
        self.current['files'][0].update(path='current.py', old_path='code.py')
        self.commit['files'][0].update(status='renamed', previous_filename='old.py')
        self.contents[(self.parent, 'old.py')] = self.contents.pop((self.parent, 'code.py'))
        result = self.context()
        self.assertEqual('code.py', result['location']['path'])
        self.assertEqual('old.py', result['snapshot']['files'][0]['old_path'])

    def test_deleted_and_binary_file_context(self):
        self.thread.update(subject_type='file', original_line=0, original_start_line=0)
        self.commit['files'][0]['status'] = 'removed'
        result = self.context()
        self.assertEqual('base', result['location']['side'])
        self.assertEqual('commit-parent-file', result['snapshot']['context']['kind'])
        self.assertNotIn('matches the original excerpt', result['snapshot']['context']['note'])
        self.commit['files'][0]['status'] = 'modified'
        self.contents[(self.head, 'code.py')] = b'\0binary'
        self.assertEqual('head', self.context()['location']['side'])

    def test_root_commit_and_missing_history(self):
        self.commit['parents'] = []
        self.commit['files'][0]['status'] = 'added'
        self.thread['hunk'] = '@@ -0,0 +1,3 @@\n+one\n+new\n+three'
        result = self.context()
        self.assertEqual('empty-parent:' + self.head, result['snapshot']['base'])
        self.assertIn('root commit', result['snapshot']['comparison_note'])
        with patch.object(self.api, 'api', side_effect=hub.Failure('Commit unavailable', 'unavailable')):
            with self.assertRaisesRegex(hub.Failure, 'Commit unavailable'):
                self.context()

    def test_membership_and_anchor_changes_reject_before_source_read(self):
        for target in ({'thread': 'other', 'token': hub.original_source(self.thread)['token']}, {'thread': '101', 'token': 'stale'}):
            with self.assertRaises(hub.Failure):
                self.api.thread_context({'number': 42, 'target': target})
        self.assertEqual([], self.paths)
        first = hub.original_source(self.thread)['token']
        self.thread['comments'][0]['body'] = 'Edited prose'
        self.assertEqual(first, hub.original_source(self.thread)['token'])
        self.thread['original_line'] = 3
        self.assertNotEqual(first, hub.original_source(self.thread)['token'])

    def late_thread(self):
        self.thread['native_id'] = 'PRRT_101'
        self.current.update(snapshot=self.current['base'] + ':' + self.current['head'],
                            threads=[], feedback={'cursor': 'page-2'},
                            inventory={'threads': {'state': 'partial', 'total': 30}})
        self.current['capabilities'].update(feedback_lookup={'enabled': True}, feedback_page={'enabled': True})

    def page(self, threads, cursor='page-2', next_cursor='page-3'):
        return {'snapshot': self.current['snapshot'], 'cursor': cursor, 'next_cursor': next_cursor,
                'threads': copy.deepcopy(threads), 'inventory': {'threads': {'state': 'partial' if next_cursor else 'complete'}}}

    def test_later_page_uses_native_lookup_and_legacy_reference_reopens(self):
        self.late_thread()
        with patch.object(self.api, 'open', return_value=copy.deepcopy(self.current)) as opening, \
             patch.object(self.api, 'feedback_lookup', return_value={'thread': copy.deepcopy(self.thread)}) as lookup, \
             patch.object(self.api, 'feedback_page', return_value=self.page([self.thread])) as page:
            result = self.context(lookup='PRRT_101')
            opening.assert_called_once_with(42,incremental=True)
            self.assertEqual('PRRT_101', lookup.call_args.args[0]['target']['lookup'])
            self.assertEqual('101', lookup.call_args.args[0]['target']['message'])
            page.assert_not_called()
            snapshot = result['snapshot']
            self.assertEqual('page-2', snapshot['feedback']['cursor'])
            self.assertEqual('partial', snapshot['inventory']['threads']['state'])
            self.assertEqual(['101'], [t['id'] for t in snapshot['threads']])
            # Context identities stay compatible; no new locator is required in
            # a saved reference. Reopening may use bounded paging instead.
            reference = self.api.comparison_reference(snapshot)
            self.assertNotIn('lookup', reference['context'])
            opening.return_value=copy.deepcopy(self.current)
            self.assertEqual(snapshot, self.api.comparison({'number':42,'reference':reference}))
            page.assert_called_once()

    def test_paging_retains_only_target_and_preserves_cursor(self):
        self.late_thread()
        other = dict(self.thread, id='201', native_id='PRRT_201')
        pages = [self.page([other]), self.page([self.thread], 'page-3', '')]
        with patch.object(self.api, 'feedback_page', side_effect=pages) as page:
            snapshot = self.context()['snapshot']
        self.assertEqual(2,page.call_count)
        self.assertEqual(['101'],[t['id'] for t in snapshot['threads']])
        self.assertEqual('page-2',snapshot['feedback']['cursor'])
        self.assertEqual('partial',snapshot['inventory']['threads']['state'])

    def test_mixed_lookup_falls_back_but_scope_failures_do_not(self):
        self.late_thread()
        with patch.object(self.api, 'feedback_lookup', side_effect=hub.Failure('Use ordinary feedback paging','incomplete')), \
             patch.object(self.api, 'feedback_page', return_value=self.page([self.thread])) as page:
            self.assertEqual('101',self.context(lookup='PRRT_101')['thread'])
            page.assert_called_once()
        for code in ['stale','unavailable','permission']:
            with patch.object(self.api, 'feedback_lookup', side_effect=hub.Failure('Scope changed',code)), \
                 patch.object(self.api, 'feedback_page') as page, self.assertRaisesRegex(hub.Failure,'Scope changed'):
                self.context(lookup='PRRT_101')
            page.assert_not_called()

    def test_bad_anchor_or_locator_never_reads_historical_source(self):
        self.late_thread()
        for change in [{'native_id':'PRRT_foreign'}, {'hunk':'changed excerpt'}]:
            with patch.object(self.api, 'feedback_lookup', return_value={'thread':dict(self.thread,**change)}), \
                 self.assertRaises(hub.Failure):
                self.context(lookup='PRRT_101')
        self.assertEqual([],self.paths)
        with self.assertRaisesRegex(hub.Failure,'thread identity'):
            self.context(lookup=['not a locator'])

    def test_paging_cycles_and_revision_changes_stop_before_source(self):
        self.late_thread()
        for page in [self.page([],next_cursor='page-2'),dict(self.page([]),snapshot='different')]:
            with patch.object(self.api, 'feedback_page',return_value=page), self.assertRaises(hub.Failure):
                self.context()
        self.assertEqual([],self.paths)

    def test_paging_has_a_hard_continuation_bound(self):
        self.late_thread()
        def next_page(request):
            cursor=request['cursor']
            return self.page([],cursor,'page-'+str(int(cursor.split('-')[1])+1))
        with patch.object(self.api,'feedback_page',side_effect=next_page) as page, self.assertRaisesRegex(hub.Failure,'page limit'):
            self.context()
        self.assertEqual(100,page.call_count)
        self.assertEqual([],self.paths)

    def test_direct_context_composes_real_lookup_membership_guard(self):
        import test_feedback_pages as fixtures
        self.late_thread()
        self.api.conn = {'host':'github.example'}
        self.api.token = 'fixture'
        node = fixtures.thread()
        node.update(originalLine=2, originalStartLine=2, isOutdated=True, line=None)
        node['comments']['nodes'][0].update(diffHunk=self.thread['hunk'],originalCommit={'oid':self.head})
        pr = {'number':42,'repository':{'nameWithOwner':self.api.repo},
              'headRefOid':self.current['head'],'baseRefOid':self.current['base_tip'],
              'updatedAt':'2026-09-14T00:00:00Z','reviews':{'nodes':[]}}
        node['pullRequest'] = copy.deepcopy(pr)
        calls=[]
        def graphql(query, variables, write=False):
            self.assertFalse(write)
            self.assertNotIn('mutation',query)
            calls.append(variables)
            return {'viewer':{'login':'alex'},'node':copy.deepcopy(node)} if 'id' in variables else {'viewer':{'login':'alex'},'repository':{'pullRequest':copy.deepcopy(pr)}}
        self.api.graphql=graphql
        self.thread=self.api.feedback_thread(node)
        result=self.context(lookup='PRRT_101')
        self.assertEqual(2,len(calls))
        self.assertEqual(['101','102'],[m['id'] for m in result['snapshot']['threads'][0]['comments']])
        self.assertIn('not the full original PR diff',result['snapshot']['comparison_note'])
        node['pullRequest']['number']=99
        with self.assertRaisesRegex(hub.Failure,'unavailable in the requested review'):
            self.context(lookup='PRRT_101')


if __name__ == '__main__':
    unittest.main()
