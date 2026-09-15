"""Head-bound, read-only readiness observations, including fork PR identity."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('readiness_hub', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


def check(identity='check-1', **changes):
    value = {'__typename': 'CheckRun', 'id': identity, 'name': 'Tests', 'status': 'COMPLETED',
             'conclusion': 'FAILURE', 'detailsUrl': 'https://ci.example/run/1', 'permalink': 'https://github.example/check/1', 'isRequired': True}
    return dict(value, **changes)


class ReadinessTest(unittest.TestCase):
    def setUp(self):
        self.api = object.__new__(hub.GitHub)
        self.api.conn = {'host': 'github.example'}
        self.api.repo = 'owner/repo'
        self.reference = {'snapshot': 'snapshot-1', 'head': 'a' * 40, 'base': 'b' * 40}
        self.pr = {'id': 'PR_global', 'url': 'https://github.example/owner/repo/pull/42',
                   'headRefOid': 'a' * 40, 'baseRefOid': 'c' * 40, 'isDraft': False, 'state': 'OPEN',
                   'reviewDecision': 'REVIEW_REQUIRED', 'mergeStateStatus': 'BLOCKED', 'mergeable': 'MERGEABLE'}
        self.page = {'nodes': [check()], 'totalCount': 1, 'pageInfo': {'hasNextPage': False, 'endCursor': 'end'}}
        self.calls = []
        self.change = None
        self.rollup = True
        def graphql(query, variables, write=False):
            self.assertFalse(write)
            self.assertNotIn('mutation', query)
            self.calls.append((query, copy.deepcopy(variables)))
            pr = copy.deepcopy(self.pr)
            if 'contexts(first:50' in query:
                self.assertEqual('PR_global', variables['pr'])
                self.assertIn('isRequired(pullRequestId:$pr)', query)
                pr['commits'] = {'nodes': [{'commit': {'oid': pr['headRefOid'], 'statusCheckRollup': {'contexts': copy.deepcopy(self.page)} if self.rollup else None}}]}
            if self.change:
                self.change(pr, len(self.calls), query)
            return {'repository': {'pullRequest': pr}}
        self.api.graphql = graphql

    def read(self, cursor=''):
        return self.api.readiness({'number': 42, 'reference': self.reference, 'cursor': cursor})

    def test_readonly_page_with_required_and_optional_results(self):
        self.page['nodes'].append(check('check-2', isRequired=False, conclusion='SKIPPED'))
        self.page['totalCount'] = 2
        result = self.read()
        self.assertEqual(['failed', 'skipped'], [c['state'] for c in result['checks']])
        self.assertEqual([True, False], [c['required'] for c in result['checks']])
        self.assertEqual('Review required', result['facts'][0]['value'])
        self.assertTrue(result['complete'])
        self.assertEqual(3, len(self.calls))
        self.assertEqual(self.reference, result['reference'])
        self.assertEqual(self.pr['headRefOid'], result['head'])
        self.assertIn('missing required checks', result['scope'])

    def test_status_semantics_and_unknowns(self):
        for conclusion, expected in [('SUCCESS', 'passed'), ('CANCELLED', 'cancelled'), ('NEUTRAL', 'neutral'), ('SKIPPED', 'skipped'), ('STALE', 'unknown'), (None, 'unknown'), ('NEW_VALUE', 'unknown')]:
            self.assertEqual(expected, hub.readiness_check(check(conclusion=conclusion))['state'])
        self.assertEqual('pending', hub.readiness_check(check(status='WAITING', conclusion=None))['state'])
        status = {'__typename': 'StatusContext', 'id': 'status', 'context': 'Build', 'state': 'EXPECTED', 'description': None, 'targetUrl': None, 'isRequired': None}
        self.assertEqual('pending', hub.readiness_check(status)['state'])
        self.assertIsNone(hub.readiness_check(status)['required'])
        self.pr['reviewDecision'] = None
        self.assertEqual('Unavailable', self.read()['facts'][0]['value'])

    def test_empty_report_is_not_all_requirements_satisfied(self):
        self.rollup = False
        result = self.read()
        self.assertEqual([], result['checks'])
        self.assertEqual(0, result['total'])
        self.assertEqual('Blocked', result['facts'][1]['value'])
        self.assertNotIn('ready', result)

    def test_cursor_scopes_and_paging(self):
        self.page['totalCount'] = 2
        self.page['pageInfo'] = {'hasNextPage': True, 'endCursor': 'page2'}
        first = self.read()
        self.page['nodes'] = [check('check-2')]
        self.page['pageInfo'] = {'hasNextPage': False, 'endCursor': 'end'}
        second = self.read(first['next_cursor'])
        self.assertEqual('page2', self.calls[-2][1]['after'])
        self.assertTrue(second['complete'])
        for changed in [{'review': 'other/review'}, {'reference': {'snapshot': 'other'}}, {'after': ''}]:
            cursor = dict(json.loads(first['next_cursor']), **changed)
            before = len(self.calls)
            with self.assertRaises(hub.Failure): self.read(json.dumps(cursor))
            self.assertEqual(before, len(self.calls))
        self.pr['baseRefOid'] = 'd' * 40
        with self.assertRaisesRegex(hub.Failure, 'branches changed'): self.read(first['next_cursor'])

    def test_read_races_and_wrong_commit(self):
        for stage in (2, 3):
            self.calls.clear()
            self.change = lambda pr, n, q: pr.update(headRefOid='d' * 40) if n == stage else None
            with self.assertRaisesRegex(hub.Failure, 'changed'): self.read()
        self.calls.clear()
        self.change = lambda pr, n, q: pr['commits']['nodes'][0]['commit'].update(oid='wrong') if 'commits' in pr else None
        with self.assertRaisesRegex(hub.Failure, 'match'): self.read()

    def test_malformed_pages_and_duplicate_ids(self):
        for changes in [{'nodes': [check(), check()]}, {'totalCount': True}, {'pageInfo': {'hasNextPage': 'false'}}, {'pageInfo': {'hasNextPage': True, 'endCursor': ''}}, {'nodes': [None]}]:
            original = copy.deepcopy(self.page)
            self.page.update(changes)
            with self.subTest(changes=changes), self.assertRaises(hub.Failure): self.read()
            self.page = original
        with self.assertRaises(hub.Failure): hub.readiness_check(check(isRequired=1))


if __name__ == '__main__':
    unittest.main()
