**Historical GitHub extraction plan**

The current package and counterparty decisions are in the
[architecture](doc/plugin-architecture.md). Public packages are now
`vim-code-review` and `vim-code-review-github`, with Codex and Claude
integrations planned. Git capture and local storage are internal helpers.
The checkpoints and sequencing below retain the earlier implementation history;
they are not the current package roadmap.

Design follow-up (2026-09-14): [One review UX, composable plugins](doc/plugin-architecture.md)
explores an independent card library, review backends, and agent participants
for GitHub, Piper, Codex, and Claude. Local human/agent iteration before commit
uses the internal local backend, with its own conversation store and workflow.
The shared layer owns presentation, the review contract, and pending draft
recovery. These proposed boundaries do not change the shipped version-1
provider contract or the current ownership described below.

Status: implementation in progress. The first GitHub workflow was implemented
and verified on 2026-09-11; the broader roadmap below remains planned.

2026-09-14 backend checkpoint: a common session-scoped binding now routes both
reads and writes. The bundled local backend adds immutable Git captures,
SQLite conversations and receipts, inline replies, and a saved-review picker.
The existing GitHub bridge and draft keys remain compatible. MCP, agent runs,
revision advancement, and Git notes are subsequent work.

2026-09-14 interaction audit: [Vim UX backlog](doc/interaction-backlog.md) refines
the packages below into interaction-level stories, with current code evidence,
acceptance criteria, and dependencies. Panel targeting, native navigation,
focused discussions and atomic review batches now have tested foundations.
Individual inline collapsing is removed; global visibility and unified diff
remain held decisions. The P0 panel-state defect is now fixed and regression
tested. Commands/configurable maps, focused messages, quote/copy actions, and
draft preview/context are implemented; see the backlog's implementation
checkpoint for remaining work and verification limits.

Resolution/recovery checkpoint: UX-26 now preserves uncertainty across failed
receipt reads and disallows discard/unpack. UX-09 has targeted resolve/reopen,
confirmation, state/counts, and local/GitHub backend operations. Real Vim process
tests and local HTTP tests verify failure/restart handling. Session acceptance
survives failed refresh. The full Revue suite (11 local tests), 28 companion
provider tests, and companion integration/restart suite pass. Live authenticated
GitHub resolution is still a release gate. Next finish narrow-pane reading,
outcome history, revision navigation, and review-wide discovery; these checks
do not establish overall parity.

Reading-layout checkpoint: native pane focus/restore, automatic narrow-terminal
focus, sidebar hide/reopen, and bounded card reading width are implemented.
Replies/previews return through saved window sizing and origin positions.
The 80/120/200-column suite covers a thread taller than the screen, resize,
sidebar transitions, refresh while composing, and configuration opt-out. Real
isolated terminal captures are under `output/layout/`. Manual window topology
reconstruction stays outside this slice; remaining UX-03 lifecycle, revision
navigation and review-wide discovery work continues.

Batch checkpoint: selection/edit/preview and durable atomic batch submission
now work across the local and GitHub backends. GitHub uses a single review
request; local feedback commits in one SQLite transaction. Frozen payloads,
receipt completeness, failure unpacking, and restart recovery are tested.
Server-side pending-review synchronization and revision switching
remain further work.

Current delivery: the companion lives at `../vim-code-review-github` and is installed
alongside Revue. It provides the PR tree, conversation preview, pinned file
contents, existing threads, inline comments/replies, and review decisions.
Revue now has a provider-neutral snapshot entry point, multiline persistent
drafts, and submission recovery. Live public PR browsing/composer opening,
15 local HTTP provider tests, and real Vim integration/restart tests pass.
The tests include the user's Vim configuration. No test comments were posted
to the public demonstration PR. The actual transport uses Python's standard
HTTP library with credentials retrieved from GitHub CLI; this also supports
anonymous public reads. Internal-provider integration and the remaining
roadmap features are not complete.

Build a GitHub-like review workflow in Vim using two independently useful
plugins: `vim-code-review` for reviewing code and a companion, provisionally named
`vim-code-review-github`, for finding and interacting with PR/CL providers. The names
of commands and new APIs below are proposed.

