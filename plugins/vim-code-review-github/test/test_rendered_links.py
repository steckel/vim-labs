"""Read-only link resolution from GitHub's rendered message, with exact identity."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('hub', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


class RenderedLinksTest(unittest.TestCase):
    def setUp(self):
        self.api = object.__new__(hub.GitHub)
        self.api.repo = 'owner/repo'
        self.comment = {'id': 102, 'node_id': 'node102', 'body': '[guide](../guide)',
                        'in_reply_to_id': 100, 'pull_request_review_id': 7, 'user': {'login': 'alex'},
                        'html_url': 'https://github.example/owner/repo/pull/42#discussion_r102'}
        self.html = '<p><a href="/owner/repo/blob/head/guide">The <strong>guide</strong></a></p>'
        self.target = {'message': '102', 'message_kind': 'comment', 'thread': '100', 'pending_review': '7',
                       'body': self.comment['body'], 'expected_version': hub.normalize_comment(self.comment)['version']}
        self.paths = []
        self.api.pages = self.pages
        self.api.graphql = self.graphql
        self.api.api = lambda *a, **kw: self.fail('No REST write or unrelated API call is permitted')

    def pages(self, path):
        self.paths.append(path)
        return [self.comment]

    def graphql(self, query, variables, **kwargs):
        self.assertEqual({'id': 'node102'}, variables)
        self.assertFalse(kwargs.get('write', False))
        return {'node': {'id': 'node102', 'body': self.comment['body'], 'bodyHTML': self.html}}

    def load(self, **target):
        return self.api.rendered_links({'number': 42, 'target': dict(self.target, **target)})

    def test_server_rendered_destination_and_nested_label(self):
        result = self.load()
        self.assertEqual([{'label': 'The guide', 'url': 'https://github.example/owner/repo/blob/head/guide'}], result['links'])
        self.assertEqual(['repos/owner/repo/pulls/42/reviews/7/comments'], self.paths)
        self.assertEqual('102', result['message'])
        self.assertEqual(self.target['expected_version'], result['version'])

    def test_html_parser_entities_fragments_and_dangerous_schemes(self):
        self.html = '<a href="#section">Section</a><a href="https://e.test/?a=1&amp;b=2">A &amp; B</a><a href="javascript:alert(1)">bad</a><img src="https://e.test/not-loaded"><a href="file:///tmp/private">file</a><a href="https://[invalid">bad host</a>'
        links = self.load()['links']
        self.assertEqual(['https://github.example/owner/repo/pull/42#section', 'https://e.test/?a=1&b=2'], [x['url'] for x in links])
        self.assertEqual('A & B', links[1]['label'])

    def test_stale_body_version_membership_and_wrong_thread(self):
        for target in ({'body': 'other'}, {'expected_version': 'old'}, {'message': '103'}, {'thread': '99'}, {'pending_review': '8'}):
            with self.subTest(target=target), self.assertRaises(hub.Failure): self.load(**target)

    def test_rendered_read_cannot_replace_newer_body_or_wrong_node(self):
        for node in ({'id': 'other', 'body': self.comment['body'], 'bodyHTML': self.html},
                     {'id': 'node102', 'body': 'new body', 'bodyHTML': self.html},
                     {'id': 'node102', 'body': self.comment['body']}):
            self.api.graphql = lambda *a, node=node, **kw: {'node': node}
            with self.assertRaises(hub.Failure): self.load()

    def test_conversation_and_review_summary_list_membership(self):
        self.comment.pop('in_reply_to_id')
        self.load(thread='', pending_review='')
        self.assertEqual('repos/owner/repo/issues/42/comments', self.paths[-1])
        self.load(thread='', pending_review='', message_kind='COMMENTED')
        self.assertEqual('repos/owner/repo/pulls/42/reviews', self.paths[-1])

    def test_duplicate_links_and_empty_html(self):
        self.html *= 2
        self.assertEqual(1, len(self.load()['links']))
        self.html = ''
        self.assertEqual([], self.load()['links'])


if __name__ == '__main__': unittest.main()
