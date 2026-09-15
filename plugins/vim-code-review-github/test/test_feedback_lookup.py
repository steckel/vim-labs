"""Selected-thread reads bind parent review, complete replies and actor/source."""
import copy
import unittest
import test_feedback_pages as fixtures

hub = fixtures.hub


class LookupTest(unittest.TestCase):
    def setUp(self):
        self.api = object.__new__(hub.GitHub)
        self.api.conn = {'host': 'github.example', 'repo': 'owner/repo'}
        self.api.repo, self.api.token = 'owner/repo', 'fixture'
        self.ref = {'snapshot': 'a'*40 + ':' + 'b'*40, 'base': 'a'*40, 'head': 'b'*40, 'base_tip': 'c'*40}
        self.target = {'kind': 'thread', 'thread': '101', 'message': '102', 'message_kind': 'comment', 'lookup': 'PRRT_101'}
        self.pr = {'number': 42, 'repository': {'nameWithOwner': 'owner/repo'}, 'headRefOid': self.ref['head'],
                   'baseRefOid': self.ref['base_tip'], 'updatedAt': '2026-09-14T00:00:00Z', 'reviews': {'nodes': []}}
        self.node = dict(fixtures.thread(), pullRequest=copy.deepcopy(self.pr))
        self.nested = None
        self.viewer, self.final_viewer = 'alex', 'alex'
        self.calls = []

        def graphql(query, variables, write=False):
            self.assertFalse(write)
            self.assertNotIn('mutation', query)
            self.calls.append((query, copy.deepcopy(variables)))
            if 'after' in variables:
                return {'node': {'comments': copy.deepcopy(self.nested)}}
            if 'id' in variables:
                return {'viewer': {'login': self.viewer}, 'node': copy.deepcopy(self.node)}
            return {'viewer': {'login': self.final_viewer}, 'repository': {'pullRequest': copy.deepcopy(self.pr)}}
        self.api.graphql = graphql

    def read(self, **overrides):
        return self.api.feedback_lookup(dict(number=42, target=self.target, reference=self.ref, **overrides))

    def test_exact_reply_and_parent_review_are_bound(self):
        result = self.read()
        self.assertEqual('github.example/owner/repo/42', result['key'])
        self.assertEqual(self.ref, result['reference'])
        self.assertEqual(self.target, result['target'])
        self.assertEqual(['101', '102'], [m['id'] for m in result['thread']['comments']])
        self.assertNotIn('inventory', result)
        self.assertNotIn('next_cursor', result)
        self.assertEqual(2, len(self.calls), 'One target read plus a consistency guard')
        self.assertEqual({'id': 'PRRT_101'}, self.calls[0][1])
        self.assertIn('pullRequest{number repository{nameWithOwner}', self.calls[0][0])

    def test_nested_replies_are_complete_before_return(self):
        self.node['comments'] = fixtures.connection([fixtures.message(101)], 'next', 3)
        self.nested = fixtures.connection([fixtures.message(102, 101), fixtures.message(103, 101)])
        self.target['message'] = '103'
        self.assertEqual(3, len(self.read()['thread']['comments']))
        self.assertEqual({'id': 'PRRT_101', 'after': 'next'}, self.calls[1][1])
        self.assertEqual(3, len(self.calls))

    def test_foreign_or_unavailable_nodes_are_rejected(self):
        original = copy.deepcopy(self.node)
        cases = [None, [], 'bad', dict(original, id='foreign'), dict(original, pullRequest=[]),
                 dict(original, pullRequest=dict(self.pr, number=43)),
                 dict(original, pullRequest=dict(self.pr, repository={'nameWithOwner': 'foreign/repo'}))]
        for node in cases:
            self.node = node
            with self.subTest(node=node), self.assertRaises(hub.Failure):
                self.read()

    def test_wrong_root_or_exact_reply_is_rejected(self):
        for field in ('thread', 'message', 'message_kind'):
            original = self.target[field]
            self.target[field] = 'foreign'
            with self.subTest(field=field), self.assertRaises(hub.Failure):
                self.read()
            self.target[field] = original

    def test_changed_source_actor_or_inventory_is_rejected(self):
        for field in ('headRefOid', 'baseRefOid', 'updatedAt'):
            original = self.pr[field]
            self.pr[field] = 'changed'
            with self.subTest(field=field), self.assertRaises(hub.Failure):
                self.read()
            self.pr[field] = original
        self.final_viewer = 'another-person'
        with self.assertRaises(hub.Failure):
            self.read()

    def test_private_or_incomplete_threads_offer_paging_fallback(self):
        for comments in [fixtures.connection([fixtures.message(101)]),
                         fixtures.connection([fixtures.message(101)], 'next', 2)]:
            self.node['comments'] = comments
            self.nested = fixtures.connection([])
            if not comments['pageInfo']['hasNextPage']:
                self.node['comments']['nodes'][0]['state'] = 'PENDING'
            with self.subTest(comments=comments), self.assertRaisesRegex(hub.Failure, 'ordinary feedback paging'):
                self.read()

    def test_historical_or_invalid_references_do_not_query(self):
        for ref in [None, {}, dict(self.ref, range={}), dict(self.ref, context={}), dict(self.ref, head='bad')]:
            with self.subTest(ref=ref), self.assertRaises(hub.Failure):
                self.api.feedback_lookup({'number': 42, 'target': self.target, 'reference': ref})
        self.assertEqual([], self.calls)


if __name__ == '__main__':
    unittest.main()