Planning defaults: retain Vim 9.1+ and Vim9script; ship a GitHub workflow first;
validate the provider boundary early against a second, CL-shaped fixture; then
ship the real internal integration when its supported interface is known.
The companion is a separate repository. This plan does not create it.
If an existing provider plugin is selected, it can implement the same bridge
instead of requiring a new browsing UI.

**1. Product boundary and ownership**

| Responsibility | vim-code-review-github | vim-code-review |
| --- | --- | --- |
| Connections, authentication, account/host selection | Owns | Receives opaque connection identity |
| PR/CL lists, queries, pagination, saved filters | Owns | No dependency |
| Change description, author, reviewers, status, checks, timeline | Owns detail view | Shows a compact summary/link |
| Revision selection and provider comparison semantics | Resolves immutable comparison | Displays the selected comparison |
| File contents, diffs, existing inline threads | Fetches and normalizes | Loads through session callbacks and renders |
| File/hunk navigation, old/new panes, viewed markers | Opens selected review | Owns |
| Inline comments, multiline editing, replies, resolution controls | Translates and executes remote actions | Owns inline interaction and drafts |
| Review summary and decision | Executes provider operation | Owns submission composer and preview |
| Change-level discussion and metadata actions | Owns | Optional jump back to details |
| Persistent inline review drafts and mutation journal | Returns remote receipts/reconciliation results | Owns storage and recovery |
| Provider metadata/content cache | Owns, with connection-aware keys | Owns only session buffers |
| Standalone Git/jj review and Markdown export | Not required | Owns |

Dependency direction: ReviewHub calls Revue's documented public API; Revue
does not import ReviewHub. ReviewHub can browse without Revue installed and
offers a web link when the diff viewer is unavailable. Revue continues to
work without a provider plugin. Git/jj are local content adapters, distinct
from the GitHub/internal review-service adapters.

Provider differences stay visible through capability descriptors and native
labels. Preserve PR/CL identifiers, decision meanings, patchset identities,
and native states. Do not equate approval with merge/landing or assume every
system has Git branches, repositories, or GitHub-style review batches.

**2. User workflows and feature scope**

| Workflow | First GitHub release | Multi-provider release / later |
| --- | --- | --- |
| Discover work | Review requested, authored, open changes; repository scope; search; pagination; refresh | Saved cross-provider views; unread indicators |
| Open change | URL or explicit provider/change ID; description, reviewers, checks/status summary, timeline | Revision history and patchset-to-patchset selection |
| Review files | Read-only old/new snapshots, file and hunk navigation, additions/deletions/renames, both-side line ranges | Unified view, richer binary previews, commit-by-commit review |
| Existing discussion | Inline threads; resolved/outdated state; change-level discussion in details | Enhanced discussion filtering and notifications |
| Draft feedback | Multiline add/edit/delete, review summary, viewed state, restart recovery | Suggestions and provider-native draft synchronization |
| Publish feedback | Comment/approve/request-changes when supported; replies and thread resolution when allowed | Additional native decisions and actions |
| Handle updates | Explicit refresh; report a new revision; retain outdated anchors without silently moving them | Assisted re-anchoring and incremental review |
| Multiple systems | GitHub adapter plus non-Git contract fixture | Real internal CL provider, same core UI |
| Change lifecycle | Read current state; open provider web page | Reviewer/label edits, ready/close/reopen; merge/land only through supported explicit actions |
| Local review | Keep `:Revue [revision]`, context callback, Markdown export | Optional deliberate checkout/edit integration |

Binary, oversized, unavailable, and unsupported files must appear in the
file list with an explanation and provider link in the first release. They
must never look like empty text files or disappear. Full binary rendering is
later work. An approval or summary-only review must work without inline comments.

Suggested entry points: `:Reviews [query]`, `:ReviewOpen <url-or-id>`,
`:ReviewConnections`, `:ReviewRefresh`, and a contextual action menu.
Retain `:Revue [revision]` for local review. An unqualified numeric change ID
requires a known connection/project context. No implicit checkout occurs.

