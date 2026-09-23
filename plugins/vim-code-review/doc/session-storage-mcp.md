# Agent-review storage, MCP participation, and Git notes

Design proposal, 2026-09-14. Extends [the plugin architecture](plugin-architecture.md).
The checkpoint below distinguishes implemented behavior from the remaining
interface and storage proposals.

Implementation checkpoint: the first local backend stores immutable Git
captures, comments/replies, receipts, and events in SQLite and opens through
the common backend binding. Explicit follow-up captures now retain source history
and share the conversation, with original-anchor return and receipt recovery.
Local assignments and a scoped stdio MCP transport now have an implemented
backend core: selected-comment/source identity, attributed replies, per-comment
outcomes and transactional receipt recovery. See the [implemented MCP contract](participant-mcp.md).
Vim assignment selection/outcome/cancellation UI is implemented. Actual participant
launch/resume adapters,
and Git notes remain proposed. The current API is documented in
[provider-api.md](provider-api.md).

## Decision

Expose agent-backed review through `vim-code-review-codex` and
`vim-code-review-claude`, alongside `vim-code-review-github`. The shared
`vim-code-review` layer owns presentation, contracts, and reusable session
machinery. There is no separate public local or Git plugin to install.

The current internal local backend supplies captured source, durable review
conversations, receipts, and assignment scope. Agent integrations will compose
that machinery with their runtime adapters. The current `:ReviewLocal` workflow,
storage paths, backend identifiers, and recovery behavior remain available;
changing public package names does not migrate stored sessions.

Use a version-control-independent storage model internally, with Git notes as
optional checkpoint transport. An agent-backed review can outlive Vim or an
agent runtime without imposing a local conversation store on a GitHub review.
The agent runtime transcript and the review conversation are distinct records.

MCP can be a shared gateway to backend capabilities. Conversation storage is
a backend responsibility, not a prerequisite imposed by MCP. Remote reviews
use their existing services; local reviews use the local backend's store.

Each backend handles both reads and supported writes. An operation's destination
is a target backend and review, not a second provider interface. MCP dispatches
through this same contract. Exporters produce artifacts; participant adapters
run agents. Neither requires a separate review-destination plugin category.

The reusable card library stays presentation-only. A card renders a thread
from the session; an agent reply updates that thread and therefore the card.
Neither storage nor MCP needs to know which Vim window currently displays it.

## Planned agent-counterparty interaction

1. Open a review with Codex or Claude, bound to a workspace and captured source.
   Select code and leave a comment in the shared inline composer.
2. Choose “Ask Codex about this thread,” or collect several threads into a batch.
3. The counterparty integration uses its runtime adapter to start or resume an
   agent with the selected scope, frozen snapshot, and access to review MCP tools.
4. The agent reads a thread with its code context and replies to its stable ID.
   Quotes and suggestions use the same card presentation as human comments.
5. A proposed fix references a new snapshot or patch. The card shows
   “Addressed · inspect changes”; the reviewer can reply, resolve, or reopen it.
6. Closing and reopening Vim restores the conversation and pending work.

A whole-session discussion holds the overall request and unanchored questions.
File threads hold feedback at specific code anchors. A reply can reference an
individual comment within a thread; it must not create a second unrelated
thread simply because it came from a different agent.

The UI keeps reviewer resolution separate from agent work state. “Working,”
“needs input,” and “addressed” describe an assignment. “Open” and “resolved”
describe the review concern. A failed run cannot erase a comment or resolve it.

## One contract, several backends and clients

```text
Vim + review cards ──────────────┐
                               ├── Review contract / capability dispatch
Agent clients ────── MCP ────────┘       ├── GitHub integration ── GitHub reviews
                                       ├── Codex integration ── Codex runtime
                                       └── Claude integration ── Claude runtime
                                                  │
                                      shared captures / local review store
```

