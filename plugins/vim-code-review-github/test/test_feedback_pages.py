"""GitHub continuation preserves complete threads and native message preconditions."""
import copy
import importlib.util
import json
import threading
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('feedback_hub', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


def message(identity, reply=None):
    return {'fullDatabaseId': str(identity), 'body': 'Body ' + str(identity), 'createdAt': '2026-09-14T00:00:00Z',
            'updatedAt': '2026-09-14T01:00:00Z', 'url': 'https://example.test/' + str(identity),
            'author': {'login': 'alex', 'databaseId': 7, '__typename': 'User'}, 'authorAssociation': 'MEMBER',
            'viewerCanUpdate': True, 'viewerCanReact': True, 'reactionGroups': [], 'state': 'SUBMITTED',
            'path': 'code.py', 'diffHunk': '@@ -1 +1 @@\n-old\n+new', 'originalCommit': {'oid': 'b'*40},
            'replyTo': {'fullDatabaseId': str(reply)} if reply else None}


def connection(nodes, after=None, total=None):
    return {'nodes': nodes, 'totalCount': len(nodes) if total is None else total,
            'pageInfo': {'hasNextPage': after is not None, 'endCursor': after}}


def thread(identity=101):
    return {'id': 'PRRT_' + str(identity), 'path': 'code.py', 'diffSide': 'RIGHT', 'startDiffSide': None,
            'line': 1, 'startLine': None, 'originalLine': 1, 'originalStartLine': None, 'subjectType': 'LINE',
            'isOutdated': False, 'isResolved': False, 'resolvedBy': None,
            'viewerCanReply': True, 'viewerCanResolve': True, 'viewerCanUnresolve': False,
            'comments': connection([message(identity), message(identity+1, identity)])}


class FeedbackTest(unittest.TestCase):
    def setUp(self):
        self.api = object.__new__(hub.GitHub)
        self.api.conn = {'host': 'github.example', 'repo': 'owner/repo'}
        self.api.repo, self.api.token = 'owner/repo', 'fixture'
        self.ref = {'snapshot': 'a'*40 + ':' + 'b'*40, 'base': 'a'*40, 'head': 'b'*40, 'base_tip': 'c'*40}
        self.pr = {'headRefOid': self.ref['head'], 'baseRefOid': self.ref['base_tip'], 'updatedAt': '2026-09-14T02:00:00Z',
                   'reviews': {'nodes': []}, 'reviewThreads': connection([thread()], 'next-thread', 2),
                   'comments': connection([message(501)], 'next-comment', 2)}
        self.viewer = 'alex'
        self.calls, self.nested = [], None
        self.guard_override = None
        def graphql(query, variables, write=False):
            self.assertFalse(write)
            self.assertTrue(query.startswith('query('))
            self.assertNotIn('mutation', query)
            self.calls.append((query, copy.deepcopy(variables)))
            if variables.get('id'):
                if isinstance(self.nested, Exception):
                    raise self.nested
                return {'node': {'comments': copy.deepcopy(self.nested)}}
            pr = self.guard_override if 'threads' not in variables and self.guard_override else self.pr
            return {'viewer': {'login': self.viewer}, 'repository': {'pullRequest': copy.deepcopy(pr)}}
        self.api.graphql = graphql

    def read(self, cursor=''):
        return self.api.feedback_page({'number': 42, 'reference': self.ref, 'cursor': cursor})

    def test_pages_bind_review_actor_and_comparison(self):
        first = self.read()
        self.assertFalse(first['complete'])
        self.assertEqual(['101', '102'], [m['id'] for m in first['threads'][0]['comments']])
        self.assertTrue(first['threads'][0]['capabilities']['pending_reply']['enabled'])
        self.pr['reviewThreads'] = connection([thread(201)], total=2)
        self.pr['comments'] = connection([message(601)], total=2)
        second = self.read(first['next_cursor'])
        self.assertTrue(second['complete'])
        self.assertEqual('', second['next_cursor'])
        self.assertEqual('next-thread', self.calls[-2][1]['ta'])
        self.assertEqual('next-comment', self.calls[-2][1]['ca'])
        self.assertEqual('complete', second['inventory']['thread_state']['state'])
        self.assertEqual(first['next_cursor'], second['cursor'])

    def test_exhausted_connection_is_not_requested_again(self):
        self.pr['reviewThreads'] = connection([thread()])
        first = self.read()
        self.pr['comments'] = connection([message(601)], total=2)
        self.read(first['next_cursor'])
        self.assertFalse(self.calls[-2][1]['threads'])
        self.assertTrue(self.calls[-2][1]['conversation'])

    def test_all_nested_reply_pages_are_loaded_before_a_thread_is_exposed(self):
        self.pr['reviewThreads']['nodes'][0]['comments'] = connection([message(101), message(102, 101)], 'reply-next', 3)
        self.nested = connection([message(103, 101)])
        result = self.read()
        self.assertEqual(['101', '102', '103'], [m['id'] for m in result['threads'][0]['comments']])
        self.assertEqual('PRRT_101', self.calls[1][1]['id'])
        self.assertEqual('reply-next', self.calls[1][1]['after'])

    def test_file_comment_with_no_line_or_side_retains_file_scope(self):
        node = thread()
        node.update(subjectType='FILE', line=None, startLine=None, diffSide=None)
        result = self.api.feedback_thread(node)
        self.assertEqual(('file', '', 0, 0), tuple(result[k] for k in ('subject_type', 'side', 'start', 'line')))
        self.assertFalse(result['outdated'])

    def test_missing_or_changed_nested_replies_fail_the_whole_page(self):
        self.pr['reviewThreads']['nodes'][0]['comments'] = connection([message(101)], 'reply-next', 2)
        for extra in [connection([message(101)]), connection([message(102, 999)]), connection([]),
                      connection([message(102, 101)], 'reply-next'), hub.Failure('Reply read failed')]:
            self.nested = extra
            with self.subTest(extra=extra), self.assertRaises(hub.Failure):
                self.read()

    def test_changed_source_actor_private_review_or_inventory_requires_refresh(self):
        first = self.read()
        original = copy.deepcopy(self.pr)
        for key, value in [('headRefOid', 'changed'), ('baseRefOid', 'changed'), ('updatedAt', 'new timestamp'),
                           ('reviews', {'nodes': [{'id': 'private-review'}]})]:
            self.pr = dict(original, **{key: value})
            with self.subTest(key=key), self.assertRaises(hub.Failure):
                self.read(first['next_cursor'])
        self.pr = original
        self.viewer = 'another-person'
        with self.assertRaises(hub.Failure):
            self.read(first['next_cursor'])
        self.viewer = 'alex'
        self.guard_override = dict(original, reviews={'nodes': [{'id': 'late-private-review'}]})
        with self.assertRaisesRegex(hub.Failure, 'private review'):
            self.read()

    def test_invalid_cursors_do_not_send_requests(self):
        saved = json.loads(self.read()['next_cursor'])
        self.calls.clear()
        cases = [None, [], '[]', '{}', 'null', 'malformed']
        cases += [json.dumps(dict(saved, **{key: value})) for key, value in
                  [('review', 'other'), ('reference', {}), ('viewer', ''), ('threads_done', 1), ('threads_after', None)]]
        for cursor in cases:
            with self.subTest(cursor=cursor), self.assertRaises(hub.Failure):
                self.read(cursor)
        self.assertEqual([], self.calls)

    def test_changed_total_requires_refresh_even_if_update_marker_is_unchanged(self):
        first = self.read()
        self.pr['reviewThreads'] = connection([thread(201)], 'next-thread-2', 3)
        with self.assertRaisesRegex(hub.Failure, 'count changed'):
            self.read(first['next_cursor'])

    def test_rest_and_graphql_message_versions_and_native_permissions_agree(self):
        node = message(101)
        rest = {'id': 101, 'body': node['body'], 'created_at': node['createdAt'], 'updated_at': node['updatedAt'],
                'html_url': node['url'], 'user': {'id': 7, 'login': 'alex'}, 'author_association': 'MEMBER'}
        projected = hub.feedback_message(node)
        self.assertEqual(hub.normalize_comment(rest)['version'], projected['version'])
        node['viewerCanUpdate'] = False
        projected = hub.feedback_message(node)
        hub.feedback_message_rules([projected], 'alex')
        hub.feedback_message_rules([projected], 'alex')
        self.assertFalse(projected['capabilities']['edit']['enabled'])
        self.assertEqual('Member', projected['author_role'])
        self.assertEqual(8, len(projected['reactions']['items']))

    def configure_open(self, pending=False):
        pr = {'head': {'sha': self.ref['head']}, 'base': {'sha': self.ref['base_tip']}, 'user': {'login': 'author'},
              'title': 'Review', 'html_url': 'https://example.test/pr', 'state': 'open', 'changed_files': 1}
        self.rest_calls = []
        self.api.api = lambda path: {'merge_base_commit': {'sha': self.ref['base']}} if '/compare/' in path else copy.deepcopy(pr)
        review = {'id': 7, 'state': 'PENDING' if pending else 'APPROVED', 'user': {'login': 'alex'}, 'body': 'Summary',
                  'submitted_at': '2026-09-14T03:00:00Z', 'commit_id': self.ref['head']}
        self.open_review = review
        def pages(path):
            self.rest_calls.append(path)
            if path.endswith('/files'):
                return [{'filename': 'code.py', 'status': 'modified', 'additions': 1, 'deletions': 1}]
            if path.endswith('/reviews'):
                return [copy.deepcopy(review)]
            return []
        self.api.pages = pages
        self.api.action_rules = lambda _: ({}, ['COMMENT'], 'alex')
        self.api.thread_states = lambda _: {}
        self.api.load_pending = lambda number, identity: (copy.deepcopy(review), [])

    def test_initial_open_pages_feedback_but_keeps_reviews_and_source(self):
        self.configure_open()
        opened = self.api.open(42, incremental=True)
        self.assertTrue(opened['feedback']['cursor'])
        self.assertEqual(self.ref['snapshot'], opened['snapshot'])
        self.assertEqual(['comment', 'APPROVED'], [m['kind'] for m in opened['conversation']])
        self.assertTrue(opened['capabilities']['feedback_page']['enabled'])
        self.assertTrue(opened['capabilities']['feedback_refresh']['enabled'])
        self.assertFalse(any(path.endswith('/comments') for path in self.rest_calls))
        self.assertEqual('partial', opened['inventory']['threads']['state'])
        self.assertEqual(2, opened['inventory']['threads']['total'])
        self.assertEqual(3, opened['inventory']['conversation']['total'])
        self.assertEqual('101', opened['threads'][0]['id'])

    def test_pending_inventory_keeps_full_reader_and_schema_failure_falls_back(self):
        self.configure_open(pending=True)
        opened = self.api.open(42, incremental=True)
        self.assertNotIn('feedback', opened)
        self.assertEqual('7', opened['pending_reviews']['items'][0]['id'])
        self.assertEqual(2, len(self.calls), "Try paging, then retain the complete fallback when private identity disagrees")
        self.assertEqual(2, sum(path.endswith('/comments') for path in self.rest_calls))
        self.configure_open()
        self.api.graphql = lambda *args, **kwargs: (_ for _ in ()).throw(hub.Failure('Schema unavailable', 'graphql'))
        opened = self.api.open(42, incremental=True)
        self.assertFalse(opened['capabilities']['feedback_page']['enabled'])
        self.assertIn('complete inventory', opened['feedback_loading_note'])
        self.assertEqual(2, sum(path.endswith('/reviews') for path in self.rest_calls))

    def test_private_review_appearing_during_initial_page_reloads_private_inventory(self):
        self.configure_open()
        def changed(*args, **kwargs):
            self.open_review['state'] = 'PENDING'
            raise hub.Failure('Private review appeared', 'stale')
        self.api.graphql = changed
        opened = self.api.open(42, incremental=True)
        self.assertEqual('7', opened['pending_reviews']['items'][0]['id'])
        self.assertNotIn('feedback', opened)
        self.assertFalse(opened['capabilities']['feedback_page']['enabled'])

    def test_private_reply_in_public_thread_keeps_native_edit_and_delete_targets(self):
        self.configure_open(pending=True)
        public = {'id': 101, 'path': 'code.py', 'line': 1, 'body': 'Public root', 'user': {'login': 'another-person'}}
        private = {'id': 102, 'path': 'code.py', 'line': 1, 'in_reply_to_id': 101, 'pull_request_review_id': 7,
                   'body': 'Private reply', 'user': {'login': 'alex'}}
        original = self.api.pages
        self.api.pages = lambda path: [public] if path.endswith('/pulls/42/comments') else original(path)
        self.api.load_pending = lambda number, identity: (copy.deepcopy(self.open_review), [private])
        opened = self.api.open(42, incremental=True)
        root, reply = opened['threads'][0]['comments']
        self.assertEqual(['101', '102'], [root['id'], reply['id']])
        self.assertFalse(root['capabilities']['edit']['enabled'])
        self.assertEqual('7', reply['pending_review'])
        self.assertEqual('pending', reply['publication'])
        self.assertTrue(reply['capabilities']['edit']['enabled'])
        self.assertTrue(reply['capabilities']['delete']['enabled'])

    def private_node(self, total=2):
        return {'id': 'PRR_7', 'fullDatabaseId': '7', 'state': 'PENDING', 'body': 'Summary',
                'updatedAt': '2026-09-14T05:00:00Z', 'url': 'https://example.test/review/7',
                'commit': {'oid': self.ref['head']}, 'author': {'login': 'alex'}, 'comments': {'totalCount': total}}

    def private_thread(self, identity=101):
        node = thread(identity)
        for m in node['comments']['nodes']:
            m.update(state='PENDING', pullRequestReview={'fullDatabaseId': '7'})
        return node

    def private_read(self, cursor=''):
        return self.api.feedback_page({'number': 42, 'reference': self.ref, 'cursor': cursor, 'allow_pending': True})

    def test_private_pages_keep_complete_threads_and_partial_review_coverage(self):
        self.pr['reviews'] = {'nodes': [self.private_node(4)], 'totalCount': 1}
        self.pr['reviewThreads'] = connection([self.private_thread()], 'later', 2)
        self.pr['comments'] = connection([])
        first = self.private_read()
        pending = first['pending_reviews']['items'][0]
        self.assertEqual((2, 4, False, ''), (len(pending['comments']), pending['total'], pending['complete'], pending['version']))
        self.assertEqual(['pending', 'pending'], [m['publication'] for m in first['threads'][0]['comments']])
        self.assertTrue(first['threads'][0]['capabilities']['pending_reply']['enabled'])
        self.assertFalse(first['threads'][0]['capabilities']['reply']['enabled'])
        self.assertFalse(first['threads'][0]['capabilities']['resolve']['enabled'])
        self.assertFalse(first['threads'][0]['comments'][0]['capabilities']['delete']['enabled'])
        self.assertTrue(first['threads'][0]['comments'][1]['capabilities']['delete']['enabled'])
        self.assertTrue(first['threads'][0]['comments'][1]['capabilities']['edit']['enabled'])
        self.assertFalse(first['threads'][0]['comments'][1]['capabilities']['reaction']['enabled'])
        self.pr['reviewThreads'] = connection([self.private_thread(201)], total=2)
        second = self.private_read(first['next_cursor'])
        self.assertTrue(second['complete'])
        self.assertEqual(pending['read_version'], second['pending_reviews']['items'][0]['read_version'])
        self.assertEqual(['201', '202'], [t['message'] for t in second['pending_reviews']['items'][0]['comments']])
        self.assertNotIn('Body 101', second['cursor'])
        self.assertNotIn('Summary', second['cursor'])

    def test_private_reply_in_public_paged_thread_retains_its_private_parent(self):
        self.pr['reviews'] = {'nodes': [self.private_node(1)], 'totalCount': 1}
        node = thread()
        node['comments']['nodes'][1].update(state='PENDING', pullRequestReview={'fullDatabaseId': '7'}, viewerCanUpdate=False)
        self.pr['reviewThreads'] = connection([node])
        result = self.private_read()
        root, reply = result['threads'][0]['comments']
        self.assertNotEqual('pending', root.get('publication'))
        self.assertEqual(('7', 'github-login:alex'), (reply['pending_review'], reply['actor']))
        self.assertFalse(reply['capabilities']['edit']['enabled'])
        self.assertTrue(result['threads'][0]['capabilities']['reply']['enabled'])
        self.assertEqual('101', result['pending_reviews']['items'][0]['comments'][0]['thread'])

    def test_private_change_publication_actor_and_foreign_message_reject_pages(self):
        self.pr['reviews'] = {'nodes': [self.private_node()], 'totalCount': 1}
        self.pr['reviewThreads'] = connection([self.private_thread()], 'later', 2)
        first = self.private_read()
        original = copy.deepcopy(self.pr)
        for field, value in [('body', 'Changed privately'), ('updatedAt', 'changed'), ('comments', {'totalCount': 3}), ('state', 'COMMENTED'), ('author', {'login': 'someone-else'})]:
            self.pr = copy.deepcopy(original)
            self.pr['reviews']['nodes'][0][field] = value
            with self.subTest(field=field), self.assertRaises(hub.Failure):
                self.private_read(first['next_cursor'])
        self.pr = copy.deepcopy(original)
        self.pr['reviews'] = {'nodes': [], 'totalCount': 0}
        with self.assertRaises(hub.Failure):
            self.private_read(first['next_cursor'])
        self.pr = copy.deepcopy(original)
        self.pr['reviewThreads']['nodes'][0]['comments']['nodes'][1]['pullRequestReview']['fullDatabaseId'] = '999'
        with self.assertRaisesRegex(hub.Failure, 'review or author'):
            self.private_read()

    def test_private_open_does_not_fetch_all_comments_and_preserves_native_edit(self):
        self.configure_open(pending=True)
        self.pr['reviews'] = {'nodes': [self.private_node()], 'totalCount': 1}
        self.pr['reviewThreads'] = connection([self.private_thread()])
        self.api.load_pending = lambda *args: self.fail('Opening paged feedback must not hydrate the private review')
        opened = self.api.open(42, incremental=True)
        self.assertFalse(any(path.endswith('/comments') for path in self.rest_calls))
        self.assertFalse(opened['pending_reviews']['items'][0]['complete'])
        self.assertTrue(opened['capabilities']['verify_pending']['enabled'])
        self.assertTrue(opened['threads'][0]['comments'][1]['capabilities']['edit']['enabled'])
        self.assertTrue(opened['threads'][0]['capabilities']['pending_reply']['enabled'])
        self.assertEqual(2, opened['inventory']['conversation']['total'], 'pending summary is not a public conversation item')

    def test_verification_uses_complete_rest_inventory_without_writing(self):
        self.configure_open(pending=True)
        self.pr['reviews'] = {'nodes': [self.private_node()], 'totalCount': 1}
        self.pr['reviewThreads'] = connection([self.private_thread()])
        first = self.private_read()
        header = first['pending_reviews']['items'][0]
        raw = [{'id': i, 'body': 'Body ' + str(i), 'user': {'login': 'alex'}, 'path': 'code.py', 'side': 'RIGHT',
                'line': 1, 'pull_request_review_id': 7, **({'in_reply_to_id': 101} if i == 102 else {})} for i in (101, 102)]
        self.api.load_pending = lambda *args: (copy.deepcopy(self.open_review), copy.deepcopy(raw))
        request = {'number': 42, 'reference': self.ref, 'target': {'review': '7', 'actor': header['actor'], 'read_version': header['read_version']}}
        result = self.api.verify_pending(request)
        self.assertTrue(result['review']['complete'])
        self.assertEqual(2, len(result['review']['comments']))
        self.assertEqual(hub.pending_record(self.open_review, raw, header['actor'])['version'], result['review']['version'])
        self.pr['reviews']['nodes'][0]['body'] = 'Edited elsewhere'
        with self.assertRaisesRegex(hub.Failure, 'changed'):
            self.api.verify_pending(request)
        self.pr['reviews']['nodes'][0]['body'] = 'Summary'
        self.api.load_pending = lambda *args: (copy.deepcopy(self.open_review), raw[:1])
        with self.assertRaisesRegex(hub.Failure, 'changed'):
            self.api.verify_pending(request)

    def test_complete_thread_inventory_cannot_omit_private_comments(self):
        self.pr['reviews'] = {'nodes': [self.private_node(3)], 'totalCount': 1}
        self.pr['reviewThreads'] = connection([self.private_thread()])
        with self.assertRaisesRegex(hub.Failure, 'not fully represented'):
            self.private_read()
        self.pr['reviews']['nodes'][0]['comments']['totalCount'] = 1
        with self.assertRaises(hub.Failure):
            self.private_read()

    def test_verification_rechecks_private_generation_after_complete_read(self):
        self.configure_open(pending=True)
        self.pr['reviews'] = {'nodes': [self.private_node(0)], 'totalCount': 1}
        self.pr['reviewThreads'] = connection([])
        header = self.private_read()['pending_reviews']['items'][0]
        request = {'number': 42, 'reference': self.ref, 'target': {'review': '7', 'actor': header['actor'], 'read_version': header['read_version']}}
        def changed(*args):
            self.pr['reviews']['nodes'][0]['updatedAt'] = 'changed during verification'
            return copy.deepcopy(self.open_review), []
        self.api.load_pending = changed
        with self.assertRaisesRegex(hub.Failure, 'changed while verifying'):
            self.api.verify_pending(request)

    def test_open_overlaps_independent_reads_before_identity_checks(self):
        self.configure_open()
        barrier = threading.Barrier(4, timeout=3)
        seen = []
        original_api, original_pages, original_rules = self.api.api, self.api.pages, self.api.action_rules
        def rendezvous(label):
            seen.append(label)
            barrier.wait()
        def api(path):
            if '/compare/' in path:
                rendezvous('merge base')
            else:
                # The first identity read precedes the wave; subsequent reads
                # must occur only after all independent reads were scheduled.
                if seen:
                    self.assertEqual(4, len(seen))
            return original_api(path)
        def pages(path):
            if path.endswith('/files') or path.endswith('/reviews'):
                rendezvous(path.rsplit('/', 1)[-1])
            return original_pages(path)
        def rules(pr):
            rendezvous('actor')
            return original_rules(pr)
        self.api.api, self.api.pages, self.api.action_rules = api, pages, rules
        opened = self.api.open(42, incremental=True)
        self.assertEqual({'files', 'reviews', 'merge base', 'actor'}, set(seen))
        self.assertEqual(self.ref['snapshot'], opened['snapshot'])
        self.assertEqual(2, len(self.calls), 'Page and post-page inventory guard remain')

    def test_parallel_open_still_rejects_changed_source_and_actor(self):
        self.configure_open()
        original = self.api.api
        identities = []
        def changed(path):
            result = original(path)
            if '/compare/' not in path:
                identities.append(path)
                if len(identities) > 1:
                    result['head']['sha'] = 'changed'
            return result
        self.api.api = changed
        with self.assertRaisesRegex(hub.Failure, 'PR changed'):
            self.api.open(42, incremental=True)
        self.configure_open()
        self.api.action_rules = lambda _: ({}, [], 'different-actor')
        with self.assertRaisesRegex(hub.Failure, 'actor changed'):
            self.api.open(42, incremental=True)

    def test_parallel_initial_read_failure_never_returns_partial_snapshot(self):
        self.configure_open()
        original = self.api.pages
        self.api.pages = lambda path: (_ for _ in ()).throw(hub.Failure('Files unavailable', 'transport')) if path.endswith('/files') else original(path)
        with self.assertRaisesRegex(hub.Failure, 'Files unavailable'):
            self.api.open(42, incremental=True)

    def test_successful_page_guard_is_the_last_remote_read(self):
        self.configure_open()
        events = []
        original_api, original_graphql = self.api.api, self.api.graphql
        def api(path):
            events.append(('rest', path))
            return original_api(path)
        def graphql(query, variables, write=False):
            events.append(('graphql', 'page' if 'threads' in variables else 'guard'))
            return original_graphql(query, variables, write)
        self.api.api, self.api.graphql = api, graphql
        self.api.open(42, incremental=True)
        self.assertEqual(('graphql', 'guard'), events[-1])
        self.assertEqual(2, sum(kind == 'rest' and path.endswith('/pulls/42') for kind, path in events))
        # Schema fallback lacks that successful final guard and retains REST.
        events.clear()
        self.api.graphql = lambda *args, **kwargs: (_ for _ in ()).throw(hub.Failure('Unsupported schema'))
        self.api.open(42, incremental=True)
        self.assertEqual(('rest', 'repos/owner/repo/pulls/42'), events[-1])
        self.assertEqual(3, sum(kind == 'rest' and path.endswith('/pulls/42') for kind, path in events))


if __name__ == '__main__':
    unittest.main()
