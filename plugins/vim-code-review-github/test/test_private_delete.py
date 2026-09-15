"""Private deletion scope and recovery; never contacts a provider."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('reviewhub', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


class PrivateDeleteTest(unittest.TestCase):
    def setUp(self):
        self.provider = object.__new__(hub.GitHub)
        self.provider.repo, self.provider.token = 'owner/repo', 'fixture'
        self.parent = {'id': 7, 'state': 'PENDING', 'commit_id': 'head', 'user': {'login': 'alex'}}
        self.comment = {'id': 102, 'node_id': 'comment102', 'in_reply_to_id': 100,
                        'pull_request_review_id': 7, 'body': 'Second reply', 'updated_at': 'then',
                        'user': {'login': 'alex'}}
        self.comments = [self.comment]
        self.other = []
        self.writes = []
        self.permission = True
        self.response = None
        self.actor = 'alex'
        self.provider.api = self.api
        self.provider.pages = self.pages
        self.provider.graphql = self.graphql
        self.draft = {'id': 'delete1', 'kind': 'delete_pending_comment', 'message': '102',
                      'thread': '100', 'message_kind': 'comment', 'pending_review': '7',
                      'actor': 'github-login:alex', 'body': '', 'delete_scope': 'message',
                      'pending_head': 'head', 'original_body': 'Second reply',
                      'expected_version': hub.normalize_comment(self.comment)['version']}

    def api(self, path, method='GET', body=None):
        if method == 'DELETE':
            self.writes.append((path, method, body))
            if isinstance(self.response, Exception): raise self.response
            return self.response
        if path == 'user': return {'login': self.actor}
        self.assertEqual('repos/owner/repo/pulls/42/reviews/7', path)
        return copy.deepcopy(self.parent)

    def pages(self, path):
        if path == 'repos/owner/repo/pulls/42/reviews/7/comments': return copy.deepcopy(self.comments)
        self.assertEqual('repos/owner/repo/pulls/42/comments', path)
        return copy.deepcopy(self.other)

    def graphql(self, query, variables):
        self.assertEqual({'id': self.comment['node_id']}, variables)
        return {'node': {'id': self.comment['node_id'], 'viewerCanDelete': self.permission,
                         'pullRequestReview': {'databaseId': self.parent['id'], 'state': self.parent['state']}}}

    def run_delete(self, reconcile=False, **fields):
        return self.provider.mutate({'number': 42, 'draft': dict(self.draft, **fields), 'reconcile': reconcile})

    def test_exact_reply_receipt_and_endpoint(self):
        receipt = self.run_delete()
        self.assertEqual([('repos/owner/repo/pulls/comments/102', 'DELETE', None)], self.writes)
        self.assertTrue(receipt['deleted'])
        for key in ('id', 'message', 'thread', 'message_kind', 'pending_review', 'actor', 'delete_scope'):
            self.assertEqual(self.draft[key], receipt[key])

    def test_unknown_reads_only_and_can_observe_after_publication(self):
        with self.assertRaises(hub.Failure) as caught: self.run_delete(True)
        self.assertTrue(caught.exception.unknown)
        self.comments = []
        self.parent['state'] = 'COMMENTED'
        self.assertTrue(self.run_delete(True)['observed'])
        self.assertEqual([], self.writes)

    def test_missing_parent_or_lost_access_is_not_success(self):
        self.comments = []
        self.parent['id'] = 99
        with self.assertRaises(hub.Failure): self.run_delete(True)
        self.parent['id'] = 7
        self.provider.pages = lambda path: (_ for _ in ()).throw(hub.Failure('Forbidden', '403'))
        with self.assertRaises(hub.Failure): self.run_delete(True)
        self.assertEqual([], self.writes)

    def test_identity_scope_body_and_version(self):
        for fields in ({'message': '../102'}, {'thread': '101'}, {'message_kind': 'PENDING'},
                       {'actor': 'github-login:other'}, {'delete_scope': 'thread'}, {'body': 'text'},
                       {'expected_version': 'stale'}, {'original_body': 'wrong'}, {'pending_head': 'old'}):
            with self.subTest(fields=fields), self.assertRaises(hub.Failure): self.run_delete(**fields)
        self.assertEqual([], self.writes)

    def test_published_foreign_permission_and_missing_comment(self):
        for key, value in (('state', 'COMMENTED'), ('user', {'login': 'other'})):
            original = self.parent[key]
            self.parent[key] = value
            with self.assertRaises(hub.Failure): self.run_delete()
            self.parent[key] = original
        self.permission = False
        with self.assertRaises(hub.Failure): self.run_delete()
        self.permission = True
        self.comments = []
        with self.assertRaises(hub.Failure): self.run_delete()
        self.assertEqual([], self.writes)

    def test_root_with_replies_never_deletes(self):
        self.comment.pop('in_reply_to_id')
        self.other = [{'id': 103, 'in_reply_to_id': 102}]
        with self.assertRaisesRegex(hub.Failure, 'Root deletion'): self.run_delete(thread='102')
        self.assertEqual([], self.writes)
        self.other = []
        self.assertTrue(self.run_delete(thread='102')['deleted'])

    def test_malformed_and_transport_outcomes_stay_unknown(self):
        for response in ({'id': 102}, hub.Failure('Response too large', 'too_large'), hub.Failure('timeout', 'transport', True)):
            self.response = response
            with self.subTest(response=response), self.assertRaises(hub.Failure) as caught: self.run_delete()
            self.assertTrue(caught.exception.unknown)

    def test_recovery_does_not_treat_foreign_inventory_as_absent(self):
        self.comments = [{'id': 999, 'pull_request_review_id': 9}]
        with self.assertRaises(hub.Failure): self.run_delete(True)
        self.assertEqual([], self.writes)


if __name__ == '__main__': unittest.main()
