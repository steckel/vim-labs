import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('inventory_hub', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


class InventoryTest(unittest.TestCase):
    def test_private_and_resolution_failures_do_not_claim_full_coverage(self):
        threads = [{'comments': [{'id': '1'}]}, {'comments': [{'publication': 'pending'}]}]
        pending = {'available': False, 'items': [], 'error': 'Private read failed'}
        coverage = hub.review_inventory([{}], threads, [{}], pending, 'actor', 'States unavailable', False)
        self.assertEqual('complete', coverage['files']['state'])
        self.assertEqual('partial', coverage['threads']['state'])
        self.assertNotIn('total', coverage['threads'])
        self.assertEqual('failed', coverage['private']['state'])
        self.assertEqual('failed', coverage['thread_state']['state'])
        self.assertEqual(1, coverage['thread_state']['total'])
        self.assertIn('excludes system events', coverage['conversation']['scope'])

    def test_complete_empty_differs_from_unavailable_and_orphan_replies(self):
        pending = {'available': True, 'items': [], 'error': ''}
        coverage = hub.review_inventory([], [], [], pending, 'actor', '', False)
        self.assertTrue(all(v['state'] == 'complete' and v['total'] == 0 for v in coverage.values()))
        partial = hub.review_inventory([], [], [], pending, 'actor', '', True)
        self.assertEqual('partial', partial['threads']['state'])
        self.assertIn('no available root', partial['threads']['reason'])
        pending.update(available=False, error='Sign in')
        public = hub.review_inventory([], [], [], pending, '', 'Sign in', False)
        self.assertEqual('complete', public['threads']['state'])
        self.assertEqual('unknown', public['private']['state'])

    def test_missing_resolution_is_partial_not_unresolved(self):
        threads = [{'comments': [{}], 'resolved': False}, {'comments': [{}]}]
        coverage = hub.review_inventory([], threads, [], {'available': True, 'items': []}, 'actor', '', False)
        self.assertEqual('complete', coverage['threads']['state'])
        self.assertEqual('partial', coverage['thread_state']['state'])
        self.assertEqual(2, coverage['thread_state']['total'])


if __name__ == '__main__':
    unittest.main()
