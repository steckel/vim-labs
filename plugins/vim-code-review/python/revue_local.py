#!/usr/bin/env python3
"""Local review backend: immutable Git/jj captures and transactional discussion.

One JSON request on stdin, one response on stdout. This module is deliberately
independent of Vim so other transports can call the same backend operations.
Only this backend opens its SQLite database; remote providers do not depend on it.
"""

import argparse
import copy
import datetime
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import stat
import subprocess
import sys
import uuid


MAX_CONTENT = 2 * 1024 * 1024
REACTIONS = {'+1': 'Thumbs up', '-1': 'Thumbs down', 'laugh': 'Laugh', 'hooray': 'Hooray',
             'confused': 'Confused', 'heart': 'Heart', 'rocket': 'Rocket', 'eyes': 'Eyes'}


def message_target(snapshot, target):
    messages = snapshot['conversation']
    if target.get('thread'):
        threads = [t for t in snapshot['threads'] if t['id'] == target['thread']]
        messages = threads[0]['comments'] if len(threads) == 1 else []
    matches = [m for m in messages if m['id'] == target.get('message') and m.get('kind', 'comment') == target.get('message_kind')]
    if len(matches) != 1:
        raise ValueError('Message does not belong to this discussion')
    return matches[0]


def reaction_data(snapshot, message, details=False):
    actor = 'local:' + snapshot['author']
    members = message.get('reaction_members', [])
    items = []
    for key, label in REACTIONS.items():
        matches = [m for m in members if m['content'] == key]
        item = {'id': key, 'label': label, 'count': len(matches),
                'mine': any(m['actor'] == actor for m in matches)}
        if details:
            item['members'] = {'items': [{'id': m['actor'],
                'label': m['actor'][6:] if m['actor'].startswith('local:') else m['actor']}
                for m in matches], 'unavailable': 0}
        items.append(item)
    return {'actor': actor, 'actor_label': snapshot['author'], 'complete': True,
            'items': items}


def encode(value):
    return json.dumps(value, ensure_ascii=True, sort_keys=True, separators=(",", ":"))


def identity():
    return uuid.uuid4().hex


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def git(root, *args, check=True):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True)
    if check and result.returncode:
        raise ValueError(result.stderr.decode("utf-8", "replace").strip() or "Git operation failed")
    return result


def content(raw):
    result = {"hash": hashlib.sha256(raw).hexdigest(), "lines": []}
    if len(raw) > MAX_CONTENT:
        return dict(result, kind="unavailable", message="File exceeds the 2 MiB capture limit.")
    if b"\0" in raw:
        return dict(result, kind="binary", message="Binary content.")
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return dict(result, kind="binary", message="Content is not UTF-8 text.")
    # Preserve source line coordinates; normalize CRLF only for display.
    lines = text.split("\n")
    if lines[-1] == "":
        lines.pop()
    return dict(result, kind="text", lines=[line.removesuffix("\r") for line in lines],
                final_newline=text.endswith("\n"))


def absent():
    return {"kind": "absent", "lines": []}


def range_revision(data, selection):
    """Compare retained trees; no workspace or Git reads, including on restart."""
    if not isinstance(selection, dict) or set(selection) != {'from', 'to'}:
        raise ValueError('A range requires from and to endpoints')
    endpoints = []
    for name in ('from', 'to'):
        endpoint = selection.get(name, {})
        if not isinstance(endpoint, dict) or not isinstance(endpoint.get('reference'), dict):
            raise ValueError('A range endpoint requires a comparison reference')
        reference = endpoint.get('reference', {})
        revision = data['revisions'].get(reference.get('snapshot'))
        if endpoint.get('side') not in ('base', 'head') or revision is None:
            raise ValueError('Choose a retained capture and its base or head for each endpoint')
        source = revision['snapshot']
        if 'range' in source or 'range' in reference or any(reference.get(k) != source[k] for k in ('snapshot', 'base', 'head')) or reference.get('base_tip', source['base_tip']) != source['base_tip']:
            raise ValueError('Range endpoints must identify original captures, not derived ranges')
        endpoints.append(revision)
    if endpoints[0]['snapshot']['base'] != endpoints[1]['snapshot']['base']:
        raise ValueError('Local range endpoints must share their captured baseline')
    baseline = {}
    for revision in endpoints:
        for file in revision['snapshot']['files']:
            before = revision['contents'][file['id']]['base']
            if file['old_path'] in baseline and baseline[file['old_path']] != before:
                raise ValueError('Retained captures disagree about their immutable baseline')
            baseline[file['old_path']] = before
    trees = []
    for name, revision in zip(('from', 'to'), endpoints):
        tree = dict(baseline)
        if selection[name]['side'] == 'head':
            # Remove rename origins before adding destinations (also handles swaps).
            for file in revision['snapshot']['files']:
                if file['status'] in ('R', 'renamed'):
                    tree[file['old_path']] = absent()
            for file in revision['snapshot']['files']:
                tree[file['path']] = revision['contents'][file['id']]['head']
        trees.append(tree)
    files, contents = [], {}
    same_source = endpoints[0]['snapshot'][selection['from']['side']] == endpoints[1]['snapshot'][selection['to']['side']]
    for path in sorted(set(trees[0]) | set(trees[1])):
        before, after = (tree.get(path, absent()) for tree in trees)
        if before == after and (before['kind'] != 'unavailable' or before.get('hash') or same_source):
            continue
        file_id = hashlib.sha256(path.encode()).hexdigest()
        patch = ''
        if before['kind'] in ('text', 'absent') and after['kind'] in ('text', 'absent'):
            patch = '\n'.join(difflib.unified_diff(before['lines'], after['lines'], fromfile='base', tofile='head', lineterm=''))
        status = 'A' if before['kind'] == 'absent' else 'D' if after['kind'] == 'absent' else 'M'
        files.append({'id': file_id, 'path': path, 'old_path': path, 'status': status, 'patch': patch})
        contents[file_id] = {'base': before, 'head': after}
    snapshot = copy.deepcopy(data['snapshot'])
    snapshot.update(snapshot='range:' + hashlib.sha256(encode(selection).encode()).hexdigest(),
                    base=endpoints[0]['snapshot'][selection['from']['side']],
                    head=endpoints[1]['snapshot'][selection['to']['side']], files=files,
                    range=copy.deepcopy(selection), threads=[], conversation=[],
                    comparison_note='Selected retained trees; renames are shown as removal/addition. Current conversation keeps original anchors.')
    return {'snapshot': snapshot, 'contents': contents, 'created': now(), 'sequence': 0}


