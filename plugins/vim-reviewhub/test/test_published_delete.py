"""Published comment deletion contracts; all service responses are fixtures."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('reviewhub_delete', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


class PublishedDeleteTest(unittest.TestCase):
    def setUp(self):
        self.provider = object.__new__(hub.GitHub)
        self.provider.repo, self.provider.token = 'owner/repo', 'fixture'
        self.actor = 'alex'
        self.comment = {'id': 102, 'node_id': 'node102', 'in_reply_to_id': 100, 'body': 'Second reply',
                        'updated_at': 'then', 'user': {'login': 'alex'},
                        'pull_request_url': 'https://api.github.com/repos/owner/repo/pulls/42',
                        'issue_url': 'https://api.github.com/repos/owner/repo/issues/42'}
        self.comments = [self.comment]
        self.permission, self.state, self.response = True, 'COMMENTED', None
        self.writes = []
        self.final = None
        self.pr = {'number': 42}
        self.provider.api, self.provider.pages, self.provider.graphql = self.api, self.pages, self.graphql
        self.draft = {'id': 'delete1', 'kind': 'delete_message', 'message': '102', 'message_kind': 'comment',
                      'thread': '100', 'actor': 'github-login:alex', 'delete_scope': 'message', 'body': '',
                      'original_body': 'Second reply', 'expected_version': hub.normalize_comment(self.comment)['version']}

    def api(self, path, method='GET', body=None):
        if method == 'DELETE':
            self.writes.append(path)
            if isinstance(self.response, Exception): raise self.response
            return self.response
        if path == 'user': return {'login': self.actor}
        if path == 'repos/owner/repo/pulls/42':
            if isinstance(self.pr, Exception): raise self.pr
            return copy.deepcopy(self.pr)
        self.assertIn(path, ['repos/owner/repo/pulls/comments/102', 'repos/owner/repo/issues/comments/102'])
        return copy.deepcopy(self.final or self.comment)

    def pages(self, path):
        self.assertIn(path, ['repos/owner/repo/pulls/42/comments', 'repos/owner/repo/issues/42/comments'])
        return copy.deepcopy(self.comments)

    def graphql(self, query, variables):
        self.assertEqual({'id': 'node102'}, variables)
        return {'node': {'id': 'node102', 'body': self.comment['body'], 'viewerCanDelete': self.permission,
                         'pullRequestReview': {'state': self.state}}}

    def delete(self, reconcile=False, **fields):
        return self.provider.mutate({'number': 42, 'draft': dict(self.draft, **fields), 'reconcile': reconcile})

    def test_exact_reply_and_general_routes(self):
        receipt = self.delete()
        self.assertEqual(['repos/owner/repo/pulls/comments/102'], self.writes)
        self.assertTrue(receipt['deleted'])
        for key in ('id', 'message', 'message_kind', 'thread', 'actor', 'delete_scope', 'expected_version'):
            self.assertEqual(self.draft[key], receipt[key])
        receipt = self.delete(thread='')
        self.assertEqual('repos/owner/repo/issues/comments/102', self.writes[-1])
        self.assertEqual('', receipt['thread'])

    def test_reconciliation_reads_only_and_does_not_treat_lost_access_as_absence(self):
        with self.assertRaises(hub.Failure) as error: self.delete(True)
        self.assertTrue(error.exception.unknown)
        self.comments = []
        self.assertTrue(self.delete(True)['observed'])
        self.pr = hub.Failure('Access lost', 'auth')
        with self.assertRaises(hub.Failure): self.delete(True)
        self.assertEqual([], self.writes)

    def test_scope_and_membership(self):
        for fields in ({'thread': '999'}, {'message_kind': 'COMMENTED'}, {'message': '102/extra'}, {'actor': 'other'},
                       {'pending_review': '7'}, {'delete_scope': 'thread'}, {'body': 'new'}, {'expected_version': 'old'},
                       {'original_body': 'changed'}):
            with self.assertRaises(hub.Failure): self.delete(**fields)
        self.comment['pull_request_url'] = 'https://api.github.com/repos/owner/repo/pulls/99'
        with self.assertRaises(hub.Failure): self.delete()
        with self.assertRaises(hub.Failure): self.delete(True)
        self.assertEqual([], self.writes)

    def test_permission_publication_owner_and_final_version(self):
        self.permission = False
        with self.assertRaises(hub.Failure): self.delete()
        self.permission = True
        self.state = 'PENDING'
        with self.assertRaises(hub.Failure): self.delete()
        self.state = 'COMMENTED'
        self.comment['user']['login'] = 'other'
        with self.assertRaises(hub.Failure): self.delete()
        self.comment['user']['login'] = 'alex'
        self.final = dict(self.comment, body='Concurrent edit')
        with self.assertRaises(hub.Failure): self.delete()
        self.assertEqual([], self.writes)

    def test_roots_with_replies_are_not_deleted_and_leaf_roots_are_supported(self):
        self.comment.pop('in_reply_to_id')
        self.comments.append(dict(self.comment, id=103, in_reply_to_id=102))
        with self.assertRaises(hub.Failure): self.delete(thread='102')
        self.assertEqual([], self.writes)
        self.comments.pop()
        self.assertTrue(self.delete(thread='102')['deleted'])

    def test_malformed_inventory_and_uncertain_delete(self):
        self.comments.append(copy.deepcopy(self.comment))
        with self.assertRaises(hub.Failure): self.delete(True)
        self.comments.pop()
        self.response = {'unexpected': True}
        with self.assertRaises(hub.Failure) as error: self.delete()
        self.assertTrue(error.exception.unknown)
        self.response = hub.Failure('Response too large', 'too_large')
        with self.assertRaises(hub.Failure) as error: self.delete()
        self.assertTrue(error.exception.unknown)

    def test_capabilities_preserve_private_summary_and_root_boundaries(self):
        root = dict(hub.normalize_comment(self.comment), id='100', author='alex')
        reply = dict(root, id='102')
        private = dict(root, id='103', publication='pending')
        summary = dict(root, id='7', kind='COMMENTED')
        for m in (root, reply, private, summary): m['capabilities'] = {}
        hub.published_delete_rules([{'id': '100', 'comments': [root, reply, private]}], [summary], 'alex')
        self.assertFalse(root['capabilities']['delete_message']['enabled'])
        self.assertTrue(reply['capabilities']['delete_message']['enabled'])
        self.assertFalse(private['capabilities']['delete_message']['enabled'])
        self.assertFalse(summary['capabilities']['delete_message']['enabled'])
        hub.published_delete_rules([], [reply], '')
        self.assertFalse(reply['capabilities']['delete_message']['enabled'])


if __name__ == '__main__': unittest.main()
