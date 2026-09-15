# Provider integration (version 1)

## Backend bindings

`revue#backend#Open(backend, file_index)` is the shared entry point for new
backends. A binding supplies `{id, connection, review, snapshot, Request}`:
the backend name, connection identity, backend-owned review identity, initial
version-1 snapshot, and a session-scoped callback. `Request(request, Done)`
implements both reads and supported writes using the operations below.
There is no separate destination contract or required global registry.

Revue qualifies snapshot keys using backend, connection, and review identity
and preserves that binding on refresh. This isolates tabs and pending drafts
across connections. Accepted conversation state and persistence belong to the
backend. Shared draft files hold an outbox for unsent or uncertain operations
plus local delivery/read metadata; they do not mirror accepted conversations.
Remote backends do not load the bundled local backend or its SQLite database.

Single-suggestion application uses a backend-declared destination, a read-only
plan and exact-intent mutation receipt. See the
[application contract](suggestion-application.md#backend-contract). The bundled
local backend saves a workspace file and captures the resulting saved source;
it does not create a GitHub-style commit.

The existing entry point below is a compatibility adapter. It preserves the
original snapshot key and saved draft location; existing providers need no
changes. Calling `revue#session#Open` directly remains supported internally.

## Read-only readiness extension

The optional `readiness` capability supplies head-bound check and requirement
observations through `op: readiness`. The shared view supports explicit reload,
paging, cancellation and source links. See the [complete contract](readiness.md#backend-contract).
Completeness refers to reported checks, not all repository policy. No readiness
operation writes or authorizes a merge; local backends may report unavailable.

## Native pending review extension

Native pending state is supplied as `snapshot.pending_reviews: {available,
actor, items, error?}`. An unavailable actor or failed/incomplete read is not
an empty inventory. Each item contains opaque `id`, verified `actor`, display
`author`, immutable reviewed `head`, summary `body`, opaque `version`, `state:
"pending"`, `url` and full `comments`. Comment entries carry exact `message`,
`message_kind`, root `thread`, `path`, `side`, `start`, `line`, `subject_type?`,
`author` and raw `body`. The pending version covers both summary and the complete
comment set/anchors. These are server conversation objects, not outbox drafts.

GitHub filters native pending reviews to the verified actor, reads each review's
private comments through its review-specific endpoint, and merges those IDs
into the discussion once. A pending root disables published reply/resolution
actions until the native review is published. Unknown ownership/read failure
is explicit; another actor's pending summary is never imported. This filtering
does not erase previously saved local caches when accounts change.

`:RevuePending` exposes inventory, summary, private comments and reviewed source.
`:RevueOpenPending` navigates to the exact loaded message, retaining return
context. A changed/disappeared selection becomes inert on refresh. Optional
`capabilities.submit_pending` enables `:RevuePublishPending [event]`, which uses
the backend's review action IDs and permissions. A durable `submit_pending`
draft stores native `pending_review`, `actor`, `expected_version`,
`pending_head`, full frozen `pending_comments`, selected `event`, editable
summary `body`, and normal comparison/operation fields. Local outbox feedback
is excluded. This operation is separate from batch submission.

Publication preview shows all included private comments and your summary.
When the server changes, it also shows current server summary/comments.
`:RevuePendingBase` explicitly accepts refreshed pending contents and comparison
after confirmation, preserving the user's summary. It cannot alter an unknown
publication. The backend checks exact ownership, version/comment set, decision
permission and the PR source refs before submitting the existing review ID.
Its original reviewed revision remains explicit, including when older than the
current comparison. Published decision metadata can include `reviewed_head`.

GitHub's submission endpoint has no atomic version precondition: a comment
change after preflight can race publication. This is checked preflight, not
atomic synchronization. Receipt `{id: operation_id, pending_review, actor,
event, url}` must match the frozen operation. A `revue-publish` marker binds
the source/contents/summary/decision to the operation and preserves earlier
receipt markers. Recovery reads the existing review and never submits it again;
later dismissal does not erase its prior publication receipt. Missing or
malformed success remains unknown. No live GitHub publication was used in tests.

Optional `capabilities.discard_pending` enables `:RevueDiscardPending` on a
selected native review. It prepares a read-only operation and immediately opens
a full preview of the private summary and every comment to be removed. The
operation freezes `pending_review`, `actor`, `expected_version`, `pending_head`,
`pending_comments`, `pending_body` and normal comparison/operation fields; `body`
is empty. `:RevueSend` requires a Delete confirmation. `:RevueDiscard` cancels
only this local operation. Neither action includes unrelated outbox drafts.
Existing publication/discard operations for the same native ID are reused,
including unknown operations. Changing intent requires cancelling the known
local operation first. A changed private review requires a new preview and
operation; PendingBase cannot retarget a discard.

The GitHub adapter rechecks the actor, ownership, pending state and entire frozen
contents before DELETE `/pulls/{number}/reviews/{id}`. It does not require that
the PR source is still the latest: the exact selected private review is the
object being removed. Published reviews are rejected. A matching response
produces `{id: operation_id, pending_review, actor, discarded: true}`. A malformed
or uncertain write freezes the operation. Reconciliation verifies the same
actor and successfully reads the complete reviews list. If the ID is absent it
returns `observed: true`, labeled as absence for that actor, not proof that this
operation caused deletion. Present IDs, lost authentication and failed reads
remain uncertain. Reconciliation never repeats DELETE. A bare 404 is not enough.
GitHub provides no atomic content/version precondition for this endpoint, so
another client's change after preflight can still race deletion. No live GitHub
review was deleted during verification.

### Individual private-comment deletion

Optional `capabilities.delete_pending_comment: {enabled, body_required: false}`
and message `capabilities.delete: {enabled, scope: "message", reason?}` expose
`:RevueDeletePendingComment`. A root's scope must be established before enabling
it. GitHub currently disables roots with replies; replies and roots without
replies are supported. Review summaries and published feedback are separate.

The read-only operation has `kind: "delete_pending_comment"`, empty `body`,
`message`, `message_kind: "comment"`, `thread`, `pending_review`, `pending_head`,
`actor`, `delete_scope: "message"`, `expected_version`, `original_body`, plus
normal operation/comparison identity. Frozen `path`, `anchor_label` and
`message_author` provide display context; message IDs define deletion identity.
Preparation opens the complete original
body and exact target. A refreshed body is shown separately. Changed contents
require cancelling and preparing a new operation; EditBase cannot retarget it.
Pending publication/discard, private saves and edits surface an unfinished
deletion before continuing, including an uncertain deletion after restart.

The GitHub adapter verifies the actor, review-specific comment membership,
parent state/head, message version/body, thread and author. It checks live
GraphQL `viewerCanDelete` for the comment's opaque node ID and pending parent.
Root deletion also checks for replies in both private and PR comment inventories.
Only then does it call DELETE `/pulls/comments/{message}`. The documented empty
response produces `{id: operation_id, message, message_kind, thread,
pending_review, actor, delete_scope: "message", deleted: true}`. All these fields
must match the retained Vim operation; malformed success becomes unknown.

Recovery never sends DELETE. It verifies the same actor and parent ownership,
then reads the complete review-specific comment inventory. Absence returns the
same receipt with `observed: true`, even if the parent was since published.
Present IDs, a missing parent, 404/access loss and failed/incomplete reads cannot
establish absence. Observed absence does not identify who removed the comment.
GitHub has no documented conditional-delete version/state field; another client
can change content or publication after preflight. Live mutation verification
and root-with-replies behavior remain outstanding.

Sources: [REST review-comment deletion](https://docs.github.com/en/rest/pulls/comments#delete-a-review-comment-for-a-pull-request),
[GraphQL comment permission fields](https://docs.github.com/en/graphql/reference/pulls#pullrequestreviewcomment).

Private editing uses the existing `edit` operation with explicit
`pending_review` and `actor` fields. Optional `capabilities.edit_pending` must
allow it, in addition to normal snapshot/message edit capabilities. Native
pending items provide a `summary` message with `kind: "PENDING"`, `id` equal to
the native review ID, normalized body/version, `publication: "pending"`,
`pending_review`, `actor`, and `capabilities.edit`. Private inline messages carry
the same pending identity fields and their own message versions. Summary
`capabilities.edit.body_required: false` permits clearing a private summary;
inline comments still require text.

`:RevueEditPending` edits the selected summary or exact comment in the inventory.
`:RevueEditMessage` also works from a focused private discussion. Both use the
same original/current/proposed preview and `:RevueEditBase` conflict workflow.
The confirmation says Save privately. An unavailable, changed-owner or published
review retains the edit and cannot be accepted as a public edit via EditBase.
Publish/discard opens an unfinished edit for that native review first; editing
opens an existing publication/discard instead. Different private messages may
have separate drafts, but all must be completed or cancelled before publication.
Uncertain work can only reconcile.

The GitHub adapter proves comment membership using `/reviews/{id}/comments`,
fetches the exact object and pending parent, checks both owners and the selected
message version/body, then PATCHes the comment or PUTs the summary with only a
`body` field. No submit event is sent. Receipts include the private review ID and
actor, and the edit marker digest binds those fields too. Earlier published-edit
markers retain their original digest format. Recovery reads without writing and
can find an edit marker after subsequent browser publication. Lost/malformed
receipts stay unknown. As with published edits, GitHub has no atomic version or
pending-state precondition: a browser edit or publication after preflight can
race this write, including making the target public before the update arrives.
The client labels current publication state only after refresh. Authenticated
live private editing remains an integration gate; tests use fixtures.

Optional `capabilities.start_pending` enables `:RevueStartPending`, an editable
optional-summary draft with kind `start_pending`, `pending_mode: "create"`,
`pending_review: ""`, verified `actor`, and normal comparison/operation fields.
`:w` remains a local save; Send confirms Save privately and creates the native
review. An existing native review opens the inventory instead. An unfinished
creation is reused, including after restart.

Optional `capabilities.save_pending: {enabled, kinds}` enables
`:RevueSavePending` in a `comment` (including suggestion) or `file_comment` draft.
This explicitly prepares private delivery and opens preview, preserving its
text and source anchor. No backend write occurs until Send. With no native
review, an inline comment binds `pending_mode: "create"`; with one review it
binds `pending_mode: "add"`, `pending_review`, `pending_head`, and `actor`.
Multiple native reviews require further selection rather than guessing.
Whole-file feedback currently requires an existing native review. Saved private
drafts cannot enter a publishing batch; both client and GitHub adapter reject
that combination. Publication/discard first reopens unfinished additions. An
uncertain creation also blocks editing/publishing/discarding newly visible
native reviews until its receipt is checked. This prevents switching operations
to bypass unresolved delivery.

The GitHub adapter creates through POST `/pulls/{number}/reviews` with
`commit_id`, summary body, and optional first inline comment, omitting `event`.
It refuses a second actor-owned pending review. Creation checks current head/base,
actor, file identity and full selected diff range. Whole-file additions and
single/multi-line additions use GraphQL `addPullRequestReviewThread` with the
verified parent's `node_id` as `pullRequestReviewId`, body, path and `subjectType`;
line additions also include side/range. The parent must still be pending, owned
by the actor and refer to the draft's current head. Adding to an older pending
source is explicitly unavailable. Additions do not overwrite other comments or
require an unchanged comment-set version. Replies use the separate thread-ID
workflow below.

Private-save receipts are `{id: operation_id, pending_mode, pending_review,
actor, url?}` and must match the prepared target. A `revue-pending` marker binds
mode, actor, comparison, source anchor, suggestion intent and exact body. For
first-comment creation, both the review and its comment must have matching
receipts; a missing comment or failed verification read leaves the outcome
unknown. Additions validate the returned native parent ID and comment marker.
Reconciliation reads the review or its comment list, including after browser
publication, and never repeats creation/addition. A deleted receipt remains
unknown. Earlier marker types are preserved by edits and publication. API source
checks remain preflight and cannot atomically prevent all concurrent changes.
No live authenticated creation/addition has been exercised.
[GitHub pending review threads](https://docs.github.com/en/graphql/reference/pulls#addpullrequestreviewthread).

Private replies use kind `reply`, `pending_mode: "add"`, exact root `thread`,
`pending_review`, `pending_head` and `actor`. They require an existing pending
review, `capabilities.save_pending.kinds` containing `reply`, and the thread's
explicit `capabilities.pending_reply.enabled`. Public reply permission is
independent: disabling it does not disable a separately permitted private reply.
GitHub derives pending_reply from the verified actor, native thread identity and
GraphQL viewerCanReply. Private roots continue to disable public reply and
resolution actions, while their card footer offers Reply privately.

`:RevueReplyPending` explicitly creates a private reply to a selected thread;
`:RevueSavePending` can explicitly convert an editable ordinary reply draft.
Ordinary Reply and Quote automatically bind private delivery when the root or
selected message is pending. Ordinary replies to published messages stay public.
Existing replies retain text and delivery mode; changing a public draft to private
requires SavePending. Private quotes append to a matching editable reply only;
uncertain or incompatible drafts reopen without appending or creating another.
An existing uncertain private reply remains reachable after browser publication
or loss of the native pending inventory. Unrelated drafts remain untouched.

GitHub uses `addPullRequestReviewThreadReply` with both the verified pending
review node ID and the current thread node ID. The latter is resolved from that
PR's current thread inventory and checked for reply permission. The mutation has
no line coordinates, review event or resolution action. Replies may target old
or outdated discussions: the pending reviewed head must match the frozen
pending_head, but need not equal the current source head. New line/file threads
retain their stricter current-source requirements.

Private reply receipt markers additionally bind `thread`, without changing old
non-reply marker formats. Receipts include `thread`, and the returned parent
review ID, replyTo root ID and marker must match. Recovery validates the REST
comment's review ID and in_reply_to_id, including after browser publication;
missing, ambiguous or mismatched receipts stay unknown. No recovery write occurs.
Live authenticated private replies remain unverified; fixture and real-Vim tests
cover this flow. Source/state preflight is not an atomic server-side guarantee.
[GitHub review-thread replies](https://docs.github.com/en/graphql/reference/pulls#addpullrequestreviewthreadreply).

Standalone private-comment deletion remains open. Local backends do not emulate
a GitHub pending review. Their accepted feedback and the shared outbox retain
their existing meanings.
[GitHub review endpoints](https://docs.github.com/en/rest/pulls/reviews).

## Private staging queues

The optional `capabilities.stage_batch` object has `enabled`, `reason`,
`mode: "sequential"`, supported `kinds`, and optional nonnegative integer
`min_interval_ms`. This authorizes client orchestration of the existing private
save operations; it does not add a backend batch mutation or a second destination.
GitHub advertises comment/file_comment/reply and a 1000 ms interval, following
its recommendation to space mutative requests.
[GitHub API guidance](https://docs.github.com/en/rest/using-the-rest-api/best-practices-for-using-the-rest-api).

`:RevueStageBatch` previews the selected bodies, actor, comparison, and native
review (or creation intent). All selected items must have the same latest
comparison. Review decisions, other unsupported kinds, already prepared private
operations, and unselected drafts remain outside the queue. No decision is
silently converted into a private summary. Without a native review, an explicit
creation step uses `start_pending` with an empty summary; subsequent additions
bind the receipt's exact native ID and the original head. This supports a first
file comment or reply without pretending they are line comments.

The locally persisted parent has `kind: "batch"`, `delivery: "private"`, original
`items`, `actor`, `pending_review`, `pending_head`, `private_mode`, and `steps`.
Each step has an original `item` ID (empty for native creation), a complete
private-save `draft` with a distinct operation ID, `state`, and eventual
`receipt`/`error`. Step states are waiting, submitting, accepted, failed, unknown.
The UI calls accepted "saved" and waiting "not saved". Original bodies and
anchors remain frozen; only the initially unknown native ID is bound after a
verified creation receipt. Per-step bodies use the existing receipt fingerprint.

Before each backend call, the submitting step is persisted. Each accepted
receipt is persisted before dispatching another write. A failure stops the
queue. Parent `failed` means paused and can include already accepted steps;
the step inventory supplies the actual outcome of every item. Unknown or
interrupted submitting steps reconcile through the existing single-save read
path. Receipt recovery never begins a waiting write. A new confirmation resumes
only known-unsaved steps. If the process stops between steps, recovery observes
that no uncertain request remains and requires confirmation for the rest.

Exact operation, actor, create/add mode, native review and reply-thread receipts
are checked. Missing/mismatched receipts and failed post-acceptance local saves
freeze the affected step. Permission/comparison changes retain results and stop
new writes. Backend preflight still verifies current source, ownership and native
pending state for each addition; local receipt knowledge is not a claim of an
atomic server transaction or protection against concurrent browser publication.

Unpacking a known paused queue restores only unsaved original items. It never
reposts accepted items, deletes native feedback, or deletes an empty review that
was successfully created. An unknown queue cannot be unpacked. Native
publication/discard and conflicting private actions surface the existing queue.
Completion aggregates per-item receipts using the original draft IDs. The normal
public atomic batch endpoint and its receipt contract remain separate.

`test/staging.py` verifies four real Vim processes, new/existing reviews, mixed
file/reply/suggestion items, preserved review decisions, partial failures,
interrupted submissions, wrong-review receipts, persistence failure, safe unpack,
same-operation resume, and receipt-only recovery after permission loss. Fixture
writes only; authenticated GitHub staging remains an unexecuted release check.

## Message reactions extension

Messages may contain `reactions: {items, complete}`. Each item has backend ID,
display `label`, nonnegative integer `count`, and optional boolean `mine`.
Missing `mine` means unknown actor state, never false. Cards and real-text
discussions show positive counts and `[you]` only when explicitly supplied;
this footer stays outside the raw body used by copy/quote. Counts alone do not
grant permission to remove a reaction.

Optional `snapshot.capabilities.reactions.enabled` and message-specific
`capabilities.reactions.enabled` enable `op: "reactions", target: {message,
message_kind, thread}`. The backend returns `{items, complete: true, actor,
actor_label?}` with all supported reaction choices, including zero counts.
`actor` is a stable backend actor identity; empty means unavailable. The UI
requires complete, valid data before enabling selection and distinguishes
loading/error from zero reactions. Detail reads are lazy, scoped to one message;
late callbacks cannot replace another panel or a returned discussion.

A detail item may additionally contain `members: {items: [{id, label}],
unavailable: N}`. IDs are stable backend actor identities, unique within that
reaction. Each returned person accounts for one reaction; the item count must
equal `len(members.items) + unavailable`. `unavailable` counts reactions whose
account details cannot be shown (for example a deleted account). Omitted
`members` means the backend did not supply participant details, never that nobody
reacted. Counts and identities describe the completed read, not a subscription
or an atomic snapshot across service pages. Paging failures reject the read;
GitHub's existing list reader caps retrieval at 100 pages.

The chooser retains compact Add/Remove choices, then lists people grouped by
reaction in a read-only section. Participant rows cannot execute reaction
writes. Own membership uses stable identity, not a matching display name. Names
remain readable when the viewer's identity is unavailable. Reload uses
`:RevueReactions`; close returns to the selected message. No extra network call
is added: GitHub retains user fields already present in its lazy reaction list;
local membership details are included only on the detail read, not every card.

Writes additionally require snapshot and message `capabilities.reaction.enabled`.
A normal durable draft uses `kind: "reaction"`, exact message/kind/thread,
`reaction` ID, `reaction_label`, `actor`, optional `actor_label`, boolean `present`
and empty `body`. An explicit Add/Remove choice sends in place; there is no
separate operation-buffer or confirmation detour. Reopening a pending choice retains the original intent, including
unknown operations. These drafts are sent separately from review batches.

Receipt fields `{id, message, message_kind, thread, actor, reaction, present}`
must match the frozen request exactly. A malformed receipt remains unknown.
Local state changes and receipts share a transaction; membership and removal
are scoped to the review owner's actor. Earlier receipts do not reapply a
reaction that was subsequently removed. Reactions change neither body/version
nor thread resolution nor review decisions.

GitHub supports published inline and issue-conversation comments here; review
summary and pending-review reactions remain unsupported. It validates PR/thread
membership, loads the current actor and the message's reaction list, and removes
only that actor's exact reaction ID. After a write it verifies the resulting
state. Reconciliation only observes state: `observed: true` establishes the
desired state at read time, not which attempt caused it. Actor changes, missing
targets, unavailable reads, or the opposite state keep an uncertain operation
unresolved. No reaction write is automatically repeated. Summary counts in a
refreshed snapshot may lack actor state until detail is reloaded; no extra
per-message list calls are made during initial review load.
[GitHub reaction endpoints](https://docs.github.com/en/rest/reactions/reactions).

## Published-message editing extension

Editing requires both `snapshot.capabilities.edit.enabled` and the selected
message's `capabilities.edit.enabled`; missing metadata never grants permission.
The backend supplies an opaque nonempty message `version`. The UI never derives
permissions from authorship labels. A draft carries `kind: "edit"`, `message`
(the exact message ID), `message_kind` (its normalized kind), `thread` (root ID,
or empty for conversation), `expected_version`, `original_body`, and replacement
`body`, plus normal operation/comparison fields. Reopening the same target keeps
the existing draft. Edits are submitted separately from review batches.

Before writing, validate review membership, exact thread/message/kind, actor,
version and original body. A version conflict preserves the draft. The preview
shows original and proposed text plus the current message when it differs.
`:RevueRefresh` is also available in the composer without a default mapping.
`:RevueEditBase` explicitly accepts the latest loaded version after confirmation,
retaining replacement text; it does not merge content. Missing/deleted targets
and frozen operations cannot acquire a new edit base.

An accepted edit returns `{id: operation_id, message, message_kind, thread, url}`.
All target fields must match the frozen operation; malformed success is unknown.
Receipt-only recovery bypasses current edit availability and never writes again.
The UI removes an accepted draft and refreshes the conversation while preserving
the selected message ID. Durable activity identifies the message, not just its
thread. Historical comparison navigation does not change conversation identity.

The local backend serializes version checks and replacement in one SQLite
transaction. Each edit gets a new version, even when text returns to a previous
value. Backend events retain before/after bodies and the receipt. Accepted
creation receipts remain valid after editing. Current local policy allows edits
to feedback authored by the review owner; future participant policy belongs to
that backend, not the UI.

GitHub supports the actor's own published inline replies/root comments, general
conversation comments and review-summary bodies. It validates membership by
listing the PR's messages, then fetches the exact current object and checks its
body/version before PATCH/PUT. The documented endpoint does **not** provide an
atomic expected-version parameter: a concurrent external write after this
preflight can race. Do not claim atomic conflict protection for GitHub. Private pending review edits are described above; moderator edits, delete and
edit-history browsing remain separate work. These endpoints change body text, not the review decision.

GitHub appends a `revue-edit` receipt marker containing the operation ID and a
digest of its exact target/base/replacement. It preserves earlier creation,
batch and edit markers so later edits do not erase prior recoverability. Marker
removal/deletion outside Revue can make reconciliation inconclusive; it never
authorizes a repeat update. Normalized body text hides receipt markers and
retains surrounding user whitespace. Actual GitHub writes have not been used
for verification; tests inspect exact transport requests and recovery behavior.
[Review comment updates](https://docs.github.com/en/rest/pulls/comments#update-a-review-comment-for-a-pull-request),
[conversation comment updates](https://docs.github.com/en/rest/issues/comments#update-an-issue-comment),
[review summary updates](https://docs.github.com/en/rest/pulls/reviews#update-a-review-for-a-pull-request).

## Existing provider entry point

`revue#review#OpenReview(snapshot, Host, file_index)` opens a provider-supplied
review and returns its session ID. `file_index = -1` opens the conversation;
otherwise it selects a zero-based changed-file index. Reopening an existing
visible change focuses its session. The local `:Revue` interface is unchanged.

`Host` is a session-scoped Funcref accepting `(request, Done)`. It starts an
asynchronous operation and calls `Done(result)` once. `result` is either
`{ok: true, data: ...}` or `{ok: false, error: message, unknown: boolean}`.
An uncertain write outcome must set `unknown`; Revue retains and locks the
draft and requests reconciliation without automatically reposting it.

The snapshot contains:

- `version: 1`, stable provider/host/project/change `key`, `display_id`,
  `title`, `author`, `state`, `body`, `url`, and `reviewers`.
- Immutable `base`, `head`, `snapshot` comparison ID, and optional
  `base_tip` for providers whose comparison base differs from the target tip.
- `files`: `{id, path, old_path, status, patch}`. `patch` is unified diff
  text used to validate source-line ranges under the default hunk scope.
  Backends may declare whole changed-file scope below. `path` is the new/canonical path;
  `old_path` preserves the original name. Absent sides are never fake text.
- `threads`: `{id, path, side, line, start, outdated, hunk?, comments}`.
  `side` is `base` or `head`. An outdated thread remains readable and replyable
  without claiming that its original anchor is current.
  Optional `subject_type: "file"` instead identifies a whole-file discussion;
  `side: ""`, `start: 0`, `line: 0` are non-coordinate sentinels. Missing
  `subject_type` retains the legacy line interpretation. Never infer a file
  discussion from an absent line: an outdated line comment is a different target.
  Optional `resolved` is a boolean independent of `outdated`; omit it when
  unavailable. Optional `resolved_by` is a display name. Resolution does not
  collapse the thread or change its anchor. `native_id` may carry an adapter's
  own mutation identity while `id` remains stable for replies and saved drafts.
- `conversation`: comment/review entries with `id`, `author`, `body`,
  `created`, and `kind`. Thread `comments` use the same entry structure.
- Optional message metadata: `author_role` is a backend-supplied display label;
  `author_type: "bot"` identifies an explicitly known bot. `updated` is the known
  update timestamp; `edited: true` requires evidence of an actual edit. Revue
  does not infer editing solely from `updated != created`. `publication` may be
  `pending` (native pending review) or `local` (accepted in the local backend).
  Unknown/missing publication is left unlabeled. `decision` is an optional
  backend-native review decision label. These fields carry no permissions.
  Headers sanitize metadata to one line and wrap it, while body copy/quote
  remains exact Markdown. The source card and focused discussion share labels.
- `review_actions`: `{id, label}` entries. Action IDs are opaque to Revue;
  an adapter may offer native decisions rather than GitHub's labels.
  Optional `enabled`, `reason`, and `body_required` describe availability and
  validation. Missing values default to enabled and body required.
- Optional `capabilities`: action-kind keys (`comment`, `file_comment`, `reply`, `conversation`,
  `review`, `thread_state`, `capture`, `comparisons`, `comparison_range`, `thread_context`, `edit`, `reactions`, `reaction`, `pending_reviews`, `start_pending`, `save_pending`, `edit_pending`, `submit_pending`, `discard_pending`, `delete_pending_comment`) mapping to `{enabled, reason?, body_required?}`. When this object is
  present, omitted kinds are unsupported. Without it, existing version-1
  adapters retain their prior behavior. Threads may supply
  `capabilities.reply` to further restrict replies; this cannot widen the
  review's permissions. Unknown review-action IDs are always rejected.
  Thread resolution always requires explicit opt-in and target-specific
  `capabilities.resolve` / `capabilities.reopen`; legacy fallback cannot enable it.
- Optional `submit_label` and `submit_target` customize the confirmation and
  composer action. Defaults retain the existing Send behavior. The local
  backend uses Save and a local review label. Submission still calls `mutate`.

Host request operations:

| `op` | Request | Result data |
| --- | --- | --- |
| `file` | `snapshot`, `file` | `base` and `head`, each with `kind`, `lines`, optional `message` |
| `refresh` | No extra fields | Updated latest snapshot; a changed comparison is retained for explicit navigation without moving drafts |
| `comparisons` | No extra fields; optional capability | `{items, complete, scope, latest?}` immutable references and optional current snapshot |
| `comparison` | `reference` | Snapshot for that exact immutable reference |
| `comparison_range` | `selection: {from, to}`; optional capability | Full derived snapshot with matching `range` and exact endpoint `base`/`head` |
| `thread_context` | `target: {thread, token}`; optional capability | `{thread, token, snapshot, location}` for verified original discussion source |
| `reactions` | `target` | Complete supported reaction choices/counts and known actor state for one message |
| `mutate` | `draft`, `reconcile` | Provider receipt `{id, url}`, optionally `recovered` |

Content kinds are `text`, `absent`, `binary`, or `unavailable`. Source windows
are read-only, have modelines disabled, and use generated internal names.
The UI uses actual source lines, not diff-filler or annotation rows.

Draft kinds are `comment`, `file_comment`, `reply`, `conversation`, `review`, `thread_state`, `capture`, `edit`, `reaction`, `submit_pending`, `discard_pending`, `delete_pending_comment`, or `start_pending`. All include
`id`, `body`, `state`, `head`, `base_tip`, and `snapshot`. Inline comments also
include `path`, `old_path`, `side`, `start`, and `end`; ranges are inclusive and
1-based. File comments include only `path` and `old_path`, with no `side`,
`start`, `end` or `line`. Replies include a root `thread` ID; reviews include the opaque
provider action in `event`. Validate permissions, anchors, revision freshness,
and supported actions at the provider boundary before writing.

Revue owns persistent drafts and rejects conflicting saves from another Vim.
The host owns authentication, networking, provider IDs, posting, and receipt
reconciliation. It must not interpret `reconcile: true` as permission to
create another remote comment. Individual sends remain supported alongside the
batch contract below. Thread-state operations use the extension below.

An unsuccessful receipt read must retain an earlier unknown write outcome even
if the read failure itself has `unknown: false`. Revue carries reconciliation
intent through callbacks, keeps the operation immutable, and disallows discard
or batch unpacking until resolved. `:RevueCheckReceipt` performs only recovery;
it does not turn a failed initial draft into a new submission.

Capability rules are checked before draft creation and before submission.
Refresh updates them without discarding drafts. Body requirements are per
action: a backend can accept an opaque decision without prose, while ordinary
comments still require content. A failed/unknown draft is retained; receipt-only
reconciliation bypasses current write availability and body validation because
it must never create new feedback. The backend must independently authorize
each actual write; UI metadata is not an authorization token.

The GitHub adapter reports known authentication/actor restrictions and checks
the actor again for review decisions. It allows bodyless Approve; Comment and
Request changes through the current single-review REST path require a body.
This follows the [REST review endpoint](https://docs.github.com/en/rest/pulls/reviews#create-a-review-for-a-pull-request);
native pending-review synchronization remains separate work. GitHub still
checks token scopes, repository permissions, and other policy at submission.
If actor lookup fails (including unsupported token identity endpoints), review
decisions requiring a verified actor are unavailable until it can be verified.

See `../vim-reviewhub/autoload/reviewhub/bridge.vim` and its fixture provider
for working adapters. No ReviewHub import is required inside Revue.

## Thread resolution

Enable `capabilities.thread_state` with `body_required: false`, and supply known
boolean resolution plus per-thread resolve/reopen rules. Revue exposes named
commands and a selected-message action; overlapping anchors require selection.
Missing state or permissions disables the operation with a reason.

The durable operation has `kind: "thread_state"`, empty `body`, stable `thread`,
boolean `resolved` (requested state), boolean `expected_resolved` (state inspected
before acting), and the usual operation/comparison fields. An explicit
Resolve/Reopen command or message-menu action sends in place, with no composer
or second confirmation. Waiting/failure/unknown status stays beside the thread;
`:RevueCheckThreadState` checks uncertain outcomes. Activity retains optional
read-only operation details. The discussion stays expanded.
State changes are sent individually and are not comment/review batch items.

Re-read target state and permissions before a mutation. A successful response
includes `{id, thread, resolved, url?}`; a mismatching response remains unknown.
Revue retains acceptance separately from refresh status and updates displayed
thread state from the refreshed snapshot, without an optimistic local toggle.
Acceptance/receipt metadata and refresh errors persist in local activity history;
backend conversation bodies remain backend-owned. Unsupported or failed
operations leave conversation text unchanged.

GitHub loads paginated GraphQL thread state/permissions and maps each thread to
its REST root comment ID, preserving existing reply IDs. It uses the native
resolve/unresolve mutations. GraphQL failure leaves REST discussion readable
with resolution unavailable. The enterprise endpoint is `/api/graphql`.
[GitHub thread schema and mutations](https://docs.github.com/en/graphql/reference/pulls).

GitHub recovery reads the thread: if the desired state is observed, the result
has `observed: true`; this confirms the current outcome, not who caused it or a
durable receipt for `clientMutationId`. If the opposite state is observed, keep
the operation unknown and do not repeat the mutation. A later actor may have
changed it again; manual investigation can be needed. There is no claimed
atomic compare-and-set guarantee between the state read and mutation.

The local backend commits state, event, and exact operation receipt in one
SQLite transaction. Receipt recovery remains valid even if a later operation
changes the state; the subsequent snapshot is authoritative for current state.
Unknown-state handling and receipts belong to the backend; the UI has no
GitHub-specific dispatch and requires no GitHub connection for local resolution.

## Review batches

Backends opt in with `capabilities.batch`: `enabled`, `mode: "atomic"`, supported
`kinds`, `max_reviews` (currently one), and optional `default_label`. This first
implementation requires atomic delivery; it never silently turns a batch into
several unrelated remote writes. `review_body_optional_with_comments` permits an
empty review summary when selected inline comments carry the feedback.

Submission still uses `mutate`, with `draft.kind: "batch"`, stable `id`, empty
`body`, comparison fields, and `items` containing frozen full drafts. The shared
outbox replaces the selected drafts with that batch before sending. Unselected
drafts remain editable. If another editor changes selected text after preview,
the queue refreshes and requires the user to inspect it before sending again.

A successful receipt includes `items: [{draft, id, url?}]`, acknowledging every
selected draft ID exactly once. GitHub item receipts refer to the containing
review; local receipts identify individual saved messages. Incomplete receipts
are treated as unknown outcomes, not as partial success that can be reposted.
Failure known to precede acceptance allows unpacking the batch for editing.
Unknown/submitting batches stay frozen and survive restart; sending an unknown
batch only checks its receipt. Reconciliation still works after write access is
lost while the review remains readable. Backend deduplication rejects reuse of
a batch ID with different content.

The GitHub adapter creates one native review containing inline comments and an
optional selected review decision. With no decision selected, it publishes a
Comment review. Replies and general conversation drafts are explicitly excluded
from this native batch and can be sent separately. The review body contains
hidden receipt/fingerprint metadata; it never invents human summary text. Local
batches save comments, replies, conversation and an optional summary in one
SQLite transaction, rolling all new entries back if any item fails.

Native server-side pending-review synchronization and non-atomic delivery modes
remain separate work. A Revue batch is a local frozen outbox operation until
the backend acknowledges it; it is not a GitHub pending review.

## Bundled local backend

`autoload/revue/backends/local.vim` binds a local review to the same contract.
It starts `python/revue_local.py` for asynchronous JSON requests, with the
store directory captured in the binding. Changing `g:revue_local_dir` affects
new bindings, not already open reviews. Python 3.9+ with SQLite is required
only for this backend.

The companion accepts one request on stdin and returns the same result
envelope on stdout. In addition to `file`, `refresh`, and `mutate`, it supports
`create` (`cwd`, `base`, optional `untracked`), `list`, and `open` (`review`).
Review-bound requests include `review`. Create/open return
`{connection, review, snapshot}`; list returns review summaries. These local
operations are callable without Vim and form a transport-independent boundary.

Current capture supports Git saved working-tree changes versus a resolved
commit. It retains text content and generates hunks from that exact content;
later workspace edits do not alter the review. Binary/non-UTF-8 content and
files over 2 MiB have explicit non-text states. Untracked files require opt-in,
unsaved editor buffers are excluded, and capture does not stage or commit.
The original `:Revue` path remains available for jj and callback/clipboard use.

Local mutations validate snapshot identity and source ranges and serialize
conversation updates with SQLite transactions. A receipt keyed by review and
draft ID is committed with the comment and event. Retrying an identical
operation returns that receipt; reusing the ID for different content fails.
Reconciliation only looks for a receipt and never creates another comment.
Owner-side feedback identity comes from the captured local review, not a request
author field. Participant replies bind identity to the owner-created assignment;
that separate scoped contract is documented below.

The local backend supports retained immutable comparisons, inline/file feedback,
replies, conversation messages, review summaries, resolution, and follow-up
capture. Local assignment storage and a scoped MCP transport now have an
[implemented contract](participant-mcp.md). Vim assignment selection, preview and
creation use the durable outbox. Assignment/outcome reads and cancellation have
separate capabilities. Agent runners and Git notes transport remain planned.
The local store is bundled here until
the interface is proven; it is not a dependency of the generic UI.

## Local activity and reading metadata

The existing locked, atomically replaced version-1 outbox has optional
`activity`, `refresh_state`, and `read_state` fields. Old outboxes still load.
Accepted draft removal and outcome recording share a save; if saving fails,
Vim shows `NOT SAVED` and keeps its in-memory receipt. The durable submitting
intent reopens as unknown and queries the backend for recovery. No activity
metadata enters the frozen mutation payload or operation fingerprint.

Activity stores operation/kind, target/comparison, terminal outcome, timestamp,
and allowlisted receipt identifiers/state/URLs, including batch item targets
and receipts. It retains 200 outcomes by default; pending work is not evicted.
This is delivery history rather than the backend conversation event log.

Read metadata uses `[thread ID, message kind, message ID]`; the kind separates
review and comment ID namespaces. First observation establishes a baseline;
subsequent new IDs become unread, including the current actor's new messages.
Only explicit message/thread acknowledgement clears a currently visible marker.
Messages absent from the current snapshot lose their unread marker, but their
known IDs remain to avoid false arrivals when a comparison is reopened. No
body hashing, edits-as-new, cross-device sync, provider notification mutation,
or automatic polling is implied. Revision-switch semantics remain UX-12.

## Comparison history and source identity

Opt in with `capabilities.comparisons.enabled`. Legacy adapters retain observed
in-memory navigation without claiming historical retrieval support.

`comparisons` returns `{items, complete, scope, latest?}`. Each item contains
`snapshot`, `base`, `head`, optional `base_tip`, `head_repo`, and human-readable
`label`. IDs/refs must be immutable. `complete` applies to the described `scope`,
not every revision the service may ever have held. `latest`, when supplied, is
a full current snapshot. The binding normalizes its review key/metadata just as
it does `refresh` and `comparison` snapshots. History reads and refreshes are
ordered so an older result cannot roll back a newer latest pointer.

`comparison` receives `{reference}` and returns a full version-1 snapshot for
that reference. The UI verifies review key, snapshot ID, and supplied base/head
identities before displaying it. A legacy draft may only have `snapshot`, `head`,
and `base_tip`; the adapter may resolve its own snapshot identifier, but core
never parses provider-specific IDs or guesses a different base. Return an error
if the exact source cannot be retrieved. Never substitute latest source.

File caches and view positions are scoped by comparison identity. `file` must
honor the supplied snapshot and original/canonical paths. Superseded source
callbacks are discarded. Historical lookup may cache a successful response, but
it does not move focus after the originating view/selection changed or its draft
was edited. Selecting another comparison supersedes an earlier open request.

The optional v1 outbox `navigation` field stores `selected`, `order`, and
`references`. Each reference entry contains the backend reference, selected file
ID/side and Vim view positions. It contains no snapshot, source cache, accepted
conversation body or credentials. Startup opens current backend code;
`:RevueResumeComparison` explicitly retrieves the saved selection. Opening a
saved draft does not move its anchor; `:RevueDraftComparison` retrieves its source
comparison. Original operation IDs and receipt-only recovery are unchanged.

GitHub history paginates immutable compare-commit results and lists the current
PR comparison plus each reachable commit against its first parent. Root commits
without a parent are reported as omitted. This does not discover every abandoned
force-pushed branch; saved references can still retrieve surviving objects.
Historical lookup compares exact object IDs, verifies the merge base, and refuses
missing or capped file inventories. GitHub's JSON comparison includes at most
300 changed files, so reaching 300 is treated as unverifiable completeness.
The existing current-PR files endpoint retains its separate completeness check.
See [GitHub compare documentation](https://docs.github.com/en/rest/commits/commits#compare-two-commits).

Historical lookup reads current conversation/state. An original head-side anchor
is placed only when original commit ID equals selected head and the original
path/line is present in the comparison. A historical base cannot be inferred
from an original head ID; unproven anchors remain unplaced with original hunk
context. Resolution and reply permissions remain independent of placement.
New inline/review actions on historical source are unavailable; replies still
address stable thread IDs. Current backend validation governs all writes.

The local backend returns retained captures and current shared conversation,
rejecting other review/snapshot refs. Explicit capture advancement is described below.

### Selected ranges

Opt in independently with `capabilities.comparison_range = {enabled, sides,
semantics, reason?}`. `sides` explicitly lists `base` and/or `head`; `semantics`
explains supported comparisons in the picker. The request's `selection` contains
`from` and `to`, each `{reference, side}`. References are original immutable
comparisons; derived ranges and original contexts cannot be used as endpoints. Core does not parse
snapshot IDs or infer merge bases. Endpoint commands default to `head`.

Return a full snapshot whose `range` equals that selection, `base` equals the
start reference's selected side, and `head` equals the end reference's selected
side. Use a distinct derived snapshot identity, even when endpoints match the
current review comparison. This prevents a read-only range from replacing the
current writable snapshot. Core checks the complete selection and exact refs
before caching/opening; clearing/changing endpoints supersedes an in-flight
request. Navigation or draft edits while loading prevent a focus jump.

The standard reference now preserves optional `range`, `context` and `base_repo` as well
as `head_repo`. `comparison` must reopen the same derived source, including after
restart; `file` must honor each side's repository and path. Bindings normalize
`comparison_range` snapshot key/backend identity like ordinary comparison reads.
The local outbox persists `navigation.range_selection`; new replies created
while viewing a range retain its `range` metadata for source recovery. Existing
drafts are never rewritten. Read-only source restrictions do not themselves
disable replies, reactions or lifecycle actions targeting existing messages.

The local backend atomically caches derived snapshots/contents in its own store,
without advancing latest or changing the conversation. It reconstructs retained
endpoint contents from the captures' common baseline and deltas, including a
file changed in only one capture. It supports either direction and base/head
selection; renames are displayed as removal/addition. Binary/raw-byte hashes and
newline flags remain intact. Missing content/mode metadata in a capture cannot
be reconstructed; unavailable content stays explicitly unavailable. The frontend
outbox still stores references, not source content.

GitHub ranges use immutable object IDs and require the start to equal the
comparison API's merge base. Fork repository routing is preserved on both sides.
Non-ancestor ranges and the compare endpoint's file cap remain explicit errors;
there is no silent replacement with the merge base. Full native original-thread
comparison recovery is separate work: the original head alone does not identify
the original base.
Non-ancestor GitHub ranges and complete abandoned-history discovery remain future
work. Explicit local draft movement uses the separate capability below; history
access never moves feedback.

### Original discussion context

A backend may retain `thread.original_comparison`, a standard immutable reference,
for exact original-source navigation. Otherwise opt into lazy verification with
`capabilities.thread_context = {enabled, reason?}` and per-thread
`original_source = {token, available, label?, reason?, lookup?}`. The token is an opaque
identity for the original anchor, not the current message body or current line.
Changing that anchor invalidates previous lookup requests/references.

The read-only `thread_context` request carries `target: {thread, token, lookup?}`.
If advertised, `lookup` is an opaque locator passed through by the shared UI;
it is not an anchor identity or proof of membership. Verify review membership
and that exact anchor before retrieving source. Return:

```json
{
  "thread": "thread-id",
  "token": "original-anchor-token",
  "snapshot": {
    "context": {
      "thread": "thread-id", "token": "original-anchor-token",
      "kind": "original-head", "label": "Verified original head",
      "basis": "Original PR base unverified",
      "note": "One file at its original commit and parent; original PR base unverified.",
      "path": "src/example.vim", "side": "head", "start": 12, "line": 14
    }
  },
  "location": {"path": "src/example.vim", "side": "head", "start": 12, "line": 14}
}
```

`snapshot` above abbreviates a **full version-1 snapshot**. It must use a distinct
derived identity, explicit immutable base/head, valid file entries and the
context descriptor. `location` must exactly match the descriptor, identify a
supplied file and use a positive same-side inclusive range. For a whole-file
discussion, `location.line = 1` is only a navigation position: the thread retains
its whole-file target and zero line coordinates. Never convert it into a line
comment. The binding normalizes the nested snapshot's review key/backend identity.

Core verifies the returned target, file inventory, snapshot identity and descriptor.
Malformed or mismatched replies leave the discussion readable. Superseded requests
are ignored; a valid late response can cache source without moving focus away
from another message/view. `:RevueReturnContext` returns to the exact previous
message/source in the current Vim session, recreating a managed panel if needed.
The return origin is transient. Persisted references and newly created reply
drafts retain `context`; `comparison` must reopen and validate that descriptor
after restart. If its original anchor/source is unavailable, return an error;
do not silently replace the context with latest code.

The GitHub implementation verifies original path/range and diff-hunk text against
the original commit's source. Its one-file context uses that commit and its first
parent (an empty base for a root commit), **not a reconstructed original PR diff**.
`kind: original-head` verifies the head excerpt; `matching-parent` only proves
the base excerpt matches the parent; `commit-parent-file` identifies a deleted
whole-file's parent content. All retain an explicit unverified-original-base
label. A failed match preserves the original hunk in the discussion. Explicit
rename metadata may recover an old path; unrelated similarly named files are
not searched. Missing commits or unavailable fork sources remain unavailable.

GitHub starts this inspection with an incremental review read. If the selected
thread is outside the initial page, its advertised native locator uses the
existing complete-thread lookup with review/source/actor checks. Unsupported
direct lookups and saved references without a locator use authenticated feedback
paging, stopping at the target or at the 100-page/cursor-cycle bound. Scope,
permission and stale-reference errors are not retried as another target.
Only the requested thread is retained from the extra pages; the general feedback
cursor is not advanced and coverage remains partial. The anchor token is checked
before historical file reads. Locators are not added to persisted `context`
identity, so existing saved references remain compatible.

Previously this route called the complete-inventory form of `open`; it already
could find later-page threads. The improvement avoids that full feedback reload
while preserving reachability. A public read verified an outdated thread beyond
the initial 20 and reopened its saved one-file context.
Evidence (local evidence: `../output/historical-context/validation.json`).

Existing discussion replies and lifecycle permissions remain current. Disable
new inline/file feedback, review and batch creation on this derived source;
the user returns to Latest for those operations. Context inspection does not
advance latest, mutate feedback, move anchors or publish anything.

## Local discovery and file progress

The shared discussion index searches the current snapshot's loaded threads and
conversation plus the local outbox. It issues no search or mutation RPC. Stable
thread/message IDs and message kinds determine selection; providers should
preserve them across refresh. Outdated or absent-file threads remain discoverable.
A draft in an atomic batch resolves to its owning frozen operation.

Snapshots may supply `inventory`, a map with entries for `files`, `threads`,
`conversation`, and optional `private` and `thread_state`. Each entry has
`state: complete|loading|partial|failed|unsupported|unknown`, optional integer
`total`, and optional display `scope`/`reason`. A complete inventory describes
all accessible records in its stated scope, including full bodies and replies;
it does not claim every service event kind or another actor's private data.

Loaded counts come from the snapshot, never from supplied display text:
files and threads count their respective arrays; conversation counts messages;
private counts `pending_reviews.items`; thread_state counts published threads
with a known `resolved` field. The latter total counts published threads only.
`total` is an unfiltered known inventory size, not the number matching a search.
Omit it when unknown. A negative/noninteger total, total below loaded count,
or complete total unequal to loaded count is shown as completeness unknown.
Absent/malformed metadata also stays unknown; it never becomes complete zero.

GitHub declares coverage after existing pagination/completeness checks. Missing
root discussions or failed private reads make thread coverage partial. Private
access and resolution reads have separate states; their failure does not hide
public message bodies. Conversation scope excludes system timeline events.
Derived historical contexts update their file coverage to the selected source.
The local backend supplies complete retained-source and shared-conversation
coverage dynamically, including after mutations and historical retrieval.

Search remains local to loaded bodies plus outbox drafts. `refresh` is the retry
path for partial/failed/loading inventories; it returns a replacement snapshot,
not an append delta. A failed refresh retains previous data with a visible error.
The index shows refresh progress without changing its stable selection, and
successful replacement preserves exact message identity and unsent drafts.
There is no cursor/page-continuation contract in this increment. Adapters must
not suggest that retry can exceed their documented caps; keep explicit errors
and browser fallbacks. Generic incremental paging remains separate work.

File filters are session-local. Viewed acknowledgements persist under optional
`progress` in the locked atomic v1 outbox: `marks` maps file identity hashes to
acknowledged content stamps; `observed` maps comparison/file IDs to metadata and
content stamps. No source bodies are persisted. Older outboxes without this key
remain supported. This is client progress, not server Viewed state.

For reliable byte identity, each `file` response side can include `hash`, a
stable raw-content digest. Local and GitHub adapters supply SHA-256 for text and
binary contents. Text identity also includes lines and supplied `final_newline`,
`fileformat`, and `mode`; binary identity requires a nonempty hash. `absent` is a
known state; `unavailable` cannot establish a new acknowledgement. File path,
old path, status, patch and supplied mode also participate. Backends must not
reuse an immutable comparison reference for different source content. Missing
metadata is treated as unknown, not inferred to have a particular value.

Verification reuses comparison-scoped source caches and serializes background
`file` reads for previously acknowledged files that need checking. A selected
mark/unmark may also request an unloaded file. These callbacks update metadata
without changing source selection or focus; closing cancels a pending local
mark's intent. Explicit Verify retries unavailable checks. A failed fetch cannot
erase already verified content for an immutable comparison. Remote Viewed sync
would require a separately declared backend operation and is not implemented.

## Message presentation metadata

GitHub normalization retains author association, explicit user type, update
stamp and review-decision labels from its existing reads. It labels a returned
inline comment pending only when its review ID matches a known PENDING review;
the native pending extension above supplies separate editing/publication operations. Generic update
timestamps do not become `edited` flags. Local accepted messages carry
`publication: "local"`; older stored messages remain compatible without it.
[GitHub review-comment fields](https://docs.github.com/en/rest/pulls/comments#list-review-comments-on-a-pull-request).

The shared renderer preserves the raw message body. Nested quote containers,
fenced code, headings and list markers have terminal presentation; quotations
of suggestions must not acquire an actionable anchor or before/after against
a different source. Full Markdown stays available in the real-text discussion.
Card rendering is intentionally not a full GFM/HTML implementation. GitHub's
[formatting reference](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax)
and [fence rules](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/creating-and-highlighting-code-blocks)
remain the external comparison; unsupported constructs must stay readable.

## Suggestion composition

Backends opt in with `capabilities.suggestion = {"enabled": true,
"sides": ["head"]}` and may supply a disabled `reason`. Missing support disables
the dedicated creation action; ordinary comment support alone does not imply it.
The local and GitHub adapters support head-side suggestions. Ordinary comment
permissions, immutable comparison checks and anchor validation still apply.

A suggestion draft remains `kind: "comment"` with an additional boolean
`suggestion: true`. Its original `path`, `old_path`, `side`, `start`,
`end` and comparison identity remain ordinary inline-comment coordinates.
The body is Markdown with exactly one closed top-level `suggestion` fence;
explanation before or after it is allowed. The replacement can be empty.
Literal backticks in source cause the composer to choose a longer enclosing
fence. Quoted fences and fences inside ordinary code do not count; suggestion
offset syntax is not part of this composer contract.

Both adapters validate the flagged body before publication, including every item
in an atomic batch. The flag must be boolean true and target a head-side comment.
Receipt-only reconciliation occurs without reposting, including after restart
or capability loss. Unflagged manually written Markdown retains ordinary comment
behavior. No new mutation kind, apply endpoint or commit operation is introduced.

Fixture tests cover exact single-comment and native review-batch payloads,
deletion, validation, rollback and receipt recovery. Longer fence delimiters
follow the linked GitHub fence rules, but their native suggestion rendering has
not been verified through an authenticated live publication. Applying proposals
is a separate operation: GitHub's
[application workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request)
creates commits, and remains outside this implementation.

## File discussions

`capabilities.file_comment` requires explicit opt-in even for legacy snapshots
without a capabilities object. The new `file_comment` mutation kind preserves
the ordinary immutable operation fields and a whole-file target. Both adapters
reject source-coordinate fields, missing/changed file identity, stale comparison
and suggestion flags on this action. The source may be text, binary, absent or
unavailable; writing feedback never requires reading the blob. The local backend
stores the file anchor and ordinary root/replies in its conversation database.

GitHub uses the existing review-comment endpoint with `subject_type: "file"`,
`commit_id`, `path`, and `body`, without line/side fields. It validates the
changed-file/rename identity before writing. Returned explicit file subjects
normalize as whole-file threads even when line is null. Available GraphQL thread
state remains authoritative; a null line alone cannot establish outdated state
for a file subject. Historical placement requires the original commit reference
and path to match; otherwise the discussion remains available as outdated.
[GitHub file comments](https://github.blog/changelog/2023-04-11-commenting-on-files-in-a-pull-request-is-now-generally-available/),
[REST target contract](https://docs.github.com/en/rest/pulls/comments#create-a-review-comment-for-a-pull-request).

The local atomic batch capability includes `file_comment`. GitHub's current REST
review batch capability omits it because the documented comments array does not
include `subject_type`; the client explicitly offers individual delivery and
does not emulate an atomic review using multiple writes. Native pending-review
support may extend this later. Existing receipt markers and receipt-only recovery
apply. Contract/fixture tests cover payloads, permissions/staleness, replies,
binary/deleted/renamed/unavailable targets and restart; authenticated live file
publication remains unverified.

## Line-anchor scope

Optional `capabilities.comment.anchors` declares `{scope, sides, reason?}`.
`scope: "diff"` accepts lines represented in returned patch hunks;
`scope: "changed_file"` accepts any valid line range in the immutable text of a
file in the snapshot inventory. Missing scope defaults to `diff`, and missing
sides to `["base", "head"]`. Unknown scope or unsupported side produces an
explicit unavailable action. This never grants access to arbitrary unchanged
files or enables an otherwise disabled comment action. The same scope governs
suggestion anchors in addition to the separate suggestion capability.

Creation validates path/old path, side, numeric range, and loaded text bounds.
Single and batch submission revalidate file identity and current anchor policy;
comparison freshness and body/permission rules still apply. Policy loss retains
drafts. Backend mutation handlers must independently validate source bounds
against immutable content. Receipt-only recovery bypasses write availability
and does not reinterpret or move a stored anchor.

The local backend declares `changed_file` on both sides and checks its captured
bytes, retaining hash and selected source in the accepted anchor. Current working
tree edits cannot move an existing captured target. GitHub declares `diff` with
an explanatory reason: its web UI supports unchanged lines, but the documented
API support is limited and creation outside hunks has not been verified here.
Existing API reads preserve explicit current line/range positions even outside
the returned patch. Do not infer outdated state from hunk membership.
[GitHub unchanged-line support and API caveat](https://github.blog/changelog/2025-09-25-pull-request-files-changed-public-preview-now-supports-commenting-on-unchanged-lines/).

## Retained local captures

Optional `capabilities.capture` enables the bodyless `capture` mutation kind.
Its durable draft includes the usual operation/comparison fields, `body: ""`,
and a boolean `untracked`. The preview uses `snapshot.capture_context` metadata:
`workspace`, fixed `base`, previous `untracked`, and `options_known`. That metadata
is presentation; the backend obtains its actual workspace/base from the bound
review, never from caller-supplied paths. The action is not a review-batch item.

The local backend double-reads saved files against the existing fixed base,
detects observable in-flight edits, and retains the resulting content-addressed
comparison. Identical source reuses an existing comparison. A later empty diff
is valid. A SQLite transaction commits the current revision pointer, retained
source, capture settings, operation receipt and `revision.captured` event. Two
captures from the same old pointer cannot both advance it. Capture does not
edit/stage/commit workspace files or auto-resolve discussion.

The receipt is `{id, previous_snapshot, snapshot, changed, url?}`. `id` matches the
operation and `previous_snapshot` matches the draft's expected comparison.
Malformed/incomplete success becomes unknown in Vim. Receipt-only reconciliation
never performs another capture, even after restart, later revisions or loss of
write capability. The shared refresh path offers the new comparison without
switching views; old drafts keep their original target and cannot be published
as new inline feedback on the newer comparison.

Storage remains version 1 with additive `revisions` and `capture_options` in the
backend record. Each retained revision holds source snapshot metadata/content,
capture time and sequence; accepted conversation exists in one shared collection.
Legacy records are upgraded on read and retained on the next write. Missing old
capture options are explicit and default to excluding untracked files until the
user chooses otherwise. Source access verifies review/comparison/file identity.

Historical views project that shared conversation onto retained source. Line
placement requires verified original file identity and the same complete source-
side hash; changed/unproven anchors retain original source context as outdated.
File threads can follow a proven stable original-base path across a rename.
No heuristic line remapping is claimed. Each local thread returns
`original_comparison` (a standard immutable reference), `original_path`, and,
when outdated, optional `original_context` display lines. The raw backend anchor
remains unchanged. Replies/state operations can use retained comparisons; new
comments, file comments, reviews and captures require the current one.

Optional `capabilities.comparisons.refresh_on_open` asks the UI to retrieve
current discussion when revisiting cached immutable source. Local views enable
it. `:RevueThreadComparison` follows the exact original path/side/line when
provided, using existing async focus guards. This is not polling. Agent
assignment/run state and MCP dispatch remain separate. Explicit local draft
re-anchoring is described in its own capability contract below.


## Rendered message links

Optional `capabilities.rendered_links: {enabled, reason?}` enables a read-only
`op: "rendered_links"` request. Its `target` contains `message`, `message_kind`,
`thread`, `pending_review` (empty when published), `body` and `expected_version`.
A successful response returns `{message, message_kind, thread, version, links}`;
`links` contains `{label, url}` entries with explicit HTTP(S) destinations. The
frontend checks message/version/selection and a request token before showing a
chooser. Late, malformed or stale data never opens a destination. URLs are shown
before a second open/copy choice; this operation does not publish anything.

GitHub verifies review/issue-list membership, thread/private identity and the
normalized body/version. It reads `body` and `bodyHTML` from the exact GraphQL
node, compares the raw body, and extracts anchors with Python's HTMLParser.
Rendered relative hrefs resolve against the message's web permalink; this uses
GitHub's rendered href rather than inferring Markdown behavior from the source
file. Labels include nested text/image alt text. No HTML executes and no images
or linked resources load. The read covers inline comments, conversation comments
and published review summaries. It requires authenticated GraphQL access.

Without this capability, Revue parses a documented Markdown subset locally.
A message may include `resolved_links: {raw_destination: absolute_web_url}` for
backend-owned resolution; the frontend guesses no relative base. The raw
`:RevueBodyURLs` fallback includes URLs inside code and reference definitions.
Both routes retain raw Markdown for exact copy, quote and edit operations.

Sources: [GitHub review-comment fields](https://docs.github.com/en/graphql/reference/pulls#pullrequestreviewcomment),
[GitHub Markdown links](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#links).

Live verification (2026-09-14): the read-only path passed on public conversation
comment 691117172 in vim/vim#6932 and inline comment 3140841349 in
tpope/vim-fugitive#2474, with matching message versions. The former returned
three labeled attachments; the latter returned no links. No linked resource was
opened or review content written. Private/enterprise cases retain fixture-only
coverage. See [evidence](research/rendered-links-live.json).

## Typed review timeline

`capabilities.timeline: {enabled, reason?}` advertises a read-only history
projection. The UI calls `{op: 'timeline', cursor: ''}` for the newest page and
passes the returned `next_cursor` unchanged to load earlier events. A successful
callback has the standard `{ok: 1, data: ...}` envelope:

```json
{
  "cursor": "",
  "items": [{
    "id": "event-id", "kind": "PullRequestReview", "title": "Approved",
    "actor": "reviewer", "created": "2026-09-14T12:00:00Z",
    "body": "Review summary", "url": "https://example.test/review/event",
    "provenance": "Review backend", "details": ["Reviewed commit: …"],
    "target": {"kind": "conversation", "message": "message-id", "message_kind": "APPROVED"}
  }],
  "complete": false, "next_cursor": "opaque-older-cursor",
  "total": 123, "scope": "Current event bodies; reload for newer activity."
}
```

`items` are chronological within each page; the view shows newest first.
`cursor` must echo the request. Completion is a JSON Boolean (Vim integer 0/1
is also accepted), with an empty next cursor only when complete. Noncomplete
pages must advance to a nonempty cursor. Missing or malformed pages leave the
previous inventory intact. Repeated identities within a page are invalid;
identities overlapping previously loaded pages are deduplicated. A nonfinal
page with no new identities is rejected to prevent endless continuation.

Every event requires string `id`, `kind`, `title`, `actor`, `created`, `body`,
`url`, `provenance`, plus `details` as a list of strings. Empty author/time/link
values mean unavailable. IDs must remain stable within the bound review.
Unknown event types stay visible with explicit missing-detail text. `total` is
optional and shown only when consistent with the number of loaded events.

The optional `target` identifies a message, which may not yet be loaded. `kind` is
`conversation` or `thread`; both require exact nonempty `message` and
`message_kind`, and a thread target also requires `thread`. Message kind is the
backend's actual message kind, including local `reply` or GitHub `APPROVED`;
it must not be inferred from the event title. Missing targets offer the event
link rather than guessing a thread. For an unloaded target, the UI can explicitly
load one feedback page and follow the exact target if found; it never drains the
inventory automatically. Existing message permissions apply after
navigation. Closing returns by stable event identity and relative position.

Cursors belong to the backend review, not to the selected diff. GitHub encodes
host/repository/review identity with its GraphQL cursor and fetches up to 50
older events per read. GraphQL sign-in is required; signed-out users receive
an explicit browser fallback. Local cursors bind to review ID and ordered event
identity inventory; additions/deletions invalidate an outstanding cursor and
request reload. Derived comparison ranges do not create capture events.

This is a projection, not an immutable event ledger. GitHub may return current
review states/bodies; local history consists of retained captures and current
authored messages, without edit/resolution lifecycle records. State that scope.
A reviewed commit can appear as `reviewed_head` and in details; it does not
establish the original comparison base or current readiness. To enable
`:RevueEventComparison`, an event may supply `reviewed_comparison` with a complete
immutable reference (`snapshot`, `base`, `head`, and supported optional reference
fields) and a nonempty `comparison_provenance` explaining its evidence. If
`reviewed_head` is also supplied, it must match. A one-file `context` reference is
not a full reviewed comparison and is rejected. Existing comparison retrieval
capabilities apply; conflicting retained identities cannot be overwritten.

Local capture events provide their retained references. Newly saved local reviews
retain the submitted reference; older reviews can recover it from a matching
saved review receipt and retained revision. Missing or inconsistent evidence is
unavailable, never inferred from the current capture or timestamp. GitHub events
currently expose reviewed heads without verified original PR bases, so they retain
the native browser route. Providers must not substitute a commit's parent for the
original PR base. Open/return preserves the exact history event; reloaded history
or changed focus prevents a late response from switching the displayed source.

Reload replaces the inventory on success; cancellation invalidates the current
read generation. Late responses cannot steal focus from another panel or
composer. Timeline bodies are session-only and never enter the outbox or local
Activity receipts. Loading events does not mutate feedback or read markers.
Generic feedback-inventory continuation uses the separate contract below.

## Explicit local draft movement

A backend may advertise `capabilities.reanchor_draft` with `enabled: true` and
`kinds: ["comment", "file_comment"]`. This authorizes local draft preparation,
not a backend mutation. New targets still require the current normal comment,
file-comment and suggestion capabilities and anchor policies. Both bundled
backends opt in; missing capability disables the workflow.

The UI accepts only independent local drafts in `draft` or known-`failed` state.
Replies, edits, private delivery, pending-review operations, frozen batch children
and uncertain submissions retain their targets. A location must be explicitly
selected from the latest comparison. The proposal binds current comparison,
refresh epoch, source location and the complete original draft. Any intervening
refresh, comparison change, draft edit or capability loss requires reselection.
Old source can be unavailable, but its exact reference remains visible; the UI
never substitutes current source as historical evidence.

Acceptance atomically replaces the local outbox entry with a fresh operation ID,
the new reference/location, state `draft`, unchanged body and suggestion intent.
Range/context fields come from the new comparison; old error/delivery outcomes
are not reused. `reanchored_from` records the preceding draft ID, comparison and
anchor, without copied source bodies. This metadata is not permission to act on
an old backend message. A later ordinary submission uses the normal backend
validation and receipt contract with the fresh ID. Earlier batch selection is
cleared and requires explicit reselection.

Save failure restores the original entry. Tentative selection/source previews
remain in memory only; restart retains the original draft until acceptance and
the moved draft after acceptance. No network mutation or repository edit occurs
as part of moving the draft. This capability does not imply support for moving
published comments, private server comments, or reassigning an existing thread.

## Exact saved-message deletion

`delete_message` is a separate mutation kind from `delete_pending_comment`,
`discard_pending` and local outbox discard. Require global
`capabilities.delete_message.enabled` and a message rule of the same name with
`enabled`, `scope: "message"` and a stable `actor`. Unsupported scope must have
a reason; the UI never infers permission from editability.

The immutable draft binds operation `id`, review/comparison, `message`,
`message_kind`, `thread` (empty for general conversation), `actor`,
`delete_scope: "message"`, `expected_version`, `original_body`, and empty `body`.
Presentation metadata includes author, location and publication state. Recheck
membership, scope, actor, version/body and current permission at mutation time.
The UI previews the exact message before Send confirmation and rejects changes
that occur during confirmation. Deletion is never eligible for a comment batch.

An accepted receipt must echo `id`, `message`, `message_kind`, `thread`, `actor`,
`delete_scope`, `expected_version`, with native Boolean `deleted: true`.
Malformed acceptance becomes unknown. Reconciliation must never invoke DELETE.
Local receipt recovery binds the original payload and is atomic with removing
one message and saving its audit event. Empty threads disappear; nonempty threads
keep their stable IDs, including when their first message is deleted. Current
local support covers owner-authored comments/replies/file/general comments;
review decisions remain separate. Local audit data is retained, not erased.

GitHub checks the current actor, successful PR access, full review-specific
comment inventory, exact native ID/thread/author/body/version, and GraphQL
`viewerCanDelete` (plus published review state for inline comments). It rechecks
current REST content before deleting through the inline or issue-comment
endpoint. Roots with replies and published review summaries are unsupported.
There is no documented atomic version condition on DELETE; concurrent changes
after preflight remain possible. Reconciliation establishes absence only from
a successful complete inventory, and sets `observed: true` without attributing
that absence to the request. Lost access and failed/incomplete reads stay unknown.

References: [inline comment deletion](https://docs.github.com/en/rest/pulls/comments#delete-a-review-comment-for-a-pull-request),
[general comment deletion](https://docs.github.com/en/rest/issues/comments#delete-an-issue-comment),
[review deletion scope](https://docs.github.com/en/rest/pulls/reviews#delete-a-pending-review-for-a-pull-request).

## Per-message edit history

The shared reader calls `message_history` with `target` and a string `cursor`
(empty for the first page). Both snapshot and selected message must advertise
`capabilities.message_history.enabled`. Target fields are `message`,
`message_kind`, `thread` (empty for conversation), `expected_version` and `body`.
They identify one exact current message; history readability is independent of
permission to edit it. The provider must verify membership and version/body.

Return the exact target and incoming cursor, `items`, `complete` (Boolean),
`next_cursor`, optional nonnegative `total`, and a human-readable `scope`.
Entries use the timeline's stable chronological page schema: `id`, `kind`,
`title`, `actor`, `created`, `body`, `url`, `provenance`, `details`, plus
`content_state`: `available`, `redacted` or `unavailable`. The latter two require
an empty body. Never reconstruct redacted content. Newest entries appear first
in the view; providers return each page in chronological order and page backward.
Bind cursors to target/version and inventory; reject foreign, stalled or changed
inventories. Reload and cancellation preserve the last good view. Comparison,
message, version and request-generation checks reject obsolete callbacks.

The local backend pages 50 retained before/after edit events, producing text
diffs with final-newline changes labeled separately. The GitHub adapter pages
native edit content for supported public inline/general comments and published
review summaries, verifying REST identity and current body around the GraphQL
read. Native content may include initial creation; it is not guaranteed to be
a unified patch. GitHub private histories are unsupported in this integration.
A complete inventory means all reported entries, not an unlimited edit archive.

History bodies remain ephemeral UI data, outside the outbox. Read-only surfaces
preserve literal body text and use ordinary Vim wrapping. `revue#surface#Paint`
applies shared card colors without padding bodies; `Clear` removes decorations
when a managed buffer changes roles. No individual collapse or revision-delete
operation is provided. A browser link opens the original message, not necessarily
its edit-history control.

## Targeted discussion lookup

Optional `capabilities.feedback_lookup: {enabled, requires_token?, current_only?}`
enables fetching one complete discussion from an unloaded history target.
`requires_token` requires a nonempty opaque `target.lookup` string; `current_only`
excludes derived `range` and one-file `context` references. These are shared
capability rules, not backend-name checks. Existing paging remains the fallback.

Request: `{op: 'feedback_lookup', reference, target}`. `target` carries the exact
`kind: 'thread'`, `thread`, `message`, `message_kind` and optional `lookup` from
the history event. The session binding supplies review/connection identity.
Success data is `{key, reference, target, thread}`: echo the complete request
reference and target; use the provider's native snapshot `key` and the ordinary
complete thread schema, including every readable reply and current metadata.
The backend binding verifies the native key before qualifying it for the session.
Reject wrong reviews, sources, thread IDs and missing requested messages. Fail
the entire lookup when a complete unit cannot be returned.

The UI merges by stable identity, preserves ordinary paging cursor/coverage,
and does not generate unread notifications for retrieved older messages.
Finding an extra thread in a supposedly complete inventory makes that coverage
unknown. Internally, `feedback.lookups` tracks new thread IDs until ordinary
paging encounters them; one such overlap can advance without being mistaken
for a duplicate page. Existing cursor-cycle checks still apply.
Cancel/refresh invalidate late callbacks; a changed event, view or composer
prevents automatic follow. Closing returns to the originating event and offset.
This read neither resolves nor publishes feedback and creates no outbox item.

The local backend supports retained comparisons and returns one complete thread
from its stored conversation. It still projects the review in memory; this is a
navigation/payload optimization, not constant-time storage access. GitHub uses
the native GraphQL thread node, verifies its parent repository/PR, loads nested
reply pages, then checks source, actor, update time and private-review state again.
Its initial implementation supports public threads on the current comparison;
private/mixed discussions offer ordinary paging or the service link.
The parent relationship and reply connection are documented in GitHub's
[PullRequestReviewThread schema](https://docs.github.com/en/graphql/reference/pulls#pullrequestreviewthread).
See lookup verification (local evidence: `../output/feedback-lookup/validation.json`) for live-read
scope and fixture costs. General conversation and search-result lookup are not
added by this capability.

## Incremental feedback inventories

`capabilities.feedback_page: {enabled, reason?}` enables the shared Load more
interaction. An initial snapshot may include only some `threads` and
`conversation` entries, with `feedback: {cursor: 'opaque-next-page'}` and honest
`inventory` coverage. Omit the cursor or use an empty string when all available
feedback is loaded. The UI sends `{op: 'feedback_page', cursor, reference}`;
`reference` is the displayed immutable comparison reference. The session binding
supplies backend/connection/review identity as usual.

A successful response uses the standard callback envelope with this data:

```json
{
  "snapshot": "the-requested-comparison-id",
  "cursor": "the-requested-cursor",
  "next_cursor": "opaque-next-page",
  "complete": false,
  "threads": [],
  "conversation": [],
  "inventory": {
    "threads": {"state": "partial", "total": 120},
    "conversation": {"state": "complete", "total": 8}
  }
}
```

Entries use the ordinary snapshot schema. A thread is a **complete discussion
unit**, including every readable reply and current anchor/message/capability
metadata. Do not silently truncate a thread to its first nested comment page.
If that unit cannot be read fully, fail the page with an actionable reason.
Unloaded conversations remain covered by the inventory's partial state.

Merge by stable thread ID or conversation `(kind, id)`, preserving existing
positions and appending new units. An overlapping entry replaces that complete
unit; it is not interpreted as a delta of replies. Duplicate identities within
a page are invalid. `complete` is a JSON Boolean (Vim integer 0/1 also accepted).
A nonfinal page must supply a new nonempty cursor and additional units. The UI
rejects nonadvancing/cyclic cursors, wrong source/request identity and malformed
core message/anchor fields before replacing the displayed inventory. Empty final
pages are valid. Backend cursors must bind review, comparison and a suitable
feedback inventory generation; cross-review reuse is never allowed.

Optional `inventory` values replace coverage for threads, conversation and
resolution states; file/private coverage is retained. Without thread/conversation
coverage, the UI marks them partial until the final page. Never infer complete
resolution-state coverage merely from complete message bodies. Known totals
must count the same units the corresponding inventory displays.

Cancellation ignores the outstanding read generation and retains previous
feedback/cursor. Refresh supersedes page reads, including when the source ID
stays unchanged. Responses from another selected comparison cannot overwrite
current feedback. Reading a page neither publishes nor acknowledges a message;
older entries become known locally without inventing new-arrival markers. The
outbox persists reading identities and source references, not accepted bodies.

The local backend opens large reviews in pages of 50 complete units (threads,
then conversation messages). Cursors bind comparison and the current feedback
contents/metadata hash; a concurrent change asks for refresh. Cursors survive
restart when the underlying inventory is unchanged. Small reviews keep their
existing complete snapshot shape. A refresh with `incremental: true` uses the
same initial-page reader; a legacy request retains the complete inventory. The SQLite store still reads its retained review object in
full; this bounds UI/transport inventory, not storage read cost.

The GitHub adapter now implements this contract. UI opens request incremental
loading when signed in: up to 20 review threads and 50 issue comments, plus the
complete review-summary list and complete file inventory. Each thread follows
its nested comment connection to completion before normalization. Public
message IDs, bodies and edit versions use REST-compatible fields; native
message permissions and reaction counts are preserved. Known thread and
conversation totals include the already loaded review summaries.

Cursors bind host/repository/review, base/head/base-tip/source identity, signed-in
actor, PR update marker, individual connection cursors and known totals. Source,
actor/private state and the update marker are checked before returning a page,
including after nested reads. A changed count also requires refresh. These are
consistency checks, not an atomic snapshot of all remote conversation edits.
A page never fetches the entire changed-file list again.

Private review headers and pending comments now participate in the paged
contract below. A private inventory change invalidates the cursor. If initial
paging fails or does not account for private comments, review inventory is
reread before the complete-reader fallback. Signed-out access or unsupported
GraphQL schema/access also uses the complete reader. Failed full
fallbacks remain explicit errors, never empty complete reviews. The adapter
records a fallback reason in `feedback_loading_note` and the capability reason.
Refresh forwards the explicitly requested `incremental` flag through the
companion bridge (default false for legacy callers). Internal mutation and
precondition reads continue using the complete reader.

### Bounded replacement refresh

Optional `capabilities.feedback_refresh: {enabled, scope?, reason?}` allows the
shared UI to send `{op: "refresh", incremental: true}`. The response is a normal
snapshot with an optional `feedback.cursor`, complete loaded threads, stable
message IDs and coverage. The cap means the adapter accepts incremental reads;
it may still use its documented complete-reader fallback when private coverage
is inconsistent or service access is unsupported. Providers without the capability receive false and
retain the legacy replacement behavior.

The UI stages this candidate separately from the displayed snapshot. For the
same source, it commits only when all previously loaded message keys are present
or the candidate has no continuation. Until then, ContinueRefresh issues exactly
one `feedback_page` request against the candidate reference/cursor. It reuses
page validation and rejects repeated cursors, malformed messages, source identity
conflicts, changed selection generations and late read epochs. A new source is
observed as another comparison without auto-navigation. Capability/permission
metadata is adopted with the coherent candidate; backend mutation preconditions
remain authoritative during any remote read.

CancelRefresh invalidates the callback epoch and drops the candidate; it does
not cancel transport I/O. Ordinary LoadMoreFeedback cannot extend the old view
while replacement is pending. Retry preserves successful candidate pages;
Refresh starts over. No automatic cursor loop, polling or reposting is added.
Candidate content and required message-key sets are ephemeral; only the usual
refresh status and accepted reading metadata are saved. A saved refreshing or
partial-refresh status becomes interrupted on restart. The shared UI records
`refresh_state.read_seconds` and `apply_seconds` for the last read/adoption;
these separate callback wait from local adoption, not individual HTTP timings.

**Limits:** the page budget concerns outer feedback units. File inventories,
review summaries and complete nested replies may require additional requests;
local SQLite still loads its stored object. Measured interactive remote latency
targets remain to be delivered. Private paging has the supported contract below. Complete nested discussions can
still be large. The separate timeline cursor API remains a different inventory.


### Private reviews within feedback pages

Incremental GitHub opening passes `allow_pending: true` to its feedback reader.
Cursors retain this mode, per-review read-generation hashes and accumulated
private comment counts. They contain no comment or summary bodies. Legacy
public-only callers continue to reject pending state. GraphQL reads all visible
pending review headers (up to 100, with total-count verification) and checks
author, state, head, summary, update time and comment total before and after
thread reads. A changed actor, publication state, header or count invalidates
the cursor. Exhausting the thread connection without accounting for every
private comment is an error; initial open can fall back to the complete reader.
The native fields are documented in GitHub's [review schema](https://docs.github.com/en/graphql/reference/pulls#pullrequestreview).

Pages still contain complete threads. Each private message has its exact
`pending_review`, `actor`, `publication: "pending"` and native edit capability.
Private roots disable public reply and resolve/reopen; their independently
verified private-reply capability remains. Reactions/history remain unavailable
for private messages. Private root deletion with replies remains unsupported.
A private reply to a published root does not change the root's publication state.

Page `pending_reviews` contains `{available, actor, items, error}`. Every item
has the normal id/author/head/body/summary/comments fields plus `total`,
`complete: false`, `version: ""`, and `read_version`. Its comment targets cover
only private messages in that page's threads. The shared merge validates the
unchanged header generation and actor, merges by exact message ID, checks targets
against loaded private messages and preserves any already verified complete
record. Per-review loaded/total counts are separate from the number of private
review headers. Full thread coverage alone does not grant a publication version.

Optional `capabilities.verify_pending.enabled` exposes `verify_pending` with
`{target: {review, actor, read_version}, reference}`. GitHub verifies the current
header generation and comparison, performs its complete review-specific REST
read, then checks the private header again, including total, actor and source.
It returns `{target, snapshot, review}` where `review.complete` is true and
`version` is the existing complete `pending_record` digest. Legacy complete
records may omit `complete`; absence retains their established complete meaning.
The response includes a verified summary version for summary editing.

The client validates response identity, complete count, unique message IDs,
target shapes and agreement with already loaded text before adopting it. It
ignores cancelled, superseded or different-comparison callbacks and preserves
focus and the selected message by stable ID. Verification never writes; it only
makes existing publication/discard preparation available. Their normal frozen
operation, full preview, confirmation, preflight and receipt paths are unchanged.
Candidate/full read content is not saved as a second conversation store; only a
subsequently prepared operation retains its usual immutable target/body fields.

This is a supported adapter/UI core with fixture and subprocess coverage, not
proof of every live private-role behavior. A public live query validates schema
and public normalization; live private reads/mutations and root-with-replies
scope remain release checks. GitHub's reads are not an atomic snapshot of all
concurrent edits, and cancellation ignores callbacks rather than aborting I/O.


### Measured remote-read scheduling

GitHub opening now schedules file/review inventory, merge-base lookup and actor
rules together after the first PR identity read, with at most four concurrent
workers. A source check follows this wave. Feedback still verifies actor,
source, private generation and nested-message coverage before returning. On a
successful paged open, that final GraphQL guard is the last remote read; only
local projection follows. The duplicate final REST PR read was removed from
this branch. Complete-reader fallbacks retain their final REST identity check.
No read cache, mutation retry or permission prediction was added.

The shared UI compares the full displayed snapshot with the accepted response.
An exact match leaves rich message buffers, draft context and annotations intact;
status-dependent index/activity/anchor-preview content still updates. Any change
to messages, capabilities, inventory or source takes the normal update path.
Beginning/pausing/cancelling a read also avoids rebuilding unchanged conversation
content just to change its status bar. This preserves message and draft identity
without delaying the adoption of changed feedback.

The retained request traces (local evidence: `../output/remote-latency/validation.json`) show an
identical full snapshot fingerprint before/after scheduling changes, eight reads
instead of nine, and one sample moving from 4.805 s to 3.965 s. Separate actual
Vim PTY/bridge/GitHub runs while typing observed unchanged adoption moving from
357.6 ms to 11.2 ms; the largest 20 ms timer gap fell from 376.2 ms to 46.0 ms.
These are individual observations, not percentile guarantees or OS paint times.
Changed-content rendering and large nested discussions remain performance work.

## Personal service progress extension

Optional `service_progress` reads and `service_viewed` mutations are documented
in [the service progress contract](service-progress.md). They use the existing
outbox, stable actor/review identities and read-only receipt reconciliation;
service marks never replace local content-based Viewed evidence.