def working_content(root, path):
    file = root / path
    # A tracked directory replaced by a symlink must not make a capture read
    # an unrelated file outside the workspace. Final symlinks are read as links.
    if root.resolve() not in (file.parent.resolve(), *file.parent.resolve().parents):
        raise ValueError("File parent escapes workspace: " + path)
    try:
        mode = file.lstat().st_mode
    except FileNotFoundError:
        return absent()
    if stat.S_ISLNK(mode):
        return content(os.fsencode(os.readlink(file)))
    if not stat.S_ISREG(mode):
        return {"kind": "unavailable", "lines": [], "message": "Non-regular file or submodule."}
    return content(file.read_bytes())


def capture_files(root, base, untracked):
    names = git(root, "diff", "--no-ext-diff", "--no-textconv", "--name-status", "-z", "-M", base, "--").stdout.split(b"\0")
    entries = []
    index = 0
    while index < len(names) and names[index]:
        status = names[index].decode("ascii")[0]
        old = names[index + 1].decode("utf-8")
        index += 2
        path = old
        if status in ("R", "C"):
            path = names[index].decode("utf-8")
            index += 1
        entries.append((path, old, status))
    if untracked:
        tracked_paths = {entry[0] for entry in entries}
        entries.extend((p.decode("utf-8"), p.decode("utf-8"), "A") for p in
                       git(root, "ls-files", "--others", "--exclude-standard", "-z").stdout.split(b"\0")
                       if p and p.decode("utf-8") not in tracked_paths)
    files, contents = [], {}
    for path, old, status in sorted(set(entries)):
        tree_entry = git(root, "ls-tree", "-z", base, "--", old).stdout
        if tree_entry.startswith(b"160000 "):
            before = {"kind": "unavailable", "lines": [], "message": "Submodule content is not captured."}
        else:
            base_result = git(root, "show", base + ":" + old, check=False)
            if base_result.returncode and status != "A":
                raise ValueError("Cannot capture base content: " + old)
            before = absent() if base_result.returncode else content(base_result.stdout)
        # A staged removal may leave an untracked file on disk. Include it
        # only when requested, and do not emit two entries for the same path.
        after = absent() if status == "D" and not untracked else working_content(root, path)
        if status == "D" and after["kind"] != "absent":
            status = "M"
        file_id = hashlib.sha256(path.encode()).hexdigest()
        patch = ""
        if before["kind"] in ("text", "absent") and after["kind"] in ("text", "absent"):
            patch = "\n".join(difflib.unified_diff(before["lines"], after["lines"],
                                                  fromfile="base", tofile="head", lineterm=""))
        files.append({"id": file_id, "path": path, "old_path": old, "status": status, "patch": patch})
        contents[file_id] = {"base": before, "head": after}
    return files, contents


def jj(root, *args, snapshot=False, check=True):
    # cwd matters: -R alone leaves paths relative to the caller's directory.
    argv = ["jj", "--color=never", "--no-pager"]
    if not snapshot:
        argv.append("--ignore-working-copy")
    result = subprocess.run([*argv, *args], cwd=root, capture_output=True)
    if check and result.returncode:
        raise ValueError(result.stderr.decode("utf-8", "replace").strip() or "jj operation failed")
    return result


def jj_revision(root, expression, snapshot=False):
    revisions = jj(root, "log", "-r", expression, "--no-graph", "-T", 'commit_id ++ "\\n"',
                   snapshot=snapshot).stdout.decode().splitlines()
    if len(revisions) != 1 or not re.fullmatch(r"[0-9a-f]+", revisions[0]):
        raise ValueError("Choose exactly one jj revision: " + expression)
    return revisions[0]


def capture_jj_files(root, base, head):
    # JSON fields preserve literal rename/copy paths, spaces and newlines.
    template = ('"[" ++ json(status_char) ++ "," ++ json(path) ++ "," ++ '
                'json(source.path()) ++ "," ++ json(source.file_type()) ++ "," ++ '
                'json(target.file_type()) ++ "]\\n"')
    entries = jj(root, "diff", "--from", base, "--to", head, "--template", template).stdout.decode().splitlines()
    files, contents = [], {}
    for status, path, old, base_kind, head_kind in sorted((json.loads(line) for line in entries), key=lambda entry: entry[1]):
        sides = []
        for revision, name, kind in [(base, old, base_kind), (head, path, head_kind)]:
            if not kind:
                sides.append(absent())
            elif kind == "file":
                sides.append(content(jj(root, "file", "show", "-r", revision, "-T", "", "--", "file:" + json.dumps(name, ensure_ascii=False)).stdout))
            else:
                sides.append({"kind": "unavailable", "lines": [], "message": "jj " + kind + " content is not captured."})
        before, after = sides
        file_id = hashlib.sha256(path.encode()).hexdigest()
        patch = ""
        if before["kind"] in ("text", "absent") and after["kind"] in ("text", "absent"):
            patch = "\n".join(difflib.unified_diff(before["lines"], after["lines"],
                                                   fromfile="base", tofile="head", lineterm=""))
        files.append({"id": file_id, "path": path, "old_path": old, "status": status, "patch": patch})
        contents[file_id] = {"base": before, "head": after}
    return files, contents


def capture(request, allow_empty=False):
    cwd = request["cwd"]
    vcs = request.get("vcs", "")
    jj_root = jj(cwd, "root", check=False) if vcs != "git" and shutil.which("jj") else None
    if vcs == "jj" or (jj_root is not None and jj_root.returncode == 0):
        if jj_root is None or jj_root.returncode:
            raise ValueError("Cannot open this jj workspace; check that jj is installed.")
        root = Path(jj_root.stdout.decode().strip())
        vcs = "jj"
        base_expression = request.get("base") or "@-"
        # Snapshot saved files once, then read both immutable trees by commit ID.
        head = jj_revision(root, "@", snapshot=True)
        base = jj_revision(root, base_expression)
        files, contents = capture_jj_files(root, base, head)
        if jj_revision(root, "@", snapshot=True) != head:
            raise ValueError("Workspace changed during capture; retry when edits have settled.")
        author = jj(root, "log", "-r", head, "--no-graph", "-T", "author.name()").stdout.decode().strip() or "You"
        untracked = bool(request.get("untracked", False))
        inclusion = "Files tracked by jj are included; jj automatically tracks new non-ignored files."
    else:
        vcs = "git"
        root = Path(git(cwd, "rev-parse", "--show-toplevel").stdout.decode().strip())
        base_expression = request.get("base") or "HEAD"
        base = git(root, "rev-parse", "--verify", "--end-of-options", base_expression + "^{commit}").stdout.decode().strip()
        untracked = bool(request.get("untracked", False))
        files, contents = capture_files(root, base, untracked)
        # Patch and display always derive from the exact same retained content.
        if (files, contents) != capture_files(root, base, untracked):
            raise ValueError("Workspace changed during capture; retry when edits have settled.")
        author = git(root, "config", "user.name", check=False).stdout.decode("utf-8", "replace").strip() or "You"
        inclusion = "Untracked files included." if untracked else "Untracked files excluded."
    if not files and not allow_empty:
        raise ValueError("No changes to capture against " + base_expression)
    snapshot_id = hashlib.sha256(encode([base, files, contents]).encode()).hexdigest()
    review = identity()
    return {
        "id": review, "workspace": str(root), "vcs": vcs, "created": now(), "contents": contents,
        "capture_options": {'base': base, 'untracked': untracked},
        "snapshot": {
            "version": 1, "key": "local/" + review, "display_id": "Local " + review[:8],
            "title": root.name + " · " + base_expression + " → saved working tree",
            "author": author, "state": "open", "body": "Captured saved files. Unsaved buffers excluded. " +
            inclusion,
            "url": "", "reviewers": [], "base": base, "base_tip": base, "head": snapshot_id,
            "submit_label": "Save", "submit_target": "local review " + review[:8],
            "snapshot": snapshot_id, "files": files, "threads": [], "conversation": [],
            "review_actions": [{"id": "COMMENT", "label": "Leave review summary", "body_required": True}],
            "capabilities": local_capabilities(),
        },
    }


