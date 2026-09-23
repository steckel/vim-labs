"""Package install/switch behavior; no dependency downloads or live Vim session."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('labs_install', ROOT / 'scripts/install.py')
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='vim labs install ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.vim = self.root / 'vim'
        self.source = self.source_tree('pinned checkout')

    def source_tree(self, name):
        source = self.root / name
        for component, marker in installer.COMPONENTS.items():
            path = source / 'plugins' / component / marker
            path.parent.mkdir(parents=True)
            path.write_text('" fixture\n')
        return source

    def install(self, source=None):
        return installer.install(source or self.source, self.vim, dependencies=False, helptags=False)

    def test_native_links_and_idempotence(self):
        links, backup = self.install()
        self.assertIsNone(backup)
        self.assertEqual(3, len(links))
        for link, target in links.items():
            self.assertTrue(link.is_symlink())
            self.assertEqual(target, link.resolve())
        self.assertIsNone(self.install()[1])

    def test_switch_to_dev_and_back_preserves_sources_and_old_links(self):
        self.install()
        dev = self.source_tree('local dev')
        links, backup = self.install(dev)
        records = json.loads((backup / 'manifest.json').read_text())
        self.assertEqual(3, len(records))
        for record in records:
            self.assertEqual(Path(record['target']), Path(record['backup']).resolve())
        for link in links:
            self.assertEqual(dev / 'plugins' / link.name, link.resolve())
        self.install(self.source)
        self.assertTrue((dev / 'plugins/vim-code-review/plugin/revue.vim').exists())
        self.assertIsNone(self.install()[1])

    def test_legacy_links_through_dotfiles_symlink_are_backed_up(self):
        packages = self.root / 'dotfiles/plugins'
        (packages / 'start').mkdir(parents=True)
        (self.vim / 'pack').mkdir(parents=True)
        (self.vim / 'pack/plugins').symlink_to(packages)
        legacy = packages / 'start/vim-revue'
        old = self.root / 'old revue'
        old.mkdir()
        legacy.symlink_to(os.path.relpath(old, legacy.parent))
        _, backup = self.install()
        self.assertFalse(legacy.is_symlink())
        record = json.loads((backup / 'manifest.json').read_text())[0]
        self.assertEqual(old, Path(record['backup']).resolve())
        self.assertTrue(old.is_dir())
        self.assertFalse(Path(record['target']).is_absolute())

    def test_real_directory_conflict_fails_before_any_preparation(self):
        conflict = self.vim / 'pack/plugins/start/vim-code-review'
        conflict.mkdir(parents=True)
        (conflict / 'keep').write_text('local work')
        with patch.object(installer, 'prepare') as prepare:
            with self.assertRaisesRegex(ValueError, 'real file or directory'):
                self.install()
            prepare.assert_not_called()
        self.assertEqual('local work', (conflict / 'keep').read_text())
        self.assertFalse((self.vim / 'pack/vim-labs').exists())

    def test_dependency_failure_leaves_active_links_unchanged(self):
        links, _ = self.install()
        dev = self.source_tree('dev')
        with patch.object(installer, 'prepare', side_effect=ValueError('dependency failure')):
            with self.assertRaisesRegex(ValueError, 'dependency failure'):
                self.install(dev)
        for path, target in links.items():
            self.assertEqual(target, path.resolve())
        self.assertFalse((self.vim / 'vim-labs-backups').exists())

    def test_incomplete_source_rejected(self):
        with self.assertRaisesRegex(ValueError, 'Missing component'):
            self.install(self.root / 'not a checkout')
        self.assertFalse(self.vim.exists())

    @unittest.skipUnless(shutil.which('vim'), 'Vim is required for package discovery')
    def test_real_vim_discovers_all_three_packages_once(self):
        installer.install(ROOT, self.vim, dependencies=False, helptags=False)
        result = self.root / 'commands.json'
        quote = lambda value: "'" + str(value).replace("'", "''") + "'"
        script = self.root / 'discover.vim'
        script.write_text(
            "let g:vim9_mcp_autoconnect = v:false\n"
            f"execute 'set packpath=' . fnameescape({quote(self.vim)})\n"
            "packloadall\n"
            "let found = [exists(':Review'), exists(':ReviewSaved'), "
            "exists(':ReviewResume'), exists(':Reviews'), exists(':VimMCPStatus')]\n"
            "let obsolete = getcompletion('Revue', 'command') + getcompletion('ReviewLocal', 'command')\n"
            "let counts = map(['plugin/revue.vim', 'plugin/reviewhub.vim', 'plugin/vim9mcp.vim'], "
            "{_, path -> len(globpath(&runtimepath, path, 0, 1))})\n"
            f"call writefile([json_encode({{'commands': found, 'obsolete': obsolete, 'copies': counts}})], {quote(result)})\nqa!\n")
        subprocess.run(['vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-es', '-S', str(script)],
                       check=True, timeout=20)
        self.assertEqual({'commands': [2] * 5, 'obsolete': [], 'copies': [1, 1, 1]}, json.loads(result.read_text()))


if __name__ == '__main__':
    unittest.main()
