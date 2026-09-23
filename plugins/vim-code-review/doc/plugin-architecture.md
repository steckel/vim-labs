# One code-review UX, counterparty plugins

Architecture roadmap, 2026-09-14. The current provider contract remains version
1; the checkpoint below distinguishes implemented behavior from planned work.

Implementation checkpoint: backend bindings and a bundled local backend now
use the version-1 request contract. Local Git captures, SQLite conversations,
inline replies, reopen, retained follow-up captures, and shared conversation
across revisions are implemented. Existing provider callbacks retain
their draft keys. See [the implemented backend API](provider-api.md). The shared
UI and GitHub package directories now use `vim-code-review` and
`vim-code-review-github`; agent package extraction and Git notes remain proposed.
Local assignment storage and
scoped MCP participation have an [implemented backend core](participant-mcp.md);
Vim assignment selection, outcome navigation and cancellation are implemented;
participant launch/resume adapters remain planned.

The public organizing question is **“Who am I reviewing this with?”**
`vim-code-review` supplies the shared interface. Counterparty integrations
supply GitHub reviews, Codex sessions, or Claude sessions. Git captures and
local conversation storage are shared internals, not separate public plugins.

A review session has a durable identity, conversation, comparisons, and a
workflow supplied through a backend binding. The GitHub integration uses native
GitHub objects. Planned Codex and Claude integrations will combine their runtime
with shared local review storage and captured source. A review conversation is
not the agent runtime's transcript; it must survive Vim and agent restarts.

The existing internal local backend remains usable through `:ReviewLocal` while
agent integrations are built. It is an implementation building block, not a
fourth counterparty or an additional package users must install. It continues
to support standalone review and fixtures without requiring an agent.

## Public plugins and internal responsibilities

| Public package | Review experience | Supporting implementation |
| --- | --- | --- |
| `vim-code-review` | Shared files, diffs, cards, composers, navigation and action dispatch | Normalized contracts, drafts, recovery and reusable local session helpers |
| `vim-code-review-github` | Review a GitHub PR with its people and bots | Native review storage/actions, authentication and GitHub comparison semantics |
| `vim-code-review-codex` (planned) | Iterate on changes with a selected Codex session | Shared captures/conversation store plus a Codex runtime adapter |
| `vim-code-review-claude` (planned) | Iterate on changes with a selected Claude session | The same review machinery plus a Claude runtime adapter |

Within a plugin, separate durable review operations, agent runtime operations,
content acquisition, and optional export. This separation avoids duplicating
SQLite persistence or Git comparison logic in every agent integration; it does
not create public Git/local-storage/participant packages that users must assemble.
Git and jj supply content; neither supplies a discussion counterparty. Git notes
remain optional checkpoint transport, not the required conversation database.

A review backend supplies reads and supported writes. An operation's destination
is its owning backend instance and review, not a second destination-only plugin
contract. An integration may use a runtime adapter when acting as a participant
in another review. This leaves room for a GitHub review to involve Codex without
moving the PR's authoritative conversation out of GitHub. The interaction design
for that combination is deferred to the [handoff backlog](review-handoffs.md).

Capabilities describe supported actions and connection-specific availability.
The UI uses accurate labels such as “Publish review” and “Send to Codex.”
Starting an agent run and approving a review remain separate operations. A
plugin cannot infer service permissions from the selected counterparty name.

## Ownership across backends

| Shared Code Review layer | Counterparty integration / backend |
| --- | --- |
| Cards, diff layout, navigation, composers | Review discovery, identity, and lifecycle |
| Normalized snapshots, anchors, threads, capabilities | Content acquisition and revision semantics |
| Pending editor drafts and operation recovery | Accepted conversation state and durable history |
| Action dispatch and optional MCP gateway | Storage, authentication, writes, and reconciliation |

Shared draft recovery is an outbox for pending operations, not a second
authoritative conversation database. A backend receipt determines whether a
draft has been accepted. Keep native states and action labels; local review
readiness, GitHub approval, and a Piper decision need not mean the same thing.

Persistence implementation is private to each backend. SQLite and Git notes
are implementation choices for agent-backed reviews; remote backends need no
mandatory local conversation database.
The shared contract must work with a remote or fixture backend that has no
local review store, agent runtime, or Git repository.

## The user-facing loop

1. Choose a counterparty and change: a GitHub PR, or a Codex/Claude session
   bound to a workspace and captured changes (agent integrations planned).