def local_capabilities():
    rules = {kind: {"enabled": True, "body_required": True, "reason": ""}
             for kind in ("comment", "file_comment", "reply", "conversation", "review", "edit")}
    rules['batch'] = {'enabled': True, 'body_required': False, 'mode': 'atomic',
                      'kinds': ['comment', 'file_comment', 'reply', 'conversation', 'review'], 'max_reviews': 1,
                      'default_label': 'Save feedback'}
    rules['suggestion'] = {'enabled': True, 'sides': ['head']}
    rules['readiness'] = {'enabled': False, 'reason': 'Local reviews do not provide CI checks or repository merge requirements.'}
    rules['apply_suggestion'] = {'enabled': True, 'body_required': False, 'destination': 'workspace'}
    rules['assignment'] = {'enabled': True, 'body_required': False, 'max_targets': 50}
    rules['assignments'] = {'enabled': True}
    rules['cancel_assignment'] = {'enabled': True, 'body_required': False}
    rules['participant_run'] = {'enabled': True, 'body_required': False, 'adapters': ['codex'], 'abandon': True}
    rules['comment']['anchors'] = {'scope': 'changed_file', 'sides': ['base', 'head']}
    rules['comparisons'] = {'enabled': True, 'refresh_on_open': True}
    rules['timeline'] = {'enabled': True}
    rules['message_history'] = {'enabled': True}
    rules['reanchor_draft'] = {'enabled': True, 'kinds': ['comment', 'file_comment']}
    rules['delete_message'] = {'enabled': True, 'body_required': False}
    rules['feedback_page'] = {'enabled': True}
    rules['feedback_lookup'] = {'enabled': True, 'requires_token': False}
    rules['feedback_refresh'] = {'enabled': True, 'scope': 'Up to 50 complete feedback units per read'}
    rules['comparison_range'] = {'enabled': True, 'sides': ['base', 'head'],
                                 'semantics': 'Exact retained trees against a shared captured baseline; no workspace reads.'}
    rules['capture'] = {'enabled': True, 'body_required': False}
    rules['thread_state'] = {'enabled': True, 'body_required': False}
    rules['reactions'] = {'enabled': True}
    rules['reaction'] = {'enabled': True, 'body_required': False}
    return rules


def validate_suggestion(draft):
    if not draft.get('suggestion'):
        return
    if draft['suggestion'] is not True or draft.get('kind') != 'comment' or draft.get('side') != 'head':
        raise ValueError('Suggestions require a head-side inline comment')
    lines = draft.get('body', '').split('\n')
    index = found = 0
    while index < len(lines):
        fence = re.match(r'^ {0,3}(`{3,}|~{3,})\s*(.*)$', lines[index])
        if not fence:
            index += 1
            continue
        suggestion = fence[2].strip() == 'suggestion'
        closing = re.compile(r'^ {0,3}' + re.escape(fence[1][0]) + '{' + str(len(fence[1])) + r',}\s*$')
        index += 1
        while index < len(lines) and not closing.match(lines[index]):
            index += 1
        if suggestion:
            if index == len(lines):
                raise ValueError('Close the suggestion fence before submitting')
            found += 1
        index += 1
    if found != 1:
        raise ValueError('Keep exactly one suggestion block for the selected range')