Opening an item keeps the inbox available, shows details, and enters Revue
on request. Revue uses a file sidebar, old/new panes, and a thread/composer
window opened as needed. Submission previews destination, reviewed revision,
decision, summary, and pending comments. Successful operations refresh the
relevant threads/details. Closing a view retains its draft; discarding it is
a separate deliberate action.

**3. Shared contract, version 1**

Publish the schema, validation, examples, and contract fixtures in Revue.
ReviewHub declares compatible API versions; reject incompatible major
versions before creating windows. Additive optional fields remain compatible.
There is no third runtime plugin and no provider-specific branch in Revue's
renderer. Keep serializable data separate from runtime callbacks.

| Object | Required meaning |
| --- | --- |
| ChangeKey | Provider namespace, instance/host, connection/account identity, project key, opaque change ID; never assume a numeric ID or local directory |
| ReviewSnapshot | API version, ChangeKey, display metadata, opaque snapshot/comparison ID, immutable base/head revision IDs, selected patchset, capabilities, file inventory and its completeness |
| FileChange | Stable ID within comparison, status, old/new paths, content handles for each present side, content kind, optional modes, diff availability/completeness |
| FileContent | Snapshot-bound handle, text lines plus encoding/newline metadata, or an explicit binary/too-large/unavailable result; absence is distinct from empty content |
| Diff | Comparison-bound old/new coordinates and hunk records; provider supplies or validates canonical anchors and commentable ranges |
| Thread | Opaque thread/comment IDs, author/body/timestamps, optional anchor, resolved/outdated state, and allowed actions |
| Anchor | Comparison ID, revision ID, file ID, side (`base`/`head`), original path on that side, inclusive 1-based start/end lines; file-level comments have a distinct kind |
| DraftReview | Local ID, ChangeKey and comparison, revision-aware anchors, summary, requested decision/action ID, comments/replies, persistence schema version |
| Capability | Action ID and display label, supported/enabled state, disabled reason, applicable object and constraints; advertised per change/thread and revalidated before writes |
| OperationResult | Request ID, outcome, returned data, provider receipts/IDs, per-item results where needed, structured error and retry/reconciliation guidance |

Both-side ranges refer to actual source lines, never screen rows, virtual
annotation rows, or diff filler. A range belongs to one side. Removed code
is commentable on the base side. Renames retain both paths. Outdated threads
without a valid current anchor stay accessible as outdated discussion.

Proposed public entry point:

```text
revue#review#OpenReview(snapshot, host) -> session_id

host.Request(request, Done) -> request_id
host.Cancel(request_id)

request = {session_id, generation, kind, change_key, snapshot_id, payload}
Done(result)                         # exactly one terminal result
```

Request kinds initially cover `load_file`, `load_diff`, `list_threads`,
`refresh`, `submit_review`, `reply`, `set_thread_state`, and
`reconcile_submission`. Paged reads return an opaque next cursor and explicit
completeness. Cancel is best effort; cancellation of a write does not prove
the write failed. All callbacks belong to a session, not a global provider.

Revue discards stale read results using session IDs and request generations.
Mutation receipts still update the persistent journal even if the view was
closed. Providers return structured failures such as authentication required,
permission denied, missing content, stale revision, throttled, unsupported,
transport failure, or unknown write outcome. Empty results mean successful
empty results only.

ReviewHub's adapter interface covers connection validation, list/get change,
list revisions/files/threads/timeline, load content/diff, execute action,
and reconcile write. ReviewHub translates that interface into Revue host
requests. Listing and all remote operations run asynchronously using Vim jobs
and channels, with explicit argument arrays and JSON input/output. They do
not infer connection or repository from the current working directory.

**4. Revision, draft, and submission rules**

Remote views use provider-resolved immutable snapshots for both panes. A
GitHub adapter must resolve the intended PR comparison, including its
comparison base; an internal adapter resolves the equivalent CL/patchset
comparison. Revue does not guess this from `main` or `@`. A provider must
return coherent metadata and content handles; detect and retry inconsistent
read snapshots before showing them as one review.

