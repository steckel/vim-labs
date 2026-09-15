import importlib.util
import json
from pathlib import Path
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('reviewhub', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class Handler(BaseHTTPRequestHandler):
    requests = []
    comments = []
    post_status = 201
    head = 'b' * 40
    base = 'c' * 40
    viewer = 'reviewer'
    author = 'author'
    graphql_responses = []

    def log_message(self, *args):
        pass

    def do_GET(self):
        self.requests.append(('GET', self.path, None, self.headers.get('Authorization')))
        if self.path == '/user':
            data = {'login': self.viewer}
        elif self.path.split('?')[0].endswith('/pulls/42'):
            data = {'head': {'sha': self.head}, 'base': {'sha': self.base}, 'user': {'login': self.author}}
        else:
            data = self.comments
        self.send_response(200)
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.requests.append(('POST', self.path, body, self.headers.get('Authorization')))
        self.send_response(self.post_status)
        self.end_headers()
        response = self.graphql_responses.pop(0) if self.path.endswith('/graphql') and self.graphql_responses else {'id': 999, 'html_url': 'https://example.test/receipt', 'message': 'simulated'}
        self.wfile.write(json.dumps(response).encode())


class ProviderTest(unittest.TestCase):
    def test_private_reply_exact_native_target_and_recovery(self):
        parent = {'id': 7, 'node_id': 'PRR_seven', 'state': 'PENDING', 'commit_id': 'older-source', 'user': {'login': 'reviewer'}}
        draft = dict(self.draft, kind='reply', thread='101', pending_mode='add', pending_review='7', pending_head='older-source', actor='github-login:reviewer', body='> Quoted feedback\n\nPrivate answer')
        for key in ('path', 'old_path', 'side', 'start', 'end'): draft.pop(key)
        comments, writes = [], []
        def api(path, method='GET', body=None):
            self.assertEqual('GET', method)
            if path == 'user': return {'login': 'reviewer'}
            if path.endswith('/reviews/7'): return parent
            return {'head': {'sha': 'newer-source'}, 'base': {'sha': 'newer-base'}}
        def pages(path):
            self.assertTrue(path.endswith('/reviews/7/comments'))
            return comments
        def graphql(query, variables, write=False):
            self.assertTrue(write)
            self.assertIn('AddPullRequestReviewThreadReplyInput!', query)
            value = variables['input']
            writes.append(value)
            comments.append({'id': 102, 'pull_request_review_id': 7, 'in_reply_to_id': 101, 'body': value['body']})
            return {'addPullRequestReviewThreadReply': {'clientMutationId': draft['id'], 'comment': {
                'databaseId': 102, 'body': value['body'], 'pullRequestReview': {'databaseId': 7}, 'replyTo': {'databaseId': 101}}}}
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'thread_states', return_value={'101': {'native_id': 'PRRT_exact', 'capabilities': {'reply': {'enabled': True}}}}), patch.object(self.api, 'graphql', side_effect=graphql):
            receipt = self.api.mutate({'number': 42, 'draft': draft})
            self.assertEqual('101', receipt['thread'])
            self.assertEqual('7', receipt['pending_review'])
            self.assertEqual({'pullRequestReviewId', 'pullRequestReviewThreadId', 'body', 'clientMutationId'}, set(writes[0]))
            self.assertEqual(('PRR_seven', 'PRRT_exact'), (writes[0]['pullRequestReviewId'], writes[0]['pullRequestReviewThreadId']))
            self.assertEqual(draft['body'], module.normalize_comment(comments[0])['body'])
            parent['state'] = 'COMMENTED'
            self.assertTrue(self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})['recovered'])
            with self.assertRaisesRegex(module.Failure, 'No unique matching'):
                self.api.mutate({'number': 42, 'draft': dict(draft, thread='999'), 'reconcile': True})
            comments[0]['in_reply_to_id'] = 999
            with self.assertRaisesRegex(module.Failure, 'Mismatched private comment receipt'):
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
            self.assertEqual(1, len(writes))

    def test_private_reply_permissions_and_incomplete_receipt(self):
        parent = {'id': 7, 'node_id': 'PRR_seven', 'state': 'PENDING', 'commit_id': Handler.head, 'user': {'login': 'reviewer'}}
        draft = dict(self.draft, kind='reply', thread='101', pending_mode='add', pending_review='7', pending_head=Handler.head, actor='github-login:reviewer')
        states = {}
        def api(path, method='GET', body=None):
            if path == 'user': return {'login': 'reviewer'}
            if path.endswith('/reviews/7'): return parent
            return {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}}
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', return_value=[]), patch.object(self.api, 'thread_states', side_effect=lambda _: states), patch.object(self.api, 'graphql', return_value={}) as write:
            for states in ({}, {'101': {'native_id': 'PRRT_exact', 'capabilities': {'reply': {'enabled': False}}}}):
                with self.assertRaisesRegex(module.Failure, 'does not allow replies'):
                    self.api.mutate({'number': 42, 'draft': draft})
            with self.assertRaisesRegex(module.Failure, 'Start a pending review'):
                self.api.mutate({'number': 42, 'draft': dict(draft, pending_mode='create', pending_review='')})
            write.assert_not_called()
            states = {'101': {'native_id': 'PRRT_exact', 'capabilities': {'reply': {'enabled': True}}}}
            with self.assertRaisesRegex(module.Failure, 'private reply receipt') as error:
                self.api.mutate({'number': 42, 'draft': draft})
            self.assertTrue(error.exception.unknown)
            with self.assertRaisesRegex(module.Failure, 'No unique matching'):
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
            self.assertEqual(1, write.call_count)

    def test_start_pending_and_first_inline_comment(self):
        for kind in ('start_pending', 'comment'):
            for side in ('base', 'head'):
                draft = dict(self.draft, kind=kind, pending_mode='create', pending_review='', actor='github-login:reviewer', side=side)
                if kind == 'start_pending': draft['body'] = ''
                reviews, writes = [], []
                def pages(path):
                    if path.endswith('/comments'):
                        return [dict(writes[0][1]['comments'][0], id=101, pull_request_review_id=7)]
                    return [{'filename': draft['path'], 'previous_filename': draft['old_path'], 'patch': '@@ -1,4 +1,4 @@\n a\n b\n c\n d'}] if path.endswith('/files') else reviews
                def api(path, method='GET', body=None):
                    if path == 'user': return {'login': 'reviewer'}
                    if method == 'POST':
                        writes.append((path, body))
                        reviews.append({'id': 7, 'state': 'PENDING', 'body': body['body'], 'user': {'login': 'reviewer'}})
                        return reviews[-1]
                    return {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}}
                with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages):
                    result = self.api.mutate({'number': 42, 'draft': draft})
                    self.assertEqual('7', result['pending_review'])
                    self.assertEqual('create', result['pending_mode'])
                    payload = writes[0][1]
                    self.assertNotIn('event', payload)
                    self.assertEqual(Handler.head, payload['commit_id'])
                    if kind == 'comment':
                        comment = payload['comments'][0]
                        self.assertEqual(('LEFT' if side == 'base' else 'RIGHT'), comment['side'])
                        self.assertEqual(2, comment['start_line'])
                        self.assertEqual(4, comment['line'])
                        self.assertEqual(draft['body'], module.normalize_comment(dict(comment, id=1))['body'])
                    else:
                        self.assertNotIn('comments', payload)
                        self.assertEqual('', module.normalize_comment(reviews[0])['body'])
                    reviews[0]['state'] = 'COMMENTED'
                    self.assertTrue(self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})['recovered'])
                    with self.assertRaisesRegex(module.Failure, 'No unique matching'):
                        self.api.mutate({'number': 42, 'draft': dict(draft, body='Changed intent'), 'reconcile': True})
                    self.assertEqual(1, len(writes))

    def test_created_review_requires_first_comment_receipt(self):
        draft = dict(self.draft, pending_mode='create', pending_review='', actor='github-login:reviewer')
        reviews, writes = [], []
        def pages(path):
            if path.endswith('/comments'): return []
            if path.endswith('/files'):
                return [{'filename': draft['path'], 'previous_filename': draft['old_path'], 'patch': '@@ -1,4 +1,4 @@\n a\n b\n c\n d'}]
            return reviews
        def api(path, method='GET', body=None):
            if path == 'user': return {'login': 'reviewer'}
            if method == 'POST':
                writes.append(body)
                reviews.append({'id': 7, 'state': 'PENDING', 'body': body['body']})
                return reviews[0]
            return {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}}
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages):
            for reconcile in (False, True):
                with self.assertRaisesRegex(module.Failure, 'first-comment receipt') as error:
                    self.api.mutate({'number': 42, 'draft': draft, 'reconcile': reconcile})
                self.assertTrue(error.exception.unknown)
            self.assertEqual(1, len(writes))

    def test_pending_creation_conflicts_and_malformed_receipt(self):
        draft = dict(self.draft, kind='start_pending', pending_mode='create', pending_review='', actor='github-login:reviewer')
        reviews = [{'id': 5, 'state': 'PENDING', 'body': '', 'user': {'login': 'reviewer'}}]
        writes = []
        def api(path, method='GET', body=None):
            if path == 'user': return {'login': 'reviewer'}
            if method == 'POST':
                writes.append(path)
                return {'id': 7, 'state': 'COMMENTED', 'body': body['body']}
            return {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}}
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=lambda _: reviews):
            with self.assertRaisesRegex(module.Failure, 'already exists'):
                self.api.mutate({'number': 42, 'draft': draft})
            reviews.clear()
            with self.assertRaisesRegex(module.Failure, 'actor changed'):
                self.api.mutate({'number': 42, 'draft': dict(draft, actor='other')})
            with self.assertRaisesRegex(module.Failure, 'comparison changed'):
                self.api.mutate({'number': 42, 'draft': dict(draft, head='older')})
            self.assertEqual([], writes)
            with self.assertRaisesRegex(module.Failure, 'creation receipt') as error:
                self.api.mutate({'number': 42, 'draft': draft})
            self.assertTrue(error.exception.unknown)
            with self.assertRaisesRegex(module.Failure, 'No unique matching'):
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
            self.assertEqual(1, len(writes))

    def test_add_pending_line_and_file_threads_graphql(self):
        for kind in ('comment', 'file_comment'):
            draft = dict(self.draft, kind=kind, pending_mode='add', pending_review='7', pending_head=Handler.head, actor='github-login:reviewer')
            if kind == 'file_comment':
                for key in ('side', 'start', 'end'): draft.pop(key)
            parent = {'id': 7, 'node_id': 'PRR_seven', 'state': 'PENDING', 'commit_id': Handler.head, 'user': {'login': 'reviewer'}}
            comments, writes = [], []
            def pages(path):
                return [{'filename': draft['path'], 'previous_filename': draft['old_path'], 'patch': '@@ -1,4 +1,4 @@\n a\n b\n c\n d'}] if path.endswith('/files') else comments
            def api(path, method='GET', body=None):
                self.assertEqual('GET', method)
                if path == 'user': return {'login': 'reviewer'}
                if path.endswith('/reviews/7'): return parent
                return {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}}
            def graphql(query, variables, write=False):
                self.assertTrue(write)
                self.assertIn('addPullRequestReviewThread', query)
                value = variables['input']
                writes.append(value)
                comments.append({'id': 101, 'pull_request_review_id': 7, 'body': value['body']})
                return {'addPullRequestReviewThread': {'clientMutationId': draft['id'], 'thread': {'comments': {'nodes': [
                    {'body': value['body'], 'databaseId': 101, 'pullRequestReview': {'databaseId': 7}}]}}}}
            with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'graphql', side_effect=graphql):
                receipt = self.api.mutate({'number': 42, 'draft': draft})
                self.assertEqual('7', receipt['pending_review'])
                self.assertEqual('PRR_seven', writes[0]['pullRequestReviewId'])
                self.assertEqual('FILE' if kind == 'file_comment' else 'LINE', writes[0]['subjectType'])
                self.assertNotIn('pullRequestId', writes[0], 'must name the exact pending review')
                if kind == 'file_comment': self.assertNotIn('line', writes[0])
                else:
                    self.assertEqual((2, 4, 'LEFT'), (writes[0]['startLine'], writes[0]['line'], writes[0]['side']))
                self.assertTrue(self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})['recovered'])
                self.assertEqual(1, len(writes))
                with self.assertRaisesRegex(module.Failure, 'cannot be published'):
                    self.api.batch({'number': 42, 'draft': {'id': 'batch', 'kind': 'batch', 'items': [draft]}})

    def test_pending_add_rejects_stale_source_and_invalid_range(self):
        draft = dict(self.draft, pending_mode='add', pending_review='7', pending_head=Handler.head, actor='github-login:reviewer')
        parent = {'id': 7, 'node_id': 'PRR_seven', 'state': 'PENDING', 'commit_id': Handler.head, 'user': {'login': 'reviewer'}}
        def api(path, method='GET', body=None):
            if path == 'user': return {'login': 'reviewer'}
            if path.endswith('/reviews/7'): return parent
            return {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}}
        def pages(path):
            return [{'filename': draft['path'], 'previous_filename': draft['old_path'], 'patch': '@@ -1,2 +1,2 @@\n a\n b'}] if path.endswith('/files') else []
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'graphql') as write:
            with self.assertRaisesRegex(module.Failure, 'outside the returned diff'):
                self.api.mutate({'number': 42, 'draft': draft})
            parent['commit_id'] = 'old'
            with self.assertRaisesRegex(module.Failure, 'another source revision'):
                self.api.mutate({'number': 42, 'draft': draft})
            parent['state'] = 'COMMENTED'
            with self.assertRaisesRegex(module.Failure, 'no longer pending'):
                self.api.mutate({'number': 42, 'draft': draft})
            write.assert_not_called()

    def test_discard_pending_exact_contents_and_observed_absence(self):
        review = {'id': 7, 'state': 'PENDING', 'commit_id': Handler.head,
                  'body': 'Private summary', 'user': {'login': 'reviewer'}}
        comments = [{'id': 101, 'pull_request_review_id': 7, 'path': 'code.py', 'line': 2, 'body': 'Private comment'}]
        native = module.pending_record(review, comments, 'github-login:reviewer')
        draft = dict(self.draft, kind='discard_pending', pending_review='7', actor=native['actor'],
                     pending_head=native['head'], expected_version=native['version'],
                     pending_comments=native['comments'], pending_body=native['body'], body='')
        writes, reviews = [], [review]
        def api(path, method='GET', body=None):
            if path == 'user':
                return {'login': 'reviewer'}
            if method == 'DELETE':
                writes.append((path, method, body))
                reviews.clear()
            return dict(review)
        def pages(path):
            return list(comments if path.endswith('/comments') else reviews)
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages):
            # All included content, including summary, must match the preview.
            for altered in [dict(draft, pending_body='Other'), dict(draft, pending_comments=[]),
                            dict(draft, expected_version='old'), dict(draft, pending_head='old')]:
                with self.assertRaisesRegex(module.Failure, 'Pending review changed'):
                    self.api.mutate({'number': 42, 'draft': altered})
            comments[0]['body'] = 'Browser change'
            with self.assertRaisesRegex(module.Failure, 'Pending review changed'):
                self.api.mutate({'number': 42, 'draft': draft})
            comments[0]['body'] = 'Private comment'
            with self.assertRaisesRegex(module.Failure, 'still exists'):
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
            self.assertEqual([], writes)
            receipt = self.api.mutate({'number': 42, 'draft': draft})
            self.assertTrue(receipt['discarded'])
            self.assertEqual(draft['id'], receipt['id'])
            self.assertEqual([('repos/team/project/pulls/42/reviews/7', 'DELETE', None)], writes)
            recovered = self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
            self.assertTrue(recovered['observed'])
            self.assertEqual(1, len(writes))
            with self.assertRaisesRegex(module.Failure, 'actor changed'):
                self.api.mutate({'number': 42, 'draft': dict(draft, actor='github-login:other'), 'reconcile': True})
        with patch.object(self.api, 'api', return_value={'login': 'reviewer'}), patch.object(self.api, 'pages', side_effect=module.Failure('access lost', '403')):
            with self.assertRaisesRegex(module.Failure, 'access lost'):
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})

    def test_discard_pending_rejects_published_foreign_and_bad_receipts(self):
        review = {'id': 7, 'state': 'PENDING', 'commit_id': Handler.head,
                  'body': '', 'user': {'login': 'reviewer'}}
        native = module.pending_record(review, [], 'github-login:reviewer')
        draft = dict(self.draft, kind='discard_pending', pending_review='7', actor=native['actor'],
                     pending_head=native['head'], expected_version=native['version'],
                     pending_comments=[], pending_body='', body='')
        writes = []
        def api(path, method='GET', body=None):
            if path == 'user': return {'login': 'reviewer'}
            if method == 'DELETE':
                writes.append(path)
                return {'id': 99}
            return dict(review)
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', return_value=[]):
            review['state'] = 'COMMENTED'
            with self.assertRaisesRegex(module.Failure, 'no longer pending'):
                self.api.mutate({'number': 42, 'draft': draft})
            review['state'] = 'PENDING'
            review['user'] = {'login': 'other'}
            with self.assertRaisesRegex(module.Failure, 'another actor'):
                self.api.mutate({'number': 42, 'draft': draft})
            self.assertEqual([], writes)
            review['user'] = {'login': 'reviewer'}
            with self.assertRaisesRegex(module.Failure, 'No matching pending-review discard') as error:
                self.api.mutate({'number': 42, 'draft': draft})
            self.assertTrue(error.exception.unknown)
            self.assertEqual(1, len(writes))
            self.api.token = ''
            with self.assertRaisesRegex(module.Failure, 'Sign in'):
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})

    def test_private_edits_summary_root_and_reply_preserve_receipts(self):
        for target in ('summary', 'root', 'reply'):
            parent = {'id': 7, 'state': 'PENDING', 'commit_id': Handler.head,
                      'user': {'login': 'reviewer'}, 'body': 'Original summary'}
            comment = {'id': 101, 'pull_request_review_id': 7, 'path': 'code.py', 'line': 2,
                       'user': {'login': 'reviewer'}, 'body': 'Original private comment'}
            if target == 'reply': comment['in_reply_to_id'] = 100
            current = parent if target == 'summary' else comment
            kind, thread = ('PENDING', '') if target == 'summary' else ('comment', '100' if target == 'reply' else '101')
            current['body'] += '\n\n<!-- revue:creation -->'
            normalized = module.normalize_comment(current, kind)
            draft = dict(self.draft, kind='edit', message=str(current['id']), message_kind=kind, thread=thread,
                         pending_review='7', actor='github-login:reviewer', original_body=normalized['body'],
                         expected_version=normalized['version'], body='' if target == 'summary' else 'Changed private feedback')
            writes, lists = [], []
            def pages(path):
                lists.append(path)
                return [dict(comment)] if path.endswith('/comments') else [dict(parent)]
            def api(path, method='GET', body=None):
                if path == 'user': return {'login': 'reviewer'}
                if method != 'GET':
                    writes.append((path, method, body))
                    current['body'] = body['body']
                return dict(comment if '/pulls/comments/' in path else parent)
            with patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'api', side_effect=api):
                receipt = self.api.mutate({'number': 42, 'draft': draft})
                self.assertEqual('7', receipt['pending_review'])
                self.assertEqual(draft['actor'], receipt['actor'])
                self.assertEqual('PENDING', parent['state'])
                self.assertEqual(draft['body'], module.normalize_comment(current, kind)['body'])
                self.assertIn('<!-- revue:creation -->', current['body'])
                self.assertEqual({'body'}, set(writes[0][2]))
                if target == 'summary':
                    self.assertEqual(('repos/team/project/pulls/42/reviews/7', 'PUT'), writes[0][:2])
                else:
                    self.assertEqual(('repos/team/project/pulls/comments/101', 'PATCH'), writes[0][:2])
                    self.assertEqual(['repos/team/project/pulls/42/reviews/7/comments'], lists)
                # A later browser publication cannot erase proof of a private edit.
                parent['state'] = 'COMMENTED'
                self.assertTrue(self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})['recovered'])
                with self.assertRaisesRegex(module.Failure, 'No matching edit receipt'):
                    self.api.mutate({'number': 42, 'draft': dict(draft, actor='github-login:other'), 'reconcile': True})
                self.assertEqual(1, len(writes))

    def test_private_edit_stale_actor_parent_and_unknown_response(self):
        parent = {'id': 7, 'state': 'PENDING', 'user': {'login': 'reviewer'}}
        comment = {'id': 101, 'pull_request_review_id': 7, 'body': 'Private', 'user': {'login': 'reviewer'}}
        normalized = module.normalize_comment(comment)
        draft = dict(self.draft, kind='edit', message='101', message_kind='comment', thread='101',
                     pending_review='7', actor='github-login:reviewer', original_body='Private',
                     expected_version=normalized['version'], body='Proposed')
        writes = []
        def api(path, method='GET', body=None):
            if path == 'user': return {'login': 'reviewer'}
            if method != 'GET':
                writes.append(path)
                return {'id': 999, 'body': body['body']}
            return dict(comment if '/pulls/comments/' in path else parent)
        with patch.object(self.api, 'pages', return_value=[comment]), patch.object(self.api, 'api', side_effect=api):
            for edited, why in [(dict(draft, actor='github-login:other'), 'actor changed'),
                                (dict(draft, expected_version='stale'), 'Message changed'),
                                (dict(draft, body=''), 'replacement message')]:
                with self.assertRaisesRegex(module.Failure, why):
                    self.api.mutate({'number': 42, 'draft': edited})
            parent['state'] = 'COMMENTED'
            with self.assertRaisesRegex(module.Failure, 'no longer pending'):
                self.api.mutate({'number': 42, 'draft': draft})
            parent['state'] = 'PENDING'
            parent['user'] = {'login': 'other'}
            with self.assertRaisesRegex(module.Failure, 'another actor'):
                self.api.mutate({'number': 42, 'draft': draft})
            parent['user'] = {'login': 'reviewer'}
            comment['pull_request_review_id'] = 8
            with self.assertRaisesRegex(module.Failure, 'no longer belongs'):
                self.api.mutate({'number': 42, 'draft': draft})
            comment['pull_request_review_id'] = 7
            self.assertEqual([], writes)
            with self.assertRaisesRegex(module.Failure, 'matching edit receipt') as error:
                self.api.mutate({'number': 42, 'draft': draft})
            self.assertTrue(error.exception.unknown)
            with self.assertRaisesRegex(module.Failure, 'No matching edit receipt'):
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
            self.assertEqual(1, len(writes))

    def test_publish_native_pending_review_and_receipt_preservation(self):
        for event, state in [('COMMENT', 'COMMENTED'), ('APPROVE', 'APPROVED'), ('REQUEST_CHANGES', 'CHANGES_REQUESTED')]:
            review = {'id': 7, 'state': 'PENDING', 'commit_id': Handler.head, 'user': {'login': 'reviewer'},
                      'body': 'Browser summary\n\n<!-- revue:created_pending -->', 'html_url': 'https://example.test/review/7'}
            comments = [{'id': 101, 'pull_request_review_id': 7, 'path': 'code.py', 'line': 2, 'body': 'Private feedback', 'user': {'login': 'reviewer'}}]
            native = module.pending_record(review, comments, 'github-login:reviewer')
            draft = dict(self.draft, kind='submit_pending', pending_review='7', actor=native['actor'], pending_head=native['head'],
                         expected_version=native['version'], pending_comments=native['comments'], event=event, body=' Exact summary\n')
            writes = []
            def api(path, method='GET', body=None):
                if path == 'user':
                    return {'login': 'reviewer'}
                if path.endswith('/pulls/42'):
                    return {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}, 'user': {'login': 'author'}}
                if method == 'POST':
                    writes.append((path, body))
                    self.assertTrue(path.endswith('/reviews/7/events'))
                    review.update(state=state, body=body['body'])
                return dict(review)
            with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', return_value=comments):
                receipt = self.api.mutate({'number': 42, 'draft': draft})
                self.assertEqual(draft['id'], receipt['id'])
                self.assertEqual('7', receipt['pending_review'])
                self.assertEqual({'body', 'event'}, set(writes[0][1]))
                self.assertEqual(event, writes[0][1]['event'])
                self.assertEqual(draft['body'], module.normalize_comment(review, state)['body'])
                self.assertIn('<!-- revue:created_pending -->', review['body'])
                # Later dismissal does not erase proof of the earlier publication.
                review['state'] = 'DISMISSED'
                self.api.token = ''
                self.assertTrue(self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})['recovered'])
                self.assertEqual(1, len(writes))
                with self.assertRaisesRegex(module.Failure, 'No matching publication receipt'):
                    self.api.mutate({'number': 42, 'draft': dict(draft, body='changed frozen summary'), 'reconcile': True})
            self.api.token = 'test-only'

    def test_pending_publication_conflicts_ownership_and_unknown_results(self):
        review = {'id': 7, 'state': 'PENDING', 'commit_id': Handler.head, 'body': '', 'user': {'login': 'reviewer'}}
        comments = [{'id': 101, 'pull_request_review_id': 7, 'path': 'code.py', 'line': 2, 'body': 'Private'}]
        record = module.pending_record(review, comments, 'github-login:reviewer')
        draft = dict(self.draft, kind='submit_pending', pending_review='7', actor=record['actor'], pending_head=record['head'],
                     expected_version=record['version'], pending_comments=record['comments'], event='COMMENT', body='')
        writes = []
        def api(path, method='GET', body=None):
            if path == 'user':
                return {'login': 'reviewer'}
            if path.endswith('/pulls/42'):
                return {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}, 'user': {'login': 'author'}}
            if method == 'POST':
                writes.append(body)
                return {'id': 99, 'state': 'COMMENTED', 'body': body['body']}
            return dict(review)
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=lambda _: list(comments)):
            comments[0]['body'] = 'Concurrent change'
            with self.assertRaisesRegex(module.Failure, 'Pending review changed'):
                self.api.mutate({'number': 42, 'draft': draft})
            comments[0]['body'] = 'Private'
            with self.assertRaisesRegex(module.Failure, 'ownership changed'):
                self.api.mutate({'number': 42, 'draft': dict(draft, actor='github-login:other')})
            self.assertEqual([], writes)
            with self.assertRaisesRegex(module.Failure, 'No matching published review receipt') as error:
                self.api.mutate({'number': 42, 'draft': draft})
            self.assertTrue(error.exception.unknown)
            with self.assertRaisesRegex(module.Failure, 'No matching publication receipt'):
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
            self.assertEqual(1, len(writes))
        with patch.object(self.api, 'api', side_effect=[review, dict(review, state='COMMENTED')]), patch.object(self.api, 'pages', return_value=comments):
            with self.assertRaisesRegex(module.Failure, 'changed while loading'):
                self.api.load_pending(42, '7')

    def test_reactions_counts_own_identity_and_explicit_add_remove(self):
        for thread, suffix in [('100', 'pulls/comments/101/reactions'), ('', 'issues/comments/101/reactions')]:
            comment = {'id': 101, 'in_reply_to_id': 100, 'body': 'Unchanged comment'}
            entries = [{'id': 5, 'content': 'heart', 'user': {'id': 99, 'login': 'other'}}]
            writes = []
            target = {'message': '101', 'message_kind': 'comment', 'thread': thread}
            def pages(path):
                return list(entries) if path.endswith('/reactions') else [comment]
            def api(path, method='GET', body=None):
                if path == 'user':
                    return {'id': 17, 'login': 'reviewer'}
                writes.append((path, method, body))
                if method == 'POST':
                    self.assertEqual('repos/team/project/' + suffix, path)
                    entries.append({'id': 7, 'content': body['content'], 'user': {'id': 17, 'login': 'reviewer'}})
                    return dict(entries[-1])
                self.assertEqual('DELETE', method)
                self.assertEqual('repos/team/project/' + suffix + '/7', path)
                entries[:] = [r for r in entries if r['id'] != 7]
                return None
            with patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'api', side_effect=api):
                data = self.api.reactions({'number': 42, 'target': target})
                self.assertEqual('github:17', data['actor'])
                self.assertEqual((1, False), tuple(next(r for r in data['items'] if r['id'] == 'heart')[k] for k in ('count', 'mine')))
                self.assertEqual({'items': [{'id': 'github:99', 'label': 'other'}], 'unavailable': 0},
                                 next(r for r in data['items'] if r['id'] == 'heart')['members'])
                self.assertEqual([], writes, 'Inspecting membership must be read-only')
                draft = dict(self.draft, kind='reaction', body='', actor=data['actor'], reaction='heart', present=True, **target)
                receipt = self.api.mutate({'number': 42, 'draft': draft})
                self.assertTrue(receipt['observed'])
                self.assertEqual(1, len(writes))
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
                self.assertEqual(1, len(writes))
                draft.update(id='remove_reaction', present=False)
                self.api.mutate({'number': 42, 'draft': draft})
                self.assertEqual([5], [r['id'] for r in entries], 'removal cannot target another actor')
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
                self.assertEqual(2, len(writes))
                with self.assertRaisesRegex(module.Failure, 'actor changed'):
                    self.api.mutate({'number': 42, 'draft': dict(draft, actor='github:99')})
                self.assertEqual('Unchanged comment', comment['body'])

    def test_reaction_membership_reads_all_pages_without_writes(self):
        self.api.token = ''
        people = [{'id': n, 'content': 'heart', 'user': {'id': n, 'login': 'user' + str(n)}} for n in range(101)]
        calls = []
        def read(path, method='GET', body=None):
            self.assertEqual('GET', method)
            calls.append(path)
            return people[:100] if path.endswith('page=1') else people[100:]
        with patch.object(self.api, 'reaction_context', return_value='reactions'), patch.object(self.api, 'api', side_effect=read):
            data = self.api.reactions({'number': 42, 'target': {}})
        heart = next(r for r in data['items'] if r['id'] == 'heart')
        self.assertEqual(101, heart['count'])
        self.assertEqual(101, len(heart['members']['items']))
        self.assertEqual('user100', heart['members']['items'][-1]['label'])
        self.assertEqual(['reactions?per_page=100&page=1', 'reactions?per_page=100&page=2'], calls)
        self.assertNotIn('mine', heart)

    def test_reaction_membership_unavailable_anonymous_and_duplicate_pages(self):
        entries = [{'content': 'heart', 'user': {'id': 99, 'login': 'renamed'}},
                   {'content': 'heart', 'user': None},
                   {'content': 'heart', 'user': {'id': 17}}]
        groups = module.reaction_groups(entries, '')
        heart = next(r for r in groups if r['id'] == 'heart')
        self.assertEqual(3, heart['count'])
        self.assertNotIn('mine', heart)
        self.assertEqual({'items': [{'id': 'github:99', 'label': 'renamed'}], 'unavailable': 2}, heart['members'])
        self.assertEqual({'items': [], 'unavailable': 0}, groups[0]['members'])
        with self.assertRaisesRegex(module.Failure, 'membership changed'):
            module.reaction_groups([entries[0], entries[0]], 'github:99')

    def test_reaction_unknown_reconciliation_and_summary_limits(self):
        comment = {'id': 101, 'in_reply_to_id': 100, 'body': 'Text', 'reactions': {'heart': 2}}
        normalized = module.normalize_comment(comment)
        self.assertEqual([{'id': 'heart', 'label': 'Heart', 'count': 2}], normalized['reactions']['items'])
        self.assertFalse(normalized['reactions']['complete'])
        entries, writes = [], []
        target = {'message': '101', 'message_kind': 'comment', 'thread': '100'}
        draft = dict(self.draft, kind='reaction', body='', actor='github:17', reaction='heart', present=True, **target)
        def pages(path):
            return entries if path.endswith('/reactions') else [comment]
        def api(path, method='GET', body=None):
            if path == 'user':
                return {'id': 17, 'login': 'reviewer'}
            writes.append(method)
            raise module.Failure('lost connection', 'transport', True)
        with patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'api', side_effect=api):
            with self.assertRaises(module.Failure) as error:
                self.api.mutate({'number': 42, 'draft': draft})
            self.assertTrue(error.exception.unknown)
            with self.assertRaisesRegex(module.Failure, 'not observed'):
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
            self.assertEqual(['POST'], writes)
            entries.append({'id': 7, 'content': 'heart', 'user': {'id': 17}})
            self.assertTrue(self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})['observed'])
            self.assertEqual(['POST'], writes)
            self.api.token = ''
            anonymous = self.api.reactions({'number': 42, 'target': target})
            self.assertEqual('', anonymous['actor'])
            self.assertTrue(all('mine' not in r for r in anonymous['items']))
        self.api.token = 'test-only'
        calls = 0
        def post_read_failure(path):
            nonlocal calls
            if not path.endswith('/reactions'):
                return [comment]
            calls += 1
            if calls == 1:
                return []
            raise module.Failure('read denied', '403', False)
        with patch.object(self.api, 'pages', side_effect=post_read_failure), patch.object(self.api, 'api', side_effect=lambda p, *args: {'id': 17} if p == 'user' else {}):
            with self.assertRaisesRegex(module.Failure, 'read denied') as error:
                self.api.mutate({'number': 42, 'draft': draft})
            self.assertTrue(error.exception.unknown, 'failed read after write cannot unlock retry')

    def test_edit_routes_exact_targets_and_preserves_receipts(self):
        for kind, thread, expected_path, method in [
            ('comment', '100', 'pulls/comments/101', 'PATCH'),
            ('comment', '', 'issues/comments/101', 'PATCH'),
            ('APPROVED', '', 'pulls/42/reviews/101', 'PUT')]:
            current = {'id': 101, 'user': {'login': 'reviewer'}, 'body': 'Original\n\n<!-- revue:creation -->\n\n<!-- revue-batch:batch:item -->',
                       'updated_at': '2026-09-14T00:00:00Z', 'html_url': 'https://example.test/comment'}
            if thread:
                current['in_reply_to_id'] = 100
            elif kind != 'comment':
                current['state'] = kind
            normalized = module.normalize_comment(current, kind)
            draft = dict(self.draft, kind='edit', message='101', message_kind=kind, thread=thread,
                         original_body=normalized['body'], expected_version=normalized['version'], body='  Replacement 日本語\n')
            calls = []
            def api(path, method='GET', body=None):
                calls.append((path, method, body))
                if path == 'user':
                    return {'login': 'reviewer'}
                self.assertEqual('repos/team/project/' + expected_path, path)
                if method != 'GET':
                    current.update(body=body['body'], updated_at='2026-09-14T01:00:00Z')
                return dict(current)
            with patch.object(self.api, 'pages', side_effect=lambda _: [dict(current)]), patch.object(self.api, 'api', side_effect=api):
                receipt = self.api.mutate({'number': 42, 'draft': draft})
                self.assertEqual(draft['id'], receipt['id'])
                self.assertEqual('101', receipt['message'])
                self.assertEqual(method, calls[-1][1])
                self.assertIn('<!-- revue:creation -->', current['body'])
                self.assertIn('<!-- revue-batch:batch:item -->', current['body'])
                self.assertEqual(draft['body'], module.normalize_comment(current, kind)['body'])
                self.assertTrue(module.normalize_comment(current, kind)['edited'])
                # A later edit preserves the first edit's receipt.
                later = module.normalize_comment(current, kind)
                second = dict(draft, id='second_edit', original_body=later['body'], expected_version=later['version'], body='Later edit')
                self.api.mutate({'number': 42, 'draft': second})
                calls.clear()
                self.api.token = ''
                self.assertTrue(self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})['recovered'])
                self.assertEqual([], calls, 'receipt lookup never requests permission or writes')
                self.assertEqual('Later edit', module.normalize_comment(current, kind)['body'])
                self.api.token = 'test-only'
                with self.assertRaisesRegex(module.Failure, 'different replacement'):
                    self.api.mutate({'number': 42, 'draft': dict(draft, body='Changed operation payload')})

    def test_edit_stale_missing_permission_pending_and_unknown(self):
        current = {'id': 101, 'in_reply_to_id': 100, 'user': {'login': 'reviewer'}, 'body': 'Original', 'updated_at': 'first'}
        message = module.normalize_comment(current)
        draft = dict(self.draft, kind='edit', message='101', message_kind='comment', thread='100',
                     original_body=message['body'], expected_version=message['version'], body='Replacement')
        writes = []
        viewer = 'reviewer'
        def api(path, method='GET', body=None):
            if path == 'user':
                return {'login': viewer}
            if method != 'GET':
                writes.append((path, method, body))
                return None
            return dict(current)
        with patch.object(self.api, 'pages', side_effect=lambda path: [{'id': 7, 'state': 'PENDING'}] if path.endswith('/reviews') else [dict(current)]), patch.object(self.api, 'api', side_effect=api):
            current['updated_at'] = 'changed'
            with self.assertRaisesRegex(module.Failure, 'Message changed'):
                self.api.mutate({'number': 42, 'draft': draft})
            current['updated_at'] = 'first'
            viewer = 'other'
            with self.assertRaisesRegex(module.Failure, 'own feedback'):
                self.api.mutate({'number': 42, 'draft': draft})
            viewer = 'reviewer'
            with self.assertRaisesRegex(module.Failure, 'selected thread'):
                self.api.mutate({'number': 42, 'draft': dict(draft, thread='999')})
            current['pull_request_review_id'] = 7
            with self.assertRaisesRegex(module.Failure, 'published'):
                self.api.mutate({'number': 42, 'draft': draft})
            current.pop('pull_request_review_id')
            with self.assertRaisesRegex(module.Failure, 'No matching edit receipt') as error:
                self.api.mutate({'number': 42, 'draft': draft, 'reconcile': True})
            self.assertTrue(error.exception.unknown)
            self.assertEqual([], writes)
            with self.assertRaisesRegex(module.Failure, 'matching edit receipt') as error:
                self.api.mutate({'number': 42, 'draft': draft})
            self.assertTrue(error.exception.unknown, 'malformed success leaves edit frozen')
            self.assertEqual(1, len(writes))
        with patch.object(self.api, 'pages', return_value=[]), patch.object(self.api, 'api') as request:
            with self.assertRaisesRegex(module.Failure, 'no longer available'):
                self.api.mutate({'number': 42, 'draft': draft})
            request.assert_not_called()
        current.pop('in_reply_to_id')
        current['state'] = 'COMMENTED'
        message = module.normalize_comment(current, 'COMMENTED')
        mismatched = dict(draft, thread='', message_kind='APPROVED', original_body=message['body'], expected_version=message['version'])
        with patch.object(self.api, 'pages', return_value=[current]), patch.object(self.api, 'api', side_effect=api):
            with self.assertRaisesRegex(module.Failure, 'review state changed'):
                self.api.mutate({'number': 42, 'draft': mismatched})

    def test_file_comment_payload_validation_and_receipt_recovery(self):
        self.draft['kind'] = 'file_comment'
        for key in ('side', 'start', 'end'):
            self.draft.pop(key)
        files = [{'filename': self.draft['path'], 'previous_filename': self.draft['old_path'], 'status': 'renamed'}]
        with patch.object(self.api, 'pages', side_effect=lambda p: files if p.endswith('/files') else Handler.comments):
            self.assertEqual('999', self.mutate()['id'])
            payload = self.posts()[0][2]
            self.assertEqual({'body', 'path', 'commit_id', 'subject_type'}, set(payload))
            self.assertEqual('file', payload['subject_type'])
            self.assertEqual(self.draft['path'], payload['path'])
            self.assertEqual(Handler.head, payload['commit_id'])
            self.assertEqual('/repos/team/project/pulls/42/comments', self.posts()[0][1])
            Handler.comments = [{'id': 999, 'body': payload['body']}]
            self.assertTrue(self.mutate(reconcile=True)['recovered'])
            self.assertEqual(1, len(self.posts()))
            Handler.comments = []
            for fields in ({'side': 'head'}, {'start': 1}, {'path': 'missing'}, {'old_path': 'wrong'}, {'suggestion': True}):
                with self.subTest(fields=fields), self.assertRaises(module.Failure):
                    self.api.mutate({'number': 42, 'draft': dict(self.draft, **fields)})
            Handler.head = 'changed'
            with self.assertRaisesRegex(module.Failure, 'PR changed'):
                self.mutate()
            self.assertEqual(1, len(self.posts()))
        rules, _, _ = self.api.action_rules({'user': {'login': 'author'}})
        self.assertTrue(rules['file_comment']['enabled'])
        self.assertEqual('diff', rules['comment']['anchors']['scope'])
        self.assertIn('not verified', rules['comment']['anchors']['reason'])
        self.assertNotIn('file_comment', rules['batch']['kinds'])
        with self.assertRaisesRegex(module.Failure, 'batches accept'):
            self.api.batch({'number': 42, 'draft': {'kind': 'batch', 'id': 'batch', 'items': [self.draft]}})

    def test_file_thread_normalization_does_not_infer_outdated_from_null_line(self):
        pr = {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}, 'title': 'Fixture',
              'user': {'login': 'author'}, 'html_url': 'https://example.test/pr', 'state': 'open'}
        files = [{'filename': path, 'status': status, 'additions': 0, 'deletions': 0}
                 for path, status in [('binary.png', 'modified'), ('gone.py', 'removed'), ('renamed.py', 'renamed')]]
        comments = [{'id': n, 'subject_type': 'file', 'path': path, 'line': None,
                     'body': 'Whole file', 'original_commit_id': Handler.head}
                    for n, path in enumerate(['binary.png', 'gone.py', 'renamed.py', 'absent.py'], 1)]
        comments.append({'id': 5, 'in_reply_to_id': 1, 'body': 'Reply to file'})
        comments.append({'id': 6, 'path': 'gone.py', 'line': None, 'body': 'Old line comment'})
        comments.append({'id': 7, 'path': 'renamed.py', 'line': 50, 'start_line': 48,
                         'body': 'Unchanged lines outside the returned hunks'})
        def pages(path):
            if path.endswith('/files'):
                return files
            return comments if '/pulls/' in path and path.endswith('/comments') else []
        def api(path, **kwargs):
            if path == 'user':
                return {'login': 'reviewer'}
            return {'merge_base_commit': {'sha': Handler.base}} if '/compare/' in path else pr
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'thread_states', return_value={}):
            snapshot = self.api.open(42)
        for thread in snapshot['threads'][:4]:
            self.assertEqual(('file', '', 0, 0), (thread['subject_type'], thread['side'], thread['start'], thread['line']))
        self.assertEqual([False, False, False, True, True, False], [t['outdated'] for t in snapshot['threads']])
        self.assertEqual(('line', 48, 50), (snapshot['threads'][-1]['subject_type'], snapshot['threads'][-1]['start'], snapshot['threads'][-1]['line']))
        self.assertEqual(['1', '5'], [c['id'] for c in snapshot['threads'][0]['comments']])

    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        Handler.requests = []
        Handler.comments = []
        Handler.post_status = 201
        Handler.head = 'b' * 40
        Handler.base = 'c' * 40
        Handler.viewer = 'reviewer'
        Handler.author = 'author'
        Handler.graphql_responses = []
        self.api = module.GitHub({'host': 'github.com', 'repo': 'team/project'}, token='test-only')
        self.api.root = 'http://127.0.0.1:' + str(self.server.server_port)
        self.draft = {'id': 'test_draft', 'kind': 'comment', 'head': Handler.head, 'base_tip': Handler.base,
                      'path': 'src/new.py', 'old_path': 'src/old.py', 'side': 'base', 'start': 2, 'end': 4,
                      'body': 'Please explain.\nAnother paragraph.'}

    def mutate(self, **kwargs):
        return self.api.mutate(dict(number=42, draft=self.draft, **kwargs))

    def posts(self):
        return [r for r in Handler.requests if r[0] == 'POST']

    def state_page(self, resolved=False, root=101, more=False, cursor=None, **fields):
        node = dict(id='THREAD-' + str(root), isResolved=resolved, isOutdated=False,
                    viewerCanReply=True, viewerCanResolve=not resolved, viewerCanUnresolve=resolved,
                    resolvedBy={'login': 'reviewer'} if resolved else None,
                    comments={'nodes': [{'databaseId': root}]})
        node.update(fields)
        return {'data': {'repository': {'pullRequest': {'reviewThreads': {
            'nodes': [node], 'pageInfo': {'hasNextPage': more, 'endCursor': cursor}}}}}}

    def test_thread_state_pagination_and_enterprise_endpoint(self):
        self.api.root += '/api/v3'
        Handler.graphql_responses = [self.state_page(more=True, cursor='second'), self.state_page(True, root=102)]
        states = self.api.thread_states(42)
        self.assertEqual({'101', '102'}, set(states))
        self.assertEqual('THREAD-101', states['101']['native_id'])
        self.assertTrue(states['102']['resolved'])
        self.assertEqual('reviewer', states['102']['resolved_by'])
        self.assertTrue(states['102']['capabilities']['reopen']['enabled'])
        self.assertEqual('/api/graphql', self.posts()[0][1])
        self.assertEqual('second', self.posts()[1][2]['variables']['after'])
        self.assertEqual('Bearer test-only', self.posts()[0][3])

    def test_thread_resolution_and_reopening_mutation_payload(self):
        for desired in [True, False]:
            Handler.requests = []
            name = 'resolveReviewThread' if desired else 'unresolveReviewThread'
            Handler.graphql_responses = [self.state_page(not desired), {'data': {name: {
                'clientMutationId': 'test_draft', 'thread': {'id': 'THREAD-101', 'isResolved': desired}}}}]
            self.draft.update(kind='thread_state', thread='101', body='', resolved=desired, expected_resolved=not desired)
            receipt = self.mutate()
            self.assertEqual(desired, receipt['resolved'])
            self.assertEqual('101', receipt['thread'])
            self.assertEqual('/graphql', self.posts()[1][1])
            self.assertIn(name, self.posts()[1][2]['query'])
            self.assertEqual({'threadId': 'THREAD-101', 'clientMutationId': 'test_draft'}, self.posts()[1][2]['variables']['input'])

    def test_resolution_recovery_observes_state_without_reposting(self):
        self.draft.update(kind='thread_state', thread='101', body='', resolved=True, expected_resolved=False)
        Handler.graphql_responses = [self.state_page(True)]
        receipt = self.mutate(reconcile=True)
        self.assertTrue(receipt['observed'])
        self.assertTrue(receipt['recovered'])
        self.assertEqual(1, len(self.posts()))
        Handler.graphql_responses = [self.state_page(False)]
        with self.assertRaises(module.Failure) as result:
            self.mutate(reconcile=True)
        self.assertTrue(result.exception.unknown)
        self.assertEqual(2, len(self.posts()))
        self.assertTrue(all(r[2]['query'].startswith('query') for r in self.posts()))

    def test_resolution_denial_and_incomplete_response(self):
        self.draft.update(kind='thread_state', thread='101', body='', resolved=True, expected_resolved=False)
        Handler.graphql_responses = [self.state_page(viewerCanResolve=False)]
        with self.assertRaises(module.Failure) as result:
            self.mutate()
        self.assertEqual('permission', result.exception.code)
        self.assertEqual(1, len(self.posts()))
        Handler.graphql_responses = [self.state_page(), {'data': {'resolveReviewThread': None}}]
        with self.assertRaises(module.Failure) as result:
            self.mutate()
        self.assertTrue(result.exception.unknown)

    def test_resolution_inventory_errors_do_not_invent_state(self):
        for response in [self.state_page(isResolved=None), self.state_page(more=True), {'errors': [{'message': 'Denied'}]}]:
            Handler.graphql_responses = [response]
            with self.assertRaises(module.Failure):
                self.api.thread_states(42)
        Handler.post_status = 403
        with self.assertRaises(module.Failure) as result:
            self.api.thread_states(42)
        self.assertFalse(result.exception.unknown)
        self.api.token = ''
        with self.assertRaises(module.Failure) as result:
            self.api.thread_states(42)
        self.assertEqual('auth', result.exception.code)

    def test_resolution_metadata_merge_and_read_failure_fallback(self):
        pr = {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}, 'title': 'Fixture',
              'user': {'login': 'author'}, 'html_url': 'https://example.test/pr', 'state': 'open'}
        comment = {'id': 101, 'path': 'code.py', 'line': 2, 'body': 'Root', 'user': {'login': 'author'}, 'created_at': 'today'}
        def api(path, **kwargs):
            return {'merge_base_commit': {'sha': Handler.base}} if '/compare/' in path else pr
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=lambda p: [comment] if '/pulls/' in p and p.endswith('/comments') else []):
            with patch.object(self.api, 'thread_states', side_effect=module.Failure('Denied')):
                snapshot = self.api.open(42)
                self.assertNotIn('resolved', snapshot['threads'][0])
                self.assertFalse(snapshot['capabilities']['thread_state']['enabled'])
                self.assertEqual('Root', snapshot['threads'][0]['comments'][0]['body'])
            with patch.object(self.api, 'thread_states', return_value={'101': {'native_id': 'NATIVE', 'resolved': True}}):
                snapshot = self.api.open(42)
                self.assertEqual('101', snapshot['threads'][0]['id'])
                self.assertTrue(snapshot['threads'][0]['resolved'])

    def test_base_multiline_payload_and_receipt(self):
        result = self.mutate()
        self.assertEqual('999', result['id'])
        method, path, body, auth = self.posts()[0]
        self.assertEqual('/repos/team/project/pulls/42/comments', path)
        self.assertEqual('Bearer test-only', auth)
        self.assertEqual(('LEFT', 'LEFT', 2, 4), (body['side'], body['start_side'], body['start_line'], body['line']))
        self.assertEqual('src/new.py', body['path'])
        self.assertIn('<!-- revue:test_draft -->', body['body'])

    def test_single_line_head_comment(self):
        self.draft.update(side='head', start=4)
        self.mutate()
        body = self.posts()[0][2]
        self.assertEqual('RIGHT', body['side'])
        self.assertNotIn('start_line', body)

    def test_reply_targets_root(self):
        self.draft.update(kind='reply', thread='101')
        self.mutate()
        self.assertEqual('/repos/team/project/pulls/42/comments/101/replies', self.posts()[0][1])
        self.assertEqual({'body'}, set(self.posts()[0][2]))

    def test_conversation_endpoint(self):
        self.draft['kind'] = 'conversation'
        self.mutate()
        self.assertEqual('/repos/team/project/issues/42/comments', self.posts()[0][1])

    def test_approval_and_changes_request(self):
        for event in ['APPROVE', 'REQUEST_CHANGES', 'COMMENT']:
            self.draft.update(kind='review', event=event)
            self.mutate()
            self.assertEqual(event, self.posts()[-1][2]['event'])
            self.assertEqual(Handler.head, self.posts()[-1][2]['commit_id'])

    def test_stale_head_does_not_write(self):
        Handler.head = 'd' * 40
        with self.assertRaises(module.Failure) as error:
            self.mutate()
        self.assertEqual('stale', error.exception.code)
        self.assertFalse(self.posts())

    def test_empty_approval_but_not_empty_comment(self):
        self.draft.update(kind='review', event='APPROVE', body='')
        self.mutate()
        self.assertEqual('APPROVE', self.posts()[-1][2]['event'])
        self.assertEqual('', module.normalize_comment({'id': 1, 'body': self.posts()[-1][2]['body']})['body'])
        for event in ['COMMENT', 'REQUEST_CHANGES']:
            self.draft['event'] = event
            with self.assertRaises(module.Failure):
                self.mutate()
        self.assertEqual(1, len(self.posts()))

    def test_actor_capabilities_and_revalidation(self):
        pr = {'user': {'login': 'author'}}
        rules, actions, viewer = self.api.action_rules(pr)
        self.assertTrue(rules['comment']['enabled'])
        self.assertEqual('reviewer', viewer)
        self.assertTrue(next(a for a in actions if a['id'] == 'APPROVE')['enabled'])
        Handler.viewer = 'AUTHOR'
        _, actions, _ = self.api.action_rules(pr)
        self.assertFalse(next(a for a in actions if a['id'] == 'APPROVE')['enabled'])
        self.draft.update(kind='review', event='APPROVE')
        with self.assertRaises(module.Failure) as error:
            self.mutate()
        self.assertEqual('permission', error.exception.code)
        self.assertFalse(self.posts())
        self.api.token = ''
        rules, actions, _ = self.api.action_rules(pr)
        self.assertFalse(any(a['enabled'] for a in actions))
        self.assertFalse(rules['reply']['enabled'])

    def test_unknown_actor_does_not_offer_approval(self):
        with patch.object(self.api, 'api', side_effect=module.Failure('denied')):
            _, actions, _ = self.api.action_rules({'user': {'login': 'author'}})
        self.assertFalse(next(a for a in actions if a['id'] == 'APPROVE')['enabled'])

    def test_receipt_survives_permission_loss(self):
        self.api.token = ''
        Handler.comments = [{'id': 123, 'body': '<!-- revue:test_draft -->'}]
        self.assertTrue(self.mutate(reconcile=True)['recovered'])
        self.assertFalse(self.posts())

    def test_stale_target_does_not_write(self):
        Handler.base = 'd' * 40
        with self.assertRaises(module.Failure):
            self.mutate()
        self.assertFalse(self.posts())

    def test_unknown_result_is_not_reposted(self):
        with self.assertRaises(module.Failure) as error:
            self.mutate(reconcile=True)
        self.assertTrue(error.exception.unknown)
        self.assertFalse(self.posts())

    def test_receipt_reconciliation(self):
        Handler.comments = [{'id': 123, 'body': 'message\n<!-- revue:test_draft -->', 'html_url': 'https://example.test'}]
        result = self.mutate(reconcile=True)
        self.assertTrue(result['recovered'])
        self.assertEqual('123', result['id'])
        self.assertFalse(self.posts())

    def test_5xx_is_unknown_but_validation_failure_is_not(self):
        for status, unknown in [(503, True), (422, False), (403, False)]:
            Handler.post_status = status
            with self.assertRaises(module.Failure) as error:
                self.mutate()
            self.assertEqual(unknown, error.exception.unknown)

    def test_no_credentials_blocks_post(self):
        self.api.token = ''
        with self.assertRaises(module.Failure) as error:
            self.mutate()
        self.assertEqual('auth', error.exception.code)
        self.assertFalse(self.posts())

    def test_connection_forms(self):
        for value in ['team/project', 'https://github.com/team/project.git', 'git@github.com:team/project.git']:
            self.assertEqual('team/project', module.connection(value, '.')['repo'])
        conn = module.connection('https://github.example/team/project/pull/42', '.')
        self.assertEqual(('github.example', 42), (conn['host'], conn['number']))
        with self.assertRaises(module.Failure):
            module.connection('https://evil.test/team/../project', '.')

    def test_pagination(self):
        with patch.object(self.api, 'api', side_effect=[list(range(100)), [101]]) as api:
            self.assertEqual(101, len(self.api.pages('example')))
            self.assertIn('page=2', api.call_args[0][0])

    def test_raw_content_absence_binary_and_unavailable(self):
        request = {'snapshot': {'base': 'a', 'head': 'b'}, 'file': {'path': 'new', 'old_path': 'old', 'status': 'added'}}
        with patch.object(self.api, 'api', return_value=b'first\n\nthird\n'):
            content = self.api.file(request)
            self.assertEqual('absent', content['base']['kind'])
            self.assertEqual(['first', '', 'third'], content['head']['lines'])
        with patch.object(self.api, 'api', return_value=b'\0binary'):
            self.assertEqual('binary', self.api.file(request)['head']['kind'])
        with patch.object(self.api, 'api', side_effect=module.Failure('missing')):
            self.assertEqual('unavailable', self.api.file(request)['head']['kind'])

    def test_content_fingerprints_cover_bytes_not_just_rendered_lines(self):
        request = {'snapshot': {'base': 'a', 'head': 'b'}, 'file': {'path': 'new', 'old_path': 'old', 'status': 'added'}}
        hashes = []
        for raw in [b'line', b'line\n', b'line\r\n', b'\0one', b'\0two', b'\xff']:
            with patch.object(self.api, 'api', return_value=raw):
                content = self.api.file(request)['head']
            self.assertEqual(module.hashlib.sha256(raw).hexdigest(), content['hash'])
            hashes.append(content['hash'])
        self.assertEqual(len(hashes), len(set(hashes)))

    def history_snapshot(self):
        return {'version': 1, 'key': 'github.com/team/project/42', 'snapshot': 'a' * 40 + ':' + 'b' * 40,
                'base': 'a' * 40, 'head': 'b' * 40, 'base_tip': 'f' * 40, 'head_repo': 'team/project',
                'capabilities': {'comparisons': {'enabled': True}, 'reply': {'enabled': True}},
                'files': [], 'threads': [], 'conversation': []}

    def test_comparison_history_paginates_and_uses_immutable_first_parents(self):
        commits = [{'sha': char * 40, 'parents': [{'sha': 'a' * 40}],
                    'commit': {'message': 'Change ' + char + '\nBody'}} for char in ('c', 'd')]
        with patch.object(self.api, 'open', return_value=self.history_snapshot()), patch.object(self.api, 'api', side_effect=[
                {'total_commits': 2, 'commits': commits[:1]}, {'total_commits': 2, 'commits': commits[1:]}]) as api:
            result = self.api.comparisons({'number': 42})
        self.assertEqual(3, len(result['items']))
        self.assertTrue(result['complete'])
        self.assertEqual('a' * 40 + ':' + 'd' * 40, result['items'][-1]['snapshot'])
        self.assertEqual('Commit: Change d', result['items'][-1]['label'])
        self.assertIn('page=2', api.call_args[0][0])
        self.assertEqual('b' * 40, result['latest']['head'])

    def test_comparison_history_rejects_incomplete_or_duplicate_pages(self):
        commit = {'sha': 'b' * 40, 'parents': [{'sha': 'a' * 40}], 'commit': {'message': 'Change'}}
        for pages in ([{'total_commits': 2, 'commits': [commit]}, {'total_commits': 2, 'commits': []}],
                      [{'total_commits': 2, 'commits': [commit, commit]}]):
            with self.subTest(pages=pages), patch.object(self.api, 'open', return_value=self.history_snapshot()), patch.object(self.api, 'api', side_effect=pages):
                with self.assertRaises(module.Failure):
                    self.api.comparisons({'number': 42})

    def test_historical_comparison_preserves_only_proven_head_anchors(self):
        snapshot = self.history_snapshot()
        root = {'id': '1', 'path': 'new.py', 'side': 'head', 'line': 0, 'start': 0, 'outdated': True,
                'original_line': 7, 'original_start_line': 5, 'original_commit_id': 'c' * 40,
                'resolved': True, 'comments': [{'body': 'Original discussion'}]}
        snapshot['threads'] = [root, dict(root, id='2', side='base'), dict(root, id='3', original_commit_id='e' * 40)]
        reference = dict(snapshot='a' * 40 + ':' + 'c' * 40, base='a' * 40, head='c' * 40, head_repo='fork/project')
        result = {'merge_base_commit': {'sha': 'a' * 40}, 'files': [{'filename': 'new.py', 'previous_filename': 'old.py', 'status': 'renamed'}]}
        with patch.object(self.api, 'open', return_value=snapshot), patch.object(self.api, 'api', return_value=result) as api:
            historical = self.api.comparison({'number': 42, 'reference': reference})
        self.assertEqual(reference['snapshot'], historical['snapshot'])
        self.assertEqual('old.py', historical['files'][0]['old_path'])
        self.assertFalse(historical['threads'][0]['outdated'])
        self.assertEqual((5, 7), (historical['threads'][0]['start'], historical['threads'][0]['line']))
        self.assertTrue(historical['threads'][0]['resolved'])
        self.assertTrue(all(t['outdated'] and t['line'] == 0 for t in historical['threads'][1:]))
        self.assertFalse(historical['capabilities']['comment']['enabled'])
        self.assertTrue(historical['capabilities']['reply']['enabled'])
        self.assertIn('...fork:' + 'c' * 40, api.call_args[0][0])
        self.assertEqual(1, len(api.call_args.args))  # GET only, no mutation argument

    def test_historical_file_threads_preserve_only_proven_file_references(self):
        snapshot = self.history_snapshot()
        root = {'id': '1', 'subject_type': 'file', 'path': 'new.py', 'side': '', 'line': 0, 'start': 0,
                'outdated': False, 'original_commit_id': 'c' * 40, 'comments': [{'body': 'File feedback'}]}
        snapshot['threads'] = [root, dict(root, id='2', original_commit_id='e' * 40), dict(root, id='3', path='missing.py')]
        reference = dict(snapshot='a' * 40 + ':' + 'c' * 40, base='a' * 40, head='c' * 40)
        result = {'merge_base_commit': {'sha': 'a' * 40}, 'files': [{'filename': 'new.py', 'status': 'modified'}]}
        with patch.object(self.api, 'open', return_value=snapshot), patch.object(self.api, 'api', return_value=result):
            historical = self.api.comparison({'number': 42, 'reference': reference})
        self.assertEqual([False, True, True], [t['outdated'] for t in historical['threads']])
        self.assertTrue(all(t['side'] == '' and t['start'] == 0 and t['line'] == 0 for t in historical['threads']))
        self.assertFalse(historical['capabilities']['file_comment']['enabled'])

    def test_historical_comparison_rejects_identity_changes_and_file_cap(self):
        reference = dict(snapshot='a' * 40 + ':' + 'c' * 40, base='a' * 40, head='c' * 40)
        with patch.object(self.api, 'open') as opened:
            with self.assertRaises(module.Failure):
                self.api.comparison({'number': 42, 'reference': dict(reference, head='d' * 40)})
            opened.assert_not_called()
        cases = [{'merge_base_commit': {'sha': 'd' * 40}, 'files': []},
                 {'merge_base_commit': {'sha': 'a' * 40}, 'files': [{}] * 300},
                 {'merge_base_commit': {'sha': 'a' * 40}}]
        for result in cases:
            with self.subTest(result=str(result)[:80]), patch.object(self.api, 'open', return_value=self.history_snapshot()), patch.object(self.api, 'api', return_value=result):
                with self.assertRaises(module.Failure):
                    self.api.comparison({'number': 42, 'reference': reference})

    def test_marker_hidden_in_display(self):
        comment = module.normalize_comment({'id': 1, 'body': 'Visible\n\n<!-- revue:test_draft -->'})
        self.assertEqual('Visible', comment['body'])

    def test_message_metadata_preserves_evidence_without_guessing_edits(self):
        raw = {'id': 2, 'body': 'Text', 'user': {'login': 'helper', 'type': 'Bot'},
               'created_at': '2026-09-01T10:00:00Z', 'updated_at': '2026-09-02T10:00:00Z',
               'author_association': 'MEMBER', 'state': 'APPROVED'}
        message = module.normalize_comment(raw, 'APPROVED')
        self.assertEqual('Member', message['author_role'])
        self.assertEqual('bot', message['author_type'])
        self.assertEqual(raw['updated_at'], message['updated'])
        self.assertEqual('Approved', message['decision'])
        self.assertNotIn('edited', message)
        self.assertNotIn('publication', message)
        self.assertEqual('pending', module.normalize_comment(raw, pending=True)['publication'])
        self.assertEqual('pending', module.normalize_comment({'id': 3, 'state': 'PENDING'})['publication'])
        unknown = module.normalize_comment({'id': 4, 'user': {'login': 'looks-like[bot]'}, 'author_association': 'NONE'})
        self.assertNotIn('author_type', unknown)
        self.assertNotIn('author_role', unknown)

    def test_pending_badge_is_correlated_with_the_comments_review(self):
        pr = {'head': {'sha': Handler.head}, 'base': {'sha': Handler.base}, 'title': 'Fixture',
              'user': {'login': 'author'}, 'html_url': 'https://example.test/pr', 'state': 'open'}
        comments = [{'id': 101, 'path': 'code.py', 'line': 2, 'body': 'Private review feedback',
                     'pull_request_review_id': 7, 'user': {'login': 'reviewer'}, 'author_association': 'CONTRIBUTOR'},
                    {'id': 102, 'in_reply_to_id': 101, 'body': 'Different review',
                     'pull_request_review_id': 8, 'user': {'login': 'reviewer'}}]
        viewer = ['reviewer']
        def pages(path):
            if path.endswith('/reviews/7/comments'):
                return [comments[0]]
            if path.endswith('/reviews'):
                return [{'id': 7, 'state': 'PENDING', 'user': {'login': 'reviewer'}}]
            return comments[1:] if '/pulls/' in path and path.endswith('/comments') else []
        def api(path, **kwargs):
            if path == 'user':
                return {'login': viewer[0]}
            if path.endswith('/reviews/7'):
                return {'id': 7, 'state': 'PENDING', 'body': 'Private summary', 'commit_id': Handler.head, 'user': {'login': 'reviewer'}}
            return {'merge_base_commit': {'sha': Handler.base}} if '/compare/' in path else pr
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'thread_states', return_value={'101': {'native_id': 'PRRT_101', 'capabilities': {'reply': {'enabled': True}}}}):
            snapshot = self.api.open(42)
        root, reply = snapshot['threads'][0]['comments']
        self.assertEqual('pending', root['publication'])
        self.assertEqual('Contributor', root['author_role'])
        self.assertNotIn('publication', reply)
        self.assertFalse(root['capabilities']['delete']['enabled'], 'root has replies')
        self.assertEqual('message', root['capabilities']['delete']['scope'])
        self.assertTrue(snapshot['capabilities']['delete_pending_comment']['enabled'])
        self.assertNotIn('delete', reply['capabilities'], 'published deletion is separate')
        self.assertTrue(root['capabilities']['edit']['enabled'])
        self.assertEqual('7', root['pending_review'])
        self.assertTrue(reply['capabilities']['edit']['enabled'])
        self.assertTrue(snapshot['capabilities']['edit']['enabled'])
        self.assertTrue(reply['version'])
        self.assertTrue(snapshot['pending_reviews']['available'])
        self.assertEqual('sequential', snapshot['capabilities']['stage_batch']['mode'])
        self.assertEqual(1000, snapshot['capabilities']['stage_batch']['min_interval_ms'])
        self.assertEqual(['comment', 'file_comment', 'reply'], snapshot['capabilities']['stage_batch']['kinds'])
        self.assertEqual('7', snapshot['pending_reviews']['items'][0]['id'])
        self.assertEqual('Private summary', snapshot['pending_reviews']['items'][0]['body'])
        self.assertTrue(snapshot['threads'][0]['capabilities']['pending_reply']['enabled'])
        self.assertFalse(snapshot['threads'][0]['capabilities']['reply']['enabled'])
        self.assertFalse(snapshot['threads'][0]['capabilities']['resolve']['enabled'])
        self.assertEqual([], snapshot['conversation'], 'pending reviews are not published timeline entries')
        viewer[0] = 'other'
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'thread_states', return_value={}), patch.object(self.api, 'load_pending', side_effect=AssertionError('Do not load another actor private review')):
            other = self.api.open(42)
        self.assertTrue(other['pending_reviews']['available'])
        self.assertEqual([], other['pending_reviews']['items'])
        self.assertNotIn('Private summary', json.dumps(other))
        viewer[0] = ''
        with patch.object(self.api, 'api', side_effect=api), patch.object(self.api, 'pages', side_effect=pages), patch.object(self.api, 'thread_states', return_value={}):
            unknown = self.api.open(42)
        self.assertFalse(unknown['pending_reviews']['available'], 'unknown actor is not zero pending reviews')
        self.assertFalse(unknown['capabilities']['stage_batch']['enabled'])

    def test_historical_content_uses_requested_refs_and_rename_paths(self):
        request = {'snapshot': {'base': 'old-base', 'head': 'old-head', 'head_repo': 'fork/project'},
                   'file': {'path': 'new name.py', 'old_path': 'old name.py', 'status': 'renamed'}}
        def read(path, **options):
            self.assertTrue(options['raw'])
            return path.encode()
        with patch.object(self.api, 'api', side_effect=read):
            content = self.api.file(request)
        self.assertEqual(['repos/' + self.api.repo + '/contents/old%20name.py?ref=old-base'], content['base']['lines'])
        self.assertEqual(['repos/fork/project/contents/new%20name.py?ref=old-head'], content['head']['lines'])

    def batch(self):
        first = dict(self.draft, id='first', snapshot='snapshot')
        second = dict(first, id='second', side='head', start=8, end=8, body='Second concern')
        decision = dict(first, id='decision', kind='review', event='APPROVE', body='')
        return dict(first, id='batch', kind='batch', body='', items=[first, second, decision])

    def test_native_batch_payload_and_recovery(self):
        self.draft = self.batch()
        receipt = self.mutate()
        self.assertEqual(1, len(self.posts()))
        payload = self.posts()[0][2]
        self.assertEqual('APPROVE', payload['event'])
        self.assertEqual(2, len(payload['comments']))
        self.assertEqual('LEFT', payload['comments'][0]['start_side'])
        self.assertNotIn('start_line', payload['comments'][1])
        self.assertEqual('', module.normalize_comment({'id': 1, 'body': payload['body']})['body'])
        self.assertEqual(['first', 'second', 'decision'], [r['draft'] for r in receipt['items']])
        Handler.comments = [{'id': 999, 'body': payload['body'], 'html_url': 'https://example.test/review'}]
        self.draft.update(state='unknown', error='Connection lost')
        self.api.token = ''
        self.assertTrue(self.mutate(reconcile=True)['recovered'])
        self.assertEqual(1, len(self.posts()))
        self.draft['items'][0]['body'] = 'Changed payload'
        with self.assertRaisesRegex(module.Failure, 'different feedback'):
            self.mutate(reconcile=True)

    def test_suggestion_comment_and_native_batch_preserve_fences(self):
        body = 'Explanation\n\n````suggestion\n```literal\n  replacement\n````'
        self.draft.update(suggestion=True, side='head', body=body)
        self.mutate()
        payload = self.posts()[0][2]
        self.assertEqual('RIGHT', payload['side'])
        self.assertEqual(body, module.normalize_comment({'id': 1, 'body': payload['body']})['body'])
        self.assertEqual(Handler.head, payload['commit_id'])
        batch = self.batch()
        for item in batch['items']:
            item.pop('suggestion', None)
        batch.pop('suggestion', None)
        batch['items'][1].update(suggestion=True, body='```suggestion\n```')
        self.draft = batch
        self.mutate()
        self.assertEqual('```suggestion\n```', module.normalize_comment({'id': 2, 'body': self.posts()[1][2]['comments'][1]['body']})['body'])
        self.assertEqual(2, len(self.posts()), 'suggestions use comment/review endpoints, not commit endpoints')

    def test_malformed_suggestions_do_not_publish(self):
        valid = dict(self.draft, suggestion=True, side='head', body='```suggestion\nnew\n```')
        for change in [{'side': 'base'}, {'suggestion': 1}, {'body': '```suggestion\nmissing close'},
                       {'body': '```suggestion\na\n```\n```suggestion\nb\n```'},
                       {'body': '> ```suggestion\n> quoted\n> ```'}]:
            self.draft = dict(valid, **change)
            with self.assertRaises(module.Failure):
                self.mutate()
        self.assertEqual([], self.posts())

    def test_batch_rejects_unsupported_stale_and_invalid_items(self):
        self.draft = self.batch()
        self.draft['items'][0]['kind'] = 'reply'
        with self.assertRaises(module.Failure):
            self.mutate()
        self.draft['items'][0]['kind'] = 'comment'
        self.draft['items'][0]['snapshot'] = 'another-snapshot'
        with self.assertRaises(module.Failure):
            self.mutate()
        self.draft['items'][0]['snapshot'] = 'snapshot'
        Handler.head = 'changed'
        with self.assertRaises(module.Failure):
            self.mutate()
        self.assertEqual([], self.posts())

    def test_unknown_batch_never_reposts(self):
        self.draft = self.batch()
        Handler.post_status = 503
        with self.assertRaises(module.Failure) as error:
            self.mutate()
        self.assertTrue(error.exception.unknown)
        with self.assertRaises(module.Failure) as error:
            self.mutate(reconcile=True)
        self.assertTrue(error.exception.unknown)
        self.assertEqual(1, len(self.posts()))


if __name__ == '__main__':
    unittest.main()
