# Local assignments and MCP participation

The first UX-25 backend/transport slice is implemented. An owner-created
assignment binds selected comments, a retained comparison, and one participant.
A stdio MCP connection reads that scope and saves replies into the same local
review. Revue renders the replies with an Agent badge and supports its existing
quote, reply, original-source and return interactions.

**Vim selection and creation are implemented:** choose saved messages, choose a
configured participant, inspect the full assignment and save a durable local
operation. **Assignment/outcome browsing and cancellation are also implemented.**
**Start/resume integration now has a verified fixture core:** the
[participant runtime](participant-runtime.md) connects the saved assignment to
a supervised Codex adapter and a Vim preview/action. Prepared-run abandonment also has a recoverable Vim action. Real model
validation remains. This MCP server itself does not launch an
agent. The original evidence below uses a synthetic MCP client.

## Ownership and identity

`revue_participants.py` extends the local backend's existing SQLite database.
It adds an `assignments` table and uses the existing reviews, receipts and events.
There is no second conversation store or destination interface. The backend
continues to own source captures and discussion; the transport only dispatches.
The MCP `Server` accepts a scoped participant backend interface, with the local
backend as the first concrete binding.

An assignment contains a backend/connection/review identity, exact comparison
reference, participant ID and label, up to 50 selected message/version targets,
original selected text, and per-message outcomes. Selection currently requires
an existing line or file discussion. General conversation assignments are not
implemented. Whole-thread reading is included so an agent can understand and
answer later human replies in those assigned discussions.

The trusted local launcher fixes `--store` and `--assignment`. Tool arguments
cannot select another assignment, review, author, or backend. Cancellation is
checked on each operation and disables subsequent access, including reads.
This binds MCP access; it is not an OS sandbox for a process that also has its
own filesystem tools. No network listener or shared bearer credential is used.

Agent authorship comes from the assignment, never from reply arguments. Native
actor identity controls edit/delete permissions; matching a human's display
name does not grant their rights or their Author badge.

## Creating an assignment in Vim

Configure the participants available for local assignment:

```vim
let g:revue_participants = [
      \ {'id': 'local-agent', 'label': 'Local coding agent'}]
```

This names an assignment recipient; it does not configure or start a runtime.
IDs must be stable and unique. Entries need nonempty `id` and `label` strings.
Invalid entries are omitted; no valid entries yields a setup explanation.

1. Open `:ReviewAssign` from a local review. From a selected thread message, that
   message starts selected. Otherwise choose from the loaded saved line/file
   messages; review-wide conversation and local drafts are excluded.
2. Use Space / `:ReviewToggleAssignment` to select up to 50 messages. The list
   shows file, range, author and excerpt. It reflects feedback loaded when opened;
   reopen it after loading more feedback to include that feedback.
3. Enter / `:ReviewPrepareAssignment` chooses a participant and opens a read-only
   preview with the full selected bodies and comparison. The participant can
   read whole selected threads, including later human replies.
4. `:ReviewClose` returns to the saved local operation. `:ReviewSend` confirms and
   saves the assignment to the backend. `:ReviewDiscard` cancels an unsent operation.
   Ordinary review batches do not publish assignments.
5. `:ReviewActivity` retains the assignment receipt. Unknown outcomes stay frozen;
   `:ReviewCheckReceipt` recovers the original assignment, including after restart.
   It cannot create an assignment if no receipt exists.

Mappings are configurable through the existing Revue action map. The guide lists
actual bindings. Changed message versions, comparison or participant configuration
require a new preview before a fresh submission. Receipt recovery remains available
when configuration is missing. Creating an assignment neither starts an agent nor
changes source, messages or resolution. Assignment/outcome browsing and cancellation use the commands below; the owner
JSON API remains available for integrations.

Validation and real Vim captures (local evidence: `../output/assignment-ui/validation.json`) include
an accepted backend save with a deliberately dropped response, followed by a
second Vim process recovering the same two-message assignment exactly once.

## Inspect outcomes and cancel participation in Vim

`:ReviewAssignments` reads saved assignments for the owning review. Enter opens
one assignment with its original selected text, per-comment outcome, run ID when
reported and verified result comparison when present. Addressed is the participant's
claim; it does not resolve the discussion. Assigned, working, needs input, addressed,
failed and cancellation remain distinct, including mixed outcomes in one assignment.

Within the detail view:

- Enter / `:ReviewAssignmentDiscussion` opens the exact original message.
- `:ReviewAssignmentReply` opens the latest loaded reply from this assignment
  addressed to that original message. Missing loaded feedback is explicit;
  refresh/load more review feedback before trying again.
- `:ReviewAssignmentComparison` opens the comparison assigned to the participant.
  `:ReviewAssignmentResult` opens the selected outcome's verified result capture.
  `:ReviewReturnContext` returns from source to the same outcome.
- `:ReviewClose` returns from discussion to the same outcome, or from an assignment
  to the list. Reopening managed panels preserves the return target.
- `:ReviewReloadAssignments` refreshes outcomes. `:ReviewCancelAssignmentsRead`
  cancels the read and retains loaded results. Late, malformed or foreign-review
  replies cannot replace the view. A reload preserves reading position and a human
  draft in another window. There is no background polling.
- `:ReviewCancelAssignment` opens a read-only cancellation preview. Close the preview
  and use `:ReviewSend` to confirm. Cancellation revokes assignment MCP access,
  including reads, while preserving conversation and outcomes. It does **not** stop
  an operating-system process. Assignment version changes require a fresh preview.
  Lost results stay frozen for `:ReviewCheckReceipt`, including after restarting Vim.

