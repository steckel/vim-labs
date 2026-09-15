"""Immutable range reads, including saved references and fork source routing."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('hub_ranges', Path(__file__).resolve().parents[1] / 'python/reviewhub.py')
hub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hub)


class RangeTest(unittest.TestCase):
    def setUp(self):
        self.api = object.__new__(hub.GitHub)
        self.api.repo = 'owner/repo'
        self.current = {'snapshot': 'a' * 40 + ':' + 'd' * 40, 'base': 'a' * 40, 'head': 'd' * 40,
                        'base_tip': 'f' * 40, 'head_repo': 'owner/repo', 'capabilities': {'reply': {'enabled': True}},
                        'files': [], 'threads': [], 'conversation': []}
        self.selection = {'from': self.endpoint('a', 'b'), 'to': self.endpoint('a', 'c')}

    def endpoint(self, base, head, side='head', **fields):
        return {'reference': dict(snapshot=base * 40 + ':' + head * 40, base=base * 40, head=head * 40, **fields), 'side': side}

    def read(self, selection=None):
        return self.api.comparison_range({'number': 42, 'selection': selection or self.selection})

    def test_range_and_saved_reference_preserve_endpoints_and_permissions(self):
        response = {'merge_base_commit': {'sha': 'b' * 40}, 'files': [{'filename': 'code.py', 'status': 'modified'}]}
        with patch.object(self.api, 'open', side_effect=lambda _: copy.deepcopy(self.current)), patch.object(self.api, 'api', return_value=response) as api:
            result = self.read()
            reference = self.api.comparison_reference(result)
            reopened = self.api.comparison({'number': 42, 'reference': reference})
        self.assertEqual('range:' + 'b' * 40 + ':' + 'c' * 40, result['snapshot'])
        self.assertEqual(self.selection, reopened['range'])
        self.assertEqual(('b' * 40, 'c' * 40), (reopened['base'], reopened['head']))
        self.assertTrue(result['capabilities']['reply']['enabled'])
        self.assertFalse(result['capabilities']['comment']['enabled'])
        self.assertTrue(all(len(call.args) == 1 and not call.kwargs for call in api.call_args_list))

    def test_base_side_current_range_still_has_separate_read_only_identity(self):
        selection = {'from': self.endpoint('a', 'd', 'base'), 'to': self.endpoint('a', 'd')}
        with patch.object(self.api, 'open', return_value=copy.deepcopy(self.current)), patch.object(self.api, 'api') as api:
            result = self.read(selection)
        api.assert_not_called()
        self.assertNotEqual(self.current['snapshot'], result['snapshot'])
        self.assertFalse(result['capabilities']['review']['enabled'])

    def test_fork_source_repositories_survive_range_and_saved_reference(self):
        selection = {'from': self.endpoint('a', 'b', head_repo='first/repo'), 'to': self.endpoint('a', 'c', head_repo='second/repo')}
        response = {'merge_base_commit': {'sha': 'b' * 40}, 'files': [{'filename': 'new', 'previous_filename': 'old', 'status': 'renamed'}]}
        with patch.object(self.api, 'open', return_value=copy.deepcopy(self.current)), patch.object(self.api, 'api', return_value=response) as api:
            result = self.read(selection)
            self.assertIn('first:' + 'b' * 40 + '...second:' + 'c' * 40, api.call_args.args[0])
        with patch.object(self.api, 'api', return_value=b'content\n') as api:
            self.api.file({'snapshot': result, 'file': result['files'][0]})
        paths = [c.args[0] for c in api.call_args_list]
        self.assertIn('repos/first/repo/contents/old', paths[0])
        self.assertIn('repos/second/repo/contents/new', paths[1])
        self.assertEqual('first/repo', self.api.comparison_reference(result)['base_repo'])

    def test_nonancestor_and_capped_comparisons_are_explicit_errors(self):
        for response in ({'merge_base_commit': {'sha': 'a' * 40}, 'files': []},
                         {'merge_base_commit': {'sha': 'b' * 40}, 'files': [{}] * 300}):
            with self.subTest(response=str(response)[:80]), patch.object(self.api, 'open', return_value=copy.deepcopy(self.current)), patch.object(self.api, 'api', return_value=response):
                with self.assertRaises(hub.Failure):
                    self.read()

    def test_base_endpoint_keeps_its_original_repository(self):
        selection = copy.deepcopy(self.selection)
        selection['from'] = self.endpoint('b', 'c', side='base', base_repo='parent/repo', head_repo='fork/repo')
        response = {'merge_base_commit': {'sha': 'b' * 40}, 'files': []}
        with patch.object(self.api, 'open', return_value=copy.deepcopy(self.current)), patch.object(self.api, 'api', return_value=response) as api:
            result = self.read(selection)
        self.assertIn('/compare/parent:' + 'b' * 40, api.call_args.args[0])
        self.assertEqual('parent/repo', result['base_repo'])

    def test_malformed_and_nested_endpoints_do_not_read(self):
        for change in ({'side': 'wrong'}, {'reference': {'snapshot': 'a:b', 'base': 'a', 'head': 'b'}},
                       {'reference': dict(self.selection['from']['reference'], range={})}):
            selection = copy.deepcopy(self.selection)
            selection['from'].update(change)
            with self.subTest(change=change), patch.object(self.api, 'open') as opened:
                with self.assertRaises(hub.Failure):
                    self.read(selection)
                opened.assert_not_called()

    def test_saved_range_rejects_wrong_identity(self):
        response = {'merge_base_commit': {'sha': 'b' * 40}, 'files': []}
        with patch.object(self.api, 'open', return_value=copy.deepcopy(self.current)), patch.object(self.api, 'api', return_value=response):
            with self.assertRaisesRegex(hub.Failure, 'identity'):
                self.api.comparison({'number': 42, 'reference': {'snapshot': 'wrong', 'range': self.selection}})


if __name__ == '__main__':
    unittest.main()
