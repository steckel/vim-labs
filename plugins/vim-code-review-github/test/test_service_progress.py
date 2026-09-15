"""Service Viewed reads and writes use controlled GraphQL responses only."""
import copy
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('viewed_provider', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)

class ServiceProgressTest(unittest.TestCase):
    def setUp(self):
        self.api = object.__new__(hub.GitHub)
        self.api.repo, self.api.token = 'owner/repo', 'fixture'
        self.ref = {'base': 'a'*40, 'head': 'b'*40, 'base_tip': 'c'*40, 'snapshot': 'a'*40+':'+'b'*40}
        self.actor, self.head, self.state = 'user1', self.ref['head'], 'UNVIEWED'
        self.writes, self.pages = [], 0
        self.mode = ''
        self.api.graphql = self.query
        self.request = {'number': 42, 'reference': self.ref, 'path': 'file.py'}
        self.draft = {'kind': 'service_viewed', 'id': 'op1', 'body': '', 'path': 'file.py', 'reference': self.ref, 'actor': 'github-node:user1', 'review_id': 'pr1', 'viewed': True}

    def query(self, query, variables, write=False):
        if write:
            self.writes.append((query, variables))
            self.state = 'VIEWED' if '{markFileAsViewed(' in query else 'UNVIEWED'
            if self.mode == 'lost': raise hub.Failure('Lost response', 'transport', True)
            if self.mode == 'head_after_write': self.head = 'd'*40
            return {'result': {'pullRequest': {'id': 'pr1'}}}
        pr = {'id': 'pr1', 'headRefOid': self.head, 'baseRefOid': self.ref['base_tip'], 'url': 'https://github.com/owner/repo/pull/42'}
        if 'files(first:' in query:
            self.pages += 1
            first = variables['after'] is None
            nodes = [] if (first and self.mode == 'paged') or self.mode == 'cycle' else [{'path': 'file.py', 'viewerViewedState': self.state}]
            pr['files'] = {'nodes': nodes, 'pageInfo': {'hasNextPage': not nodes, 'endCursor': 'next'}}
            if self.mode == 'actor_change' and self.pages > 1: self.actor = 'other'
        elif self.mode == 'actor_guard': self.actor = 'other'
        return {'viewer': {'id': self.actor, 'login': 'Same display name'}, 'repository': {'pullRequest': pr}}

    def test_read_paging_dismissed_and_source_guard(self):
        self.mode, self.state = 'paged', 'DISMISSED'
        data = self.api.service_progress(self.request)
        self.assertEqual('dismissed', data['state'])
        self.assertEqual(2, self.pages)
        self.assertEqual([], self.writes)
        self.head = 'd'*40
        with self.assertRaisesRegex(hub.Failure, 'source changed'): self.api.service_progress(self.request)

    def test_explicit_mark_unmark_and_no_replay(self):
        request = {'number': 42, 'draft': self.draft}
        receipt = self.api.mutate(request)
        self.assertTrue(receipt['observed'])
        self.assertEqual('op1', self.writes[0][1]['input']['clientMutationId'])
        self.assertEqual({'pullRequestId', 'path', 'clientMutationId'}, set(self.writes[0][1]['input']))
        self.api.mutate(dict(request, reconcile=True))
        self.assertEqual(1, len(self.writes))
        self.draft.update(id='op2', viewed=False)
        self.api.mutate(request)
        self.assertEqual('UNVIEWED', self.state)
        self.assertIn('unmarkFileAsViewed', self.writes[-1][0])

    def test_lost_response_reconciles_only_observed_intent(self):
        self.mode = 'lost'
        with self.assertRaises(hub.Failure): self.api.mutate({'number': 42, 'draft': self.draft})
        self.api.mutate({'number': 42, 'draft': self.draft, 'reconcile': True})
        self.state = 'DISMISSED'
        with self.assertRaisesRegex(hub.Failure, 'not observed'):
            self.api.mutate({'number': 42, 'draft': self.draft, 'reconcile': True})
        self.assertEqual(1, len(self.writes))

    def test_post_write_head_race_is_unknown(self):
        self.mode = 'head_after_write'
        with self.assertRaises(hub.Failure) as error: self.api.mutate({'number': 42, 'draft': self.draft})
        self.assertTrue(error.exception.unknown)
        self.assertEqual(1, len(self.writes))

    def test_paging_cycle_and_missing_identity_fail_without_writes(self):
        self.mode = 'cycle'
        with self.assertRaisesRegex(hub.Failure, 'cursor'): self.api.service_progress(self.request)
        self.assertEqual(2, self.pages)
        self.mode, self.actor = '', ''
        with self.assertRaisesRegex(hub.Failure, 'identity'): self.api.service_progress(self.request)
        self.assertEqual([], self.writes)

    def test_actor_identity_unknown_state_and_validation(self):
        self.draft['actor'] = 'github-node:other'
        with self.assertRaisesRegex(hub.Failure, 'actor or review changed'): self.api.mutate({'number': 42, 'draft': self.draft})
        self.mode = 'actor_guard'
        with self.assertRaisesRegex(hub.Failure, 'Viewer or review changed'): self.api.service_progress(self.request)
        self.mode, self.state = '', 'FUTURE_STATE'
        with self.assertRaisesRegex(hub.Failure, 'Unknown service'): self.api.service_progress(self.request)
        for ref in ({}, dict(self.ref, context={}), dict(self.ref, snapshot='wrong')):
            with self.assertRaises(hub.Failure): self.api.service_progress(dict(self.request, reference=ref))
        self.assertEqual([], self.writes)

if __name__ == '__main__': unittest.main()
