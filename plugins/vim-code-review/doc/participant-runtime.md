# Participant execution from a saved assignment

The local backend now connects a saved assignment to explicit start/resume
commands in Vim. The first process adapter targets Codex CLI. Verification uses
real Vim, supervisor and MCP processes with a deterministic fake executable;
a model-backed Codex run is still a release-validation step.

## Configure and use

Add a runtime to an existing configured participant:

```vim
let g:revue_participants = [{
      \ 'id': 'local-agent', 'label': 'Local coding agent',
      \ 'runtime': {'adapter': 'codex', 'executable': 'codex',
      \             'sandbox': 'workspace-write'}}]
```

`read-only` is also supported. Executable defaults to `codex` and access defaults
to `workspace-write`. The preview always states both. No model override is
supplied: the adapter uses the existing Codex login/configuration. The runtime
uses non-interactive execution, so operations requiring interactive approval
cannot request approval in this process.

1. Create an assignment with the existing selection/preview flow.
2. Open `:RevueAssignments`, then its outcomes. Use `:RevueRunParticipant` or the
   contextual action guide. There is no new default key; `run-participant` is
   configurable through `g:revue_mappings`.
3. Inspect participant, selected comparison, workspace, executable and access in
   the saved preview. Close the preview to its read-only operation and use
   `:RevueSend` to confirm. Merely opening it starts nothing.
4. Use `:RevueReloadAssignments` for current process and comment outcomes. A
   saved run receipt confirms acceptance of the operation, not task completion.
5. Once the prior execution ends, the action becomes Resume participant and
   previews the exact recorded session. Later human replies remain available
   through the same assignment's MCP connection.

Assigned source can be older than the current workspace. The agent is instructed
to inspect that difference, reply to the selected comments, record outcomes and
leave code uncommitted. Result capture and review remain existing owner actions;
process completion does not create a capture, resolve a thread or approve work.

## Durable operation and execution identity

The shared draft kind is `participant_run`. Its previewed intent includes
assignment/version, participant, reference/count, workspace/runtime and start,
resume or prepared-dispatch identity. Backend validation compares that intent
with the saved assignment and run before committing preparation. Receipts carry
the exact intent; a missing or mismatched receipt leaves Vim's operation unknown.

The backend persists preparation before launching a supervisor. A POSIX lock
admits one execution, and the child inherits ownership so supervisor loss cannot
allow a second process while the first still holds the lock. On missing ownership
with an unfinished stored state, reads report unknown and do not restart it.
Repeated dispatch may briefly create another supervisor, but not another admitted
execution. Receipt-only reconciliation never dispatches.

An error after preparation returns that durable receipt plus `dispatch_error`.
The user inspects current state instead of creating an unrelated replacement.
Prepared runs can be dispatched explicitly; stale assignment versions are
rejected. A failed pre-execution attempt or abandoned preparation does not erase
an earlier executed session. Subsequent attempts resume the most recent executed
session with its original runtime settings.

## Abandon an unstarted preparation

Use `:RevueAbandonRun` from assignment outcomes, or its contextual action. There
is no default key; `abandon-run` is configurable. Its saved preview names the
exact prepared run and states that assignment access, comments, outcomes and
previous executed sessions remain. Close the preview and confirm with
`:RevueSend`. Opening the preview alone does nothing.

This works for an outdated preparation and does not require its executable to
remain installed. A cancelled assignment's unstarted preparation can also be
released. An existing pending runtime operation opens first, so an uncertain
launch must be reconciled before another operation is prepared. Once abandoned,
reload outcomes to prepare a new start or resume of the prior executed session.

The backend requires the current assignment version, exact previewed run intent,
`prepared` state and no execution/held process ownership. If dispatch wins a
race, abandonment fails and leaves that process running. If abandonment wins,
the prepared run can no longer execute. State, event and operation receipt commit
atomically. A mismatched receipt freezes Vim's operation; a later receipt check
returns the original outcome and changes no run state.

Owner operations are `prepare_run`, `run`, `runs`, `dispatch_run` and
`abandon_run`; all are review-scoped. The shared `participant_run` capability
advertises `abandon: true`, and the durable operation uses `run_mode: abandon`.
The owner API retains legacy abandonment without an operation ID; durable callers
supply an ID and use `reconcile: true` only for receipt recovery.

Assignment cancellation remains separate: it revokes scoped MCP access and
preserves conversations. Neither abandonment nor assignment cancellation is a
process-termination control.

## Adapter contract and evidence

The adapter constructs argv directly, supplies the prompt on stdin, and reads
bounded JSONL events. It records the exact UUID from `thread.started`; resume
passes that UUID rather than `--last`. It requires the assignment/run-scoped MCP
server. Foreign run attribution and inactive/cancelled assignment writes are
rejected. This is the assignment transport's scope; existing Codex configuration
and workspace access still apply to the model process.

The installed `codex-cli 0.154.0` help was checked for exec/resume arguments.
OpenAI documents scripted execution, JSONL output and explicit-session resume.
[Non-interactive mode](https://developers.openai.com/codex/non-interactive-mode),
[CLI reference](https://developers.openai.com/codex/cli/reference/).
Documentation/help checks do not establish successful model execution.

Validation and terminal renders (local evidence: `../output/participant-runtime/validation.json`)
cover supervisor races, child ownership after supervisor loss, malformed streams,
preview binding, cancellation/version changes, prepared-run receipt recovery,
and two Vim processes performing start/recovery/exact resume through actual MCP.
The fake executable writes two inline replies for two explicit runs; resolution
stays unchanged. Abandonment verification (local evidence: `../output/abandon-run/validation.json`)
adds exact-run receipt recovery across two Vim processes, active ownership and
dispatch races, event rollback, outdated versions and cancelled preparations.
Real Codex end-to-end behavior, additional adapters and a longer
human-reply/result-capture iteration remain to verify or implement. The broader parity goal remains open.
