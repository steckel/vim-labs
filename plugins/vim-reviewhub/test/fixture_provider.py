#!/usr/bin/env python3
"""Deterministic provider process; writes only to the test's temporary store."""
import copy
import json
import os
import pathlib
import sys

SNAPSHOT = {
    "version": 1, "key": "fixture.test/team/project/42", "number": 42, "display_id": "CL 42",
    "review_actions": [{"id": "acknowledge", "label": "Acknowledge"}],
    "title": "Improve example", "body": "A multiline description.\nSecond line.", "author": "alice",
    "url": "https://fixture.test/team/project/pull/42", "state": "open", "reviewers": ["bob"],
    "head": "b" * 40, "base": "a" * 40, "base_tip": "c" * 40, "snapshot": "a:b", "authenticated": True,
    "files": [
        {"id": "one", "path": "src/example.py", "old_path": "src/old.py", "status": "renamed", "patch": "@@ -1,4 +1,4 @@\n one\n-old\n+new\n three\n four", "additions": 1, "deletions": 1},
        {"id": "two", "path": "removed.txt", "old_path": "removed.txt", "status": "removed", "patch": "@@ -1 +0,0 @@\n-deleted", "additions": 0, "deletions": 1},
        {"id": "three", "path": "x|call extend(g:, {'injected': 1})", "old_path": "x", "status": "added", "patch": "@@ -0,0 +1 @@\n+safe", "additions": 1, "deletions": 0}
    ],
    "threads": [{"id": "101", "path": "src/example.py", "side": "head", "line": 2, "start": 2, "outdated": False,
                 "comments": [{"id": "101", "author": "bob", "body": "Please explain this change.\nMore detail?", "created": "2026-01-01", "kind": "comment"}]},
                {"id": "102", "path": "src/example.py", "side": "base", "line": 2, "start": 2, "outdated": False,
                 "comments": [{"id": "102", "author": "carol", "body": "Old implementation", "created": "2026-01-01", "kind": "comment"}]}],
    "conversation": [{"id": "201", "author": "bob", "body": "Conversation message", "created": "2026-01-01", "kind": "comment"}]
}


def dispatch(req, directory):
    snapshot = copy.deepcopy(SNAPSHOT)
    snapshot['capabilities'] = {kind: {'enabled': True} for kind in ('comment', 'reply', 'conversation', 'review', 'comparisons')}
    if (directory / 'revision-b').exists():
        snapshot['head'] = 'd' * 40
        snapshot['snapshot'] = 'a:d'
    log = directory / "requests.jsonl"
    with log.open("a") as stream:
        stream.write(json.dumps(req) + "\n")
    if (directory / "fail").exists():
        mode = (directory / "fail").read_text().strip()
        (directory / "fail").unlink()
        return {"ok": False, "error": "simulated failure", "unknown": mode == "unknown"}
    if req["op"] == "list":
        return {"ok": True, "data": {"connection": {"host": "fixture.test", "repo": "team/project"}, "page": 1,
                "authenticated": True, "more": False, "items": [{"id": 42, "title": "Improve example", "author": "alice", "draft": False, "state": "open"}]}}
    if req["op"] == "open":
        if (directory / 'revision-b').exists():
            snapshot['head'] = 'd' * 40
            snapshot['snapshot'] = 'a:d'
        return {"ok": True, "data": snapshot}
    if req['op'] == 'comparisons':
        refs = [{'snapshot': 'a:' + head, 'base': 'a' * 40, 'head': head * 40, 'base_tip': 'c' * 40,
                 'label': 'Fixture comparison ' + head} for head in ('b', 'd')]
        return {'ok': True, 'data': {'items': refs, 'latest': snapshot, 'complete': True, 'scope': 'Fixture history'}}
    if req['op'] == 'comparison':
        identity = req['reference']['snapshot']
        if identity not in ('a:b', 'a:d'):
            return {'ok': False, 'error': 'Unknown fixture comparison'}
        snapshot['snapshot'] = identity
        snapshot['head'] = identity[-1] * 40
        return {'ok': True, 'data': snapshot}
    if req["op"] == "file":
        file = req["file"]["id"]
        data = {"base": {"kind": "text", "lines": ["one", "old", "three", "four"]},
                "head": {"kind": "text", "lines": ["one", "new", "three", "four"]}}
        if req['snapshot']['snapshot'] == 'a:d':
            data['head']['lines'][1] = 'new revision'
        if file == "two":
            data = {"base": {"kind": "text", "lines": ["deleted"]}, "head": {"kind": "absent", "lines": []}}
        if file == "three":
            data = {"base": {"kind": "absent", "lines": []}, "head": {"kind": "text", "lines": ["safe"]}}
        return {"ok": True, "data": data}
    if req["op"] == "mutate":
        return {"ok": True, "data": {"id": "999", "url": "https://fixture.test/receipt", "recovered": bool(req.get("reconcile"))}}
    raise ValueError(req)


if __name__ == "__main__":
    print(json.dumps(dispatch(json.load(sys.stdin), pathlib.Path(os.environ["REVUE_TEST_STORE"]))))
