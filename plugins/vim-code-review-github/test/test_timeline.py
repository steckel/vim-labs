"""Typed history is read-only, review-scoped, and explicit about missing detail."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('timeline_hub', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


class TimelineTest(unittest.TestCase):
    def setUp(self):
        self.api = object.__new__(hub.GitHub)
        self.api.conn = {'host': 'github.example'}
        self.api.repo = 'owner/repo'
        self.calls = []
        self.connection = {'nodes': [], 'pageInfo': {'hasPreviousPage': False, 'startCursor': None}, 'totalCount': 0}
        def graphql(query, variables, write=False):
            self.assertFalse(write)
            self.assertTrue(query.lstrip().startswith('query('))
            self.assertNotIn('mutation', query)
            self.calls.append(variables)
            return {'repository': {'pullRequest': {'url': 'https://github.example/owner/repo/pull/42',
                                                   'timelineItems': copy.deepcopy(self.connection)}}}
        self.api.graphql = graphql

    def read(self, cursor=''):
        return self.api.timeline({'number': 42, 'cursor': cursor})

    def test_older_cursor_is_scoped_and_forwarded_without_offsets(self):
        self.connection.update(nodes=[{'id': 'new', '__typename': 'FutureEvent'}], totalCount=2,
                               pageInfo={'hasPreviousPage': True, 'startCursor': 'opaque:50'})
        first = self.read()
        self.assertFalse(first['complete'])
        self.assertIsNone(self.calls[-1]['before'])
        self.assertEqual('github.example/owner/repo/42', json.loads(first['next_cursor'])['review'])
        self.connection.update(nodes=[{'id': 'old', '__typename': 'ClosedEvent'}],
                               pageInfo={'hasPreviousPage': False, 'startCursor': 'opaque:1'})
        older = self.read(first['next_cursor'])
        self.assertEqual('opaque:50', self.calls[-1]['before'])
        self.assertEqual(first['next_cursor'], older['cursor'])
        self.assertTrue(older['complete'])
        self.assertEqual('', older['next_cursor'])
        self.assertEqual('old', older['items'][0]['id'])

    def test_wrong_review_and_malformed_cursors_never_read(self):
        for cursor in [None, [], 'bad json', '[]', '{}', 'null',
                       json.dumps({'review': 'github.example/owner/repo/99', 'before': 'x'}),
                       json.dumps({'review': 'github.example/owner/repo/42', 'before': ''})]:
            with self.subTest(cursor=cursor), self.assertRaises(hub.Failure):
                self.read(cursor)
        self.assertEqual([], self.calls)

    def test_malformed_duplicate_and_stalled_pages_fail(self):
        event = {'id': 'a', '__typename': 'FutureEvent'}
        for nodes, page in [(None, {}), ([None], {'hasPreviousPage': False}),
                            ([event, event], {'hasPreviousPage': False}),
                            ([event], {'hasPreviousPage': 1}),
                            ([event], {'hasPreviousPage': True, 'startCursor': ''}),
                            ([], {'hasPreviousPage': True, 'startCursor': 'x'})]:
            self.connection.update(nodes=nodes, pageInfo=page)
            with self.subTest(nodes=nodes, page=page), self.assertRaises(hub.Failure):
                self.read()
        self.connection.update(nodes=[event], pageInfo={'hasPreviousPage': True, 'startCursor': 'x'})
        with self.assertRaisesRegex(hub.Failure, 'did not advance'):
            self.read(json.dumps({'review': 'github.example/owner/repo/42', 'before': 'x'}))

    def test_inconsistent_total_does_not_hide_events(self):
        self.connection.update(nodes=[{'id': 'a', '__typename': 'FutureEvent'}], totalCount=0)
        result = self.read()
        self.assertNotIn('total', result)
        self.assertEqual(1, len(result['items']))
        self.assertIn('Additional details unavailable', result['items'][0]['details'][0])
        self.assertEqual('GitHub timeline', result['items'][0]['provenance'])

    def test_exact_review_comment_and_thread_targets(self):
        comment = hub.timeline_event({'id': 'c', '__typename': 'IssueComment', 'databaseId': 7}, 'url')
        review = hub.timeline_event({'id': 'r', '__typename': 'PullRequestReview', 'databaseId': 7,
                                     'state': 'APPROVED', 'commit': {'oid': 'a'*40}}, 'url')
        thread = hub.timeline_event({'id': 't', '__typename': 'PullRequestReviewThread', 'path': 'file.py',
                                     'comments': {'nodes': [{'databaseId': 8, 'body': 'Root'}]}}, 'url')
        self.assertEqual('comment', comment['target']['message_kind'])
        self.assertEqual('APPROVED', review['target']['message_kind'])
        self.assertEqual('Approved', review['title'])
        self.assertEqual('a'*40, review['reviewed_head'])
        self.assertNotIn('base', review)
        self.assertIn('base is unavailable', review['details'][-1])
        self.assertEqual({'kind': 'thread', 'thread': '8', 'message': '8', 'message_kind': 'comment', 'lookup': 't'}, thread['target'])

    def test_commits_force_push_and_review_dismissal_remain_distinct(self):
        commit = hub.timeline_event({'id': 'c', '__typename': 'PullRequestCommit',
            'commit': {'oid': 'a'*40, 'committedDate': '2026-09-14', 'messageHeadline': 'Fix',
                       'author': {'name': 'Contributor', 'user': None}}}, 'url')
        self.assertEqual(('Committed', 'Contributor', '2026-09-14', 'Fix'),
                         tuple(commit[k] for k in ('title', 'actor', 'created', 'body')))
        force = hub.timeline_event({'id': 'f', '__typename': 'HeadRefForcePushedEvent',
                                   'beforeCommit': None, 'afterCommit': {'oid': 'b'*40}}, 'url')
        self.assertIn('Before: unavailable', force['details'])
        dismissed = hub.timeline_event({'id': 'd', '__typename': 'ReviewDismissedEvent',
                                        'dismissalMessage': 'New revision', 'previousReviewState': 'APPROVED'}, 'url')
        self.assertEqual('Dismissed review', dismissed['title'])
        self.assertEqual('New revision', dismissed['body'])
        self.assertNotIn('target', dismissed)

    def test_routine_system_events_keep_actor_time_and_commit_context(self):
        for kind in ('MentionedEvent', 'SubscribedEvent', 'UnsubscribedEvent', 'ReferencedEvent', 'MergedEvent'):
            event = hub.timeline_event({'id': 'event', '__typename': kind, 'actor': {'login': 'alex'},
                                        'createdAt': '2026-09-14T12:00:00Z', 'commit': {'oid': 'a'*40}}, 'url')
            self.assertEqual('alex', event['actor'])
            self.assertEqual('2026-09-14T12:00:00Z', event['created'])
            self.assertNotIn('Additional details unavailable', str(event['details']))
            if kind in ('ReferencedEvent', 'MergedEvent'):
                self.assertEqual(['Commit: ' + 'a'*40], event['details'])


if __name__ == '__main__':
    unittest.main()
