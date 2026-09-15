#!/usr/bin/env python3
"""Link Vim Labs components into native Vim packages from this checkout."""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import uuid


ROOT = Path(__file__).resolve().parents[1]
COMPONENTS = {
    'vim-code-review': 'plugin/revue.vim',
    'vim-code-review-github': 'plugin/reviewhub.vim',
    'vim9-mcp': 'plugin/vim9mcp.vim',
}
LEGACY = ('vim-revue', 'vim-reviewhub')


def plan(source, vim_dir):
    source = Path(source).expanduser().resolve()
    vim_dir = Path(vim_dir).expanduser().absolute()
    destination = vim_dir / 'pack/vim-labs/start'
    targets = {name: source / 'plugins' / name for name in COMPONENTS}
    for name, target in targets.items():
        if not (target / COMPONENTS[name]).is_file():
            raise ValueError(f'Missing component: {target}')
    links = {destination / name: target for name, target in targets.items()}
    existing = set()
    for name in (*COMPONENTS, *LEGACY):
        existing.update((vim_dir / 'pack').glob(f'*/start/{name}'))
    existing.update(path for path in links if os.path.lexists(path))
    changes = []
    for path in sorted(existing):
        # Real directories may be separate checkouts or submodules. Never move them.
        if not path.is_symlink():
            raise ValueError(f'Refusing to replace a real file or directory: {path}')
        if path in links and path.resolve() == links[path]:
            continue
        changes.append(path)
    return source, vim_dir, links, changes


def prepare(source, dependencies, helptags):
    if dependencies:
        node, npm = shutil.which('node'), shutil.which('npm')
        if not node or not npm:
            raise ValueError('Vim9 MCP requires Node.js 22+ and npm; install them or use --skip-deps.')
        version = subprocess.check_output([node, '--version'], text=True).strip()
        if int(version.lstrip('v').split('.')[0]) < 22:
            raise ValueError(f'Vim9 MCP requires Node.js 22+; found {version}.')
    vim = shutil.which('vim') if helptags else None
    if helptags and not vim:
        raise ValueError('Vim is required to generate help tags; use --skip-helptags to defer this.')
    # Finish prerequisites before changing the active package links.
    if dependencies:
        subprocess.run([npm, 'ci', '--ignore-scripts', '--no-audit', '--no-fund'],
                       cwd=source / 'plugins/vim9-mcp', check=True)
    if helptags:
        for name in COMPONENTS:
            doc = str(source / 'plugins' / name / 'doc').replace("'", "''")
            subprocess.run([vim, '-Nu', 'NONE', '-i', 'NONE', '-n', '-es',
                            '-c', f"execute 'helptags ' . fnameescape('{doc}')",
                            '-c', 'qa!'], check=True)


def install(source, vim_dir, *, dependencies=True, helptags=True):
    source, vim_dir, links, changes = plan(source, vim_dir)
    prepare(source, dependencies, helptags)
    # Dependencies may take time; recheck conflicts before touching active links.
    source, vim_dir, links, changes = plan(source, vim_dir)
    backup = None
    if changes:
        stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')
        backup = vim_dir / 'vim-labs-backups' / f'{stamp}-{uuid.uuid4().hex[:8]}'
        backup.mkdir(parents=True)
        manifest = []
        for index, path in enumerate(changes):
            target = os.readlink(path)
            saved = backup / f'{index}-{path.name}'
            # Relative links must still reach their original target from the backup.
            saved.symlink_to((path.parent / target).resolve())
            manifest.append({'path': str(path), 'target': target, 'backup': str(saved)})
        (backup / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    for path, target in links.items():
        if path.is_symlink() and path.resolve() == target:
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_name(f'.{path.name}-{uuid.uuid4().hex}')
        try:
            temporary.symlink_to(target, target_is_directory=True)
            os.replace(temporary, path)
        finally:
            if temporary.is_symlink():
                temporary.unlink()
    for path in changes:
        if path not in links:
            path.unlink()
    return links, backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=ROOT, help='Vim Labs checkout to link (default: this checkout)')
    parser.add_argument('--vim-dir', type=Path, default=Path.home() / '.vim', help='Vim directory (default: ~/.vim)')
    parser.add_argument('--skip-deps', action='store_true', help='keep existing MCP dependencies; do not run npm ci')
    parser.add_argument('--skip-helptags', action='store_true', help='defer generating Vim help tags')
    args = parser.parse_args()
    try:
        links, backup = install(args.source, args.vim_dir,
                                dependencies=not args.skip_deps, helptags=not args.skip_helptags)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        print(f'Install failed: {error}', file=sys.stderr)
        return 1
    for path, target in links.items():
        print(f'{path} -> {target}')
    if backup:
        print(f'Previous package symlinks saved in {backup}')
    print('Installed. Restart Vim to load this checkout. MCP client configuration is unchanged.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