2. Use the existing file tree, diff panes, comment cards, and draft composer.
3. Accumulate a review across files. Every new comment is local until delivered.
4. Open the batch panel: select comments and add a summary.
5. Submit feedback to the current backend, export it, or assign it to an agent.
6. Show agent progress in the review session. Attach replies to comment IDs when
   the integration returns that relationship; otherwise show a batch-level reply.
7. When changes are ready, inspect a new comparison. Keep the earlier discussion
   and let the reviewer decide which concerns are resolved.

A proposed batch panel might say:

```text
Working tree · captured revision 3
6 comments across 3 files
Review with Codex · “Completion cleanup”
Session: selected Codex session

[ Preview batch ]  [ Send 6 comments ]
```

A review may later involve another counterparty. A Codex review can lead to a
GitHub PR, and an existing GitHub comment can be sent to Codex for help. These
are future linked workflows, not a destructive switch of the original review's
identity or conversation owner. Keep original authorship, source comparisons,
message IDs, and operation receipts. Sharing feedback with an agent does not
by itself post an agent response to the PR. See the [deferred workflow questions](review-handoffs.md).

Available combinations depend on the connection and an appropriate workspace.
Selecting a remote change does not silently check it out or give an agent an
unrelated checkout. Before an editing run, bind the batch to a workspace that
matches the reviewed content, or create a suitable isolated workspace.

The same feedback may be delivered to an agent and later published for human
review. Those are separate delivery records, not copies that erase provenance
or an automatic forwarding rule.

## Two libraries and small integration packages

**`vim-code-review` is the base name** within Vim Labs. The implemented packages
are `vim-code-review` (formerly `vim-revue`) and `vim-code-review-github`
(formerly `vim-reviewhub`). Their directories and installation references use
the new names. Existing Vim commands, autoload namespaces, configuration keys,
backend IDs, and persistence paths retain their names for compatibility.

The planned counterparties are `vim-code-review-codex` and
`vim-code-review-claude`; no placeholder plugin is advertised as implemented.
A future Piper integration can use `vim-code-review-piper` once its supported
interfaces and product scope are established. Git capture, local storage,
exports, and agent runtime helpers remain implementation details.

The reusable inline-card library is a separate presentation primitive, usable
in ordinary buffers. Its independent package name remains undecided. The live
editor plugin/server `vim9-mcp` is separate from the code-review family. The
assignment-scoped review MCP currently remains with the shared local machinery.

Git/jj sources and file/clipboard export stay bundled. The existing `:Review`
entry points remain available; packaging does not require a storage migration.
The GitHub package keeps the working ReviewHub bridge and its native review
semantics. Agent plugin extraction should reuse these contracts and the local
store rather than introduce another conversation format.

The card library accepts a buffer attachment, an anchor, presentation data,
and action callbacks. It owns wrapping, display properties, highlights,
resize handling, and cleanup. It does not own persistence,
credentials, diffs, submission, or agent execution. Labels such as “Reply” and
“Suggested change” are supplied by Revue, not built into the generic library.
The current `comments.vim` renderer is the first extraction seam; attachment
and cleanup still live in `session.vim` and must move with it.

Start with one concrete card type and the operations attach, update, and
detach. Inline discussions remain expanded; see the
[GitHub review UX reference](github-review-ux-spec.md) for the visibility decision
and comparison. Avoid building a general widget framework. Define the package
boundary now; use both a review session and an ordinary buffer to prove it.

## A small shared data model

| Object | Stable identity and contents |
| --- | --- |
| Snapshot | Source connection, comparison ID, revision/content identities, files and canonical hunks |
| Anchor | Snapshot ID, old/new paths, side, source range, selected text and surrounding context |
| Thread | Backend-scoped stable ID, anchored discussion, native state and available actions |
| Batch | Frozen selection of comment versions, summary, referenced snapshots, context and patches |
| Delivery | Batch ID, target backend/review or participant/session, operation ID, status and receipts |
| Agent run | Delivery ID, bound workspace, execution state and resulting snapshot reference |

Qualify review and thread identities with backend and connection identity.
Keep pending draft IDs and agent session IDs separate from backend-owned
comment IDs. Record cross-backend mappings explicitly. A frozen batch cannot
change underneath an in-flight delivery: edited feedback belongs to a new
batch version. Delivery and agent-run objects are optional capabilities; a
read-only backend need not implement an agent workflow.

Use Markdown for the readable handoff and structured JSON for identities and
anchors. Include the relevant diff and source context; do not assume line
numbers alone identify code. A general agent response is not automatically a
reply to every thread, and an agent claiming a fix is not reviewer resolution.

