#!/usr/bin/env python3
"""Prepare or launch an isolated, local-only Revue discoverability trial."""
import argparse
import copy
import datetime
import json
from pathlib import Path
import subprocess
import uuid

ROOT = Path(__file__).resolve().parents[1]


def prepare(parent, remapped=False):
    directory = parent / (datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ') + '-' + uuid.uuid4().hex[:8])
    directory.mkdir(parents=True, exist_ok=False)
    fixture = json.loads((ROOT / 'test/fixtures/comment-ui.json').read_text())
    snapshot = fixture['snapshot']
    snapshot.update(key='ux-trial/' + directory.name, display_id='LOCAL UX TRIAL',
                    title='Short-query completion review', body='Local-only discoverability trial. No service connection.')
    snapshot['capabilities'] = {'reply': {'enabled': True}, 'comment': {'enabled': True},
                                'thread_state': {'enabled': True, 'body_required': False}}
    target = snapshot['threads'][0]
    target['resolved'] = False
    target['capabilities'] = {'resolve': {'enabled': True}, 'reopen': {'enabled': True}}
    target['comments'][1]['body'] = '> Morgan wrote:\n>\n> > Could we keep prefix matching for very short queries?\n\nYes. I will preserve the original list.'
    other = copy.deepcopy(target)
    other['id'], other['resolved'] = 'other-thread', True
    for message in other['comments']:
        message['id'] = 'other-' + message['id']
    other['comments'][0]['author'] = 'riley'
    other['comments'][0]['body'] = 'Keep the original list order when completion is disabled.'
    other['comments'] = other['comments'][:1]
    snapshot['threads'].append(other)
    (directory / 'fixture.json').write_text(json.dumps(fixture, indent=2) + '\n')
    (directory / 'observer.json').write_text(json.dumps({
        'status': 'not-observed', 'configuration': 'remapped' if remapped else 'default',
        'coaching_given': None, 'completed': None, 'wrong_turns': [],
        'quote_target_correct': None, 'return_position_preserved': None,
        'delivery_expectation': None, 'notes': ''}, indent=2) + '\n')
    settings = {'root': str(ROOT), 'directory': str(directory), 'remapped': remapped}
    (directory / 'settings.json').write_text(json.dumps(settings) + '\n')
    script = "let g:revue_trial_settings = " + json.dumps(str(directory / 'settings.json')) + '\n'
    script += "execute 'source ' . fnameescape(" + json.dumps(str(ROOT / 'tools/ux_trial.vim')) + ')\n'
    (directory / 'launch.vim').write_text(script)
    (directory / 'task.md').write_text('''# Local review trial

Starting in code, find Morgan's discussion about short queries. Quote only the
words “Please cover an empty query too” from Sam's reply into a reply draft.
Inspect the draft preview, then return to the same place in code. Keep the draft
unsent. Use the interface's own hints and help if needed; an observer should not
supply a sequence of keys. Stop whenever you want.

Afterward, explain who would see the saved draft and what you expected sending
it to do. Record wrong turns and any coaching in observer.json. A trace is not
a substitute for that human observation.

This lab uses only local fixture data. It records view transitions and resulting
local draft state on exit, not a keystroke log. All data stays in this directory.
It does not connect to GitHub or other services. Attempted sends are rejected;
resolution/reopening changes only the in-memory fixture. Close Vim normally to
write the trace. Use a fresh trial for a different configuration or participant.
''')
    return directory


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true', help='prepare files without opening Vim')
    parser.add_argument('--remapped', action='store_true', help='use alternate maps, surfaced by the normal UI hints')
    parser.add_argument('--output', type=Path, default=ROOT / 'output/ux-trials', help='parent for a fresh trial directory')
    args = parser.parse_args()
    directory = prepare(args.output.expanduser().resolve(), args.remapped)
    print(directory)
    if args.prepare:
        print('Prepared only; no user observation or Vim launch occurred.')
        return
    print((directory / 'task.md').read_text())
    input('Press Enter to open the local trial, or Ctrl-C to stop. ')
    subprocess.run(['vim', '-Nu', 'NONE', '-i', 'NONE', '-n', '-S', str(directory / 'launch.vim')], check=True)
    print('Trial saved in', directory)


if __name__ == '__main__':
    main()