class LocalBackend:
    def __init__(self, directory):
        directory = Path(directory).expanduser()
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.db = sqlite3.connect(directory / "reviews.sqlite3", timeout=10)
        self.db.execute("PRAGMA foreign_keys=ON")
        version = self.db.execute("PRAGMA user_version").fetchone()[0]
        if version not in (0, 1):
            self.db.close()
            raise ValueError("Unsupported local review database version")
        self.db.executescript("""
            CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS reviews (id TEXT PRIMARY KEY, data TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS receipts (
                review TEXT NOT NULL REFERENCES reviews(id), operation TEXT NOT NULL,
                payload TEXT NOT NULL, receipt TEXT NOT NULL, PRIMARY KEY(review, operation));
            CREATE TABLE IF NOT EXISTS events (
                cursor INTEGER PRIMARY KEY AUTOINCREMENT, review TEXT NOT NULL REFERENCES reviews(id),
                id TEXT NOT NULL UNIQUE, kind TEXT NOT NULL, data TEXT NOT NULL);
            PRAGMA user_version=1;
        """)
        with self.db:
            self.db.execute("INSERT OR IGNORE INTO metadata VALUES ('connection', ?)", (identity(),))
        self.connection = self.db.execute("SELECT value FROM metadata WHERE key='connection'").fetchone()[0]

    def close(self):
        self.db.close()

    def load(self, review):
        row = self.db.execute("SELECT data FROM reviews WHERE id=?", (review,)).fetchone()
        if not row:
            raise ValueError("Local review not found")
        data = json.loads(row[0])
        # Additive upgrade of version-1 records; immutable source is retained once.
        if 'revisions' not in data:
            source = copy.deepcopy(data['snapshot'])
            source['threads'], source['conversation'] = [], []
            data['revisions'] = {source['snapshot']: {'snapshot': source, 'contents': copy.deepcopy(data['contents']), 'created': data['created'], 'sequence': 1}}
        data['snapshot']['capabilities'] = local_capabilities()
        for thread in data['snapshot']['threads']:
            thread.setdefault('resolved', False)
            thread.setdefault('resolved_by', '')
            thread['capabilities'] = {'reply': {'enabled': True},
                                      'resolve': {'enabled': not thread['resolved'], 'reason': 'Already resolved' if thread['resolved'] else ''},
                                      'reopen': {'enabled': thread['resolved'], 'reason': '' if thread['resolved'] else 'Already unresolved'}}
        messages = data['snapshot']['conversation'] + [c for t in data['snapshot']['threads'] for c in t['comments']]
        for message in messages:
            message.setdefault('version', hashlib.sha256(encode({k: message.get(k) for k in ('id', 'body', 'created', 'kind')}).encode()).hexdigest())
            owner = message.get('actor', 'local:' + message['author']) == 'local:' + data['snapshot']['author']
            message['is_author'] = owner
            message['capabilities'] = {'edit': {'enabled': owner,
                                               'reason': 'Only feedback authored by the local review owner is editable.'},
                                       'reactions': {'enabled': True}, 'reaction': {'enabled': True}, 'message_history': {'enabled': True}}
            message['capabilities']['delete_message'] = {
                'enabled': owner and message.get('kind', 'comment') in ('comment', 'reply', 'file_comment', 'conversation'),
                'scope': 'message', 'actor': 'local:' + data['snapshot']['author'],
                'reason': 'Only the local owner’s comments can be deleted; review decisions are separate.'}
            message['reactions'] = reaction_data(data['snapshot'], message)
        return data

    def view(self, data, reference=None):
        identity = data['snapshot']['snapshot'] if reference is None else reference.get('snapshot')
        revision = data['revisions'].get(identity)
        if revision is None:
            raise ValueError('Comparison does not belong to this local review')
        snapshot = copy.deepcopy(revision['snapshot'])
        if identity == data['snapshot']['snapshot']:
            snapshot['body'] = data['snapshot']['body']
        if reference is not None and any(reference.get(k, snapshot[k]) != snapshot[k] for k in ('base', 'head', 'base_tip')):
            raise ValueError('Comparison reference does not belong to this immutable source')
        if reference is not None and 'range' in reference and reference['range'] != snapshot.get('range'):
            raise ValueError('Saved range reference does not match its original endpoints')
        snapshot['capabilities'] = local_capabilities()
        snapshot['capabilities']['apply_suggestion']['workspace'] = data['workspace']
        snapshot['capture_context'] = {'workspace': data['workspace'], 'base': data['snapshot']['base'],
                                       'untracked': data.get('capture_options', {}).get('untracked', False),
                                       'options_known': 'capture_options' in data}
        if identity != data['snapshot']['snapshot']:
            for kind in ('comment', 'file_comment', 'review', 'batch', 'capture', 'apply_suggestion'):
                snapshot['capabilities'][kind] = {'enabled': False, 'reason': 'Open the latest local comparison before creating new feedback or capturing files.'}
        snapshot['conversation'] = copy.deepcopy(data['snapshot']['conversation'])
        snapshot['threads'] = []
        for original in data['snapshot']['threads']:
            thread = copy.deepcopy(original)
            thread['original_path'] = original['path']
            origin_id = thread.get('anchor', {}).get('snapshot', '')
            origin = data['revisions'].get(origin_id, {})
            origin_snapshot = origin.get('snapshot', {})
            thread['original_comparison'] = {k: origin_snapshot[k] for k in ('snapshot', 'base', 'head', 'base_tip') if k in origin_snapshot}
            origin_file = next((f for f in origin_snapshot.get('files', []) if f['path'] == original['path']), None)
            current_file = next((f for f in snapshot['files'] if f['path'] == original['path']), None)
            # A rename can be proven through the stable original base path.
            if current_file is None and origin_file is not None:
                candidates = [f for f in snapshot['files'] if f['old_path'] == origin_file['old_path']]
                current_file = candidates[0] if len(candidates) == 1 else None
            exact = origin_file is not None and current_file is not None and current_file['old_path'] == origin_file['old_path']
            if exact and thread.get('subject_type') != 'file':
                side = thread['side']
                before = origin['contents'][origin_file['id']][side]
                after = revision['contents'][current_file['id']][side]
                exact = before.get('kind') == after.get('kind') == 'text' and before.get('hash') == after.get('hash')
            thread['outdated'] = not exact
            if exact:
                thread['path'] = current_file['path']
            elif thread.get('subject_type') != 'file' and origin_file is not None:
                source = origin['contents'][origin_file['id']].get(thread['side'], {})
                thread['original_context'] = [str(n) + ' │ ' + text for n, text in enumerate(
                    source.get('lines', [])[thread['start'] - 1:thread['line']], thread['start'])]
            snapshot['threads'].append(thread)
        snapshot['inventory'] = {
            'files': {'state': 'complete', 'total': len(snapshot['files']), 'scope': 'Selected retained comparison'},
            'threads': {'state': 'complete', 'total': len(snapshot['threads']), 'scope': 'Shared local review conversation'},
            'conversation': {'state': 'complete', 'total': len(snapshot['conversation']), 'scope': 'Shared local review conversation'},
            'thread_state': {'state': 'complete', 'total': len(snapshot['threads']), 'scope': 'Local review threads'}}
        return snapshot

    def opened(self, data):
        return {"connection": self.connection, "review": data["id"], "snapshot": self.feedback_initial(data)}

    def feedback_initial(self, data, reference=None):
        snapshot = self.view(data, reference)
        if len(snapshot['threads']) + len(snapshot['conversation']) <= 50:
            return snapshot
        page = self.feedback_page(data, {'reference': {'snapshot': snapshot['snapshot']}, 'cursor': ''}, snapshot)
        snapshot.update(threads=page['threads'], conversation=page['conversation'], feedback={'cursor': page['next_cursor']})
        snapshot['inventory'].update(page['inventory'])
        return snapshot

    def feedback_page(self, data, request, snapshot=None):
        if snapshot is None:
            snapshot = self.view(data, request.get('reference', {}))
        version = hashlib.sha256(encode([snapshot['threads'], snapshot['conversation']]).encode()).hexdigest()
        units = [('threads', t) for t in snapshot['threads']] + [('conversation', m) for m in snapshot['conversation']]
        cursor = request.get('cursor', '')
        if not isinstance(cursor, str) or len(cursor) > 10000:
            raise ValueError('Invalid feedback cursor')
        start = 0
        if cursor:
            try:
                saved = json.loads(cursor)
                if saved['review'] != data['id'] or saved['snapshot'] != snapshot['snapshot'] or saved['version'] != version or type(saved['offset']) is not int or not 0 < saved['offset'] < len(units):
                    raise ValueError()
                start = saved['offset']
            except (ValueError, TypeError, KeyError):
                raise ValueError('Feedback changed or the cursor belongs to another comparison; refresh the review.')
        end = min(len(units), start + 50)
        page = {'snapshot': snapshot['snapshot'], 'cursor': cursor, 'threads': [], 'conversation': [],
                'complete': end == len(units), 'next_cursor': '', 'inventory': {}}
        for name, unit in units[start:end]:
            page[name].append(unit)
        if not page['complete']:
            page['next_cursor'] = encode({'review': data['id'], 'snapshot': snapshot['snapshot'], 'version': version, 'offset': end})
        thread_total = len(snapshot['threads'])
        for name in ('threads', 'conversation', 'thread_state'):
            total = len(snapshot['conversation']) if name == 'conversation' else thread_total
            loaded = max(0, end - thread_total) if name == 'conversation' else min(end, thread_total)
            page['inventory'][name] = {'state': 'complete' if loaded == total else 'partial', 'total': total,
                                       'scope': 'Shared local feedback; each loaded thread includes all replies'}
        return page

    def feedback_lookup(self, data, request):
        target, reference = request.get('target', {}), request.get('reference', {})
        if not isinstance(reference, dict) or any(not isinstance(reference.get(k), str) or not reference[k] for k in ('snapshot', 'base', 'head', 'base_tip')):
            raise ValueError('Discussion lookup needs an exact retained comparison reference')
        if not isinstance(target, dict) or target.get('kind') != 'thread' or any(not isinstance(target.get(k), str) or not target[k] for k in ('thread', 'message', 'message_kind')):
            raise ValueError('Select an identified discussion message')
        snapshot = self.view(data, reference)
        message_target(snapshot, target)
        thread = next(t for t in snapshot['threads'] if t['id'] == target['thread'])
        return {'key': snapshot['key'], 'reference': copy.deepcopy(reference), 'target': copy.deepcopy(target), 'thread': thread}

    def message_history(self, data, request):
        target = request.get('target', {})
        current = message_target(data['snapshot'], target)
        if current['version'] != target.get('expected_version') or current['body'] != target.get('body'):
            raise ValueError('Message changed; refresh before reading its edit history')
        entries = []
        for _, event_id, raw in self.db.execute('SELECT rowid, id, data FROM events WHERE review=? AND kind=? ORDER BY rowid', (data['id'], 'comment.edited')):
            event = json.loads(raw)
            receipt = event.get('receipt', {})
            if any(receipt.get(k, '') != target.get(k, '') for k in ('message', 'message_kind', 'thread')):
                continue
            before, after = event['before'], event['after']
            if any(m.get('id') != target['message'] or m.get('kind', 'comment') != target['message_kind'] for m in (before, after)):
                raise ValueError('Stored edit identity is inconsistent')
            body = '\n'.join(difflib.unified_diff(before['body'].splitlines(), after['body'].splitlines(), fromfile='Before', tofile='After', lineterm=''))
            if before['body'].endswith('\n') != after['body'].endswith('\n'):
                body += '\nFinal newline: ' + ('present → absent' if before['body'].endswith('\n') else 'absent → present')
            entries.append({'id': event_id, 'kind': 'Edit', 'title': 'Message edited', 'actor': after['author'],
                            'created': after.get('updated', ''), 'body': body, 'url': '', 'details': ['Exact local before/after text diff'],
                            'provenance': 'Local review store', 'content_state': 'available'})
        version = hashlib.sha256(encode([e['id'] for e in entries]).encode()).hexdigest()
        cursor, end = request.get('cursor', ''), len(entries)
        binding = {'review': data['id'], 'message': target['message'], 'kind': target['message_kind'],
                   'thread': target.get('thread', ''), 'version': current['version'], 'inventory': version}
        if cursor:
            try:
                saved = json.loads(cursor)
                if any(saved.get(k) != v for k, v in binding.items()) or type(saved.get('before')) is not int or not 0 < saved['before'] <= len(entries):
                    raise ValueError()
                end = saved['before']
            except (ValueError, TypeError, KeyError, AttributeError):
                raise ValueError('Edit history changed or its cursor is invalid; reload history')
        start = max(0, end - 50)
        return {'target': target, 'cursor': cursor, 'items': entries[start:end], 'complete': start == 0,
                'next_cursor': encode(dict(binding, before=start)) if start else '', 'total': len(entries),
                'scope': 'Edits retained by this local review store; creation and external edit history are not included.'}

    def timeline(self, data, cursor):
        events = []
        # Receipts bind legacy reviews to their submitted capture. Never infer
        # this from the current head or message time after a later capture.
        reviewed = {}
        legacy = any(m.get('kind') == 'review' and not m.get('reviewed_comparison') for m in data['snapshot']['conversation'])
        for payload, receipt in self.db.execute('SELECT payload, receipt FROM receipts WHERE review=?', (data['id'],)) if legacy else []:
            draft, result = json.loads(payload), json.loads(receipt)
            if draft.get('kind') != 'review' or not result.get('id'):
                continue
            source = data['revisions'].get(draft.get('snapshot'), {}).get('snapshot', {})
            if source and all(draft.get(k) == source.get(k) for k in ('snapshot', 'head', 'base_tip')):
                reference = {k: source[k] for k in ('snapshot', 'base', 'head', 'base_tip') if k in source}
                reviewed.setdefault(result['id'], []).append(reference)
        for revision in data['revisions'].values():
            source = revision['snapshot']
            if 'range' in source:
                continue
            events.append({'id': 'capture:' + source['snapshot'], 'kind': 'Capture', 'title': 'Captured source',
                           'actor': source['author'], 'created': revision['created'], 'body': '', 'url': '',
                           'provenance': 'Local review store',
                           'details': [], 'reviewed_comparison': {k: source[k] for k in ('snapshot', 'base', 'head', 'base_tip') if k in source},
                           'comparison_provenance': 'Retained local capture'})
        groups = [('', data['snapshot']['conversation'])] + [(t['id'], t['comments']) for t in data['snapshot']['threads']]
        for thread, messages in groups:
            for index, message in enumerate(messages):
                title = ('Inline comment' if index == 0 else 'Replied') if thread else ('Reviewed' if message.get('kind') == 'review' else 'Commented')
                target = {'kind': 'thread' if thread else 'conversation', 'message': message['id'], 'message_kind': message.get('kind', 'comment')}
                if thread:
                    target['thread'] = thread
                events.append({'id': encode([thread, message.get('kind', 'comment'), message['id']]), 'kind': title,
                               'title': title, 'actor': message['author'], 'created': message['created'], 'body': message['body'],
                               'url': message.get('url', ''), 'provenance': 'Local review store', 'details': [], 'target': target})
                if message.get('kind') == 'review':
                    candidates = reviewed.get(message['id'], [])
                    saved = message.get('reviewed_comparison')
                    if isinstance(saved, dict) and saved:
                        source = data['revisions'].get(saved.get('snapshot'), {}).get('snapshot', {})
                        if source and all(saved.get(k) == source.get(k) for k in ('snapshot', 'base', 'head', 'base_tip')):
                            candidates = candidates + [saved]
                        else:
                            candidates = []
                    elif saved:
                        candidates = []
                    if candidates and all(candidate == candidates[0] for candidate in candidates):
                        events[-1].update(reviewed_comparison=candidates[0], reviewed_head=candidates[0]['head'],
                                          comparison_provenance='Verified local review capture' if saved else 'Verified from the saved review receipt')
                    else:
                        events[-1]['details'].append('The original review comparison is unavailable; current source is not a substitute.')
        events.sort(key=lambda e: (e['created'], e['id']))
        version = hashlib.sha256(encode([e['id'] for e in events]).encode()).hexdigest()
        end = len(events)
        if cursor:
            try:
                saved = json.loads(cursor)
                if saved['review'] != data['id'] or saved['version'] != version or type(saved['before']) is not int or not 0 < saved['before'] <= len(events):
                    raise ValueError()
                end = saved['before']
            except (ValueError, TypeError, KeyError):
                raise ValueError('Local history changed or its cursor is invalid; reload recent history.')
        start = max(0, end - 50)
        return {'cursor': cursor, 'items': events[start:end], 'complete': start == 0, 'total': len(events),
                'next_cursor': encode({'review': data['id'], 'version': version, 'before': start}) if start else '',
                'scope': 'Retained captures and current authored messages; edit/lifecycle events are not recorded. Reload for newer activity.'}

    def request(self, request):
        op = request["op"]
        if op in ('prepare_run', 'dispatch_run', 'abandon_run', 'run', 'runs'):
            from revue_runtime import LocalRuns
            return LocalRuns(self).owner(request)
        if op in ('assign', 'assignments', 'assignment', 'cancel_assignment'):
            from revue_participants import LocalParticipants
            result = LocalParticipants(self).owner(request)
            if op == 'assignments' and self.db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='participant_runs'").fetchone():
                from revue_runtime import LocalRuns
                runs = LocalRuns(self).owner({'op':'runs', 'review':request['review']})['items']
                for assignment in result['items']:
                    assignment['runs'] = [run for run in runs if run['assignment'] == assignment['id']]
            return result
        if op == "create":
            data = capture(request)
            with self.db:
                self.db.execute("INSERT INTO reviews VALUES (?, ?)", (data["id"], encode(data)))
            return self.opened(self.load(data['id']))
        if op == "list":
            reviews = [json.loads(row[0]) for row in self.db.execute("SELECT data FROM reviews")]
            return sorted([{"id": r["id"], "title": r["snapshot"]["title"], "created": r["created"],
                            "workspace": r["workspace"]} for r in reviews], key=lambda r: r["created"], reverse=True)
        if op == "mutate":
            return self.mutate(request)
        if op == 'comparison_range':
            # Cache an immutable derived source atomically with concurrent comments.
            # This never advances the review's current capture.
            with self.db:
                self.db.execute('BEGIN IMMEDIATE')
                data = self.load(request['review'])
                revision = range_revision(data, request.get('selection', {}))
                snapshot_id = revision['snapshot']['snapshot']
                data['revisions'].setdefault(snapshot_id, revision)
                self.db.execute('UPDATE reviews SET data=? WHERE id=?', (encode(data), data['id']))
                return self.view(data, {'snapshot': snapshot_id})
        data = self.load(request["review"])
        if op == 'message_history':
            return self.message_history(data, request)
        if op == 'feedback_page':
            return self.feedback_page(data, request)
        if op == 'feedback_lookup':
            return self.feedback_lookup(data, request)
        if op == 'timeline':
            cursor = request.get('cursor', '')
            if not isinstance(cursor, str):
                raise ValueError('Invalid timeline cursor')
            return self.timeline(data, cursor)
        if op == "open":
            return self.opened(data)
        if op == "refresh":
            return self.feedback_initial(data) if request.get("incremental") is True else self.view(data)
        if op == 'reactions':
            return reaction_data(data['snapshot'], message_target(data['snapshot'], request['target']), details=True)
        if op == "comparisons":
            items = []
            for revision in sorted(data['revisions'].values(), key=lambda r: (r.get('sequence', 0), r['created'], r['snapshot']['snapshot'])):
                reference = {key: revision['snapshot'][key] for key in ('snapshot', 'base', 'head', 'base_tip', 'range') if key in revision['snapshot']}
                reference['label'] = ('Saved range' if 'range' in reference else 'Local capture ' + str(revision.get('sequence', '?'))) + ' · ' + revision['created']
                items.append(reference)
            return {'items': items, 'latest': self.view(data), 'complete': True, 'scope': 'Retained local captures; discussion is shared across revisions.'}
        if op == "comparison":
            return self.feedback_initial(data, request.get('reference', {}))
        if op == 'suggestion_plan':
            from revue_apply import LocalApplications
            return LocalApplications(self).plan(request)
        if op == "file":
            revision = data['revisions'].get(request['snapshot']['snapshot'])
            if revision is None or any(request['snapshot'].get(k, revision['snapshot'][k]) != revision['snapshot'][k] for k in ('base', 'head', 'base_tip')):
                raise ValueError("Snapshot does not belong to this review")
            file_id = request["file"]["id"]
            file = next((f for f in revision['snapshot']['files'] if f['id'] == file_id), None)
            if file is None or any(request['file'].get(k) != file[k] for k in ('path', 'old_path')):
                raise ValueError("File does not belong to this review")
            return revision["contents"][file_id]
        raise ValueError("Unsupported local backend operation: " + str(op))

    def mutate(self, request):
        if request['draft'].get('kind') == 'apply_suggestion':
            from revue_apply import LocalApplications
            return LocalApplications(self).submit(request)
        if request['draft'].get('kind') == 'participant_run':
            from revue_runtime import LocalRuns
            return LocalRuns(self).submit(request)
        if request['draft'].get('kind') == 'cancel_assignment':
            from revue_participants import LocalParticipants
            draft = request['draft']
            if not isinstance(draft.get('id'), str) or not draft['id'].strip():
                raise ValueError('A stable cancellation operation ID is required')
            return LocalParticipants(self).owner({'op': 'cancel_assignment', 'review': request['review'],
                'id': draft.get('id'), 'assignment': draft.get('assignment'),
                'expected_version': draft.get('expected_version'), 'reconcile': request.get('reconcile', False)})
        if request['draft'].get('kind') == 'assignment':
            from revue_participants import LocalParticipants
            draft = request['draft']
            assignment = LocalParticipants(self).owner({
                'op': 'assign', 'review': request['review'], 'id': draft.get('id'),
                'participant': draft.get('participant'), 'reference': draft.get('reference'),
                'targets': draft.get('targets'), 'require_current': True,
                'reconcile': request.get('reconcile', False)})
            return {'id': draft['id'], 'assignment': assignment['id'],
                    'participant': assignment['participant'], 'reference': assignment['reference'],
                    'targets': [{k: t[k] for k in ('thread', 'message', 'message_kind', 'expected_version')}
                                for t in assignment['targets']],
                    'recovered': assignment.get('recovered', False), 'url': ''}
        if request['draft'].get('kind') == 'batch':
            return self.batch(request)
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            return self._mutate(request)

    def _mutate(self, request):
        draft = dict(request["draft"])
        operation = draft.get("id")
        if not isinstance(operation, str) or not operation:
            raise ValueError("A stable operation ID is required")
        # Outbox state changes during recovery, but message identity does not.
        draft.pop("state", None)
        payload = encode(draft)
        row = self.db.execute("SELECT payload, receipt FROM receipts WHERE review=? AND operation=?",
                              (request["review"], operation)).fetchone()
        if row:
            if row[0] != payload:
                raise ValueError("Operation ID was already used for different feedback")
            return dict(json.loads(row[1]), recovered=True)
        if request.get("reconcile"):
            raise ValueError("No saved receipt found; reconciliation did not create a comment")
        data = self.load(request["review"])
        snapshot = data["snapshot"]
        reference = data['revisions'].get(draft.get('snapshot'), {}).get('snapshot', {})
        if not reference or any(draft.get(key) != reference.get(key) for key in ('head', 'snapshot', 'base_tip')):
            raise ValueError("Feedback belongs to a different snapshot")
        if draft.get('kind') in ('comment', 'file_comment', 'review', 'capture') and draft['snapshot'] != snapshot['snapshot']:
            raise ValueError('A newer local comparison is available; the original feedback target is retained')
        if draft.get('kind') == 'delete_message':
            message = message_target(snapshot, draft)
            rule = message['capabilities']['delete_message']
            if (not rule['enabled'] or draft.get('actor') != rule['actor'] or draft.get('delete_scope') != 'message'
                    or draft.get('body') != '' or draft.get('pending_review')):
                raise ValueError('Published deletion scope or ownership is unavailable')
            if draft.get('expected_version') != message['version'] or draft.get('original_body') != message['body']:
                raise ValueError('Message changed; inspect its current contents before deleting')
            thread = next((t for t in snapshot['threads'] if t['id'] == draft.get('thread')), None)
            messages = thread['comments'] if thread else snapshot['conversation']
            before = copy.deepcopy(message)
            messages.remove(message)
            if thread and not messages:
                snapshot['threads'].remove(thread)
            receipt = {key: draft[key] for key in ('id', 'message', 'message_kind', 'thread', 'actor', 'delete_scope', 'expected_version')}
            receipt.update(deleted=True, url='')
            self.db.execute('UPDATE reviews SET data=? WHERE id=?', (encode(data), data['id']))
            self.db.execute('INSERT INTO receipts VALUES (?, ?, ?, ?)', (data['id'], operation, payload, encode(receipt)))
            self.db.execute('INSERT INTO events(review, id, kind, data) VALUES (?, ?, ?, ?)',
                            (data['id'], identity(), 'comment.deleted', encode({'before': before, 'receipt': receipt})))
            return receipt
        if draft.get('kind') == 'capture':
            if type(draft.get('untracked')) is not bool or draft.get('body') != '':
                raise ValueError('A capture requires an explicit untracked-file choice and no comment body')
            captured = capture({'cwd': data['workspace'], 'vcs': data.get('vcs', 'git'), 'base': snapshot['base'], 'untracked': draft['untracked']}, allow_empty=True)
            next_id = captured['snapshot']['snapshot']
            changed = next_id != snapshot['snapshot']
            source = captured['snapshot']
            # Keep the review identity and conversation independent of source versions.
            for key in ('key', 'display_id', 'title', 'submit_target'):
                source[key] = snapshot[key]
            data['revisions'].setdefault(next_id, {'snapshot': copy.deepcopy(source), 'contents': captured['contents'], 'created': captured['created'],
                                                  'sequence': max(r.get('sequence', 0) for r in data['revisions'].values()) + 1})
            source['threads'], source['conversation'] = snapshot['threads'], snapshot['conversation']
            data['snapshot'], data['contents'] = source, captured['contents']
            data['capture_options'] = captured['capture_options']
            receipt = {'id': operation, 'snapshot': next_id, 'previous_snapshot': draft['snapshot'], 'changed': changed, 'url': ''}
            self.db.execute('UPDATE reviews SET data=? WHERE id=?', (encode(data), data['id']))
            self.db.execute('INSERT INTO receipts VALUES (?, ?, ?, ?)', (data['id'], operation, payload, encode(receipt)))
            self.db.execute('INSERT INTO events(review, id, kind, data) VALUES (?, ?, ?, ?)',
                            (data['id'], identity(), 'revision.captured', encode(receipt)))
            return receipt
        if draft.get('kind') == 'thread_state':
            desired, expected = draft.get('resolved'), draft.get('expected_resolved')
            if type(desired) is not bool or type(expected) is not bool:
                raise ValueError('Thread state must be a boolean')
            thread = next((t for t in snapshot['threads'] if t['id'] == draft.get('thread')), None)
            if thread is None:
                raise ValueError('Thread does not belong to this review')
            observed = thread['resolved'] == desired
            if not observed and thread['resolved'] != expected:
                raise ValueError('Thread state changed; refresh before acting')
            if not observed:
                thread['resolved'] = desired
                thread['resolved_by'] = snapshot['author'] if desired else ''
            receipt = {'id': operation, 'thread': thread['id'], 'resolved': desired, 'observed': observed, 'url': ''}
            self.db.execute('UPDATE reviews SET data=? WHERE id=?', (encode(data), data['id']))
            self.db.execute('INSERT INTO receipts VALUES (?, ?, ?, ?)', (data['id'], operation, payload, encode(receipt)))
            self.db.execute('INSERT INTO events(review, id, kind, data) VALUES (?, ?, ?, ?)',
                            (data['id'], identity(), 'thread.state', encode(receipt)))
            return receipt
        if draft.get('kind') == 'reaction':
            message = message_target(snapshot, draft)
            if draft.get('actor') != 'local:' + snapshot['author']:
                raise ValueError('Reaction actor changed; reload the reaction chooser')
            if draft.get('body') != '' or type(draft.get('present')) is not bool or draft.get('reaction') not in REACTIONS:
                raise ValueError('Invalid reaction state')
            members = message.setdefault('reaction_members', [])
            own = [m for m in members if m['content'] == draft['reaction'] and m['actor'] == draft['actor']]
            if draft['present'] and not own:
                members.append({'id': identity(), 'content': draft['reaction'], 'actor': draft['actor']})
            elif not draft['present']:
                message['reaction_members'] = [m for m in members if m not in own]
            receipt = {key: draft[key] for key in ('id', 'message', 'message_kind', 'thread', 'actor', 'reaction', 'present')}
            receipt['url'] = ''
            self.db.execute('UPDATE reviews SET data=? WHERE id=?', (encode(data), data['id']))
            self.db.execute('INSERT INTO receipts VALUES (?, ?, ?, ?)', (data['id'], operation, payload, encode(receipt)))
            self.db.execute('INSERT INTO events(review, id, kind, data) VALUES (?, ?, ?, ?)',
                            (data['id'], identity(), 'reaction.changed', encode(receipt)))
            return receipt
        if draft.get('kind') == 'edit':
            messages = snapshot['conversation']
            if draft.get('thread'):
                thread = next((t for t in snapshot['threads'] if t['id'] == draft['thread']), None)
                if thread is None:
                    raise ValueError('Thread does not belong to this review')
                messages = thread['comments']
            matches = [m for m in messages if m['id'] == draft.get('message') and m.get('kind', 'comment') == draft.get('message_kind')]
            if len(matches) != 1:
                raise ValueError('Message does not belong to this discussion')
            message = matches[0]
            if not message['capabilities']['edit']['enabled']:
                raise ValueError('Editing this message is not permitted')
            if draft.get('expected_version') != message['version'] or draft.get('original_body') != message['body']:
                raise ValueError('Message changed; inspect original, current and proposed text before accepting a new edit base')
            if not isinstance(draft.get('body'), str) or not draft['body'].strip():
                raise ValueError('Write a message first')
            before = copy.deepcopy(message)
            message.update(body=draft['body'], version=identity(), updated=now(), edited=True)
            receipt = {'id': operation, 'message': message['id'], 'message_kind': message.get('kind', 'comment'), 'thread': draft.get('thread', ''), 'url': ''}
            self.db.execute('UPDATE reviews SET data=? WHERE id=?', (encode(data), data['id']))
            self.db.execute('INSERT INTO receipts VALUES (?, ?, ?, ?)', (data['id'], operation, payload, encode(receipt)))
            self.db.execute('INSERT INTO events(review, id, kind, data) VALUES (?, ?, ?, ?)',
                            (data['id'], identity(), 'comment.edited', encode({'before': before, 'after': message, 'receipt': receipt})))
            return receipt
        validate_suggestion(draft)
        body = draft.get("body")
        if not isinstance(body, str) or not body.strip():
            raise ValueError("Write a message first")
        kind = draft.get("kind")
        comment = {"id": identity(), "author": snapshot["author"], "created": now(), "body": body, "kind": kind, "publication": "local"}
        if kind == "file_comment":
            file = next((f for f in snapshot['files'] if f['path'] == draft.get('path')), None)
            if file is None or draft.get('old_path') != file['old_path'] or any(k in draft for k in ('side', 'start', 'end', 'line')):
                raise ValueError('Invalid file anchor; a file comment has a path and no line coordinates')
            snapshot['threads'].append({'id': comment['id'], 'path': file['path'], 'subject_type': 'file',
                'side': '', 'start': 0, 'line': 0, 'outdated': False, 'comments': [comment],
                'anchor': {'snapshot': snapshot['snapshot'], 'path': file['path'], 'old_path': file['old_path']}})
        elif kind == "comment":
            file = next((f for f in snapshot["files"] if f["path"] == draft.get("path")), None)
            side = draft.get("side")
            if file is None or side not in ("base", "head") or draft.get("old_path") != file["old_path"]:
                raise ValueError("Invalid code anchor")
            source = data["contents"][file["id"]][side]
            start, end = draft.get("start"), draft.get("end")
            if (type(start) is not int or type(end) is not int or source["kind"] != "text"
                    or not 1 <= start <= end <= len(source["lines"])):
                raise ValueError("Comment range is outside the captured source")
            snapshot["threads"].append({"id": comment["id"], "path": file["path"], "side": side,
                "start": start, "line": end, "outdated": False, "comments": [comment],
                "anchor": {"snapshot": snapshot["snapshot"], "hash": source["hash"],
                           "selected": source["lines"][start - 1:end]}})
        elif kind == "reply":
            thread = next((t for t in snapshot["threads"] if t["id"] == draft.get("thread")), None)
            if thread is None:
                raise ValueError("Thread does not belong to this review")
            thread["comments"].append(comment)
        elif kind in ("conversation", "review"):
            if kind == "review" and draft.get("event") != "COMMENT":
                raise ValueError("Unsupported local review action")
            if kind == 'review':
                comment['reviewed_comparison'] = {k: reference[k] for k in ('snapshot', 'base', 'head', 'base_tip') if k in reference}
            snapshot["conversation"].append(comment)
        else:
            raise ValueError("Unsupported local feedback kind")
        receipt = {"id": comment["id"], "url": ""}
        self.db.execute("UPDATE reviews SET data=? WHERE id=?", (encode(data), data["id"]))
        self.db.execute("INSERT INTO receipts VALUES (?, ?, ?, ?)", (data["id"], operation, payload, encode(receipt)))
        self.db.execute("INSERT INTO events(review, id, kind, data) VALUES (?, ?, ?, ?)",
                        (data["id"], identity(), "comment.created", encode(receipt)))
        return receipt

    def batch(self, request):
        batch = dict(request['draft'])
        batch.pop('state', None)
        batch.pop('error', None)
        items = [dict(item) for item in batch.get('items', [])]
        for item in items:
            item.pop('state', None)
        batch['items'] = items
        operation = batch.get('id')
        ids = [item.get('id') for item in items]
        if not isinstance(operation, str) or not operation or not items or any(not isinstance(i, str) or not i for i in ids) or len(set(ids)) != len(ids) or operation in ids:
            raise ValueError('A batch needs distinct stable item and operation IDs')
        if any(item.get('kind') not in local_capabilities()['batch']['kinds'] for item in items):
            raise ValueError('Unsupported item in local batch')
        if sum(item['kind'] == 'review' for item in items) > 1:
            raise ValueError('Select at most one review decision')
        if any(any(item.get(key) != batch.get(key) for key in ('head', 'base_tip', 'snapshot')) for item in items):
            raise ValueError('Batch items must use the same comparison')
        payload = encode(batch)
        with self.db:
            self.db.execute('BEGIN IMMEDIATE')
            row = self.db.execute('SELECT payload, receipt FROM receipts WHERE review=? AND operation=?',
                                  (request['review'], operation)).fetchone()
            if row:
                if row[0] != payload:
                    raise ValueError('Batch ID was already used for different feedback')
                return dict(json.loads(row[1]), recovered=True)
            if request.get('reconcile'):
                raise ValueError('No batch receipt found; reconciliation did not create feedback')
            receipts = []
            for item in items:
                receipt = self._mutate(dict(request, draft=item, reconcile=False))
                receipts.append(dict(receipt, draft=item['id']))
            result = {'id': operation, 'url': '', 'items': receipts}
            self.db.execute('INSERT INTO receipts VALUES (?, ?, ?, ?)',
                            (request['review'], operation, payload, encode(result)))
            return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--store", required=True)
    args = parser.parse_args()
    # Database, rollback journal and any newly created files are user-only.
    os.umask(0o077)
    backend = None
    try:
        request = json.load(sys.stdin)
        backend = LocalBackend(args.store)
        result = {"ok": True, "data": backend.request(request)}
    except Exception as error:
        result = {"ok": False, "error": str(error), "unknown": bool(getattr(error, 'unknown', False))}
    finally:
        if backend is not None:
            backend.close()
    print(encode(result))


if __name__ == "__main__":
    main()