## Snapshot and workspace semantics

For a local source, offer explicit comparisons such as HEAD versus the working
tree, staged changes, or a chosen branch baseline. Capture the exact content
used to build the diff. Include untracked files deliberately and identify
whether unsaved buffers were included. Existing `:Review` defaults should remain
compatible during migration.

A running agent must not make the review target drift invisibly. The displayed
snapshot stays fixed while the workspace changes. After the run, capture the
result and offer “Changes since my review” as well as the complete comparison.
If other edits occurred concurrently, do not attribute all resulting changes
to the agent. An isolated workspace is the cleanest way to attribute a run.

Anchors retain their original snapshot. A context-based remap can be offered
when unambiguous; ambiguous anchors become outdated discussion. File hashes
can detect change but cannot by themselves locate a moved line.

## Integration contracts

Use versioned, asynchronous request/result contracts and a modest event stream.
Names here are proposed, not callable functions:

```text
backend:     list_reviews, open_review, capabilities, read_changes
             open_snapshot, load_file, refresh_threads
             publish_batch, reply, set_thread_state, reconcile
participant: list_sessions, start_run, read_run, interrupt_run, reconcile
```

Start with coarse agent events: accepted, running, needs_input, completed,
failed, and interrupted. Attach optional progress text, response content, and
external IDs. Streamed progress belongs in a status area, not a new permanent
comment for each token. Correlated final responses can become card replies.

Agent input/approval requests retain their native meaning and are routed
through the participant adapter. Capability discovery should state whether
session resume, interruption, structured replies, and workspace isolation are
supported. Do not invent success for an unsupported action.

An acknowledgement means accepted, not completed. A completed run does not
mean every comment is resolved. Interrupting a run does not roll back edits.
An uncertain delivery must be reconciled before retrying; a local batch ID
alone does not guarantee provider-side idempotency. Publishing multiple remote
comments may partially succeed, so receipts must identify individual items.
Use Revue's draft/recovery machinery for pending operations; accepted history
and durable run records belong to the relevant backend or participant adapter.

## Concrete integration candidates

**Codex:** the documented app-server interface is a candidate for a persistent
Vim integration. It supports bidirectional requests, thread creation/resume,
and turn events. Use a managed local transport and bind explicit thread and
workspace identities. Verify support against the installed version; do not
assume it can attach to any running desktop/TUI session. See [Codex App
Server](https://learn.chatgpt.com/docs/app-server).

**Claude:** the Agent SDK documents persistent sessions and explicit resume
IDs. A plugin can translate those runs into the same participant events while
keeping SDK-specific behavior outside Revue. Session history is distinct from
filesystem state. Existing interactive-session attachment and account setup
must be verified for the selected interface. See [Work with
sessions](https://code.claude.com/docs/en/agent-sdk/sessions).

**Piper:** keep a concrete adapter slot, but discover the supported workspace,
change, patchset, and review APIs before committing to an implementation.
Piper integration here is a product label, not an assertion that one storage
API supplies every review operation. Validate the model against a CL-shaped
fixture in the meantime. No internal interface has been verified yet.

These are Vim integration plugins. They do not require distributing the same
plugin package inside the Codex or Claude applications. A shared Revue MCP
interface supplies session context and structured inline replies; participant
adapters retain responsibility for starting and resuming agent runs. MCP routes
through the selected backend's capabilities, including its delivery semantics;
it does not create an implicit local conversation alongside every remote review.

## Build the smallest complete loop first

1. Extract card attachment/lifecycle behind a tested API, retaining the current
   screenshots and key behavior. Exercise it in an ordinary buffer too.
2. Define the backend boundary against the working GitHub bridge and a local
   fixture. Verify that neither needs the other's store or lifecycle.
3. Reuse the implemented local captures, durable conversations, batches, and
   recovery as shared internals for agent-backed review. Retain existing entry
   points and the legacy submission callback.
4. Implement `vim-code-review-codex` as the first agent counterparty: send one
   batch, receive inline replies, capture changed files, and review the next snapshot.
5. Add `vim-code-review-claude` through the same contract. Revise the contract only for concrete
   differences exposed by that second integration.
6. Migrate GitHub batch publishing behind the backend contract while retaining
   existing remote behavior. Implement Piper after interface discovery.

The first milestone is one full feedback → agent → new diff loop. Four plugin
skeletons would not prove the architecture. Success means changing source or
participant does not require rewriting the diff layout or comment cards.
