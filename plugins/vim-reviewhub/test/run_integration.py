#!/usr/bin/env python3
"""Drive a real Vim PTY, answering only the fixture's explicit Send dialogs."""
import errno
import json
import os
from pathlib import Path
import pty
import select
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
store = Path(tempfile.mkdtemp(prefix="reviewhub-test-"))
env = dict(os.environ, REVIEWHUB_ROOT=str(ROOT), REVUE_ROOT=str(ROOT.parent / "vim-revue"),
           REVUE_TEST_STORE=str(store), TERM="xterm")
master, slave = pty.openpty()
proc = subprocess.Popen(["vim", "-N", "-u", os.environ.get("REVUE_TEST_VIMRC", "NONE"), "-n", "-S", str(ROOT / "test/integration.vim")],
                        stdin=slave, stdout=slave, stderr=slave, env=env)
os.close(slave)
pending = b""
transcript = b""
deadline = time.monotonic() + 60
while proc.poll() is None and time.monotonic() < deadline:
    if select.select([master], [], [], 0.1)[0]:
        try:
            chunk = os.read(master, 65536)
        except OSError as exc:
            if exc.errno == errno.EIO:
                break
            raise
        transcript += chunk
        pending += chunk
        if b"(S)end, [K]eep draft:" in pending:
            os.write(master, b"s\r")
            pending = b""
if proc.poll() is None:
    proc.terminate()
proc.wait(timeout=5)
os.close(master)
(store / "terminal").write_bytes(transcript)
errors = (store / "errors").read_text() if (store / "errors").exists() else "Vim did not finish"
print("Integration artifacts:", store)
if errors:
    print(errors)
    if (store / "messages").exists():
        print((store / "messages").read_text())
    raise SystemExit(1)
requests = [json.loads(line) for line in (store / "requests.jsonl").read_text().splitlines()]
mutations = [r for r in requests if r["op"] == "mutate"]
assert len(mutations) == 6, mutations
assert any(m["reconcile"] for m in mutations), mutations
assert mutations[-1]['draft']['event'] == 'acknowledge'
print("PASS: tree → threads → reply → multiline comment → failure/retry → base comment → reconciliation → draft recovery")

# Simulate a Vim crash during a submission, then start a fresh interpreter.
draft_path = next((store / 'drafts').glob('*.json'))
saved = json.loads(draft_path.read_text())
saved['drafts'][0]['state'] = 'submitting'
draft_path.write_text(json.dumps(saved))
restart = subprocess.run(['vim', '-Nu', 'NONE', '-n', '-es', '-S', str(ROOT / 'test/restart.vim')],
                         env=env, capture_output=True, timeout=20)
errors = (store / 'restart-errors').read_text() if (store / 'restart-errors').exists() else 'Restart did not finish'
if errors:
    print(errors)
    raise SystemExit(1)
assert json.loads(draft_path.read_text())['drafts'] == []
print('PASS: separate Vim process recovers an interrupted submission and reconciles without reposting')