These actions use separate `assignments` and `cancel_assignment` backend capabilities;
no participant configuration is required to inspect or cancel an existing assignment.
The current local inventory is returned in one read; assignment-list pagination is
not implemented. `[unavailable]` behavior is expressed through messages/guide reasons,
not by guessing that missing feedback was deleted.

Outcome/cancellation evidence and renders (local evidence: `../output/assignment-outcomes/validation.json`)
include two real Vim processes and the actual local backend, with a deliberately
lost accepted cancellation response. No real agent process was launched.

## Creating and inspecting an assignment through the owner API

The owner-side local backend JSON protocol exposes `assign`, `assignments`,
`assignment`, and `cancel_assignment`. These are owner-side entry points, not tools granted to the agent. Vim creation
uses the normal `mutate`/outbox flow with `kind: assignment`; its receipt includes
the operation ID, assignment ID, participant, comparison and selected targets.

Send an owner request to `python3 python/revue_local.py --store STORE`, on stdin:

```json
{
  "op": "assign",
  "id": "a-new-client-operation-id",
  "review": "review-id",
  "participant": {"id": "stable-participant-id", "label": "Local coding agent"},
  "reference": {
    "snapshot": "retained-snapshot-id",
    "base": "retained-base",
    "head": "retained-head",
    "base_tip": "retained-base-tip"
  },
  "targets": [{
    "thread": "thread-id",
    "message": "selected-comment-id",
    "message_kind": "comment",
    "expected_version": "selected-comment-version"
  }]
}
```

Use actual IDs and versions from the backend's current review. A changed target
or mismatched comparison is rejected. Repeating an identical creation operation
returns its original receipt with `recovered: true`; fetch `assignment` for its
current state. Reusing the operation ID for different selection is rejected.

`assignment` takes `review` and `assignment`. `assignments` lists assignments in
one review and returns its backend/connection/review identity. `cancel_assignment`
additionally requires the latest `expected_version`; it preserves the assignment and conversation while revoking
that participant connection. Concurrent writes are ordered by SQLite's transaction. Supplying an owner operation
`id` makes cancellation receipt-backed; `reconcile: true` only checks that receipt
and never creates a cancellation. Vim uses this through `mutate` with
`kind: cancel_assignment`. Legacy owner cancellation without an ID remains supported
for direct callers, without claiming receipt recovery.

## Starting a scoped MCP connection

Configure a stdio-capable client to launch this argv, substituting the real path,
store and returned assignment ID:

```text
python3 /path/to/vim-code-review/python/revue_mcp.py --store STORE --assignment ASSIGNMENT_ID
```

The server negotiates MCP **2025-11-25**, requires initialization, and advertises
only tools. It accepts newline-delimited UTF-8 JSON-RPC on stdin, writes protocol
messages only to stdout, and exits at EOF. Incoming lines are limited to 1 MiB.
Unsupported methods and invalid arguments produce protocol errors; backend
permission/version/scope failures produce tool results with `isError: true`.
Notifications never trigger tool execution or receive responses.

The protocol implementation follows the official
[lifecycle](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle),
[stdio transport](https://modelcontextprotocol.io/specification/2025-11-25/basic/transports),
and [tools](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)
contracts. HTTP, subscriptions, sampling, MCP tasks and resources are not advertised.

| Tool | Interaction |
| --- | --- |
| `get_assignment` | Read the frozen selection, participant, assigned comparison, version and outcomes. |
| `get_thread` | Read a permitted discussion, including later human replies, with original and assigned comparison identities. Missing original code is explicit and does not hide the conversation. |
| `get_source` | Read up to 200 lines of a permitted discussion's retained original file on the requested side; continue with `next_start`. Never reads the live workspace. |
| `get_changes` | Read scoped events after a durable numeric cursor. Continue while `has_more`; use thread/assignment reads to get current content. Pages may contain no permitted events while advancing past unrelated review events. |
| `reply_to_comment` | Save an attributed local reply to a current message in an assigned thread, with `in_reply_to` identity. Requires a stable operation ID and expected message version. |
| `set_outcome` | Mark one selected comment working, needs input, addressed, or failed. Requires a stable operation ID and assignment version; accepts a summary, optional runtime run ID, and optional verified retained result comparison. |

Mutations save state, receipt and event in one transaction. Retry an uncertain
reply/outcome with the **same operation ID and identical arguments**. Recovery
returns the saved result without adding another message; changing arguments
under that ID is rejected. The server does not retry a mutation on its own.

After a human captures agent-edited files through the existing capture workflow,
`set_outcome` can reference that resulting comparison. It cannot invent a source,
write a workspace file, capture unsaved buffers, resolve a thread, submit an
approval or create a commit. “Addressed” records the participant's claim for human
review, independently of the discussion's resolution state.

## Verification and remaining work

Recorded evidence (local evidence: `../output/participant-mcp/validation.json`) covers seven focused
backend/protocol tests, the full Revue suite, concurrent same-operation recovery,
transaction rollback, cancellation/scope rejection, retained source after a new
capture, and an actual stdio reply reopened in two separate Vim processes.
The rendered examples use disposable Git/SQLite fixtures and a synthetic client.
No GitHub write, real agent run or client installation was performed.

The [runtime integration](participant-runtime.md) adds start/resume and durable
run identity without a second conversation store. Its evidence and remaining
real-adapter/management work are separate from these original MCP checks. Git
notes remain an optional transport proposal.