Local review remains a distinct mode: the default comparison can retain its
existing base-versus-working-copy meaning. Capture the working-copy contents
into a session snapshot so displayed content, signs, and anchors agree.
Refresh creates a new snapshot. Display explicitly whether disk contents or
loaded unsaved buffers were captured, and use that same source for the diff.
Bind the local backend to the session repository; later `:cd` does not change it.

Store drafts outside the repository in a configurable user state directory,
keyed by the full ChangeKey and comparison. Use atomic writes, restrictive
permissions, schema migration, and a visible save-failure state. Persist the
draft and submission intent before attempting a remote write. Store no
credentials. Default persistent content to drafts and required anchor context;
full source caching is separately configurable. Coordinate concurrent sessions
and Vim processes with a lock or optimistic generation check, so a second
writer cannot silently overwrite a draft.

Submission states are `draft`, `submitting`, `submitted`, `failed`, `partial`,
and `unknown`. A provider operation may be one atomic review or several
writes; the result must identify which items succeeded. Never discard the
whole draft on partial success. A timeout after a write requires reconciliation,
not a blind retry. Use server idempotency only where supported; local request
IDs alone do not guarantee it. When a result cannot be verified, keep the
draft and offer inspection/recovery with the provider link.

Before submitting, revalidate revision and capabilities. A new head makes the
draft stale; preserve it on its original snapshot and offer reopening the new
revision. Do not silently move comments. The adapter should pin the revision
in writes and use server preconditions where available. Providers without an
atomic freshness check must expose the limitation; a preflight check alone
cannot eliminate a race.

The legacy `g:RevueSubmitCallback(message, context)` remains a local export
adapter. A synchronous return counts as completion under that legacy contract;
an exception preserves the draft. Network hosts use the asynchronous structured
contract. Preserve the existing context pass-through behavior and documented
entry points during migration.

**5. Provider implementation choices**

