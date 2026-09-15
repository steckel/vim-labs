"""Read-only native edit history; exact identity, paging and redaction."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('hub_history', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


class MessageHistoryTest(unittest.TestCase):
    def setUp(self):
        self.api = hub.GitHub({'host': 'github.com', 'repo': 'owner/repo'}, token='fixture')
        self.raw = {'id': 102, 'node_id': 'node102', 'body': 'Current message', 'created_at': '2026-09-14',
                    'updated_at': '2026-09-14', 'user': {'id': 9, 'login': 'alex'},
                    'html_url': 'https://github.com/owner/repo/pull/42#issuecomment-102',
                    'issue_url': 'https://api.github.com/repos/owner/repo/issues/42'}
        self.edits = [self.edit('second'), self.edit('first')]
        self.total, self.next = 2, None
        self.requests = []
        self.review_state = 'COMMENTED'
        self.api.api = self.read
        self.api.graphql = self.graphql
        self.target = {'message': '102', 'message_kind': 'comment', 'thread': '',
                       'body': self.raw['body'], 'expected_version': hub.normalize_comment(self.raw)['version']}

    def edit(self, name):
        return {'id': name, 'editedAt': '2026-09-14', 'editor': {'login': 'alex'}, 'deletedAt': None, 'diff': name + ' content'}

    def read(self, path, method='GET', *args, **kwargs):
        self.assertEqual('GET', method)
        self.requests.append(path)
        if path.endswith('/reviews/7'):
            return {'id': 7, 'state': self.review_state}
        return copy.deepcopy(self.raw)

    def graphql(self, query, variables):
        self.assertTrue(query.startswith('query('))
        self.assertIn('userContentEdits(first:50', query)
        self.assertEqual('node102', variables['id'])
        return {'node': {'id': 'node102', 'body': self.raw['body'], 'userContentEdits': {
            'nodes': copy.deepcopy(self.edits), 'totalCount': self.total,
            'pageInfo': {'hasNextPage': bool(self.next), 'endCursor': self.next}}}}

    def load(self, cursor='', **target):
        return self.api.message_history({'number': 42, 'target': dict(self.target, **target), 'cursor': cursor})

    def test_comment_history_and_pagination(self):
        self.total, self.next = 3, 'older'
        page = self.load()
        self.assertEqual(['first', 'second'], [e['id'] for e in page['items']])
        self.assertEqual(self.target, page['target'])
        self.assertFalse(page['complete'])
        self.edits, self.next = [self.edit('original')], None
        older = self.load(page['next_cursor'])
        self.assertTrue(older['complete'])
        self.assertEqual('', older['next_cursor'])
        self.assertEqual('original content', older['items'][0]['body'])

    def test_redaction_never_exposes_supplied_content(self):
        self.edits[0].update(deletedAt='2026-09-15', deletedBy={'login': 'moderator'}, diff='secret')
        self.edits[1]['diff'] = None
        page = self.load()
        self.assertEqual(['unavailable', 'redacted'], [e['content_state'] for e in page['items']])
        self.assertTrue(all(e['body'] == '' for e in page['items']))
        self.assertNotIn('secret', json.dumps(page))

    def test_inline_membership_and_private_history(self):
        self.raw.update(in_reply_to_id=100, pull_request_review_id=7, pull_request_url='https://api.github.com/repos/owner/repo/pulls/42')
        self.load(thread='100')
        with self.assertRaises(hub.Failure): self.load(thread='99')
        self.review_state = 'PENDING'
        with self.assertRaises(hub.Failure): self.load(thread='100')

    def test_review_summary_and_state_change(self):
        self.raw['state'] = 'COMMENTED'
        self.target.update(message_kind='COMMENTED', expected_version=hub.normalize_comment(self.raw, 'COMMENTED')['version'])
        self.load()
        self.raw['state'] = 'DISMISSED'
        with self.assertRaises(hub.Failure): self.load()

    def test_foreign_review_stale_version_and_missing_node(self):
        for changes in [{'body': 'different'}, {'expected_version': 'old'}, {'message_kind': 'PENDING'}, {'message': '../other'}]:
            with self.subTest(changes=changes), self.assertRaises(hub.Failure): self.load(**changes)
        self.raw['issue_url'] = 'https://api.github.com/repos/owner/repo/issues/99'
        with self.assertRaises(hub.Failure): self.load()
        self.raw['issue_url'] = 'https://api.github.com/repos/owner/repo/issues/42'
        self.raw.pop('node_id')
        with self.assertRaises(hub.Failure): self.load()

    def test_stalled_foreign_and_changed_count_cursors(self):
        self.total, self.next = 3, 'older'
        cursor = self.load()['next_cursor']
        with self.assertRaises(hub.Failure): self.load(cursor)
        saved = json.loads(cursor); saved['repo'] = 'other/repo'
        with self.assertRaises(hub.Failure): self.load(json.dumps(saved))
        self.edits, self.total, self.next = [self.edit('last')], 4, None
        with self.assertRaises(hub.Failure): self.load(cursor)

    def test_malformed_duplicate_missing_and_changed_responses(self):
        self.edits = [self.edit('same'), self.edit('same')]
        with self.assertRaises(hub.Failure): self.load()
        self.edits = []
        with self.assertRaises(hub.Failure): self.load()
        self.api.graphql = lambda *args: {'node': {'id': 'foreign'}}
        with self.assertRaises(hub.Failure): self.load()
        self.api.token = ''
        with self.assertRaises(hub.Failure): self.load()

    def test_late_message_edit_requires_reload(self):
        original = self.api.graphql
        def changed(query, variables):
            result = original(query, variables)
            self.raw['body'] = 'Edited during retrieval'
            return result
        self.api.graphql = changed
        with self.assertRaises(hub.Failure): self.load()


if __name__ == '__main__':
    unittest.main()
