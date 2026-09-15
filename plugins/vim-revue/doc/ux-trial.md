# Exact-reply discovery trial

This is the next human-observation step for UX-06/18. The fixture is prepared
and its mechanics are tested; no unfamiliar-user result is claimed.

Run from the Revue workspace:

```sh
python3 tools/ux_trial.py
```

To prepare files without opening Vim, add `--prepare`. To use an alternate set
of configured keys in a fresh trial, add `--remapped`. The existing interface
shows the configured keys; the task sheet does not tell the participant which
commands to use. Terminal dimensions are recorded, not forcibly changed.
Use an actual 80×24 terminal for the narrow observation and 120×40 for comparison.
Do not resize the user's existing Vim session to run this trial.

Each run creates a fresh directory under `output/ux-trials`, including a task
sheet, fixture, isolated draft directory, launcher, observation form and trace.
It launches a separate Vim with no user vimrc/viminfo. The source file is fixture
text in snapshot buffers. There is no GitHub/provider connection, model process
or network request. Sending prose is rejected and the local draft is retained.
Resolve/reopen changes only the in-memory fixture. Nothing touches the user's
other Vim/tmux sessions or source files.

## Task presented without a key sequence

Starting in code, find Morgan's discussion about short queries. Quote only
“Please cover an empty query too” from Sam's reply into a reply draft, inspect
its preview, then return to the same place in code. Keep the draft unsent.
Use the interface's own hints/help. Stop at any time.

Two discussions share one anchor: Morgan's unresolved root has two replies,
including an attributed nested quote and a suggestion; Riley's separate
resolved discussion remains visible. This tests thread/message identity and
reading hierarchy. The local draft created by the task remains unsent.

Afterward ask who would see that saved draft and what sending it was expected
to do. Record completion, wrong turns, target accuracy, return behavior, any
coaching and confusing labels in `observer.json`. Leave unanswered fields null.

## Observation limits

`trace.json` records view/thread/message transitions, actual terminal size,
source/final positions and remaining local drafts when Vim exits. It is not a
keystroke logger. Trial prose and draft text stay in the trial directory; the
launcher explains this before opening Vim. Exit events may omit state from a
review session already closed; the observer's record remains necessary.

A scripted route passes at 80×24 and 120×40 with default and remapped keys,
including the exact selected phrase, retained preview text and source-window
return. That proves the fixture works. It does not prove discoverability, and
the script deliberately leaves `observer.json` marked `not-observed`.

This first trial focuses on discovery and return. Private service review
visibility and permissions require the separate authorized GitHub fixture.
Refresh inserting earlier replies has automated regression coverage in
`test/thread_entry.vim`; observing it during a later human trial remains part
of the wider packet. Do not label this lab as validating every review journey.