GitHub first: use authenticated `gh api` jobs as the initial transport, with
an explicit hostname, endpoint, method, and JSON body. It supports REST,
GraphQL, and pagination, so it can reuse CLI authentication without storing
tokens in Vim settings. Fetch pages incrementally for the inbox; bound
concurrency for file loads. The transport choice stays behind the adapter.
[GitHub CLI API documentation](https://cli.github.com/manual/gh_api).

Map review decisions and the reviewed commit explicitly. GitHub's review API
accepts a commit ID and review event; the adapter needs to account for pending
reviews and provide receipts for the completed operation.
[GitHub review API](https://docs.github.com/en/rest/pulls/reviews).

Map structured line anchors to side and range fields. Keep top-level thread
identity when replying: the GitHub reply endpoint targets a top-level review
comment. Verify thread-state operations and permissions in the chosen API
before enabling those capabilities.
[GitHub review comment API](https://docs.github.com/en/rest/pulls/comments).

Internal CL provider: first identify the actual review-service CLI/API,
authentication method, change/patchset IDs, snapshot retrieval, comparison
semantics, comment anchors, supported decisions, and write receipts. Do not
assume Piper storage alone exposes a PR-style review API. Prefer a supported
existing internal CLI or plugin; normalize its output in the companion's
adapter. The real provider task is conditional on that interface and access,
but the GitHub release and non-Git fixture work are independent of it.

**6. Implementation layout**

| Repository | Proposed modules and changes |
| --- | --- |
| vim-code-review | Keep `plugin/revue.vim` for commands and `review.vim` as the facade; extract `session.vim`, `model.vim`, `diff.vim`, `draft.vim`, `submit.vim`, `ui/`, and `source/local.vim` as their tasks land |
| vim-code-review | Keep Git/jj implementations under `vcs/`; change dispatch to a repository-bound adapter; add contract docs and fixtures under `doc/` and `test/` |
| vim-code-review-github | `plugin/reviewhub.vim`; `autoload/reviewhub/{connections,providers,inbox,details,transport,cache,bridge}.vim`; adapters under `providers/{github,internal}.vim`; tests and help |

Extract modules incrementally with behavior tests. Do not start with a large
rewrite or build a generic plugin framework. Keep provider calls out of UI
modules and Vim window commands out of provider adapters.

**7. Prioritized work packages**

Priority meanings: P0 fixes current unsafe or destructive behavior; P1 is
required for the first usable GitHub release; P2 completes real multi-provider
support and broader review workflows; P3 is later enhancement. Dependencies
determine execution order within a priority. These are work packages to split
into small PRs; they are not calendar estimates.

| ID | Priority | Owner | Task and completion criteria | Depends on |
| --- | --- | --- | --- | --- |
| R01 | P0 | Revue | Remove filename command execution: generated scratch names, escaped Ex arguments, safe content handling. Hostile filename fixture cannot execute a command; remote content has modelines disabled. | — |
| R02 | P0 | Revue | Fix active selection capture. First/repeated/reversed selections produce the selected source range. | — |
| R03 | P0 | Revue | Call legacy submit before destructive cleanup. Throwing callback or clipboard failure retains comments and allows retry. | — |
| R04 | P0 | Revue | Fix lifecycle ownership: stable window/session IDs, unique scratch buffers, teardown on manual closure, restored mappings/options/signs/annotations. Two same-file reviews and tab reorder/closure do not affect other work. | — |
| D01 | P1 | Both | Publish v1 schema, capability rules, result semantics, and example payloads. Validate Git-like and CL-like fixtures before freezing the interface. | — |
| D02 | P1 | ReviewHub | Discover internal provider interface and record a capability/anchor matrix, sample sanitized responses, access requirements, and unknowns. This is discovery, not a promise of working integration. | — |
| R05 | P1 | Revue | Repair local adapters: filename encoding, jj rename/subdirectory handling, root-bound dispatch, explicit errors. Git/jj fixture matrix passes. | R01 |
| R06 | P1 | Revue | Normalize diffs and source coordinates. Actual changed lines receive signs; base-side deletion comments and renames resolve correctly; binary/unavailable content is explicit. | R02, R05, D01 |
| R07 | P1 | Revue | Introduce session model and `OpenReview`; render host-supplied immutable content without a checkout or Git/jj binary. Preserve local API compatibility. | R04, D01 |
| R08 | P1 | Revue | Add structured multiline drafts, summary/decision composer, edit/delete, and viewed markers; persist and restore by snapshot with conflict detection. | R06, R07 |
| H01 | P1 | ReviewHub | Scaffold companion, adapter registration, explicit connections, asynchronous transport, cancellation, structured errors and pagination. Fake jobs test timing and errors. | D01 |
| H02 | P1 | ReviewHub | Build inbox and change details against a fake provider: filters/search, loading/empty/error states, page loading, open URL/ID, checks/timeline summary. | H01 |
| H03 | P1 | Both | Connect a fixture provider to `OpenReview`. A CL-shaped change with opaque IDs, patchsets, different action labels, and no local repo exercises the same UI. | R07, H02 |
| H04 | P1 | ReviewHub | Implement GitHub reads: lists/details, pinned files/diff, complete thread retrieval, pagination, permissions and supported actions. Verify against a controlled repository. | H01, H03 |
| R09 | P1 | Revue | Render existing threads, unresolved/outdated state, base/head anchors, and reply/resolution controls. Missing current anchors remain visible. | R06, R07, H03 |
| R10 | P1 | Revue | Implement async submission state machine and durable journal; partial/unknown outcomes retain recoverable items, stale heads require review. | R03, R08, D01 |
| H05 | P1 | ReviewHub | Implement GitHub review writes, replies, thread-state actions, permission revalidation and receipt reconciliation. Approval/summary-only review works. | H04, R09, R10 |
| Q01 | P1 | Both | Run the complete GitHub acceptance workflow, fault injection, compatibility and responsiveness checks; document installation/configuration. | R01–R10, H01–H05 |
| H06 | P2 | ReviewHub | Implement real internal reads against the verified supported interface: list/get CL, patchsets, immutable files/diffs, discussions. | D02, H03 |
| H07 | P2 | ReviewHub | Implement internal writes and reconciliation according to native semantics; disable unsupported actions accurately. | H06, R10 |
| Q02 | P2 | Both | Run the same provider contract suite and real acceptance workflow for GitHub and the internal service. Any necessary schema changes preserve documented compatibility. | Q01, H07 |
| H08 | P2 | ReviewHub | Add saved queries, multi-connection inbox, richer checks/history and supported metadata actions. | Q01 |
| R11 | P2 | Revue | Add explicit patchset comparison selection and assisted draft migration with user-visible anchor validation. | Q02 |
| E01 | P3 | Revue | Unified diff, suggestions, richer binary previews, advanced discussion filters. | Q01 |
| E02 | P3 | ReviewHub | Notifications, deliberate checkout/edit integration, merge/land and other provider lifecycle actions. | Q02 |

Start R01–R04 immediately. Run D01/D02 as early design work so later
implementation does not bake in GitHub assumptions. Finish the no-checkout
fixture integration H03 before adding real remote writes. H04 can yield a
useful browsing/read-only milestone; H05 and Q01 make it a usable review tool.
Q02, not a mock provider, is the multi-provider release gate.

**8. Milestones and acceptance gates**

| Milestone | Demonstration required |
| --- | --- |
| Safe local foundation | Filename regression is closed; selections are correct; failed export retains drafts; multiple sessions survive tab changes; Git/jj path and diff tests pass |
| Composable viewer | ReviewHub fixture opens Git-like and CL-like snapshots through the same API; no checkout is needed; old/new contents and anchors are coherent |
| GitHub read-only preview | Browse actual PRs, open full details/files/discussions, handle pagination/errors, preserve editor responsiveness |
| GitHub review release | Browse → open → comment on either side → edit draft → restart → resume → submit/reply/resolve → see acknowledged server state; summary-only decisions also work |
| Multi-provider release | Repeat supported workflows on the real internal service; unsupported capabilities are represented accurately; no provider-specific renderer changes |

Each write-path gate includes permission denial, changed head, partial result,
timeout after server acceptance, and restart during submission. Verify no
lost draft and no automatic duplicate write. Live mutation smoke tests use
designated test changes and explicit test credentials; normal CI is offline.

**9. Verification strategy**

Extend the current runner beyond its two smoke tests. Add temporary Git/jj
repositories, deterministic fake provider jobs, schema fixtures, and Vim UI
integration scripts. Verify the documented minimum Vim version in CI; report
optional jj integration tests separately when its executable is unavailable.

Required regression cases include pipes/quotes/Unicode/tabs/newlines in
filenames; jj renames and nested working directories; invalid revisions;
diverged comparison histories; empty/binary/deleted/renamed files; blank lines
and missing final newline; source-side line coordinates; multiple sessions;
manual buffer/tab close; stale asynchronous responses; and restoration of the
user's mappings, highlights, and working buffers. Opening a remote change
must not edit or overwrite a user's existing file buffer.

Contract tests cover paginated and incomplete inventories, expired credentials,
permission changes, rate limits, absent content, outdated threads, and capability
differences. Draft tests cover atomic recovery, concurrent writers, schema
migration, partial acknowledgments, unknown outcomes and reconciliation. Fake
slow responses verify that input/navigation remain usable and request counts
stay bounded; lazy file loading must not fetch every large file up front.

**10. Decisions to revisit when more context is available**

The companion name and choice to reuse an existing provider plugin are open.
The default transport is `gh api`; an existing internal CLI/API determines the
second adapter. GitHub is the default first delivery target, not a dependency
of Revue's contract. Internal access is required only for D02/H06/H07/Q02;
absence of that access does not block the standalone fixes, shared interface,
fixture bridge, or GitHub release.

Do not expand the first release into branch management, patch application,
an issue tracker, or a universal provider framework. Finish the end-to-end
review workflow and prove the two-plugin boundary first.