Codex and Claude integrations in this diagram are planned. They reuse the
internal local backend and compose content adapters and optional checkpoint
export. Runtime adapters may also participate in compatible remote reviews.
The [handoff backlog](review-handoffs.md) defers the design of evolving a Codex
review into a GitHub PR and sending an existing PR comment to an agent.

A small local companion can host backend dispatch for Vim and MCP. Both clients
call the same operations with the same validation. The local backend owns its
transactions; remote backends translate operations into their service APIs.
Start the companion on demand; durable local reviews do not require it to run
continuously. A shared process does not imply shared storage ownership.
Use a local user-scoped connection, with each agent connection explicitly
bound to permitted sessions, threads, and actions. Discovering a tool is not
permission to read every review on the machine.

MCP gives an agent access to review context and actions. Starting a run,
interrupting it, and resuming an agent's own conversation remain participant
adapter responsibilities. Resource subscriptions are optional in MCP and
notify clients that content changed; they do not guarantee an idle agent will
wake and handle a new comment. Provide a changes-since-cursor read path for
clients without subscriptions. See the [MCP resources specification](https://modelcontextprotocol.io/specification/2025-11-25/server/resources).

## Proposed MCP surface

Names below describe the broader candidate contract. The first implemented
local subset is listed in [participant-mcp.md](participant-mcp.md); no client is
automatically configured. Handles include
backend and connection identity. Expose only supported operations, with explicit
draft-versus-publish semantics and backend-native action labels:

| Operation | Result or effect |
| --- | --- |
| `list_sessions` / `get_session` | Accessible reviews, source comparisons, participants, and summary |
| `list_threads` / `get_thread` | Discussion, comment IDs, original anchor, source context, and relevant diff |
| `create_thread` | New feedback validated against an exact snapshot and source range |
| `reply_to_thread` | Backend-routed reply, optionally to a particular comment; explicit delivery mode |
| `propose_suggestion` | Replacement content tied to an exact snapshot/range; no implicit application |
| `attach_result` | Assignment outcome and evidence: reply, patch, or resulting snapshot |
| `get_changes` | Session events after a durable cursor for reconnect and refresh |

Reading a thread should return enough context to understand it without first
opening Vim. Large source files can be separate resources. Resource addresses
such as `revue://sessions/S/threads/T` identify semantic objects, never screen
coordinates. Thread content is review data, not an instruction source that
can expand the agent's permissions.

Writes include a client operation ID for deduplication. Edits and state changes
include the expected object version so a stale client cannot overwrite newer
feedback. Persist state, operation receipt, and event in the same transaction.
Bind author identity to the connection; callers cannot impersonate another
participant just by choosing an author field.

The transaction guarantee above applies to the local backend. Remote backends
use their service's concurrency controls and reconcile uncertain writes; a
local receipt cannot make a remote API transaction atomic or idempotent.

An agent normally edits through its existing workspace tools. The selected
backend records the result and comparison when it supports that operation.
Publishing to GitHub is an explicit remote action; saving a pending reply in
the shared outbox does not publish it. Reviewer state changes use a distinct
capability from an agent marking its assignment done.

If someone wants a private local iteration on a GitHub change, explicitly create
a local review linked to that source snapshot. Its discussion belongs to the
local backend. Publishing selected feedback later is a separate delivery with
provenance. Merely opening a remote review must not create this second review.

## Local backend storage scope

Use the shared internal local backend's SQLite store, outside the checkout, with a stable
project ID and explicit workspace bindings. Avoid identifying a project solely
by its absolute path or remote URL: paths move, and repositories can have
several worktrees. Keep the storage interface small; interchangeable database
engines would add little to the first complete loop. SQLite's documented use
as a desktop application file format supports this choice; the architecture
recommendation is ours. See [Appropriate Uses For SQLite](https://sqlite.org/whentouse.html).

Persist:

- Sessions, participants, source comparisons, and workspace bindings.
- Immutable reviewed content or retained content blobs, hashes, and anchors.
- Threads, versioned comments, structured suggestions, and reviewer state.
- Drafts, frozen batches, assignments, deliveries, and external receipts.
- Agent run references and a compact history of meaningful review events.

Keep normal current-state tables plus an append-only record of meaningful
changes. Full event sourcing is unnecessary initially. Retain deletions as
tombstones where synchronization needs them. Event IDs support import dedupe;
local monotonically increasing cursors support live clients. They serve
different purposes and should not be conflated.

Store the review conversation and useful agent outcomes. Leave token streams,
hidden reasoning, and runtime-specific transcripts to the agent runtime.
Record its session/run ID so the integration can resume or open that history.

Existing persistence covers draft recovery in `session.vim`, while provider
threads are loaded into memory. Keep shared draft/outbox recovery independent
of the local backend database. Associate drafts with backend-qualified review
IDs and preserve pending or uncertain submissions during migration. Only local
review history belongs in the new local store. Keep existing entry points
working throughout extraction.

## Git notes as an additive capability

Git notes attach blobs to Git objects without changing those objects. A custom
ref such as `refs/notes/revue` can hold structured review checkpoints associated
with commits. Notes are not intrinsically limited to prose or commit objects.
See the [Git notes documentation](https://git-scm.com/docs/git-notes).

Use an explicit “Save review with commit” operation to export a selected review
checkpoint. A versioned bundle contains session/thread/comment IDs, discussion,
state, original anchors, and sufficient retained context to restore the review
without its original database. Include reviewed content when it is not already
recoverable from the transported Git objects. Group multiple sessions for one
commit in a manifest keyed by session and checkpoint IDs.

The working-tree snapshot has its own identity before a commit exists. A later
commit can be associated with it after content validation. Synthetic Git
objects are possible, but need not become the foundation for all local reviews.

Operational details belong to the Git adapter:

- Transport the notes ref deliberately through configured fetch/push refspecs.
- Configure the custom ref for note copying during supported history rewrites.
- Preserve original anchors: copying a note after rebase does not relocate code.
- Merge structured checkpoints by identity and report conflicting edits.

Git's union-style note merges combine text lines; they do not merge conversation
objects. Rewrite copying also needs a configured `notes.rewriteRef`. These
behaviors make an application-level importer/exporter necessary. See [Git
notes configuration and merge behavior](https://git-scm.com/docs/git-notes)
and [Git push refspecs](https://git-scm.com/docs/git-push).

An exported checkpoint is immutable by identity; subsequent exports append a
new checkpoint to the manifest. Updating that manifest must detect concurrent
ref changes and merge or report them rather than overwrite another writer.
An import deduplicates IDs, preserves provenance, and exposes conflicts. It
does not automatically send imported messages to an agent or remote service.

This gives local Git reviews portable history while allowing other content
adapters to support the same local workflow. JSON/Markdown export remains useful
without Git. The Piper backend remains a peer with its own review service;
using Piper content in a local review would be a separate supported combination.
Remote backends remain authoritative for their published objects. Shared
outbox receipts track delivery; local reviews retain explicit source references.

## First vertical slice

1. Verify the common contract against both the existing GitHub bridge and a
   local fixture, without requiring the local database for GitHub.
2. Persist one local review, its frozen content, drafts, and two inline threads.
3. Close and reopen Vim; recover identical discussion and anchors.
4. Expose scoped thread reads and replies through MCP routed to the backend.
5. Have one agent reply to exactly one comment; update its card live.
6. Restart and retry the same operation; verify it produces no duplicate reply.
7. Attach a result snapshot and let the reviewer inspect and resolve the thread.
8. Add export/import, then Git notes checkpoints within the local backend.

Validate stale writes, interrupted deliveries, and moving source anchors in
this slice. Defer cross-machine live synchronization and additional storage
engines until a real integration requires them.
