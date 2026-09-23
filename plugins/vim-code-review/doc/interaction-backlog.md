# Revue interaction audit and implementation backlog

> **Current planning entry point:** [GitHub → Revue gap audit](review-ux-gap-audit.md)
> Start with its [discussion-ready shortlist](review-ux-gap-audit.md#discussion-ready-shortlist). It
> compares the present implementation by user journey and orders remaining
> repairs, features and validation work separately.
> The [remaining delivery queue](#remaining-delivery-queue--reconciled-september-14)
> gives triggers, expected outcomes and acceptance criteria; the separate
> [validation queue](#validation-queue--separate-from-missing-features) records evidence still needed.
> Use it for next-work decisions; the follow-ups below preserve implementation history and the
> original UX-01–26 contracts.

Audit date: **2026-09-14**. Baseline: the current dirty working trees of Revue
and adjacent `vim-code-review-github`, including the discussion/batch foundation and
resolution/recovery foundation. Historical findings below are retained alongside
their subsequent verification. Individual inline collapsing is already removed.
This is a backlog, not a claim that the proposed interactions
already exist or an instruction to implement all of them immediately.

The [GitHub review UX reference](github-review-ux-spec.md) supplies the external
evidence and its observation limits. Its stable S/C/V/W/R/G IDs are cross-linked
below. This audit adds current code inspection, existing automated suites, and
a disposable headless Vim probe. It does not repeat the authenticated GitHub
checks still listed in that spec. Status describes working-tree behavior, not
a released version. No real provider write was performed.

## Current audit: what to implement next

### Deferred counterparty handoffs

Public packages use `vim-code-review` with GitHub, Codex, and Claude
integrations. Git capture and local persistence are shared internals. The
[architecture](plugin-architecture.md) is the current package decision;
historical package proposals below are superseded.

After the first agent-counterparty loop (UX-25c), discuss
[UX-25d: local Codex review → GitHub PR](review-handoffs.md#ux-25d--a-codex-review-evolves-into-a-github-pr)
and [UX-25e: quote a PR comment → send to Codex](review-handoffs.md#ux-25e--quote-a-github-comment-and-send-it-to-codex).
Both are deferred workflow design, not part of the package rename or a claim
that PR creation and cross-counterparty handoff are available.

### Remaining delivery queue — reconciled September 14

This queue supersedes older sequencing and status statements below. Preserve the
original UX IDs; suffixes below split work into reviewable increments. **Build**
means missing user-facing behavior; **refine** builds on an existing flow;
**validate** requires evidence, not another implementation of the same feature.
Priorities express product value, not estimated implementation time.

| Order / priority | Story / kind | Interaction to deliver | Owner / prerequisite |
| --- | --- | --- | --- |
| 1 · P1 | UX-06/18 · validate then refine | Code card → exact reply → selected quote → preview → original position; refine a cue only where discovery fails | Existing guide/discussion; unfamiliar-user observation |
| 2 · P1 | UX-08b/21a/09 · validate | Verify private/public edit, delete and resolve scope and uncertain-outcome recovery | GitHub provider; authorized disposable review and actor roles |
| 3 · P2 | UX-12d/20b · extend where provable | Historical review → verified original comparison → discussion → return | Backend revision evidence; unknown original base remains explicit |
| 4 · P3 | UX-23a · service dependency | Workspace application exists; retain native GitHub browser fallback until a supported service contract is established | [Public-schema assessment](github-suggestion-service-contract.md); generic commits are not native suggestion application |
| UX-14 · optional core delivered | Validate | Explicit per-file personal service Viewed read/mark/unmark and receipt recovery | [Contract](service-progress.md); live writes remain unverified; local marks remain independent |
| Separate track · P2 | UX-25c · finish integration | Start/resume one agent → answer inline → review resulting capture | Start/resume UI and supervisor fixture core exist; prepared-run abandonment is implemented; real adapter and extended iteration validation remain |

UX-22 participant inspection is now implemented for local feedback and supported
GitHub published inline/general comments. `:ReviewReactions` shows people grouped
by reaction below the existing choices, including explicit unavailable-account
counts. Viewing names never mutates; identity-unknown readers can still inspect
names. This uses the existing lazy read and introduces no new default key.
[Contract](provider-api.md#message-reactions-extension) ·
verification (local evidence: `../output/reaction-members/validation.json`).
Review-summary/private message reactions and live write-role validation remain
outside this increment. Older participant-list “remaining” notes below are
superseded by this status.

UX-14 now exposes optional per-file service progress through explicit commands.
This is deliberate personal-state synchronization, not automatic equivalence
with local compared-content marks. The service API cannot atomically bind a mark
to an expected commit; stale/unknown outcomes and that limitation remain visible.
[Contract and evidence](service-progress.md).

Already implemented increments are not queued again:

| Story | Implemented interaction | Remaining limit |
| --- | --- | --- |
| UX-13/15/16 measured refinements | Bounded cache improvement, faster wrapping, reader return without redundant reflow/reload, final-width initial rendering | Async adoption still costs ~0.6 s for the 250-message fixture; no SLA or unfamiliar-user result is claimed. Further performance work needs a concrete problem; [evidence](interaction-performance.md) |
| UX-24a | Head-bound read-only readiness, required check classification, review/merge facts, paging, reload/cancel and source links | Full policy and unreported requirements are not enumerated; [contract and evidence](readiness.md) |
| UX-23a | Exact single-suggestion workspace preview/application, resulting capture, original-message annotation and receipt recovery | GitHub service commits/batches remain separate; [contract and evidence](suggestion-application.md) |
| UX-09b | In-place Resolve/Reopen, waiting/failure/unknown cues, explicit receipt checking and retained Activity details | Live service roles and unfamiliar-user observation |
| UX-18c | Full-area narrow reading tabs with source preservation and exact return | Unfamiliar-user observation; split mode remains supported |
| UX-18d | Compact outcomes with full identifiers in a read-only details view | Broader readability observation |
| UX-22b | Explicit Add/Remove in the reaction chooser; durable retry/receipt recovery | Live service write-role validation; participant inspection is implemented |
| UX-15b | Targeted complete-thread lookup from history with exact reply and paging fallback | Search-result entry, private/mixed lookup and general lookup outside this increment |
| UX-25a/b | Select/save assignments, read per-comment outcomes, navigate result/reply and cancel participation | Agent process start/resume is UX-25c |

This order follows the comment-focused audit. Validation can close without new
UI; capability metadata and backend helpers alone do not close a missing user
route. The participant runtime is a separate product extension. No agent-specific
branch belongs in the renderer, and no second destination/store is introduced.
Full interaction triggers and recovery contracts follow. The current
[comparison and evidence](review-ux-gap-audit.md) supersede intermediate status
narratives later in this document.

### First iteration packet

The [local discovery trial](ux-trial.md) is now runnable with default or remapped
keys and an isolated fixture. It prepares a task sheet, observation form and
view-transition trace. The scripted harness verifies the lab, and deliberately
leaves the human result marked `not-observed`. The
[completion audit](parity-validation.md) separates the remaining human/service
inputs from implemented interactions.

Use UX-06/18 as the next comment-UX packet. This is a validation-led refinement,
not a request to rebuild the existing reader. Performance work can proceed
independently; GitHub permission verification is a separate release-evidence
track and need not block shared-UI improvements.

**One comparison fixture:** two threads at the same source anchor; one contains
a root, two replies, an attributed nested quote, a link, and a suggestion.
Include an unresolved thread and a resolved thread, plus a saved private draft.
Use exactly this content for both card and reader views at 80×24 and 120×40.
Use the existing GitHub reference for the HTML hierarchy; only call a comparison
paired when the fixtures actually match.

| Step | Interaction contract | Evidence to record |
| --- | --- | --- |
| Find | Starting in code, identify the intended thread and open its second reply | Uncoached completion, wrong turns, and whether the actual configured cue was found. |
| Read | Distinguish author, message body, quoted text, proposed replacement and thread state | Paired real Vim renders; no state communicated by color alone, clipped target identity or ambiguous suggestion text. |
| Act | Quote only a selected passage, inspect preview, then return to the draft and original source | Correct message/bytes, retained register and source position; no action implicitly targets the root. |
| Understand delivery | Predict whether saving or sending affects only local storage, a private review or published feedback | User's stated expectation versus the labeled action. Record ambiguity before proposing a label change. |
| Continue | Refresh inserts an earlier reply while composing; return to the same selected message | Stable identity and preserved draft, mode, user windows and return location. |
| Finish | Resolve the selected thread through its explicit action | State changes in place; every reply remains expanded; uncertain delivery retains the existing receipt-check route. |

**Implementation rule:** for each observed failure, attach the failed step,
current cue or screen, proposed change, owning UX ID and repeatable acceptance
case. Prefer refining the existing card hint, reader header or action label.
Do not add a new menu, default key or storage concept unless the existing route
cannot satisfy the task. Successful observation can close this packet with no
UI changes. The tests already establish correctness; observation establishes
whether someone can discover the route.

**Delivery order after this packet:** extend verified historical navigation
(UX-12d/20b); investigate
single GitHub suggestion commits before batching (UX-23a). Keep real agent
adapter integration on its separate UX-25c track. Optional Viewed synchronization
and reaction participants do not block this comment-focused milestone.
The measured performance refinements are delivered; retain their regression
evidence rather than treating the old synchronous fixture cost as an ongoing
GitHub loading defect.

#### UX-09b — Resolve and reopen without leaving the discussion

- **Status:** core implemented. Explicit commands/menu actions now send in
  place; a bodyless composer and second confirmation are absent from the normal
  path. Unknown state exposes `:ReviewCheckThreadState` and a message-menu
  action; opposite commands cannot replace uncertain intent. Activity retains
  read-only details. Existing resolution semantics and expanded cards remain.
  This supersedes UX-09's historical confirmation requirement.
  Evidence and 80/120-column terminal renders (local evidence: `../output/direct-resolution/validation.json`).
- **Original evidence:** `session#ChangeThreadState` created/reopened a bodyless operation
  buffer, then invoked `session#Send`, which prompted for confirmation. GitHub
  documents an explicit Resolve conversation action followed by resolved state
  and collapse. [Official workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/commenting-on-a-pull-request).
  We adopt the direct action; our expanded-thread decision remains in force.
- **Entry:** selected thread's action guide or explicit `:ReviewResolve` /
  `:ReviewReopen`. Multiple threads at the source anchor require selecting the
  exact thread first. Opening the guide, navigating or inspecting state never
  mutates anything.
- **Desired flow:** show the available verb and target; deliberate activation
  persists the existing operation, displays waiting in place, and updates from
  the backend result. Keep the reading position. No normal-path bodyless
  composer or second confirmation. This is a specific state command, not a
  generic toggle whose meaning can change during refresh.
- **Recovery:** while sending, suppress duplicate activation. For an unknown
  outcome, expose Check outcome against the original operation; never flip to
  the opposite verb or resend blindly. Known failure offers a clear retry when
  still permitted. Opposite pending intent must be reconciled before reversal.
  Preserve access to operation details through existing Activity recovery.
- **Acceptance:** fixture coverage for resolve and reopen, two threads at one
  anchor, stale state, permission loss, deletion, transport exceptions, restart
  and late callbacks. Preserve source/message identity, scroll, draft bytes,
  registers and another window's Insert mode. State/counts agree after success;
  already-desired state is an explicit no-op. A read observing the desired state
  is distinguished from a receipt proving this operation succeeded.
- **Visual acceptance:** paired 80×24 and wider terminal renders retain the
  selected thread and readable replies during waiting, success and failure.
  Resolution does not collapse cards, mark files Viewed, approve a review or
  change an assignment outcome.
- **Owner / size:** shared session UI, medium; reuse backend capabilities,
  expected state and durable receipts. Live GitHub permission verification is
  a separate release check. Do not generalize to publication, deletion,
  suggestion application or agent launch.

#### UX-25a — Assign selected feedback

- **Entry:** select a saved line/file message in the discussion surface, or
  select several such messages in an assignment list. Show count, file/range,
  author and a text excerpt; use stable IDs, not displayed row numbers.
- **Flow:** choose a configured participant; inspect selected messages and the
  exact retained comparison; create the assignment through a durable local
  operation. The preview states that the participant can read the full selected
  threads, including later replies, rather than only the excerpts.
- **Acceptance:** unselect/cancel preserves comments; changed message versions
  or comparison require a fresh preview; duplicate targets are rejected;
  unsupported/general messages explain why they cannot be selected. Restart or
  lost response reconciles the original operation without creating another
  assignment. No configured participant produces a useful setup explanation.
- **Boundary:** assignment creation does not itself launch a process. Existing
  storage permits up to 50 targets; the UI must expose that limit. Current
  owner API, Vim outbox integration and receipt-only recovery are implemented;
  retain them while finishing runtime integration.

#### UX-25b — Read outcomes and stop participation

- **Entry:** review action guide → assignments → selected assignment. Show
  participant, selected comparison, per-comment outcome and updated state.
- **Flow:** open the exact original message, agent reply or verified resulting
  comparison; return to the same assignment item. Refresh does not steal focus
  from a human composing a reply.
- **Acceptance:** distinguish assigned, working, needs input, addressed, failed
  and cancelled; preserve mixed/partial outcomes. “Addressed” is the agent's
  claim, not thread resolution. Cancel explains that it revokes this assignment's
  MCP access and preserves the discussion; it must not claim the OS process was
  stopped. Reconcile interrupted cancellation against current owner state.
- **Boundary:** scoped MCP cancellation, Vim presentation, command availability
  and durable cancellation recovery are implemented. Cancellation requires a
  fresh assignment version and does not claim to terminate an OS process.

#### UX-25c — Run one participant through the shared contract

- **Current status:** start/resume integration has a fixture-verified core.
  The mapped/command action, saved preview, complete-intent receipt, supervisor,
  exact-session resume and assignment status reading are wired. Actual Vim plus
  a deterministic executable exercises the supervisor and real MCP over restart.
  [Runtime contract and evidence](participant-runtime.md). Real Codex execution,
  and a longer human-reply/result-capture cycle remain; do not claim the whole
  UX-25c story complete. `:ReviewAbandonRun` now supplies the missing recovery
  action for outdated preparations, with exact-run receipts and active-process
  protection. Abandonment evidence (local evidence: `../output/abandon-run/validation.json`).
- **Entry:** a saved assignment → explicit start/resume action for one adapter.
- **Acceptance:** persist assignment/run identity before uncertain launch can
  produce duplicate work; reconnect to the same run or show an explicit unknown
  state. Attribute replies via participant identity. A later human reply is
  available in the assigned thread. Exit/failure, per-comment outcomes and source
  changes remain distinct. Open a resulting retained capture and return to the
  selected feedback; do not automatically resolve, approve or commit.
- **Scope:** one real adapter first, with a restart demonstration. Synthetic MCP
  tests establish transport/storage behavior only. Codex, Claude and other
  adapters can follow the same contract; GitHub/Piper remain review backends
  rather than hard-coded card variants. Provider-specific feasibility is separate.

#### UX-18c — Give narrow reading views more space

**Implemented follow-up:** dedicated reading tabs now preserve the original
source windows across comments, composition, preview and assignment navigation.
Narrow flows choose them automatically; `g:revue_reading_layout` also offers
explicit `tab` and the earlier `split` mode. Existing views are not moved on
resize. Hidden-window repaint keeps text and caches current without a visible
tab switch; an actual Insert-mode callback test preserves mode, buffer, window
and typed text. User-created splits/tabs survive closing views and the session.
Source navigation finds the original windows across tabs; if they were all
closed, it opens a separate source tab with an explicit explanation.

The same 80×24 assignment fixture gains two reading-window rows (19 → 21).
Unlike the earlier clone, assignment → discussion → return retains one reader
window. Native buffer labels now identify Discussion, Reply, Preview and other
surfaces rather than ending in opaque IDs. The earlier split geometry remains
covered separately. Paired renders and verification (local evidence: `../output/reading-tabs/validation.json`).

**Prototype result:** a disposable `:tab split` reader gains two body-window
rows at 80×24 (19 → 21), but following an outcome's discussion and returning
rebuilds four panes in that reader tab. The correct outcome returns; the
full-area geometry does not. It is not adopted. A viable implementation must
explicitly manage cross-tab window
identity, asynchronous callbacks and nested origin restoration, or use another
approach. This result rejects the naive tab clone, not all full-area designs.
Probe and paired renders (local evidence: `../output/assignment-density/validation.json`).

The earlier 80×24 history render retained minimized source panes above the
content. Native Focus still behaves this way in explicit split mode.
Pending/history metadata compaction was already implemented.

The acceptance contract for this increment is: paired 80×24 renders gain usable
body rows, retain a concise
target/state/return cue and improve the code → reply → preview → return journey.
Preserve draft bytes, registers, source cursor, selected message, user splits
and resized layouts. If a user changes window topology, explain any limited
restore instead of closing their new windows. Avoid assuming a new tab or
window reconstruction is necessarily better; compare with current Focus first.

#### UX-06/18 — Make the exact-message action route apparent

**Implemented entry refinement:** the card's old “full thread” hint pointed to
all file discussions. It now advertises focused message selection/quotation
through the configured thread command; file cards use their configured file
thread command. The real-text discussion header exposes configured message
motions, actions and quotation. No new menu or default binding is added.
A refreshed chooser follows its captured thread ID after reordering, and rejects
a removed/moved thread or changed source location/view. Exact-thread quotation,
preview/return, registers and custom/unmapped commands pass; the full suite
passes. Evidence and captures (local evidence: `../output/thread-entry/validation.json`).
Unfamiliar-user observation below remains open.

- **GitHub reference:** the action menu belongs to an individual message in a
  thread. Quotes and edits must target that message, not implicitly the root.
  See C01–C04/W04 in the [reference specification](github-review-ux-spec.md).
- **Current Vim route:** a source card is virtual text. Open the real-text
  discussion through the thread action, move to the intended reply, then use
  its message actions. The guide and configurable mappings already exist;
  adding another menu is not automatically an improvement.
- **Proposed refinement:** if observation reveals a missed transition, add a
  short contextual cue at that transition, using the actual configured key or
  command. Keep selected author/message context visible when the menu opens.
  Never imply that a virtual row can receive Vim's text cursor.
- **Done when:** an unfamiliar Vim user can find reply 2, quote only a selected
  passage, preview and return to the same source position without coaching.
  Record wrong turns and action count rather than inventing a speed target.
  Automated checks must also preserve exact identity with two threads on one
  anchor, earlier replies inserted by refresh, custom mappings and deleted or
  unauthorized targets. Test native yank, Visual selection and registers.
- **Owner:** shared Revue presentation. No provider-specific menu or new store.
  A successful discovery observation may close this item without more UI.

#### UX-18d — Put discussion ahead of technical metadata

**Implemented core:** outcome reading now abbreviates IDs, keeps dates compact
and moves run identifiers into `:ReviewAssignmentDetails`. The read-only details
view retains full metadata as yankable text; delayed outcome refresh does not
replace it or steal focus. Close restores the selected outcome and position.
In the paired 80×24 fixture, the first original body moves row 15 → 14 and the
second outcome heading row 22 → 20. This is a presentation measurement, not a
usability study. Full-area geometry remains separate UX-18c work.
Validation (local evidence: `../output/assignment-density/validation.json`).

- **Original evidence (before implementation):** `assignment#View` emitted full assignment/message IDs, timestamps,
  references and repeated state explanations. The retained
  80-column outcome render (local evidence: `../output/assignment-outcomes/80-outcomes.png`)
  makes their screen-space cost visible. GitHub's author/body/action hierarchy
  is the reference (F02/C01), rather than its exact typography.
- **Entry and flow:** open assignment outcomes → scan participant, file and
  outcome state → read original feedback and response → inspect full details
  through an explicit action when needed → return to the same reading position.
- **Acceptance:** at 80×24 and 120 columns, compare identical fixture content
  before/after. Gain body rows without losing participant identity, path,
  outcome state, loading/error cues or the distinction between addressed and
  resolved. Keep original versus resulting comparison distinguishable.
  Show opaque IDs compactly in the reader, with exact values copyable in a
  details view; never truncate identities used for commands or recovery.
  Long Unicode names/paths wrap without obscuring the selected message.
- **Boundary:** ordinary reading views only. Preserve full scope and consequence
  in assignment, cancellation, publication and runtime previews. Details access
  is not comment collapse. Reuse the existing guide and return mechanism;
  no new backend schema or conversation store is needed.
- **Owner / size:** Revue presentation; small-to-medium prototype. Independent
  of runtime completion; coordinate with UX-18c geometry to measure each gain.

#### UX-22b — Make lightweight acknowledgement lightweight

**Implemented core:** selecting Add/Remove now sends the persisted intent
directly from the chooser. No draft window or second confirmation opens.
Waiting, Retry and Check outcome are separate row actions/states; receipt
recovery retains the original operation and actor even when counts or read
permission disappear. The contextual guide uses the selected action label and
configured key. A delayed response preserves another reply's text and final
editor focus; normal draft autosave remains active. Existing Activity recovery
also works for retained operations. Full Revue suite passes, including the
local backend; actual GitHub mutation roles remain a separate release check.
Vim captures and validation (local evidence: `../output/direct-reactions/validation.json`).

- **Original evidence:** `session#React` opened a bodyless draft and `session#Send`
  asked for another confirmation. Counts, actor state, permissions and receipt
  recovery already existed. The implementation simplifies that flow using the
  same backend contract.
- **Entry and proposed flow:** selected message → reaction chooser showing
  current count and your state → explicit Add/Remove action → update status in
  place and remain on the message. Opening the chooser or moving its cursor
  performs no mutation. The action label names both intent and reaction.
- **Acceptance:** avoid a separate composer and redundant confirmation for this
  operation. Persist the exact requested state and operation ID before sending;
  double invocation cannot produce duplicates. An unknown outcome stays unknown
  and reconciles the same receipt, including after restart. Keep unrelated
  draft bytes, message selection, scroll position and registers unchanged.
  Permission loss, deleted targets and failed reads remain visible and do not
  optimistically assert a server change. Explicit removal remains available.
- **Boundary:** reaction acknowledgement only. Do not automatically simplify
  publication, deletion, suggestion application, review decisions or agent
  launch using this precedent. Reaction membership remains the optional UX-22
  service capability. No invented generic Undo for uncertain remote operations.
- **Owner / size:** Revue action flow plus existing backend contracts;
  medium. Validate with fixture recovery tests and authorized service checks
  before declaring full GitHub parity.

#### UX-15b and UX-12d — Reach the right feedback and source

For **15b**, targeted history lookup has a verified core in `feedback#LookupMerge`,
`session#LoadEventDiscussion`, the local provider and the GitHub companion.
The 501-thread local fixture required ten page actions after the initial fifty
threads; lookup required one action and exposed 51 threads rather than all 501.
This measures navigation/payload cost, not service latency. Real Vim/local
transport passes across two reopens, and a public GitHub lookup returned the
requested reply in a complete two-message thread using two GraphQL reads
(target plus consistency check), without writes.
Validation (local evidence: `../output/feedback-lookup/validation.json`).
A complete thread and exact message identity arrive without marking the entire
review loaded.
Cancel, unavailable/deleted/unauthorized targets and late responses preserve the
last good view and return origin. Never treat “not loaded” as “deleted.”

**Verified core gates:** foreign review/comparison/target rejection,
mocked multi-page replies within the selected thread, missing requested replies,
refresh and cancellation races, and paging after a lookup overlaps a later page.
The existing page cursor, cycle-detection history and coverage are retained.
GitHub private/mixed or historical targets retain ordinary paging or their
service link when lookup cannot return a complete unit. The selected history
entry survives return.
The present command entry is history; do not claim search-result lookup until it
has an entry point and equivalent verification. This is a bounded optimization,
not a requirement to fetch the whole review whenever a comment opens.

For **12d**, accept historical ranges only when both endpoints and semantics are
verified. Exercise renamed/deleted files, rebases, non-ancestor endpoints and
missing objects. Keep the original thread visible with a labeled one-file or
service fallback where the original PR base is unknown. More fetching alone
cannot establish a missing base; this is an evidence-limited extension.

**Original-file inspection refinement delivered:** the GitHub adapter now opens
an incremental snapshot and locates a later-page target through the existing
verified thread lookup. Private/mixed or locator-less saved references retain
bounded paging; source verification still checks the original anchor and hunk.
The UI passes an advertised opaque locator without backend-specific branching.
The general feedback cursor and saved context identity are unchanged. This
replaces a full-feedback reload, not a previously missing navigation action.
A live outdated Neovim thread outside the initial 20 opened at its original
file/lines and reopened from its saved reference. Full original PR comparisons
still require evidence of both endpoints.
[Contract](provider-api.md#original-discussion-context),
provider, Vim and live evidence (local evidence: `../output/historical-context/validation.json`).

#### Optional service interactions

**UX-23a workspace core implemented:** the selected message has a read-only
application preview. The local backend checks full file bytes and message version,
saves one replacement, preserves file metadata, and captures saved files without
committing or resolving. The exact message records applied versus observed
state; interrupted operations reconcile without repeating the filesystem write.
Actual Vim/local transport covers unsaved-buffer rejection, a dropped response,
restart, and opening the resulting capture.
[Application contract and evidence](suggestion-application.md).

**Service prerequisite verified as unresolved:** current public GraphQL
introspection exposes generic commit creation, but no review-suggestion
application mutation or `viewerCanApplySuggestion` field. The latter's earlier
mention is corrected. Retain the native browser fallback; do not keep
rediscovering this as an ordinary missing UI command. A supported native contract
or an explicitly separate generic-commit design is needed before implementation.
[Assessment and schema evidence](github-suggestion-service-contract.md).
Batch application remains later.

The retained acceptance contract starts with one proposal. The action must say whether it edits the
workspace or creates a service commit. Preview exact side/range/revision and
replacement, reject stale source, preserve the proposal on failure, show the
result and return to the same message. Batch application follows only after
single-change recovery works. Rendering/authoring suggestions already exists.

**UX-24a observation core implemented:** shared read-only view and GitHub adapter
now satisfy the bounded interaction below. [Contract and evidence](readiness.md).
Full policy enumeration remains outside this core; no merge action is exposed.

The acceptance contract is to show head-bound checks, requirements and source links; distinguish
pending, failing, passed, unavailable and stale-head data. Approval, unresolved
count and delivery success cannot substitute for merge readiness. Read-only
first; merge/land controls are outside this milestone.

- **Entry:** a capability-aware action in the existing review guide opens a
  read-only readiness view. Do not allocate a default key before this route is
  useful. Include the reviewed head, observation time and backend source link.
- **Content:** separate check results from required checks and review policy.
  A successful optional check does not satisfy an unknown requirement; skipped,
  neutral, cancelled and pending checks must not all become “passed.” Display
  unavailable policy and incomplete pages explicitly rather than inventing an
  aggregate ready/not-ready conclusion.
- **Recovery and completion:** reload and cancel preserve the last good view
  and return location. A head change labels old results stale; late responses
  cannot overwrite another comparison or steal focus from a draft. Cover no
  checks, partial results, inaccessible policy, failed reads and changed head.
  A local backend without CI exposes an unavailable reason. Completion of this
  slice enables inspection only; there is no merge or landing side effect.
- **Owner / size:** shared read-only surface plus backend data contract;
  medium. Verify service field semantics before implementing the adapter.

**UX-14/22:** remote Viewed must state local versus server ownership and handle
changed content without hiding discussions. Reaction membership needs its own
capability, paging and unknown state; existing reaction counts/toggling remain.

Split those optional features into independent increments:

| Increment | Trigger and expected interaction | Completion and recovery | Owner / size |
| --- | --- | --- | --- |
| UX-14 service progress | Explicitly opt into backend-supported Viewed synchronization; marking or unmarking a file identifies whether the state is local or shared with the service | Reconcile content/head changes and unavailable permissions; show unsynchronized state without discarding local progress. Switching review/connection cannot reuse another review's state. Marking Viewed never hides a thread. | Progress UI + service adapter; medium |
| UX-22 reaction participants | From a selected message/reaction, inspect who reacted in a read-only list | Keep exact message/reaction identity, page through members, distinguish incomplete results from zero members, preserve return position on cancel/failure, and avoid changing the current user's reaction merely by opening the list. | Message UI + service membership capability; small-to-medium |

These sizes describe interaction scope, not calendar estimates. Neither feature
blocks the core comment workflow. Browser/service links remain a usable fallback
when the capability is absent.

### Validation queue — separate from missing features

Use the [concrete current routes](review-ux-gap-audit.md#concrete-routes-to-compare)
as the baseline. A validation item only becomes implementation work after a
specific failure is recorded; keep the evidence and the proposed change linked.

| Priority / IDs | Evidence needed | Pass condition / resulting decision |
| --- | --- | --- |
| P1 · UX-06/18 | Unfamiliar Vim user at 80×24, default and custom maps: source → reply 2 → quote → preview → return | Record completion and wrong turns without coaching. Add a concise surface-specific cue only where the guide/menu route fails; do not add a duplicate menu speculatively. |
| P1 · UX-08b/21a/09 | Authorized disposable GitHub review across actor roles, root/reply/private/public states | Verify actual deletion scope and resolution permissions; preserve siblings, private summary and uncertain-operation recovery. Unsupported roots remain disabled until proven. |
| UX-13/15/16 · evidence delivered | Repeated refresh/cold-opening samples, five live GitHub reads, 40 reader journeys and 80 delivery-mode opening samples | Invariants pass. Known duplicate rendering is fixed; delayed adoption is explicitly separated from synchronous fixture gains. Reopen on a concrete real-flow problem. [Evidence](interaction-performance.md). |
| P2 · UX-10/19 | Current GitHub API capability for unchanged lines and native suggestion rendering | Capability-gate creation; received outside-hunk discussions remain readable. Do not infer API write support solely from the browser UI. |

A concrete private GitHub fixture plan (local evidence: `../output/github-validation/plan.md`)
is prepared for the currently signed-in `steckel` account. It has not executed
remote writes and requires explicit authorization to post test comments/reviews.
It can establish owner/own-message behavior only; a second actor is still needed
for foreign-author, read-only and cross-account private-visibility evidence.

Use this concrete script for the first discovery check: open a file with two
threads on one anchor; select the second reply in the intended thread; quote a
selected passage; preview; return without losing the quote or source position.
Repeat with custom keys and a refresh that inserts an earlier reply. Record
action count, wrong-target attempts and whether the user finds the message menu
without coaching. Correct stable-ID behavior in automated tests is necessary
but does not establish discoverability.

**Current audit evidence:** four focused checks passed: thread entry, action
guide, reading tabs and expanded comments. The [request-specific record](research/ux-request-audit.json)
lists exact commands, inspected sources and limitations. The earlier
[seven-check record](research/ux-audit-reconciled-current.json) remains supporting
evidence. Neither establishes live mutation permissions, real agent behavior
or unfamiliar-user discoverability. No full-suite rerun is claimed for this
planning pass. Retained renders are labeled in the
[audit evidence](review-ux-gap-audit.md#evidence-and-confidence).

### Deliberate exclusions

Keep individual inline discussions fully expanded. Global comments visibility
and unified/split choice await discussion. Native Vim editing, Visual ranges,
searchable real-text panels and explicit identity-based return are adaptations
to preserve. Full HTML rendering, avatars, moderation, rich binary previews,
repository administration and merge/land controls are outside this milestone.
Git notes remain an optional backend transport, not required conversation storage.

### Current performance result — UX-13/15/16

Five fresh Vim processes per scenario cover 100 general comments, a 100-message
thread, a 250-message thread and 500 files/2,000 messages. Each run measures
cold opening, same-process reopening and four alternating changed/unchanged
refreshes during actual Insert mode. Profiling showed the 128-body retention
limit forcing reparsing despite unused byte capacity. The entry limit is now
512 with the same 1 MiB serialized-data budget and existing invalidation rules.
Long-thread median changed adoption fell 707 → 185 ms; the largest observed
sample fell 719 → 194 ms. That experiment disabled automatic source focus;
its cold-opening number is not the normal-layout viewport benchmark below.

The next refinement speeds printable-ASCII wrapping while preserving Unicode
boundaries and complete card output. The corrected 60-process viewport
comparison measures 250-message cold opening at 1,421 → 1,327 ms (80×24) and
691 → 632 ms (120×40). Narrow first reader entry remains about 1,183 ms.
Those figures precede the reader refinement below.
Cold-opening validation (local evidence: `../output/cold-open/validation.json`).

The reader refinement avoids source-card reflow in a hidden tab and reuses
already-loaded source on return. Managed close defers resize-only events until
the final pane dimensions; native return and actual data refresh still update
cards. Forty measured journeys preserve full cards and exact source return.
At 80×24, first entry/return improves 1,827 → 484 ms; at 120×40 it improves
563 → 511 ms. The full suite and the new hidden-repaint regression pass.
The initial source-opening follow-up below closes the remaining duplicate pass.
Reader validation (local evidence: `../output/reader-entry/validation.json`).

Initial focus now precedes file delivery, so synchronous narrow opening renders
once. Its 250-message ready time improves 1,320 → 612 ms. Delayed delivery is
essentially unchanged (~670 ms including a 50 ms fixture wait), matching the
asynchronous shape used by bundled backends. Eighty samples and the full suite
cover geometry, complete cards, delayed/error delivery and focus preferences.
The identified performance refinements are delivered. Further work should be
driven by a real workflow problem, not the superseded ~1.33-second synchronous
fixture. Initial-layout validation (local evidence: `../output/initial-layout/validation.json`).

Five serial real GitHub refreshes separately measured 4.47 s median read time
and 13.3 ms median unchanged adoption. These are observed samples, not tail
percentile guarantees, and no service writes were performed. Body/markup
output, full comment visibility, draft bytes, Insert mode and exact return
remain covered. [Detailed methods and evidence](interaction-performance.md).

### Implementation history — retained for traceability

Everything from here through the original backlog cards records successive
checkpoints. A heading saying “current,” “next,” or “remaining” inside that
history refers to its checkpoint. Use only the
[reconciled queue above](#remaining-delivery-queue--reconciled-september-14)
for present sequencing and the linked contracts for acceptance.

### Current planning corrections

The [current gap audit](review-ux-gap-audit.md) supersedes sequencing statements
inside the implementation follow-ups below. Ten focused checks pass in the latest
refresh; the [record](research/interaction-backlog-refresh.json) includes exact
commands and outcomes. The earlier [record](research/current-interaction-audit.json)
retains findings subsequently fixed. Rich replies, private deletion, timeline paging and shared/local/
GitHub feedback continuation and supported message edit history have implemented
cores. Auxiliary-view contrast/chrome is now an explicit UX-18b refinement,
separate from the unfamiliar-user validation. The small overview-guide
gap (UX-06d) and unloaded history-target journey (UX-20c) subsequently gained
implemented cores; see the navigation follow-up below. The audit-only checks
do not themselves establish full-suite or live-write verification.

**Timeline follow-up — UX-20a core verified:** the first-page Boolean validation
failure recorded by the audit is fixed. First/older pages, cancellation/retry,
stable event/reply return and stale responses pass in real Vim. The full Revue
suite, 96 provider tests and companion integration/restart pass. Local paging
survives restart; changed inventories request reload. Live GitHub reads include
two successive 50-event pages. Evidence and captures (local evidence: `../output/timeline/`)
show the current core. UX-20b subsequently gained verified shared/local
navigation, with unavailable GitHub bases still explicit. UX-20c bounded retrieval and generic feedback continuation
subsequently shipped as described below.
The earlier [audit evidence](research/ux-gap-refresh-results.json) retains the
original reproduced defect and its pre-repair scope.

- **Implemented refinement — UX-06c:** existing comparison/original-code and
  file-progress journeys now appear in the contextual guide, with configured
  keys, availability reasons and identity guards. The new real Vim navigation
  guide suite covers menu execution, history changes, retained drafts and
  asynchronous Viewed recovery. Captures are in `output/navigation-guide/`.
- **Implemented range core — UX-12a:** base/head endpoints, explicit semantics,
  persistent selection, derived source retrieval, cancellation and stable picker
  selection. Local retained ranges and GitHub ancestor ranges have fixture,
  real Vim/local-backend, and live read-only GitHub evidence in the gap audit.
- **Supported core implemented — UX-12b:** local original references and GitHub's
  lazy verified original-source lookup now support exact message return and
  restart retrieval. GitHub shows one-file commit context with an unverified
  original PR base. Both Vim processes, all 86 provider tests and companion
  integration/restart pass. The initial test expectation was corrected; malformed
  responses and changed focus are covered. Live public read/reopen evidence and
  terminal captures are in `output/original-context/`. Full original-base
  reconstruction remains limited; explicit local draft re-anchoring subsequently gained the UX-12c core below.
- **Coverage/retry core implemented — UX-13/15/16:** the index now shows loaded
  and known-total counts, explicit scope and complete/partial/loading/failed/
  unsupported/unknown states. Refresh failure retains data, stable selection
  and drafts; retry makes new feedback searchable. Private/state coverage is
  separate. Full Revue, 89 provider tests, companion integration/restart and a
  live read pass. A 500-file / 2,000-message benchmark found repeated per-file
  message scans; aggregation once per redraw reduced cold open from 25.8 s to
  0.54 s and message jump from 17.6 s to 0.62 s. Interactive/remote latency
  validation, bounded refresh and private-review paging remain. Shared/local/
  GitHub continuation subsequently shipped as described below.
- **Independent release check — UX-08b:** verify private deletion permissions
  and root-with-replies scope. This does not block read-only range work.

The audit splits remote timeline, reviewed-version navigation, published
deletion and edit-history fallback into separate delivery increments. It also
defines completeness states before performance tuning and preserves native
Vim keys, fully expanded inline cards, and the deferred diff-layout decision.

### Assignment outcomes and cancellation — UX-25b

The owner can now read assignments, open per-comment outcomes, follow the exact
original message or latest loaded matching agent reply, inspect assigned/result
comparisons and return to the same outcome. Reads preserve focus and draft text;
cancelled, late, malformed and foreign-review reads retain prior data. Cancellation
uses versioned preview/confirmation, atomic backend receipts and restart recovery;
it revokes MCP access without claiming to stop an OS process. Existing replies,
outcomes and resolution remain intact. Evidence and renders (local evidence: `../output/assignment-outcomes/validation.json`).
The local assignment inventory is one complete read; pagination and automatic
polling are not included. Real runtime integration remains UX-25c.

### Vim assignment follow-up — UX-25a

The selection/creation flow now exists: loaded saved line/file messages, stable
multi-selection, configured participant choice, full read-only preview and
confirmed local creation through the durable outbox. The exact assignment receipt
survives an accepted response loss and second-process Vim recovery. Stale versions,
comparisons and changed participant configuration reject fresh submission;
receipt-only recovery remains possible. The picker has default/custom mappings
and Help return. Evidence and terminal renders (local evidence: `../output/assignment-ui/validation.json`).
Assignment/outcome/cancel browsing is now implemented above; real runtime launch/resume (25c) remains.

### Participant/MCP backend follow-up

UX-25 now has durable local assignments and a scoped stdio MCP core. Selected
comment/comparison identity, original-source reads, attributed inline replies,
per-comment outcomes and transactional receipt recovery use the existing backend
store. [Contract](participant-mcp.md) and validation (local evidence: `../output/participant-mcp/validation.json`)
include synthetic stdio, concurrent recovery, cancellation and two real Vim
reopens. The Vim picker/preview/creation and outcome/cancel presentation now work; actual
participant launch/resume adapters remain to implement; this does not complete the agent workflow.

### Large-thread rendering follow-up

UX-13/15/16 now reuses exact inline body rows and body-relative Markdown spans
across refreshes. Context changes invalidate rendered bodies; metadata, actions
and permissions remain fresh. Caches retain bounded data in memory and never
limit the displayed comments. Five actual Vim typing runs per scenario measured
median changed-refresh adoption at 216 → 42 ms for 100 general comments and
540 → 97 ms for a 100-message thread. Evidence (local evidence: `../output/thread-rendering/validation.json`)
covers source/width/Markdown changes, cache budgets, current permissions and exact
typing/return. Broader latency sampling and unfamiliar-user validation remain;
these fixture measurements do not establish a service or OS-paint guarantee.

### Changed-refresh responsiveness follow-up

UX-13/15/16 now accelerates plain-text runs in the inline Markdown reader.
Syntax-bearing characters keep the original parser behavior. A deterministic
corpus produces identical text, spans and links in 1,212 old/new comparisons.
Five actual Vim typing samples per case show median adoption of changed feedback
at 1.310 → 0.220 s for 100 general comments and 2.727 → 0.583 s for a
100-message thread. Draft bytes, focus, Insert mode and reply return are retained;
the full Revue suite passes. Evidence (local evidence: `../output/changed-refresh/validation.json`)
separates instrumented profiling from ordinary typing measurements. These use
fixture callbacks, not remote service or OS paint timing. Large-thread pauses,
broader tail latency and unfamiliar-user observation remain open.

### Narrow auxiliary-view density follow-up

UX-18b now condenses the Pending header and incomplete-review cue while keeping
backend ownership, unpublished state, loaded/total counts, action guide and
return visible. The 80×24 fixture reaches its first comment body at row 11,
previously row 15. Existing continuation and verification actions remain in the
guide. Edit history shares identical provenance/details after the loaded
entries; different metadata remains per revision. Its second body moves from
row 18 to row 16. Literal content, target mapping and window geometry are
unchanged. Evidence (local evidence: `../output/auxiliary-density/validation.json`) includes real
isolated Vim terminal renders; these are not OS screenshots or a user study.
Broader layout refinement and unfamiliar-user validation remain open.

### Remote responsiveness follow-up

UX-13/15/16 now has measured request scheduling and unchanged-refresh refinement.
Independent file/review, merge-base and actor reads overlap within a four-worker
limit. Successful paging retains its final GraphQL consistency guard and removes
a duplicate REST read; complete fallback still revalidates. An identical accepted
snapshot updates status without rebuilding rich conversation or draft buffers.
Changed messages, permissions and inventory continue to update normally.

Evidence (local evidence: `../output/remote-latency/validation.json`) records a provider sample of
4.805 → 3.965 s with identical snapshot fingerprints and nine → eight reads.
Actual Vim/bridge/GitHub typing probes observed unchanged adoption at 357.6 →
11.2 ms, with exact text and Insert mode retained. These establish concrete
improvements, not general latency guarantees. Changed-page rendering, large
nested discussions and tail-latency measurement remain.

### Private-review paging follow-up

UX-13/15/16 cut B now keeps pending comments inside complete paged threads,
including private replies to published roots. Pending shows loaded/total counts
and the exact private actor/review identity. Full-record verification through
`:ReviewVerifyPending` is required before publication, discard or summary editing;
individual loaded comments keep their own native permissions and versions.
No read or verification sends feedback. A private connection that cannot account
for its full comment count falls back to complete opening instead of claiming
complete coverage. The Pending view reuses contrasting surfaces and the guide.

Evidence and captures (local evidence: `../output/private-pages/validation.json`) cover pagination,
partial-operation gates, exact target return, stale/cancelled reads, complete
verification, actual bridge subprocesses and restart. The full Revue suite (36 local tests), 131 provider tests and companion
integration pass. The live check validates schema/public paging only; live private permissions and deletion scope remain
release checks. Measured remote latency and unfamiliar-user observation remain.

### Bounded-refresh follow-up

UX-13/15/16 cut A now supports one outer feedback page per explicit refresh or
continuation. Partial replacements retain the current view until its loaded IDs
are covered or the fresh inventory ends. Continue/cancel and retry are exposed
in the guide and status bars; exact selection, draft text, actual Insert-mode
callback delivery, stale reads, malformed pages and restart interruption are
tested. Both local and GitHub bridges opt in; legacy callers and private GitHub
state keep complete-reader fallbacks. No accepted bodies enter the outbox.

Validation and captures (local evidence: `../output/bounded-refresh/validation.json`) record the
supported core. The full Revue suite (36 local tests), 124 provider tests and companion
integration pass. One live public read (local evidence: `../output/bounded-refresh/live-read.json`)
matched the complete inventory but the bounded initial read was slower in that
sample (4.670 s versus 2.843 s). Further latency work needs request-level evidence.
This is not a bound on all HTTP requests: file/review lists and
nested replies remain uncapped by the outer page. Private paging, broader remote
latency budgets and remaining narrow-layout refinement are still open.

### Explicit draft-move follow-up

UX-12c now provides `:ReviewReanchorDraft`, source/file selection through
`:ReviewReanchorHere`, an old/new preview, explicit acceptance and cancellation.
Line/file drafts and suggestions retain their exact body. Acceptance creates a
fresh local submission ID and records `reanchored_from`; saving failure restores
the original. Tentative selections do not survive restart or change the outbox.
A changed draft, refresh, comparison or permission invalidates the preview.

Both bundled backends advertise the local-preparation capability. Their existing
anchor policies still govern the chosen target. No backend mutation happens
until the user later sends the moved draft. Replies, private-review operations,
frozen work and uncertain submissions cannot be retargeted. Missing original
source is explicitly labeled rather than substituted with current code.

The full suite passes with 36 local tests, including a real Vim/local-backend
rename/move/send/restart scenario that produces exactly one comment. There are
also 124 passing provider tests and companion integration. Focused fixtures
exercise unchanged text, Help/cancel/return, persistence rollback, stale preview,
file anchors and suggestion sides. Evidence and captures (local evidence: `../output/reanchor/validation.json`)
record the supported workflow. Bounded refresh subsequently gained the core above; private paging and remote latency remain next;
broader historical-source recovery and participant/MCP work remain separate.

### Exact saved-message deletion follow-up

UX-21a now provides `:ReviewDeleteMessage`, a compact read-only preview, explicit
Send confirmation, per-message actor/scope/version checks, receipt validation,
and neighboring-message return. Existing operations for the same message are
reopened rather than duplicated. Unknown acceptance remains frozen across
restart; checking the outcome never deletes again. Local draft discard and
private-review deletion remain separate actions.

Local owner-authored inline/file/general comments and replies support atomic
removal with retained audit events and receipts. Deleting a root preserves the
thread ID and other replies; deleting its last message removes the empty thread.
GitHub supports own published inline/general comments with current native
permissions. Roots with replies and published review summaries remain unavailable.
GitHub has no documented atomic conditional-delete protection; preflight cannot
exclude every concurrent edit/reply. Live GitHub deletion has not been exercised.

Validation and captures (local evidence: `../output/published-deletion/validation.json`) include
real Vim frozen restart recovery, actual local-backend deletion/restart,
GitHub fixture contracts and companion integration. These establish the supported
core, not unverified service behavior. Explicit local draft re-anchoring subsequently gained the UX-12c core above.
Bounded replacement refresh subsequently gained the core above.

### Auxiliary-surface implementation follow-up

UX-18b now gives history entries full-width card colors, distinct author/date
headers and muted provenance. The existing guide contains reload/older/cancel
and link actions; the view retains scope, coverage and return access. The shared
`autoload/revue/surface.vim` painter is also used for previews. It colors ordinary
text lines without padding or rewriting stored bodies, and clears when managed
buffers change roles. There is no comment collapse or new diff mode.

The full Revue suite passes, including 33 local tests. Additional checks retain
literal tabs/Unicode/fenced content through resize and verify Help cleanup and
exact-message return. At 80 columns, the first recorded body moved from terminal
row 18 to row 11. Evidence (local evidence: `../output/auxiliary-surfaces/validation.json`) and
80×24 history (local evidence: `../output/auxiliary-surfaces/80-history.png`) are actual isolated
Vim terminal renders. User observation and refinement of other auxiliary views
remain; published deletion is still UX-21a.

### Message-history audit correction and presentation follow-up

UX-21b already has `:ReviewMessageHistory`, reload/older/cancel, explicit scope
and exact-message return. Local history derives before/after diffs from retained
edit events. Supported public GitHub comments and published review summaries
use native edit content, which may include creation and is not promised to be
a reconstructed patch. Redacted/unavailable bodies stay unavailable. Private
GitHub histories and revision deletion are outside the supported scope.

The latest focused test passes for reply identity, paging, cancellation,
redaction, stale callbacks and return; retained public reads are in
the history evidence (local evidence: `../output/message-history/live-read.json`). This refresh
re-inspected the 80-column history render (local evidence: `../output/message-history/80-history.png`).
At that earlier checkpoint, plain headings, repeated provenance and command
rows were a presentation gap. The subsequent auxiliary-surface follow-up above
adds card styling and moves commands into the guide; repeated provenance and
remaining pane chrome are still candidates for measured refinement. UX-18b prioritizes
consistent contrast and more space for message content, using actual narrow
workflow observations. This is refinement, not a second history implementation.

Published deletion subsequently gained a supported core in UX-21a. Keep it separate from local draft discard,
private-message deletion and revision redaction.

### Reviewed-comparison navigation follow-up

UX-20b now accepts an event's `reviewed_comparison` and `comparison_provenance`,
displays its endpoints and opens it through `:ReviewEventComparison`.
`:ReviewReturnContext` restores the same event and offset. Conflicting references,
missing provenance, head mismatch and one-file excerpts cannot masquerade as a
full reviewed comparison. Changed history/selection prevents late navigation.

The local backend retains references on newly saved reviews and recovers older
reviews from their saved receipts and retained revisions. Capture events also
open their source. No current-head/time inference is used when evidence is
missing. GitHub events still lack verified original PR bases; their reviewed
heads and browser links remain an explicit limited case.

The full Revue suite passes, including 31 local tests and a two-process real Vim
local-backend open/return scenario. Additional Vim cases verify failure, malformed
responses, identity conflict, changed focus/history and empty/current comparisons.
Evidence and terminal captures (local evidence: `../output/event-comparison/`) record the supported
core. Published-message deletion subsequently gained a supported core; broader GitHub
historical recovery remains a backend limitation.

### Overview and history navigation follow-up

UX-06d exposes the existing Conversation view as “Read review purpose and
general conversation” in the action guide, using the configured key. It is
omitted inside that view. Source position survives visiting it and refreshing.

UX-20c now offers `:ReviewLoadEventDiscussion` for unloaded history targets.
Each action loads one complete feedback page and opens the exact message if
found; another page requires another action. Cancellation, errors, exhaustion,
changed selection, reloaded history and draft typing preserve context. Closing
the discussion returns to the same event and offset. Direct backend lookup is
an optional refinement; unavailable targets keep refresh/browser routes.

The full Revue suite passes. New real Vim cases verify page-two reply selection,
complete threads, cancellation, malformed/error results, refresh superseding
reads, Help, history reload, custom/disabled keys and retained typing. Saved
terminal captures (local evidence: `../output/history-navigation/`) show the loading state and
exact second reply. These are isolated fixture terminal cells, not OS screenshots.
No backend implementation or live remote feedback changed.

### Incremental feedback follow-up

UX-13/15/16 now has shared LoadMoreFeedback/CancelFeedback controls and a local
adapter. Pages contain complete discussions with all replies or individual
conversation messages; merge/retry preserves exact selection and unsent text.
Older pages become searchable without being marked new. Refresh supersedes
outstanding pages. Local cursors bind review/comparison/current feedback and
survive restart when unchanged; large reviews open with 50 units. Manual local
refresh still loads all feedback. SQLite storage reads are unchanged.

Real Vim fixture and actual local-transport coverage, local restart/cursor tests
and terminal captures are recorded in output/feedback-pages (local evidence: `../output/feedback-pages/`).
GitHub now implements the same contract for signed-in public reviews: 20
complete threads and 50 general comments per page, plus all review summaries.
Private reviews and unsupported GraphQL use the complete reader, and manual
refresh stays a full replacement read. A new private review or changed source,
actor/update marker/count requires refresh. Nested replies, REST-compatible
message versions and exact anchors are verified. The full Vim suite, 109 provider
tests, companion restart and a real Vim bridge fixture pass. Live reads include
20 + 14 threads whose 77 messages/anchors/versions match REST, and 50 + 37 general
comments. See GitHub paging evidence (local evidence: `../output/github-feedback/`).

Bounded refresh, private-review paging and remote latency budgets remain;
UX-13/15/16 is not fully closed by this implementation.

### Rich reply follow-up

UX-17/05 now supplies shared inline code/emphasis/strike/link spans, readable
link labels in cards, optional attributed quotes and semantic link selection.
Raw discussion text, native copying and existing reply drafts are preserved.
Preview cards omit formatting markers; source virtual rows retain them because
Vim cannot assign separate highlights within one virtual row. GitHub link reads
use the exact message's rendered HTML, including resolved relative hrefs;
non-GitHub backends can supply explicit destination mappings. :ReviewBodyURLs
retains the previous address finder for code examples and reference definitions.

Real Vim coverage includes a root plus three replies, second-reply attribution,
Unicode wrapping, raw copy, nested quoted suggestions and stale/late link reads.
Six provider tests cover rendered HTML, membership, versions and destination
filtering. :ReviewQuoteAttributed has no default key; plain Q is unchanged unless
g:revue_quote_attribution is enabled. Captures are in output/rich-replies/.
The full Revue suite, 72 provider tests and companion integration/restart pass.
Authenticated read-only GitHub checks verified a public conversation message's
three attachment links and an inline message with no links, each with a matching
version (doc/research/rendered-links-live.json). Private and enterprise cases
remain fixture-covered. Full HTML/GFM rendering is not required. Next implementation: review ranges and historical
context, with private root-deletion scope verification still outstanding.

### Individual private-comment deletion follow-up

UX-08b/21 now has `:ReviewDeletePendingComment`: select a private message in the
pending inventory or discussion, inspect its full body and exact target, then
confirm from a read-only operation. Stale bodies, ownership, publication and
permission changes prevent submission. Unknown receipts freeze the same target
across restart; recovery observes absence without repeating deletion. Other
messages, the review summary and unrelated drafts remain intact.

Two-process real Vim coverage and eight provider deletion tests pass; the full
Revue suite, all 66 provider tests and companion integration/restart pass.
`output/private-delete/` contains actual Vim ANSI previews at 80/120 columns.
GitHub roots with replies remain disabled until their scope is verified, and
live provider writes remain untested. UX-08b is therefore partial; richer
reading/quoting is the next implementation while those checks remain recorded.
Earlier statements that individual deletion is entirely missing are historical.

### Private staging follow-up

UX-08a now has :ReviewStageBatch: select/edit/preview local feedback, then confirm
private delivery to a new or existing review. File comments, replies, inline
comments and suggestions use individual private-save steps. Review decisions
remain in the outbox. Each receipt is saved before continuing; failures retain
per-item results. Unknown requests only reconcile, and recovered queues require
a fresh confirmation for remaining writes. Unpack restores only known-unsaved
items; publication/discard surfaces unfinished queues. GitHub spaces saves by
one second and revalidates each native target. This is explicitly sequential,
not an atomic multi-comment operation.

Four real Vim processes verify mixed kinds, interrupted creation, exact receipt
identity, partial failure, preserved decisions, permission loss, persistence
failure, safe unpack and resuming the same unsaved operation. The 58 provider
tests and companion integration/restart suite pass. Real isolated Vim ANSI
captures are in output/staging/ (preview at 80 columns; partial result at 120).
No live GitHub staging was performed. Individual private-comment deletion is next.

### Contextual action discovery follow-up

UX-06a/07 now has `:ReviewReviewActions` / `<LocalLeader>a`, with grouped Read,
Write and Review outcomes, configured keys, target identity and permission
reasons. Existing per-message actions remain separate. Composer choices make
local saving, private-save preparation and publication distinct; pending target
review remains accessible after preparation. The menu rechecks selection,
buffer, comparison, capabilities and draft state after input, so a timed refresh
cannot act on a stale choice. Existing draft/receipt/confirmation paths execute
the selected action.

`test/action_guide.py` uses real Vim to verify a permission-changing timer during
the menu, exact second-message selection through nested menus, local save,
private preparation, changed pending target, reply retention after access loss,
outbox reopening and custom/disabled defaults. Full suite passed; added guide
cases passed after refinement. `output/actions/` contains real isolated Vim
ANSI renders at 80/120 columns, not OS screenshots. Narrow chrome remains UX-06b;
the chooser alone does not complete all composer/discoverability refinements.

### Audit baseline

UX-06b/18 follow-up: common draft context is compact; full review context follows
the preview body. Critical availability and missing-source disclosures remain
above it. Preview labels no longer repeat private delivery, preview text follows
the configured reading width, and minimized review bars become quiet during
focus. The underlying windows/source and detailed edit/publication/deletion
context are retained. `test/chrome.vim` covers 80×24/120×40, private target,
full-detail retention, permission loss, long quoted paths and exact reply/source
return. Real isolated Vim ANSI captures are in `output/chrome/`; normal window
minimums, tab labels and scrolling still apply.
The full Revue suite passes with these layout changes and the new chrome tests.

Re-audited **2026-09-14** against the actual working tree. The earlier audit
below remains useful, but its findings must be read with the current status.
The original pass changed planning documents and added a disposable audit probe.
Subsequent implementation is recorded in the follow-ups and checkpoint below;
no live provider feedback has been published.

**Finding:** the core comment experience already has meaningful GitHub parity:
expanded root/replies, distinct code and discussion, message targeting, quote,
preview, atomic review submission, explicit resolution, and historical return.
Review-wide discovery and retained local revisions now have verified foundations.
The largest remaining gaps are completing native pending-review authoring, rich
message rendering, remote history and published-message lifecycle actions. A Vim split containing
real text is an appropriate equivalent to a docked browser discussion panel.

GitHub's current documentation confirms that its Comments panel combines review
threads and general conversation, supports quoting and state filters, and can
stay beside code. Its Viewed control tracks file progress and resets when a file
changes. These are interaction references; browser geometry and automatic file
collapse are not requirements for Revue.
[Comments panel](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/),
[docked panels](https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/),
[Viewed and review workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/reviewing-proposed-changes-in-a-pull-request).

### Discovery/progress implementation follow-up

UX-13/14/15 now have an implemented and tested core. `test/discovery.py` runs
across two real Vim processes and covers literal/combined/invalid/empty filters,
old renamed paths, native keys, exact-message selection, vanished targets,
refresh, absent-file/outdated discussions, colliding message IDs, frozen batch
items, retained composer text, and filtered-file reveals. It verifies local
Viewed across changed/unchanged revisions and restart, both-side/newline/binary
identity, failed and delayed reads, coalesced mark/unmark intent, late callbacks
after switching comparisons, and closing during verification. It performs no
provider mutations.

The follow-up fixed unsafe row retargeting after a filter or refresh, Help's
nested return route, and newline control characters in excerpts. Filters now
retain the selected result when possible and otherwise select an inert heading.
Content failure is labeled unverified, including a never-acknowledged file.
GitHub supplies raw content hashes; 34 companion provider tests pass, including
byte distinctions for newline endings and binary data. The full Revue suite
and companion integration/restart suite pass. Real isolated Vim/tmux captures
at 80/120 columns are in `output/discovery/`; PNGs render captured ANSI cells,
not macOS screenshots. These establish basic readability, not large-review
performance. Huge inventories and richer excerpt presentation remain refinements;
remote Viewed sync and server pending-review synchronization remain separate.

### Message rendering and composition follow-up

UX-17 now has shared metadata labels and richer block rendering. Source cards
and real-text discussions show backend role/bot, update/edit, publication and
review-decision metadata when supplied. GitHub uses existing REST fields and
known pending review IDs; local accepted messages carry a local-save label.
An Updated timestamp is not claimed to prove an edit. Native pending-review
synchronization remains UX-08.

Nested quotes preserve fenced code as insets. Quoted suggestions never compare
against the current source anchor. Lists retain indentation/numbering/task
markers, and headings have a distinct type. The real-text discussion highlights
the selected message header independently of card borders. Original Markdown
remains the copy/quote source. Very narrow nested containers preserve raw quote
text rather than overflowing. Inline per-span styling in source virtual rows,
full GFM rendering and quote attribution remain open. Explicit body URL actions
are implemented as described below; semantic Markdown links remain partial.

UX-06 also improves cached historical draft context and before/after preview:
use the draft's original comparison cache, not the currently displayed file.
Unavailable source/thread context preserves the exact target with an explanation.
`test/messages.vim` covers metadata, nested code/quotes, headings/tasks, Unicode
and long names at 12/16/24/48/90 columns, copy/quote body integrity, focus through
refresh/Help/return, preview/editor retention and original-source preview after
switching comparisons. Existing restart tests retain the missing-history case.
The full Revue suite, 36 companion provider tests and integration/restart pass.
Real isolated Vim ANSI captures are in `output/messages/` (source at 120 columns,
focused discussion at 80); they are not OS screenshots or live GitHub writes.

### Native private-reply follow-up

UX-08 now supports private replies to existing review threads. Reply/Quote on a
private root or selected private message stays private. `:ReviewReplyPending`
explicitly targets private delivery on a published discussion, and SavePending
can convert an editable ordinary reply while preserving its body. Existing text
and delivery mode are retained; frozen/incompatible replies reopen without quote
appends or duplicate drafts. Public and private reply permissions are independent.
Cards on permitted private threads offer Reply privately; public resolution stays
disabled until publication.

The backend resolves the exact native thread inside this PR, verifies reply
permission and the pending review owner/state, then calls the dedicated GraphQL
thread-reply mutation with both native IDs. The operation changes no resolution
or review decision. Replies can continue on older/outdated discussions without
inventing new line anchors. Receipts bind both IDs and exact body; recovery checks
review/root membership and preserves unknown results across restart, even after
browser publication. API preflight cannot eliminate concurrent state races.

The full Revue suite, 58 provider tests and companion integration/restart pass.
Real Vim tests cover explicit/automatic private intent, ordinary published replies,
public-to-private conversion, quoted text preservation, private permission changes,
wrong-thread receipts, restart/publication recovery, older pending sources and
unrelated outbox retention. Backend tests cover exact GraphQL arguments, missing
thread/permission, malformed reply results, and matching-parent/root recovery
without repeats. No live GitHub reply was posted. `output/pending/80-reply.png`
is a real isolated Vim ANSI render showing the quote, suggestion and private reply.

### Native pending creation and addition follow-up

UX-08 now supports `:ReviewStartPending` with an optional summary and
`:ReviewSavePending` from inline, suggestion and whole-file drafts. An inline
first comment can create a native review; later comments become new threads in
the selected review. Whole-file feedback requires an existing native review.
Preview states create versus add and the exact target. Send explicitly confirms
private delivery; local writes and publishing batches retain their meanings.

Drafts bind actor, comparison, anchor and create/add intent. Existing private
review creation is reused; unknown creation also blocks publishing, discarding
or editing a newly visible native review. Unfinished additions are surfaced
before publication/discard. Private-save drafts cannot enter publishing batches.
An older native reviewed head, ambiguous inventory or changed actor/source is
reported without silently changing targets. Private replies are recorded above.

GitHub creates via the review endpoint with no event, and adds threads via
GraphQL with the verified pending review ID. It validates full source ranges and
file identities. Receipts bind the exact content and target; first-comment
creation verifies both the review and comment receipt. Unknown results survive
restart, including missing first-comment verification. Recovery reads without
repeating a write and can recognize receipts after browser publication. API
preflight cannot eliminate concurrent source/state races. No live writes ran.

The full Revue suite, 56 provider tests and companion integration/restart pass.
New Vim tests span three processes: optional-summary preparation, first comment,
line/file additions, browser-created conflict, comparison mismatch, private batch
exclusion, malformed receipts, operation reuse and unrelated outbox retention.
Backend tests verify omitted publication events, exact GraphQL parent/range/file
payloads, invalid anchors, actor/revision conflicts and missing comment receipts.
Real isolated ANSI previews are `output/pending/80-start.png` and `120-add.png`.
They render actual Vim output and are not OS screenshots.

### Native private-editing follow-up

UX-08 now edits private summaries and existing inline comments/replies through
the shared message editor. `:ReviewEditPending` targets the selected inventory
summary/comment; `:ReviewEditMessage` works in the focused private discussion.
The editor retains original/current/proposed text, permits clearing the private
summary, and explicitly confirms Save privately. Private creation/addition was implemented in the later follow-up above.

Edits bind exact message, native review and actor identities. Refresh cannot
reinterpret a private edit as published feedback. Changed contents retain text
and require explicit EditBase acceptance. Publish/discard surfaces unfinished
private edits; editing surfaces an existing publication/discard operation.
Unknown work persists across restart and only reads for a matching receipt.

GitHub uses the review-specific private comment list to prove membership and
checks current message/parent ownership, pending state, body and version. It
PATCHes the comment or PUTs the summary without submitting a review event.
Receipt markers bind the private identity and survive later browser publication.
The API lacks an atomic version/state precondition, so concurrent browser edits
or publication after preflight can race the update. Live authenticated private
editing remains unverified; the verification uses fixture writes only.

Real Vim tests cover exact reply and summary targets, optional empty summary,
private/public transition rejection, changed bodies, preserved replacement text,
operation reuse, incomplete receipts and restart recovery. Provider tests cover
root/reply/summary endpoints, exact body-only payloads, ownership/state conflicts,
private membership, receipt preservation and no repeat write on recovery.
ANSI captures in `output/pending/80-summary-edit.png` and `120-reply-edit.png`
show real isolated Vim previews; they are not OS screenshots. The full Revue
suite, all 51 provider tests and companion integration/restart pass.

### Native pending-review discard follow-up

UX-08 now includes `:ReviewDiscardPending`. It opens a full preview of the selected
review's private summary and comments, then a separate read-only operation with
an explicit Delete confirmation. Local outbox feedback remains intact. Published
reviews are ineligible. A prepared publication or discard for the same review is
reused so an uncertain action cannot be bypassed by switching operations.

The backend rechecks verified actor/owner, pending state and exact frozen
contents. Changed contents require a fresh preview and operation; confirmation
also revalidates current session state. Unknown results persist across restart.
Recovery reads the complete reviews list for the same actor and labels absence
as observed state, without attributing it to this operation or repeating DELETE.
Failed reads and existing review IDs remain unknown. Like publication, GitHub's
lack of an atomic version precondition leaves a race after preflight.

Real Vim tests cover preview completeness, capability changes, local cancellation,
content conflicts, known rejection, malformed receipts, frozen restart and local
outbox preservation. Provider tests cover the exact DELETE endpoint, ownership,
published-state rejection, version/summary/comment checks and recovery reads.
Isolated ANSI captures at 80 and 120 columns are in `output/pending/*-discard.png`;
these render real Vim output and are not OS screenshots. No live review deletion
was performed. The full Revue suite, all 49 provider tests and companion
integration/restart pass. Creation/addition and private editing follow-ups are recorded above.

### Native pending-review resume/publication follow-up

UX-08 now supports discovering and resuming an existing GitHub pending review.
The backend verifies the actor, loads private comments through the review-specific
endpoint and merges IDs once into the discussion. `:ReviewPending` exposes summary,
source and private comments; Enter opens the exact loaded message. Unknown actor
or failed/incomplete reads are unavailable, not zero pending reviews. Private root
threads do not offer published reply/resolve operations before publication.

`:ReviewPublishPending [event]` prepares a durable publication draft for that
native review. Its preview includes the frozen private comment set and editable
summary, excluding local outbox drafts. Changed server contents preserve the
preparation and appear separately in preview. `:ReviewPendingBase` explicitly
accepts refreshed contents/comparison without replacing the user's summary.
The backend checks actor, native ID, summary/comment version, exact previewed
comment set, source refs and decision before submission. An older reviewed source
is labeled; published decision metadata identifies its source when available.

Publication receipt markers bind the frozen review/contents/decision. Unknown
responses remain frozen across restart; recovery reads the review without
submitting again and can recognize publication after later dismissal. The GitHub
endpoint lacks an atomic version precondition, so changes after preflight can
race publication. This does not establish full pending-review synchronization.

The full Revue suite and 47 companion provider tests pass. New real Vim tests
cover private inventory, exact-comment return, preview excluding local drafts,
changed summary/comments, explicit acceptance, failed/malformed writes and
restart receipt recovery. Backend tests cover review-specific discovery, actor
isolation, incomplete/unavailable state, all three publication decisions, exact
endpoint/body, receipt preservation, stale contents and unknown results. Tests
perform no live GitHub write. Creation/addition, native discard and private
editing follow-ups are recorded above.
Companion integration/restart passes. Real isolated Vim inventory/publication
previews at 80/120 columns are in `output/pending/`; these PNGs render terminal
ANSI captures, not macOS screenshots.

### Reaction interaction follow-up

UX-22 now has count footers and a lazy per-message chooser. `:ReviewReactions`
loads complete choices, counts and the current actor's state; `[you]` is distinct
from total count. Enter / `:ReviewReact` prepares an explicit add/remove operation
for the exact message, followed by normal preview/confirmation. Missing actor
state is unavailable, not a claim that the actor has no reactions. Counts remain
outside copy/quote bodies. Read errors, navigation during loading, Help, return,
unknown writes and restart recovery retain the correct target and view.

Local storage changes only the actor's membership inside a transaction and
retains receipts. GitHub validates review/thread membership and the signed-in
actor, loads exact reaction IDs, and removes only the actor's own. Its recovery
reports observed desired state without repeating a mutation or attributing the
state to an uncertain request. Summary counts need no per-message list calls;
own-state details load on demand. Neither backend edits body/version, resolves
threads, or changes review decisions as a reaction side effect.

The full Revue suite passes, including 20 local backend tests and actual local
Vim add/reload. `test/reactions.py` verifies two real Vim processes, actor/count
separation, reply identity, add/remove, read-only preview, raw copy integrity,
late reads, missing actor and frozen restart recovery. All 45 companion provider
tests pass; they cover endpoint/own-ID routing, other actors' counts, unknown
transport outcomes, post-write read failures and read-only reconciliation.
GitHub review-summary/pending-review reactions and participant drill-down remain
open; no authenticated GitHub write was performed.
Companion integration/restart also passes. Real isolated Vim captures in
`output/reactions/` show the chooser, real-text footer and source card at 80/120
columns. PNGs render captured terminal ANSI cells, not macOS screenshots.

### Published-message editing follow-up

UX-21 now has an editing interaction for exact messages. `:ReviewEditMessage`
requires explicit backend/message permission and an opaque version. Original
and proposed bodies persist in an outbox operation. Reopening retains edits;
preview shows original/current/proposed text. Refresh or provider rejection
preserves replacement text. `:ReviewEditBase` explicitly accepts a loaded newer
base with confirmation; no automatic merge or retry overwrites external edits.
Malformed acceptance freezes the operation; restart reconciliation only reads
receipts. Activity identifies the exact message, and accepted edits keep its ID.

Local writes enforce version/original-body checks inside a SQLite transaction
and retain before/after event history, including ABA changes and older comparison
views. GitHub routes root/reply, conversation and review-summary bodies to their
specific endpoints, restricts this interaction to the actor's own published
feedback, checks current versions and preserves earlier receipt markers. GitHub
does not document an atomic version precondition, so its preflight has a race
window; moderator edits, deletion and history browsing were still open at this
checkpoint. History reading has since shipped as described above. Native
pending editing is recorded above. A summary-body edit does not change a review decision.

`test/edits.py` covers real Vim creation, exact reply identity, reuse, preview,
concurrent changes, explicit base acceptance, permission loss, failures, frozen
malformed receipts and restart recovery. Local backend tests exercise retained
versions, concurrent transactions, receipts and before/after history; the actual
local-backend Vim integration also edits a reply from an older comparison.
Companion tests verify GitHub endpoint/payload routing, stale/unauthorized/pending
targets, marker preservation across edits and unknown outcomes without real
GitHub writes.

The full Revue suite passes, including 19 local backend tests and the expanded
local Vim integration. All 43 companion provider tests and its integration/
restart suite pass. Real isolated Vim previews at 80/120 columns are in
`output/edits/`; these are ANSI terminal renders, not OS screenshots. Deletion
and edit-history browsing were unimplemented at this checkpoint. The current
UX-21b reader and supported UX-21a deletion are described above. Private
editing is recorded above.

### Body URL interaction follow-up

UX-17 now provides `:ReviewBodyLinks` and a message-action entry. A numbered
chooser exposes explicit HTTP(S) destinations and raw-body line numbers, then
offers open/copy. It deduplicates addresses, preserves balanced path delimiters,
and retains message/source position. Cancellation has no effect; selection or
body changes during the chooser require a fresh invocation. `gx` still opens
the message permalink. No default key is added for the body chooser.

This is deliberately a raw-text URL aid: code examples and reference definitions
are included and labeled. Full Markdown destination parsing, escaped/entity
decoding, relative paths and backend-specific issue/commit references remain
open. GitHub renders labeled links and autolinks in comments; its repository
references also carry provider semantics that cannot be guessed for all backends.
[GitHub link syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax),
[autolinked references](https://docs.github.com/en/get-started/writing-on-github/working-with-advanced-formatting/autolinked-references-and-urls).

`test/links.py` exercises two real Vim processes, intercepting browser dispatch
without opening external pages. It covers URL punctuation/Unicode, unsupported
schemes, exact copy/open targets, both cancellations, retained view, selection
changes and refresh changing a message body. This does not establish full GFM
parity or browser-opener compatibility on every platform.
The full Revue suite passes; focused link tests were repeated after the final
identity guards. Isolated real Vim captures at 80/120 columns are in
`output/links/`; PNGs render captured ANSI cells, not OS screenshots.

### Suggestion creation follow-up

UX-19 now has an implemented core: `:ReviewSuggest`, explicit Ex ranges and a
configurable visual Plug action seed a proposal from immutable head-side source.
There is no default mapping. Same-anchor invocation reopens existing edits.
The fenced replacement preserves indentation, Unicode and literal backticks;
explanation stays outside. Empty replacement means deletion. Validation requires
one closed top-level suggestion block and explicit backend support. Existing
comment permissions, comparison checks, batch delivery and receipts apply.
No source edit or commit occurs. Beyond-hunk anchors remain UX-10; application
remains UX-23. Native GitHub pending-review synchronization remains UX-08.

`test/suggestions.py` verifies creation, selection, reopening, preview, malformed
bodies, permission/staleness retention and uncertain-result recovery across two
real Vim processes. The full Revue suite passes, including 13 local backend
tests; 38 companion provider tests and integration/restart pass. Backend tests
cover exact single/native-batch payloads, deletion and malformed-batch rollback.
No authenticated GitHub write was made; native rendering of longer suggestion
delimiters still requires live verification. Real isolated Vim ANSI captures at
80/120 columns are in `output/suggestions/`, not OS screenshots. The 80-column
capture also drove explicit wrapping of virtual composer context (UX-06).

### File discussion follow-up

UX-11 now has an implemented core. `:ReviewFileComment` and `:ReviewFileThreads`
work on a selected file-list row or managed source pane, with no default key.
The new draft kind retains path/old path/comparison and has no line or side.
Creation does not load source, enabling binary/deleted/unavailable files.
Same-target invocation retains edits; stale/disabled submissions preserve text;
unknown submissions reconcile across restart without posting again.

Explicit file threads appear before line discussions in the real-text panel
and above source in framed cards. Reply/quote, state actions, discovery and
navigation retain the root ID. A null GitHub line is not itself evidence that
a file thread is outdated. Historical placement requires the original commit
and path. Local batches accept file comments. GitHub uses the documented single
file-comment endpoint; its current REST batch contract omits this target and
the UI explains individual delivery. Native pending-review integration remains
UX-08, and live authenticated publication has not been exercised.

Evidence: `test/file_comments.py` runs two real Vim processes; local tests cover
file/reply persistence, binary/deleted/renamed/unavailable targets, batches,
rollback and recovery. Companion tests cover normalization, exact file payloads,
no fabricated coordinates, stale/malformed targets and historical identity.
The full Revue suite (14 local tests), 41 companion provider tests, and companion
integration/restart pass. `output/file-comments/` contains isolated real Vim ANSI
captures at 80/120 columns, rendered to PNG; these are not OS screenshots.

### Unchanged-line anchor follow-up

UX-10 now has a shared capability contract and local implementation. The local
backend accepts line comments/suggestions throughout any changed file's captured
text on supported sides. It validates original file/rename identity and source
bounds and preserves exact selected bytes. The UI uses the declared scope for
creation and revalidates it before individual or batch delivery. Invalid ranges,
absent content and policy changes are explicit; draft text survives. Receipt-only
recovery keeps the same anchor after restart or loss of write support.

GitHub's current adapter explicitly retains diff-hunk creation scope. The web
feature is documented, but its API caveat has not been superseded by verified
creation support in this adapter. Incoming current range comments outside the
patch remain current, render, and accept replies. Jump/next/previous thread open
native code folds hiding their target; individual comment collapsing stays absent.
[GitHub support caveat](https://github.blog/changelog/2025-09-25-pull-request-files-changed-public-preview-now-supports-commenting-on-unchanged-lines/).

`test/unchanged_lines.py` covers fallback/declared/unknown scopes, sides and source
bounds, reversed multiline selection, rename paths, received threads and native
folds, quote/reply, immutable preview, suggestion seed, policy loss, batches and
receipt-only recovery across two Vim processes. Local tests cover unchanged-line
batch acceptance on both sides, suggestion anchors, exact captured bytes and
later workspace edits. The full Revue suite (15 local tests), 41 companion
provider tests and integration/restart pass. Isolated real Vim ANSI captures
at 80/120 columns are in `output/unchanged-lines/`; these are not OS screenshots.

### Local revision continuity follow-up

The capture/history foundation of UX-12/25 is now implemented. `:ReviewCapture`
prepares a bodyless operation with explicit saved-file/untracked settings;
Send confirms it. Capture uses the review's bound workspace and fixed original
base. It retains source history and one shared conversation, offers the next
comparison without switching, and preserves unsent/unknown old drafts. Empty
subsequent diffs are valid; identical content reuses a comparison. Captures neither
commit nor resolve threads. Legacy records remain readable and explicitly default
missing untracked-file settings to excluded.

Historical local views refresh conversation on navigation. Verified unchanged
source-side hashes and stable original file paths retain placement; other line
anchors show original context as outdated. This does not implement heuristic
line-shift remapping. `:ReviewThreadComparison` follows the original reference to
the exact file/side/line with native fold opening and existing async focus guards.
Missing target files leave the current view intact. Replies/resolution remain
available against retained comparison IDs, while new feedback requires latest.

Evidence: 17 local backend tests pass, including retained history, shared replies,
legacy records, empty/repeated captures, exact receipts and a concurrent stale
capture race. The real local-backend Vim integration now captures a changed file,
opens latest, returns to original source, replies there and reloads shared history.
`test/captures.py` separately checks read-only settings/preview, malformed success,
frozen restart recovery, preserved drafts and live historical navigation. Full
Revue and companion suites pass. `output/revisions/` captures a real Vim session
backed by a disposable local Git review with two captures and shared replies;
PNGs render terminal cells, not OS screenshots.

Next: native pending-review continuity (UX-08) and the remaining message/rendering
refinements (UX-17/06). Participant selection, agent runs and MCP still remain
within UX-25; capture/history alone does not complete the agent loop.

### Ordered implementation queue

The [current gap audit](review-ux-gap-audit.md#discussion-ready-shortlist)
is the authoritative remaining-work queue. Completed foundations are retained
in the checkpoint and historical stories below, rather than scheduled again.

| Order | Remaining interaction | Priority | Existing story |
| --- | --- | --- | --- |
| 1 | Validate unfamiliar-user quote/preview/return at 80 columns; overview guide route is implemented | P1 | UX-06 / UX-18 |
| 2 | Independent release check: private deletion live and root-with-replies scope | P1 | UX-08b / UX-21 |
| ✓ | Shared/local evaluated-comparison open/return and bounded unloaded-target continuation | Core verified; GitHub base recovery limited | UX-20b/c |
| 3 | Refine auxiliary-view contrast and chrome using narrow-workflow evidence | P1 | UX-18b |
| ✓ | Inspect supported local/GitHub message edit history and return to the exact reply | Core verified | UX-21b |
| ✓ | Exact saved-message deletion with preview, permission checks and recovery | Supported core; GitHub scope/live checks remain | UX-21a |
| 5 | Bound refresh/private paging and validate interactive remote latency; continuation core exists | P2 | UX-13 / UX-15 / UX-16 |
| ✓ | Explicit local draft move with old/new preview and retained origin | Supported core implemented | UX-12c |
| 6 | Broaden historical comparison recovery where source can be verified | P2 | UX-12 |
| 7 | Assign selected feedback to a participant through the shared backend/MCP | P2 | UX-25 |
| 8 | Optional server Viewed sync and reaction participant details | P3 | UX-14 / UX-22 |
| 9 | Apply suggestions with explicit workspace/commit semantics | P3 | UX-23 |
| 10 | Inspect revision-specific checks and readiness | P3 | UX-24 |

Implemented cores tracked separately: contextual action discovery (UX-06a/07),
compact common composer/preview chrome (UX-06b/18), sequential private
staging (UX-08a), and rich reply reading/quoting (UX-17/05). Guide refinement
UX-06c is also implemented. User validation, narrow-layout refinement and authenticated
provider verification remain; these features must not be scheduled as absent.

Sizes, ownership, dependencies, acceptance scenarios and evidence limits are in
the linked audit. Native pending creation, individual additions/private replies,
editing, publication and whole-review discard already exist. Live authenticated
mutation verification remains an outstanding release check.

### Interaction contracts to preserve while closing gaps

| User journey | GitHub model | Vim adaptation / deliberate difference |
| --- | --- | --- |
| Enter a thread | Click an anchored conversation; act on a particular message | Named command enters a real-text discussion buffer. Ordinary source Enter stays native. Source virtual rows display all replies and never become fake editable lines. |
| Act on a reply | Menu belongs to that message | Message motions plus contextual commands use stable message IDs. Refresh, Help, and overlapping anchors must never reuse unrelated row targets. |
| Search all feedback | Review-wide comments surface and state filters | A separate explicit query searches full loaded message bodies; native `/` searches visible buffer text. Excerpts must not define the full-query search boundary. |
| Narrow the file list | File filtering and progress controls | Literal command arguments/completion, active summary and clear action. A thread jump can reveal a filtered file with a label. Filtering alone retains code focus. |
| Finish reading a file | Viewed also collapses the browser file | Local Viewed acknowledges compared content only. Keep cards expanded and preserve position. Cross-device GitHub Viewed sync is a separate optional backend feature. |
| Write a reply | Inline composer with context and preview | Editable Markdown buffer with non-editable target context, preview and return. Inline visual attachment is valuable; pretending virtual lines accept Vim edits is not. |
| Publish a review | Private server pending comments, then review decision | Local durable queue and backend-native batch. Local drafts and server pending comments retain separate identities and explicit save actions. |
| Resolve a conversation | Backend lifecycle, sometimes state-specific disclosure | Explicit action with authoritative state; keep text readable. Resolved, outdated, read and Viewed remain independent. |
| Inspect a new version | Revision selection and outdated thread context | Explicit immutable comparison navigation; retain source side/path/range and return origin. Never silently move a draft to matching line numbers in new code. |
| Consult review purpose | Overview/description alongside code | Existing Conversation includes description and reviewers. Improve discoverability within UX-06/20; a second browser-style panel is not automatically necessary. |
| Work with a local agent | Related GitHub workflows use PRs and remote agents | UX-25 is our product extension, not a missing GitHub clone. Same backend conversation and stable comment IDs; MCP is another client, not separate storage. |

### Evidence from the preceding audit pass (before implementation)

- Re-ran `sh test/run.sh`: all existing Revue suites pass, including 12 local
  backend tests, comparison/history and restart scenarios. Those suites do not
  yet constitute dedicated coverage of UX-13/14/15.
- Added [discovery probe](research/discovery-audit-probe.vim) and
  [recorded results](research/discovery-audit-results.json). It opens a temporary
  two-file fixture in headless Vim, filters files, finds text beyond the first
  180 characters in a later reply, opens that exact message in a revealed file,
  returns to its index identity, marks/unmarks Viewed and closes/reopens the
  session. It records only fixture file reads; no backend writes.
- The reopen in this probe occurs **within one Vim process**. Separate-process
  Viewed persistence, async races and revision invalidation remain acceptance
  work. It is not a screenshot or visual-usability check.
- Reviewed `discovery.vim`, `progress.vim`, command maps and session integration.
  UX-13/14/15 are **in progress**, not absent and not complete. Filters are
  session-local; Viewed stores local metadata. No GitHub Viewed synchronization
  exists. Search spans the loaded comparison's discussion snapshot, not every
  historical backend object or unloaded page.
- Rechecked the official sources linked above. The earlier browser atlas stays
  the visual reference; this pass does not claim a new authenticated UI audit.

Run the added probe with:

```sh
vim -Nu NONE -i NONE -n -es -S doc/research/discovery-audit-probe.vim
```

## Implementation checkpoint

The table distinguishes implemented foundations from remaining acceptance
criteria. Story IDs remain stable so earlier discussions still apply.
Implementation in one layer does not establish an end-to-end workflow.

| Story | Current evidence / remaining work |
| --- | --- |
| UX-01 | Implemented: explicit panel modes, mode-specific maps/commands, cleared row targets, Help-safe refresh. Regression tests reproduce the old failure and verify it is gone. |
| UX-02 | Implemented: buffer commands/Plug actions, configurable and disabled defaults, native diff motions and backward search, native composer macro key. Verified in `test/interactions.vim`; legacy `:Review` unchanged. |
| UX-03 | Managed return implemented: origin comparison/file/side/message identity and view restoration, including recreated source/discussion windows after manual closure. Arbitrary split topology is not reconstructed. Backend reference retrieval now supports original-comparison recovery after restarting Vim; unavailable objects remain explicit. |
| UX-04 | Implemented core: focused thread, overlap chooser, range-aware reply, real-text message selection, message motions and context menu. Further styling follows UX-17. |
| UX-05 | Implemented core: whole/selected and optional attributed quotes, append to existing editable reply, body/register copy, permalink actions and semantic rendered links. Raw text and exact-message versions are retained. Private/enterprise rendered links remain fixture-covered. |
| UX-06 | Core includes contextual target, compact preview/editor return, save-state statusline and action guide. UX-06c now exposes existing history/progress journeys with target/availability checks; unfamiliar-user and narrow-layout validation remain. |
| UX-07 | Implemented core: optional backend action rules, thread reply restrictions, disabled-decision explanations, per-action body validation, and refresh/submission revalidation. Real Vim tests cover read-only actors, permission loss with retained text, an opaque bodyless decision, and receipt-only recovery after permission loss. GitHub checks authentication/current actor and rejects self-approval; fine-grained scopes and repository policies remain server-authorized rather than fully predicted in the UI. |
| UX-08 | Implemented atomic batch workflow: select/edit/preview drafts, explicit decision and comparison, frozen durable payload, known-failure unpacking, and unknown-result recovery across Vim processes. GitHub uses one native review for inline comments plus an optional decision; local feedback uses one SQLite transaction. Unsupported kinds remain separate and visible. Native pending resume/publication, creation/addition, private replies/edits, sequential private staging and whole-review discard are implemented. Individual private-comment deletion has a core; GitHub roots with replies remain disabled pending scope verification. Live writes remain unverified. |
| UX-09 | Core implemented: targeted resolve/reopen commands and menu, read-only durable action, permissions, independent state/counts, and receipt-only recovery. Local SQLite and GitHub GraphQL have targeted tests. Live authenticated GitHub resolution remains an unexecuted release gate. |
| UX-10 | Shared scope validation and local changed-file anchors implemented, including suggestions, batch revalidation and restart recovery. Received GitHub outside-hunk threads remain readable/replyable; GitHub creation stays within hunks until broader API support is verified. |
| UX-11 | Core implemented: explicit file target/capability, list/source commands, no-source creation, file-first discussions/cards, shared replies and recovery. Local batches supported; GitHub file comments currently send individually. Live GitHub writes remain unverified. |
| UX-12 | Partial: history/lookup, persisted references/views, resume/draft retrieval and immutable drafts. Range chooser supports retained local trees and GitHub ancestor endpoints. Original-source context/return now has separate-process Vim and live read/reopen verification. Remaining: unprovable original PR bases, non-ancestor GitHub ranges, abandoned-history discovery. Explicit local draft re-anchoring is implemented separately. Local retained captures supply original-thread references. |
| UX-25 | Backend/MCP core implemented: retained captures, durable scoped assignments, attributed replies/outcomes and receipt recovery. Vim selection/preview/creation is implemented. Outcome/cancel views are implemented; actual runtime launch/resume remains in UX-25c. |
| UX-13 | Core implemented: literal filters, completion, visible traversal, stable targets, clear/empty/revealed states. Real Vim regression coverage and 80/120-column captures. |
| UX-14 | Local core implemented: content fingerprints, mark/unmark, checking/unverified states and persistence. Separate-process/revision/delayed-read tests. No GitHub Viewed sync. |
| UX-15 | Core implemented: loaded-review full-body search, discussion/draft filters, stable message/batch targets, refresh/return and Help safety. Coverage/counts, refresh recovery, shared/local/GitHub continuation and bounded replacement refresh exist. Private paging now has a supported core; broader interactive remote latency and live private-state checks remain. |
| UX-16 | Implemented core: durable delivery history/receipts and refresh errors, stable-ID new-message markers, explicit next-new/message-read/thread-read actions, and identity/focus-preserving refresh. Real Vim restart tests cover acceptance followed by local save failure and receipt-only recovery. No automatic polling or server notification sync. |
| UX-17 | Implemented terminal core: metadata, nested quotes/code, lists/tasks/headings, selected-message focus, inline spans in real buffers, labeled/reference links and optional attributed quotes. Source virtual rows retain formatting markers; original Markdown remains copyable. Full GFM/HTML is deliberately outside the parity requirement. |
| UX-18 | Implemented Vim adaptation: native pane maximization/restore, automatic narrow-terminal focus, sidebar hide/reopen, preserved reply/preview sizing and bounded card reading width. Full-width discussion remains ordinary searchable text; other splits retain Vim's minimum rows/columns. Tests and terminal captures cover 80/120/200 columns. Manual topology reconstruction remains in UX-03. |
| UX-19 | Core implemented: immutable selected-source seed, editable fenced replacement/explanation, same-anchor reopening, before/after preview, explicit head-side capability and body validation, single/batch delivery and receipt recovery. Applying proposals and beyond-hunk anchors remain separate. Live native GitHub rendering remains unverified. |
| UX-26 | Implemented: unsuccessful receipt reads retain unknown state, frozen payload/ID and receipt-only retry. Uncertain single drafts cannot be discarded; batches cannot be unpacked. Real Vim tests cover repeated failures and restart; the audit probe now verifies corrected behavior. |

Validation after resolution/recovery: the full Revue suite passes, including
11 local backend tests and `test/thread_state.py` across two Vim processes.
All 28 companion provider tests and its integration/restart suite pass.
No real GitHub mutation was performed. The interaction suite covers stale targets,
native keys/custom bindings, origin return, message selection, quote/copy,
preview body integrity, and identity-preserving refresh. Real isolated Vim/tmux
captures are in `output/interaction-foundation/`; their PNGs render captured ANSI
cells, not macOS window screenshots. Those early narrow-pane captures motivated UX-18; its later focused-reading
adaptation is verified below.

Capability validation additionally uses `test/capabilities.py` (real Vim PTY,
fixture writes only) and the companion's local HTTP provider tests. GitHub
bodyless Approve is verified against the REST contract and payload tests;
no real review was published to verify it. Batch coverage adds `test/batches.py`
(two real Vim processes), local backend tests, and companion provider
tests. These cover unselected draft retention, edits invalidating preview,
atomic rollback, one native review payload, changed-payload rejection, and
receipt-only recovery after restart/access loss. The live terminal capture
`output/batch-review/01-selected-feedback.png` shows the queue. New tests cover
resolution state/permissions, pagination, REST/GraphQL ID mapping, enterprise
endpoint, read-failure fallback, exact local receipts, observed-state recovery,
failed receipt reads, and refresh failure after acceptance.

The isolated captures in `output/thread-state/` show resolved status, counts,
expanded replies and the reopen hint. They render actual Vim/tmux ANSI cells;
they are not macOS screenshots. Computer use denied access to iTerm with a safety
restriction. Tall virtual cards still clip when the panel takes much of the
screen. The later UX-18 implementation provides focused real-text reading for
that case; it does not claim Vim virtual rows themselves become scrollable.
Current `output/layout/` captures verify focus at 80/120/200 columns. The
`test/layout.vim` suite additionally reaches the end of an 80-line reply,
composes in context, restores original split sizes, hides/reopens the
sidebar, preserves focus during refresh, resizes and verifies the opt-out.

UX-16 validation adds `test/activity.py` across two real Vim processes. It checks
legacy outbox loading, durable acceptance plus failed refresh, inserted-message
selection, namespace-safe message IDs, unread persistence/acknowledgement,
absent-file thread navigation, untouched composer text, safe activity actions,
and recovery after backend acceptance followed by a local save failure. Batch
restart tests also verify retained outcomes and item receipts/targets. The full
Revue suite and companion integration/restart suite pass after these changes.
`output/activity/` contains real isolated terminal captures of the activity view
and a new reply. These are ANSI-cell renderings, not OS screenshots.

The subsequent comparison foundation adds `test/comparisons.py` across two Vim
processes: immutable draft anchors after revision changes/restart, original
file/side/message returns, manual discussion closure, reused file IDs, changed
base/renames, empty comparisons, and delayed callbacks. The companion integration
now exercises a new comparison through its actual process bridge. All 29 provider
tests pass, including historical source refs and rename paths. The complete Revue
suite and companion integration/restart pass. `output/comparisons/` records the
observed-comparison picker and an explicit jump to newer code in real Vim.

History follow-up adds `test/history.py`, 12 local backend tests, and 33 companion
provider tests. All Revue and companion integration/restart suites pass. The
companion restart test now retrieves saved historical source through its actual
process bridge. The live public read and fresh-response Vim capture are recorded
under `output/history/`; UX-12 below defines their scope and remaining gaps.

## Audit conclusion

Our strongest areas are comment/code separation, immutable source anchors,
focused message reading and quoting, draft persistence, and atomic review
batches. The remaining difference is chiefly completing the review loop: authoring
server-side pending feedback, inspecting richer review history, and managing
published feedback across revisions. Discovery and retained local comparisons
now support the core navigation loop. Resolution, durable outcome feedback, and observed-comparison navigation
now have implemented foundations. Card decoration alone will not close that gap.

**The newly reproduced defects are now fixed:** UX-26 preserves uncertainty
and UX-09 commands invoke a tested lifecycle. The earlier Help targeting defect
is also fixed. Preserve these regression cases as the rest of the UX expands.

Next complete richer composition and range selection/re-anchoring where
supported, preserving the verified discovery/filter/progress slice. Preserve the implemented
focused reading and delivery/read-state behavior as those surfaces expand.

The browser's interaction model needs adaptation. A virtual card is not an
editable region of the source buffer. Use the card for reading and orientation,
and a focused, real-text discussion buffer for selection, search, quoting, and
message actions. That buffer can sit beside or below code and retain the same
card styling. It should feel like entering the discussion, not abandoning it.

## Scope and design rules

- Preserve immutable source buffers, correct line/range identity, strong card
  contrast, gutter boundaries, and all replies remaining expanded.
- Use Vim motions, visual selection, registers, splits, jumplists, and command
  completion where they help. Do not copy browser single-letter shortcuts.
- New actions get named commands and `<Plug>` mappings before default keys.
  Proposed action names below describe behavior; final command spelling is open.
- Separate selecting an object from acting on it. Never infer a message from
  an unrelated panel's row number or from the most recently opened thread.
- Keep one backend responsible for reading and writing its review. Native
  pending reviews, resolution, permissions, and receipts belong there.
- The shared local outbox is not a GitHub pending review. A saved local-backend
  message is accepted conversation, even though it has not gone to a website.
- New UI must work with the local backend and a fixture without GitHub installed.
  Unsupported backend actions are omitted or explained, never simulated.
- Keep the legacy `:Review` callback/clipboard flow working. It currently differs
  from the rich `:ReviewLocal`/provider session; do not silently redefine its keys
  or promise that its batch export is already a remote review transaction.

**Held decisions:** unified versus side-by-side; global comments visibility;
mouse-first interaction; changes to card contrast. Individual thread collapsing
is removed and is not a backlog candidate. Native resolved/outdated state is a
separate concern. No global toggle is authorized by this backlog.

## Current behavior versus intended interaction

| Area | GitHub reference | Our working tree | Assessment / backlog |
| --- | --- | --- | --- |
| Inline thread appearance | Root, ordered replies, rich body and footer; C01–C06 | Framed virtual rows, author badge, quotes, code, suggestions, gutter | Preserve; refine semantic detail in UX-17 |
| Message selection | Each message has identity and actions; C01, W04 | Focused real-text thread, stable message IDs, message motions and action menu | Core implemented, UX-04; source virtual rows remain read-only display |
| Search/copy/quote | Select text, copy links, quote into reply; C03–C04 | Whole/selected/attributed quote, raw register copy, semantic links and full loaded-body search | Core implemented, UX-05/15/17; private/enterprise links retain fixture-only verification |
| Navigation | Source, discussions, revisions are linked; S04–S07 | Native diff/search, thread motions; file/side/comparison/message return; managed source/discussion recreation | UX-02/03 managed foundation implemented; history/restart, supported ranges and verified original context implemented; full original-base recovery remains limited |
| Panel state | Different views expose appropriate actions; S06 | Explicit mode, cleared targets, Help-safe refresh | UX-01 implemented and reverified |
| Composer | Context, draft, preview, pending feedback; W01–W03 | Target/context, Markdown editor, compact read-only preview, saved/error status and action guide | UX-06/18 core and overview-guide route implemented; unfamiliar-user validation remains |
| Publish | Individual comment versus pending review plus decision; W02–W03 | Public atomic batch and separate sequential private staging; native pending creation/resume/edit/publication/discard | UX-08 core implemented; live mutation and private deletion scope validation remain |
| Action availability | Role/state-dependent controls; section 8 | Review/thread rules, per-action body validation, GitHub actor check | UX-07 core implemented; message-level rules follow new actions; server policy checks remain authoritative |
| Thread lifecycle | Resolved and outdated are independent; V03–V04 | Commands/menu, state/counts, permissions, confirmation, durable operations and recovery | UX-09 core implemented; live GitHub validation remains |
| Anchor choices | Both sides/ranges, file-level, unchanged lines in changed files; W01, R03 | Explicit file anchors and backend-scoped line ranges; local whole changed-file scope | UX-10/11 core implemented locally; wider GitHub API anchors remain unverified |
| New revisions | Historical comparisons and re-review; R01–R04 | Refresh retains current code; picker/latest/previous open observed immutable comparisons with separate caches/views | UX-12 partial; supported ranges and verified original context work; GitHub non-ancestor ranges and full original-base recovery remain; local draft movement is implemented |
| File progress | Filter/navigation/Viewed; F03 | Literal filters and local content-aware Viewed are implemented and regression-tested | UX-13–14 local core complete; remote sync optional |
| Discussion overview | Comments panel and state filters; S06 | Loaded-review index with thread/conversation/draft results and exact-message navigation is implemented | UX-15 core complete; large-review tuning |
| Async feedback | Pending, published, updated, unavailable; W02, section 8 | Frozen outbox, durable activity/receipts/errors, new-message navigation and explicit acknowledgement | UX-16 core implemented; local metadata, manual refresh; UX-26 preserves uncertainty |
| Narrow layout | Responsive reading surfaces; A02 | Native focus/restore, optional sidebar, automatic narrow reading, bounded card text | UX-18 implemented as a Vim adaptation; arbitrary manual-window lifecycle remains UX-03 |
| Suggestions | Render, propose, optionally apply; C05 | Selected-source proposal seed, editable replacement, anchored preview and normal delivery | UX-19 core implemented; beyond-hunk UX-10 and application UX-23 remain |
| Published-message actions | Edit/delete/history, reaction, quote; W04, C01 | Exact-message quote/copy/link, version-aware edit, supported edit history and own reaction updates | UX-21a GitHub scope/live verification and UX-22 participants/additional message kinds remain |
| Timeline/checks | Typed history and automated feedback; S03, S08 | Typed paged history and exact loaded-message return; no checks/readiness view | UX-20b shared/local comparison navigation and UX-20c bounded target retrieval implemented; GitHub base recovery and UX-24 readiness remain |
| Local iteration | Analogue of revision/re-review loop; R04 | Explicit new captures in the same review, retained source, shared replies and original-anchor return | UX-25 foundation implemented; assignments/runs/MCP remain |

### Code evidence

| Evidence | Source |
| --- | --- |
| Views, targets, origin, messages, composers, submissions and refresh | [`session.vim`](../autoload/revue/session.vim): `s:Panel`, `s:Return`, `FocusThread`, `MessageActions`, `Quote`, `s:Composer`, `s:Sent`, `s:BatchSent`, `s:Refreshed` |
| Commands, native keys, resolution/receipt recovery | [`maps.vim`](../autoload/revue/maps.vim): `Apply`; session `ChangeThreadState`, `CheckReceipt`, `s:Sent`, `s:BatchSent` |
| Message identity, batch preview, availability | [`discussion.vim`](../autoload/revue/discussion.vim), [`batch.vim`](../autoload/revue/batch.vim), [`capabilities.vim`](../autoload/revue/capabilities.vim) |
| Virtual cards, limited body parser, suggestion comparison | [`comments.vim`](../autoload/revue/comments.vim): `Rows`, `s:Body`, `s:Fenced` |
| Normalized objects and operations | [Provider API](provider-api.md), including the thread-state extension |
| Shared ownership and proposed extraction boundary | [Plugin architecture](plugin-architecture.md) |
| Frozen local capture and backend limitations | [Local backend contract](provider-api.md#bundled-local-backend), [`revue_local.py`](../python/revue_local.py) |
| Companion actor rules, native review batches, GraphQL resolution scaffolding | [`reviewhub.py`](../../vim-code-review-github/python/reviewhub.py): `action_rules`, `batch`, `thread_states`, `change_thread_state` |
| Companion already provides query, pagination, empty/error states | [`reviewhub.vim`](../../vim-code-review-github/autoload/reviewhub.vim): `Open`, `Search`, `s:Listed` |

The companion links point outside this repository and require that sibling
checkout. They are audit references, not runtime dependencies of Revue.

### Direct Vim probe: original findings and verification

[Probe source](research/interaction-audit-probe.vim) and
[current output](research/interaction-audit-results.json) are reproducible with
the command below. The [original output](research/interaction-audit-before.json)
records the pre-fix behavior shown in the table.

```sh
vim -Nu NONE -i NONE -n -es -S doc/research/interaction-audit-probe.vim
```

The probe creates and deletes a temporary outbox. Its fixture rejects new write
requests and simulates two failed receipt reads. It does not connect to GitHub,
edit source files, or alter the user's active Vim session.

| Probe | Original audit result | Meaning at audit baseline |
| --- | --- | --- |
| Source `]c`, `[c`, `?` | No plugin mappings | Native motions/search restored |
| Source Enter | Unmapped | Individual inline toggle remains removed |
| Threads → Help → targets/reply command | Empty targets; reply command absent | Earlier targeting defect fixed |
| Help → Refresh | Still Help | View mode preserved |
| Invoke `ReviewResolve` | E117: unknown `revue#session#ChangeThreadState` | Exposed action unfinished, UX-09 |
| Unknown single → receipt-read failure with `unknown: 0` | Becomes `failed`; composer editable | Prior uncertainty lost, UX-26 |
| Unknown batch → same read failure → Unpack | Becomes `failed`; contained draft restored | Frozen uncertain payload can change, UX-26 |

Before the fixes, the probe established the unlock/state transition, **not a duplicate remote
comment**. Adapters may still reject changed operation payloads; the UI must
preserve uncertainty independently of that protection. Existing passing tests
originally covered successful receipt recovery, but not this failed-read sequence.
Current output now shows `unknown` for both operations, a non-editable single,
a retained batch after attempted unpack, and resolution returning an unavailable-
action explanation for the capability-free fixture. New targeted tests also
exercise supported resolution and successful recovery after restart.

### External evidence used for prioritization

GitHub's newer Comments panel includes general conversation, quote replies, and
resolved/unresolved filters. This supports prioritizing review-wide discovery
and thread state alongside our existing focused-thread view.
[GitHub February update](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/).

GitHub distinguishes unpublished review comments from submitted feedback and
supports file-level comments and suggestion creation. Revue's local outbox is
useful but is not synchronized native pending-review state. Viewed progress
should be adapted independently from GitHub's file-collapse behavior.
[GitHub review workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/reviewing-proposed-changes-in-a-pull-request).

The [reference spec](github-review-ux-spec.md) remains the source for the full
surface inventory, screenshots, classic/new distinctions, and unverified
authenticated interactions. This refresh adds no new browser visual claims.

## Priorities and sequencing

P0 fixes correctness defects; the targeting, uncertainty and missing-handler
defects recorded here are now closed in the working tree.
P1 completes the everyday discussion
and review loop. P2 improves efficiency and broader parity. P3 adds workflows
with substantial provider or workspace implications. These are ordering
recommendations, not delivery dates or new authorization for remote writes.

Effort is relative: **S** one focused change, **M** several UI/contract changes,
**L** a workflow spanning shared UI and backend. Dependencies describe minimum
behavior needed, not a requirement to finish every enhancement in a parent item.

| ID | Pattern | Priority | Effort | Owner | Depends on |
| --- | --- | --- | --- | --- | --- |
| UX-01 | Explicit panel mode and safe action targets (implemented) | P0 closed | S | Revue | — |
| UX-02 | Native navigation and configurable action keys | P1 | M | Revue | — |
| UX-03 | Predictable focus and return position | P1 | M | Revue | UX-01 |
| UX-04 | Focus a thread and select an individual message | P1 | M | Revue | UX-01, UX-03 |
| UX-05 | Quote, copy body, copy/open permalink | P1 | M | Revue + backend metadata | UX-04 |
| UX-06 | Contextual composer, preview, draft state | P1 | M | Revue | UX-03 |
| UX-07 | Capability-aware actions and review validation | P1 | M | Revue + backends | — |
| UX-08 | Draft queue, batch preview, publish review | P1 | L | Revue + backends | UX-06, UX-07 |
| UX-09 | Thread status, resolve/reopen, state disclosure (core implemented) | P1 release verification | L | Revue + backends | UX-04, UX-07 |
| UX-10 | Comment outside loaded hunks in changed files | P1 | M | Revue + backends | UX-07 |
| UX-11 | File-level feedback | P2 | M | Revue + backends | UX-07 |
| UX-12 | New comparison and historical return path | P1 | L | Revue + backends | UX-03, UX-07 |
| UX-13 | Filtered file navigation | P2 core complete | M | Revue | UX-02 |
| UX-14 | Viewed progress tied to content | P2 local core complete | M | Revue + optional backend sync | UX-13 |
| UX-15 | Review-wide discussion index and search | P1 core complete | M | Revue | UX-04; UX-09 for state filters |
| UX-16 | Stable refresh, new replies, outcome feedback (core implemented) | P1 core complete | M | Revue + metadata | UX-01, UX-03 |
| UX-17 | Message metadata and readable Markdown | P2 | M | Cards + backend metadata | UX-04 |
| UX-18 | Narrow windows and bounded reading width (implemented adaptation) | P2 core complete | M | Revue + cards | UX-03 |
| UX-19 | Create a suggestion from selected code | P2 | M | Revue + backend validation | UX-06, UX-10 |
| UX-20 | Typed timeline and review-event navigation | P2 | M | Revue + backends | UX-04, UX-12 |
| UX-21 | Edit/delete published feedback | P2 | L | Revue + backends | UX-04, UX-07 |
| UX-22 | Reactions and lightweight acknowledgement | P3 | M | Revue + backends | UX-04, UX-07 |
| UX-23 | Apply a suggestion deliberately | P3 | L | Revue + capable backend | UX-07, UX-12, UX-19 |
| UX-24 | Checks/findings and review readiness | P3 | L | Companion/backends + Revue | UX-07, UX-12 |
| UX-25 | Local human–agent revision loop | P2 architecture track | L | Local backend + participant integrations | UX-08, UX-12 |
| UX-26 | Preserve uncertainty after a failed receipt read (implemented) | P0 closed | M | Revue + backend contract tests | Existing single/batch submission |

Use the [reconciled delivery queue](#remaining-delivery-queue--reconciled-september-14)
for remaining work. UX-13/14/15 have implemented, tested cores; preserve their
regressions while adding richer composition and the remaining revision loop. Keep the closed
P0 regression cases and the provider release gates throughout.

This ordering is a proposal for implementation planning. Merge/land, changing
diff presentation, and a global comment visibility toggle remain outside it.

## Backlog cards

### UX-01 — Explicit panel mode and safe action targets

**Status:** Implemented; retain regression coverage.

**Original gap, now fixed:** Help retained thread targets and refresh selected
its renderer from the thread map. Explicit modes now own targets and actions;
the current probe and interaction suite verify the fix.

**Implement:** explicit view kind plus view-owned row targets. Rebuild or clear
targets on every view transition; actions validate the current kind and target.
Help should not inherit reply/create-conversation actions as valid help actions.

**Acceptance:** Threads → Help → `r` creates no draft; refresh preserves Help;
Conversation never replies to a former thread; a panel reopened after manual
closure has correct mode and mappings. No backend mutation is issued by any
invalid-context action. Existing thread jump/reply still works. Reference S06.

### UX-02 — Native navigation and configurable action keys

**Status:** Implemented in rich sessions; legacy bindings intentionally unchanged.

**Original gap, now fixed in rich sessions:** native diff motions, reverse
search, and composer macro recording were overridden. Commands/Plug mappings,
configurable defaults and context help now exist. Short actions in immutable
review panes are deliberate; users can disable them. Legacy `:Review` is unchanged.

**Implement:** commands and `<Plug>` actions, configurable default mappings, and
a no-default-maps option. Keep distinct hunk and discussion navigation. Context
help reports actual active bindings; avoid assuming Ctrl-S reaches Vim through
every terminal/tmux configuration. Retain an Ex submission command.

**Acceptance:** a user can keep native diff motions and `/`/`?`, bind thread
motions separately, use native editing in a composer, and complete all review
actions without Ctrl-S. Mappings stay buffer-local. Reference A01.

### UX-03 — Predictable focus and return position

**Status:** Managed return behavior implemented; backend history remains UX-12.

**Behavior:** origins retain comparison, file, side, cursor/scroll, panel mode,
and stable message identity. Returning after changing files/comparisons restores
the original source and view. Returning to a discussion selects its original
message even if preceding messages changed. A manually closed source or discussion
window is recreated for that return, using the retained buffer/snapshot. Arbitrary
user-created split topology and exact geometry after manual closures are not
reconstructed. If the original comparison is unavailable, keep current code and
explain why. Cross-process comparison retrieval now uses saved references and backend lookup.
An unavailable object is an explicit error, never substituted source.

**Implement:** record origin window, file, side, source position, selected thread
and message, plus scroll position. Closing a panel or completing a reply returns
there when it still exists; otherwise use a documented fallback. Refresh must
not move focus away from the user's active edit or selected message.

**Acceptance:** base-side reply, panel reply, reopen draft, refresh while typing,
and manual origin-window closure all preserve valid context. No new action
silently switches the compared revision. Reference S06, A01.

### UX-04 — Focus a thread and select an individual message

**Status:** Core implemented; compact overlap chooser remains.

**Current foundation:** focused real-text threads, message identities, motions,
action menus and range-aware replies exist. Virtual rows still cannot provide
normal source-buffer selection/search. Overlapping threads currently open the
file thread list; a dedicated short chooser remains a refinement.

**Implement:** a focused real-text thread view with semantic message boundaries
and stable IDs. Enter it from any line in the thread range. For overlapping
threads, use a short chooser with author, preview, range, and reply count.
Provide next/previous message and a context action list for the selected message.
Retain source and all expanded inline cards while this view is open.

**Acceptance:** a three-author thread and two threads sharing an anchor are
unambiguous; selection/copy/search works with ordinary Vim operations; replying
targets the chosen thread; message actions target the chosen comment ID. A long
thread can be read entirely without altering source coordinates. C01–C02, A01.

### UX-05 — Quote, copy body, copy/open permalink

**Status:** Core implemented, including attributed quoting and semantic links.

**Current foundation:** whole/selected/attributed quoting, body/register copy,
web permalink copy/open and semantic rendered links exist. Local-reference
semantics and private/enterprise live verification remain limited; missing web
URLs stay explicit.

**Implement:** quote visual selection in the focused message view into its reply
composer; offer whole-message quote, body yank, and permalink copy/open. Preserve
Markdown/code and quote attribution where available. Local messages can expose
a stable local reference without pretending it is a web URL.

**Acceptance:** selected lines from the second reply seed the correct thread's
draft; existing draft text is retained; yanking uses the selected register;
missing URLs produce an unavailable action; no external browser opens merely
on focus. C03–C04, W04.

### UX-06 — Contextual composer, preview, draft state

**Status:** Compact context, preview, save state and contextual action guide
implemented, including UX-06d overview discovery. Unfamiliar-user validation remains.

**Current:** non-editable context, separate rendered preview, original comparison
context and save-failure state exist. Virtual context wraps to composer width;
delivery outcomes and compact preview are implemented. Validate the complete
journey with unfamiliar users at 80 columns before adding more controls.

**Implement:** a compact, non-editable context area separate from draft text:
backend/review, source range or thread summary, and intended operation. Offer
rendered preview, retain cursor when returning to edit, and show saved/unsaved/
failed/unknown state persistently. Use backend-specific Save/Publish wording.

**Acceptance:** source context is never included in the submitted body; a long
target remains discoverable at narrow widths; previewing cannot publish; save
failure leaves text visibly unsaved; closing/reopening restores text and target.
Successful local acceptance says Saved rather than Sent. W01–W02.

**UX-06d — Implemented overview route:** Conversation is a Read outcome in
the contextual guide. `C` / `:ReviewConversation` opens the description and
requested reviewers. The guide uses the actual binding and omits the redundant
action inside that view. Custom/disabled keys and source return after refresh
are verified. No new overview panel was added. S02/S06.

### UX-07 — Capability-aware actions and review validation

**Status:** Core implemented; extend object rules as actions are added.

**Current foundation:** review/thread rules, optional-body decisions and
submission revalidation exist, including current edit/reaction/private-message
rules. Extend capabilities for new actions. Permission prediction is deliberately incomplete: the provider still
authorizes actual writes. Keep denied actions discoverable with clear reasons.

**Implement:** per-review/thread/message actions and validation rules supplied by
the backend, including whether body text is required. Refresh capabilities as
identity/state changes, with backend revalidation at submission. Keep opaque
action IDs and native labels. Support a legacy adapter fallback explicitly.

**Acceptance:** read-only, author, reviewer, and non-Git fixtures show accurate
choices; supported approval without prose works; empty ordinary comment remains
invalid; permission loss retains the draft and explains the failure. W03, §8.

### UX-08 — Draft queue, batch preview, publish review

**Status:** Atomic batch core plus native pending-review discovery, resume,
publication, editing, discard, creation, thread addition and private replies
implemented, including sequential multi-draft private staging and scoped
individual private-comment deletion.

**Current:** local selection/edit/preview and atomic submission exist. Existing
GitHub pending reviews can be resumed, inspected and published with frozen
comment/summary/version checks and receipt-only recovery. Local drafts are not
automatically server pending comments.

**Remaining:** private deletion of roots with replies and live mutation
verification. Native creation/addition, private editing and review discard
are implemented.
GitHub preflight has an unavoidable update/publication race without a documented
atomic version precondition. Sequential private staging already presents
per-item results; it is not atomic. Keep UX-26
regression coverage for uncertain-result handling.

**Implement:** select drafts, inspect/edit/remove individual items, choose a
decision, and review the exact submission contents. Backend declares atomic
native review, persistent pending review, or individual delivery semantics.
Freeze the selected versions for submission; keep independent item receipts.

**Acceptance:** three comments plus summary can be reviewed before publishing;
unselected drafts remain untouched; partial success marks accepted items and
retains the rest; timeout/restart reconciles without reposting; local Save batch
does not imply GitHub publication or start an agent. W02–W03, G06–G07.

### UX-09 — Thread status, resolve/reopen, state disclosure

**Status:** Core implemented and fixture-verified; live authenticated GitHub
resolution remains an unexecuted release gate.

**Current foundation:** commands/menu, target-specific permissions, state/counts,
confirmation, read-only durable operations and receipt recovery are implemented.
The local and GitHub backends share the UI. The original missing-handler defect
is closed. Missing state remains explicit and resolution does not hide discussion.
The criteria below remain the regression and live-verification contract.

**Implement:** independent resolution and anchor-currency fields, permitted
thread actions, and backend receipts. Show state in card/index. Make Resolve
separate from Reply; if a combined action is supported, label it explicitly.
Default to leaving discussion readable after resolution; design any native
state-specific disclosure separately, without restoring arbitrary thread folds.

**Acceptance:** current/outdated × unresolved/resolved fixtures display correctly;
missing state says unknown rather than unresolved. Select thread, inspect action
and target, confirm, then refresh authoritative state. Resolve/reopen occurs
only after that explicit action; failure retains prior state; counts agree with
the index. Unsupported actions explain why; overlap requires explicit selection.
Resolved cards remain readable. An observed desired GitHub state is not proof
that this client operation caused it. Cover read failure/restart/permission loss
without repeating an uncertain mutation (UX-26). V03–V04, G08.

### UX-10 — Comment beyond currently loaded hunks

**Status:** Shared scope contract/local workflow implemented; broader GitHub
creation support remains unverified.

**Implemented:** `capabilities.comment.anchors` declares diff-hunk or whole
changed-file scope and supported sides. Source-aware creation and single/batch
revalidation preserve draft text when support changes. Local mutation validates
captured text independently of hunk membership, including suggestions. Incoming
threads are placed from their actual current coordinates. Native fold opening
on thread navigation exposes the target without introducing comment toggles.

**Remaining:** verify a supported GitHub API creation path beyond hunks before
widening that adapter's declared scope. Unsupported creation explains the
browser/whole-file alternatives. No arbitrary unchanged-file access is inferred.

**Acceptance:** unchanged line in a changed file, reversed multiline selection,
base-side deletion, renamed path, and unavailable content each resolve correctly.
An unsupported anchor produces a precise reason without dropping draft text.
No arbitrary unchanged-file capability is inferred. W01, R03.

### UX-11 — File-level feedback

**Status:** Core implemented; real Vim and backend fixture verification passes.

**Implemented:** distinct whole-file draft/action from file-list rows or source
panes with explicit capability. Target-aware composer/preview, existing-draft
reopening, file-first discussion, framed cards above code, exact root replies,
discovery, stale protection and receipt-only restart recovery. Binary, deleted,
renamed and unavailable files require no content fetch. No line 1 is fabricated.
Native Vim places virtual rows above the first buffer line for presentation;
that position is never serialized as a file-comment coordinate.

**Remaining:** authenticated GitHub write verification. Native review batching
for GitHub file comments is deferred to UX-08; current REST adapter explicitly
supports individual publication, and local batches already accept file comments.

**Acceptance:** file comment retains path/comparison without a fabricated line 1;
replies remain attached to that file; unsupported backends offer an explicit
general-conversation alternative. W01, G14.

### UX-12 — New comparison and historical return path

**Status:** Backend history and restart recovery implemented; full story partial.

**Behavior:** refresh retains displayed code and reports newer comparisons.
`:ReviewComparisons` loads backend history when supported and shows saved refs,
with viewing/latest/historical labels. Enter retrieves/opens a comparison;
`:ReviewLatest` and `:ReviewPreviousComparison` navigate; `:ReviewLoadHistory` retries
the inventory. Human-readable commit titles and abbreviated source IDs lead;
`:ReviewCopyComparison` copies full reference JSON to a Vim register.

The locked atomic outbox persists comparison references, ordering, selected
file/side and view positions, with no source or published conversation mirror.
Startup shows backend current code. `:ReviewResumeComparison` explicitly retrieves
the last saved selection; `:ReviewDraftComparison` retrieves an open draft's
original comparison. IDs and ranges never move automatically. Missing or
mismatched historical data retains source and draft text and reports an error.
Late results cannot replace a later selection, steal an edited draft's focus,
or roll back a newer latest pointer. Caches remain comparison-scoped.

GitHub lists the PR comparison and paginated reachable commit comparisons using
each commit's first parent. Saved refs may recover surviving abandoned objects.
Historical source comes from immutable object IDs, alongside current conversation
and permissions. Only verified original-head anchors are placed inline; uncertain
historical-base/path anchors remain readable with original diff context. A file
inventory reaching GitHub's 300-file comparison cap is rejected because completeness
cannot be established. Local history exposes retained captures with current
shared conversation, conservative source-hash placement and direct original return.

**Range follow-up:** UX-12a now provides explicit endpoints for retained local
captures and GitHub ancestor comparisons. References and selection persist.
Non-ancestor GitHub ranges remain unsupported; do not substitute a merge base.

**Original-context follow-up:** UX-12b's GitHub lookup and ReturnContext now have
a verified supported core. The adapter distinguishes verified original head from
a matching first-parent excerpt and explicitly leaves the original PR base
unverified. Exact message return, managed-panel recreation, late/malformed reads,
retained drafts and restart pass in real Vim. The live public read/reopen and
captures are linked from the [current evidence](review-ux-gap-audit.md#evidence-and-confidence).

**Remaining:** non-ancestor GitHub ranges, discovery of every abandoned
force-push revision, richer historical-base
anchor reconstruction, and agent-run participation (UX-25). The implemented
history scope is stated in the picker; this is not full timeline parity.

**Verified:** `test/history.py` spans two real Vim processes and covers qualified
backend keys, saved refs/positions, explicit resume, original-draft comparison,
copy/register targeting, missing/mismatched responses, changed navigation and
out-of-order history/refresh results. `test/comparisons.py` retains immutable
anchors, changed bases/renames, empty comparisons and delayed source responses.
Local backend tests verify single-capture retrieval/isolation. Companion process
integration retrieves an old comparison after restart; its 33 provider tests
include commit pagination, exact refs/fork paths, file caps and anchor projection.

A live anonymous read of [vim-fugitive PR #2474](https://github.com/tpope/vim-fugitive/pull/2474)
listed three refs, restored an earlier commit comparison, and loaded both source
sides. Evidence: `output/history/live-github-read.json`. The real-Vim capture
`output/history/01-github-history.png` uses fresh public API responses; it is an
ANSI-cell rendering, not an OS screenshot. No live GitHub write was performed.
API limits: [GitHub compare documentation](https://docs.github.com/en/rest/commits/commits#compare-two-commits).
References R01–R04 remain applicable.

### UX-13 — Filtered file navigation

**Status:** Core implemented and regression-tested; large-review tuning remains.

**Current code:** `:ReviewFileFilter` accepts path/status/threads/viewed fields
with literal values and completion. Active summary, visible count, empty result,
clear and labeled reveals exist. Next/previous use the visible inventory.

**Verified:** combined/invalid/empty filters, visible navigation, old renamed
paths, deliberate reveal/clear, stable tree selection and refresh/message return.
Command help and 80/120-column terminal captures are available. Filters are
session-local, not saved GitHub views. Huge-inventory performance remains to profile.

**Implement:** path filtering and status/discussion filters, active-filter
summary, result count, clear action, and next/previous across visible results.
Use an existing Vim-friendly list/picker rather than requiring a new framework.

**Acceptance:** selected file remains stable by ID as filters change; empty
results are explicit; revealing a referenced hidden file is deliberate; source
`/` continues searching code rather than unexpectedly filtering the tree. S04.

### UX-14 — Viewed progress tied to content

**Status:** Local core implemented and regression-tested. Remote sync is optional.

**Current code:** `:ReviewViewed`, `:ReviewUnviewed`, `:ReviewVerifyViewed` and local
content-fingerprint storage exist. Both compared sides contribute; unavailable
content cannot establish a new acknowledgement. Basic mark/unmark and session
close/reopen work in the audit probe.

**Verified:** separate-process persistence, changed/unchanged comparisons,
both-side/newline/binary identity, unavailable reads, latest mark/unmark intent,
session closure and late callbacks without source/focus changes. Refresh also
schedules needed verification. Checking/unverified state and backend metadata
limits are documented. GitHub Viewed synchronization remains unimplemented.

**Implement:** mark/unmark Viewed with local persistence keyed to review and
compared file content. Backend sync is optional and identified. A changed file
invalidates its earlier viewed marker; unchanged files retain progress.

**Acceptance:** restart preserves progress; a new revision resets only affected
files; Viewed never implies approved/resolved; marking it does not automatically
hide inline discussions or force navigation in the first implementation. F03.

### UX-15 — Review-wide discussion index and search

**Status:** Core implemented and regression-tested; rich excerpts and scale tuning remain.

**Current code:** `:ReviewDiscussions [text]`, `:ReviewDiscussionFilter` and
`:ReviewOpenDiscussion` expose a real-text index across loaded threads, general
conversation and local drafts. Full bodies participate in case-insensitive
literal search; display uses excerpts. Path/author/kind/state/anchor filters,
thread/message counts and stable targets exist. Normal `/` searches displayed
text only. Querying all backend history or unloaded pages is not implemented.

**Verified:** absent-file/outdated results, namespace-colliding message IDs,
frozen batch children, empty filters, exact-message open/return, selection after
filter/refresh, Help return and retained typing. The 80/120-column captures show
readable real-text results. Missing selections move to an inert heading. Search
stays limited to loaded discussion; rich excerpts and large-review profiling remain.

**Implement:** review-wide searchable real-text index with file/range, author,
preview, reply count, state, and stable jump targets. Filter by current/outdated,
resolution when available, and local drafts. Keep general and anchored entries
distinguishable while allowing one discovery surface.

**Acceptance:** find text in another file's reply; jump to its thread and source;
outdated/absent-file feedback stays reachable; counts describe threads versus
messages explicitly. Filtering never resolves or deletes anything. S06, G11.

### UX-16 — Stable refresh and actionable outcome feedback

**Status:** Core implemented as a Vim adaptation. Live provider-write validation
and notification synchronization are not claimed.

**Behavior:** `:ReviewActivity` lists durable terminal outcomes, operation IDs,
comparison/target references, receipts (including batch items), and refresh
status/errors. `:ReviewOpenOperation` reopens retained pending work; it never
reposts historical outcomes. `:ReviewCopyReceipt` copies the selected receipt.
Accepted writes and successful refreshes are separate facts: refreshing does
not establish that an accepted message is visible. Known failures remain
editable; uncertain operations remain frozen and recover through receipts.

Manual refresh adds `[new]` markers in cards and real-text discussion and
per-file counts. `:ReviewNextUnread` moves to a stable message ID, including
threads outside the current file inventory. `:ReviewMarkRead` acknowledges one
message; `:ReviewMarkThreadRead` acknowledges a selected thread. Overlapping
source targets require selection. Refresh itself never marks messages read or
steals the selected message/composer focus. Missing IDs cannot support markers.
The first snapshot is the baseline; later additions, including the user's own
newly observed messages, count as new until explicitly acknowledged. Editing an
existing message does not create a new-message marker. These are local reading
cues, not GitHub notification state or proof another person has read anything.

Local delivery/read metadata extends the existing locked, atomic v1 outbox.
No accepted conversation bodies are copied into activity storage. Retain the
last 200 outcomes by default (`g:revue_activity_limit`); pending drafts and
recovery intent are never evicted by this limit. Persistence failure is shown
as `NOT SAVED`; durable submitting intent recovers as unknown on restart.
Read acknowledgements are local to this review key, not synced across devices.
Automatic polling, cross-device notification sync, and large-inventory tuning
remain separate decisions. Revision switching stays in UX-12.

**Verified acceptance:** a new reply preserves selection, focus and draft text;
accepted write plus failed refresh differs from rejected/unknown delivery;
errors remain discoverable after later success; unread state and receipts
survive restart; a failed local acknowledgement after backend acceptance
recovers without reposting. Batch history retains item receipts and targets.
See `test/activity.py`, `test/batches.py`, `test/thread_state.py` and
`output/activity/`. GitHub references: W02, §8.

### UX-17 — Message metadata and readable Markdown

**Status:** Terminal core implemented: metadata, block rendering, inline spans
in real buffers, semantic links and message focus.

**Implemented:** backend-provided role/bot, Edited versus Updated, Pending review,
local acceptance and review decision labels. Source and discussion share header
formatting. Nested quote containers retain fenced code; quoted suggestions do
not become replacement diffs. Lists preserve indentation, numbering and task
markers; headings are distinct. Real-text selected-message headers follow focus,
refresh and return. Raw body copy/quote remains unchanged. Explicit body URLs
can be chosen and opened/copied from a selected message, with stale-target guards.

**Remaining:** richer discovery excerpts are optional. Full GFM/HTML and
per-span styling within a source virtual row are outside the terminal parity
requirement. Real discussion/preview buffers provide inline spans; virtual rows
retain formatting markers. Semantic/reference links and backend-rendered
destinations are implemented. Unsupported syntax stays visible; very narrow
nested quotes fall back to readable text. Backend metadata availability varies.
Test evidence and terminal captures are in the follow-up above.

**Implement:** semantic spans/blocks for inline code, links, nested quotes, lists,
and code; author-role/edited/publication metadata where supplied. Keep a bounded
metadata row and raw-Markdown access. Separate selected-message focus from the
default card border. Avoid parsing provider identity from body text.

**Acceptance:** fixtures cover Unicode, long names/URLs, blank paragraphs,
nested quoted code, and suggestions; no content disappears; unsupported markup
stays readable; color is not the only signal. C01–C05, F02, A03.

### UX-18 — Narrow windows and bounded reading width

**Status:** Implemented as native Vim maximization, with tested restoration and
reading at 80/120/200 columns. Manual window topology reconstruction is separate.

**Current refinement — UX-18b:** preserve the implemented focus/return behavior
while reducing repeated controls and metadata in auxiliary views. Give history
entries the same clear separation from code as inline cards. Validate 80×24 and
120-column reading, compare content rows before/after, preserve identity/state
and a return cue, and keep secondary actions accessible through the guide.
Never use comment collapse or a different diff layout to meet this criterion.
See the current gap audit for evidence and priority.

**Original gap:** source panes, sidebar and bottom panels competed for space;
tall virtual rows clipped, and card text had no reading-width preference.

**Current behavior:** `ReviewFocus` / `ReviewRestoreLayout` maximize/restore the
current pane without destroying window IDs. Narrow terminals focus new views
automatically; users may opt out. `ReviewFiles` hides/reopens the sidebar. Source
and discussion origins carry through reply/preview and closing restores sizes.
Cards wrap at a configurable reading limit while backgrounds span the pane.
Full-width focused discussion scrolls/searches as real text. Other windows keep
Vim's minimum rows/columns, an intentional alternative to destroying/rebuilding
the layout or implementing another diff mode.

**Implement:** preserve user split sizes, allow hiding/reopening the file list,
and provide a focus-current-side layout at narrow widths. Offer full-window
discussion with return context and bounded card reading width at wide sizes.
This is pane management; it does not implement a unified diff.

**Evidence:** `test/layout.vim` and `output/layout/capture.py` exercise
80/120/200 columns, resize, long discussion, reply/preview return, hidden-sidebar
session reuse, refresh during composition, and opt-out. The companion integration
test now verifies narrow focus and balanced panes after Restore. Both suites
pass. Native virtual-row clipping can still occur; complete comment content is
available in the focused discussion, and no comment is folded or deleted.

**Acceptance:** test 80-, 120-, and 200-column terminals, repeated resize, and a
thread taller than the screen. Full content and action names stay accessible;
no source coordinates or reply targets change. A02, F02.

### UX-19 — Create a suggestion from selected code

**Status:** Core implemented and verified with isolated Vim and backend fixtures.

**Implemented:** `:ReviewSuggest` accepts a line/range or configured visual action,
seeds exact immutable head-side text, and reopens existing drafts at the same
anchor without replacing edits. The draft remains an ordinary comment carrying
`suggestion: true`; explanation can surround its single closed suggestion fence.
Literal backticks use a longer outer fence. Preview uses original cached source.
Both backends explicitly advertise support and validate bodies before single or
batch publication. New stale proposals and unsupported sides are rejected;
saved text and receipt-only recovery survive permission loss and restart.

**Remaining:** local out-of-hunk creation uses UX-10's implemented scope;
GitHub creation remains subject to its API limit. Applying changes is UX-23.
Native pending-review synchronization is UX-08. Authenticated GitHub publication
and native rendering, including longer delimiters, remain live verification work.

**Acceptance:** multiline replacement, empty replacement/deletion, literal fence
content, and stale source are handled. Preview changes no file; submission
publishes a proposal only. C05.

### UX-20 — Typed timeline and review-event navigation

**Status:** UX-20a history, UX-20b shared/local reviewed-comparison navigation
and UX-20c bounded target continuation are implemented. GitHub original-base
recovery remains limited.

**Current:** typed event rows, actor/time/provenance, older-page continuation,
reload/cancel, exact loaded-message open/return and web links. The first-page
Boolean defect is fixed; complete scenario and provider/local contract tests
pass. GitHub requires authenticated GraphQL reads and labels unavailable event
details. Local history projects retained captures/current authored messages;
it does not record every historical edit or lifecycle transition. Timeline
bodies stay separate from durable delivery Activity and the local outbox.

**Current UX-20b:** verified references open the full retained comparison and
return to the history event. Local reviews use saved references or legacy
receipts. **Remaining:** recover broader GitHub historical bases when provable;
a reviewed-head ID and browser fallback alone do not establish full parity. The current
source must not appear under an old approval by assumption. UX-20c loads one
feedback page and follows the selected target if found; direct backend lookup
is an optional refinement. Unsupported/exhausted retrieval retains refresh and
web-link routes. Separate message edit-history reading is implemented in UX-21b.

**Implement:** normalized typed timeline with review decision, author/time,
reviewed version, related threads, and explicit continuation/loading markers.
Link a review event to the comparison it evaluated.

**Acceptance:** comments, decisions, commits, and system events are distinguishable;
loading older entries preserves location; omitted event kinds are explicit;
an old approval is not displayed as current readiness. S03, S07.

### UX-21 — Edit/delete published feedback

**Status:** Published-message editing and supported edit-history browsing are
implemented. Exact saved-message deletion now has a supported core; GitHub
root-with-replies scope and live verification remain open. GitHub atomic edit conflict
protection is not established.

**Current:** exact selected-message edits, durable original/version/replacement,
before/current/proposed preview, explicit rebase, permission/stale checks,
receipts and restart recovery are implemented in Vim and both backends.
Local storage enforces conflict checks atomically; GitHub preflights the current
object but cannot eliminate the documented API's concurrent-update race.

**Remaining:** GitHub root-with-replies semantics and live deletion verification;
moderator policy; history
presentation refinement (UX-18b). Local draft discard is never
published deletion.

**Implement:** message-scoped capability actions, edit draft with original
version, preview of changes, and explicit delete confirmation. Reconcile writes
and preserve concurrent remote changes for user review. Moderation hide is a
different operation and is outside this first slice.

**Acceptance:** editing reply 2 cannot edit the root; permission loss/concurrent
edit retains local text; deletion leaves a clear refresh outcome; immutable
receipts/history are not confused with local draft deletion. W04.

### UX-22 — Reactions and lightweight acknowledgement

**Status:** Counts and explicit add/remove implemented in Vim and both backends.

**Implemented:** per-message totals, explicit `[you]` state, lazy complete-choice
read, immutable reaction operations, exact actor/target checks, preview,
confirmation and uncertain-state reconciliation. Unsupported messages omit the
action. Local receipt recovery is durable; GitHub recovery observes desired state
without claiming which request caused it. Reactions are independent of resolution,
review decisions and message body/version.

**Remaining:** participant lists/drill-down, native pending-review reactions,
GitHub review-summary reaction support and live authenticated verification.

**Implement:** optional selected-message reaction list/counts and add/remove own
reaction through backend capabilities. Support compact text labels in terminals.

**Acceptance:** actor's reaction state is distinguishable from total count;
unsupported backends omit the action; reacting does not resolve or approve.
Do this after substantive reply workflows. C01, G13.

### UX-23 — Apply a suggestion deliberately

**Status:** Planned; not implemented as an end-to-end interaction.

**Implement:** separate Apply preview describing exact replacement, comparison,
destination, and whether the action edits a workspace or creates a remote commit.
Backend provides applicability, validation, and receipts; batch application may
follow once single-application semantics work.

**Acceptance:** stale target, conflicting suggestions, and partial batch failure
retain accurate results; rendering a suggestion never applies it; local edits
and remote commits use distinct labels and outcomes. C05, G10.

### UX-24 — Checks/findings and review readiness

**Status:** Planned; not implemented as an end-to-end interaction.

**Implement:** compact status summary and a dedicated detail view for diagnostics,
with source jump and browser fallback. Keep findings separate from authored
threads and state the revision the checks evaluated. Start with read-only data.

**Acceptance:** missing, loading, running, failed, and completed are distinct;
zero unresolved threads never implies merge readiness; unavailable diagnostics
link to backend details. Merge/land actions remain out of scope. S08.

### UX-25 — Local human–agent revision loop

**Status:** Revision/conversation foundation implemented; participant/MCP loop
remains planned and is not an end-to-end agent interaction yet.

**Implemented:** explicit saved-file capture into the same review, retained
immutable source, shared replies/state across comparisons, current-only new
feedback, read-only capture preview, stale capture rejection, exact receipts,
restart recovery and direct original-source navigation. No automatic commit or
resolution. Unproven source anchors are visibly outdated, not heuristically moved.

**Remaining:** select feedback as a versioned assignment, choose a participant/session,
show assignment/run progress, accept authored replies, and offer the resulting
comparison for review. MCP exposes the same backend objects/actions; it does not
create a second conversation store or become a mandatory UI dependency.

**Acceptance:** agent addresses a specific comment ID; human can reply inline;
new edits produce a new comparison while old context remains readable; run
completion does not auto-resolve threads or commit; backend conversation survives
Vim restart independently of the agent. R04; [architecture](plugin-architecture.md)
and [storage/MCP design](session-storage-mcp.md).

### UX-26 — Keep uncertain submissions frozen when receipt reads fail

**Status:** implemented and regression-tested; P0 closed. This is a Revue correctness requirement,
not a claim about GitHub's internal client implementation.

**Original gap (fixed):** `Send` and `SendBatch` remembered that an operation was unknown before
checking receipts, but their callbacks see only the latest result. If the read
fails with `unknown: 0`, both callbacks change the draft to `failed`. The single
composer becomes editable; the batch can be unpacked. A failed read establishes
nothing about whether the earlier write was accepted.

**Implement:** carry reconciliation intent through the callback and durable
operation state. Any unsuccessful receipt lookup preserves the original unknown
outcome, frozen payload, operation ID, and receipt-only next action. Display
“Receipt check failed; delivery still unknown,” with the latest read error and
an explicit Check receipt action. Do not call the operation rejected merely
because credentials expired or the lookup was unavailable. Keep successful
receipt evidence distinct from observing a desired thread state (UX-09).

**Acceptance:** single and batch fixtures cover unknown → read denied, timeout,
malformed/incomplete response, restart, repeated lookup, and successful recovery.
Every subsequent attempt before conclusive recovery has `reconcile: true`, the
same operation identity and identical frozen content. Editing/discard/unpack
stay unavailable; no new publication occurs. A genuinely rejected initial
write remains editable. Run the same contract against local and GitHub fixtures.
The audit probe now records `unknown` and a retained batch; new regression tests
assert that behavior. Related UX-08, UX-09, UX-16; W02, §8.

## What to copy, adapt, or leave out

| Choice | Treatment |
| --- | --- |
| Clear code/discussion contrast and inset suggestions | Preserve now |
| Per-message targeting, quotes, review preview, lifecycle | Adapt as keyboard-first workflows |
| Hover toolbar, avatar click targets, drag-only selection | Replace with contextual commands, visual selection, and stable focus |
| Browser typography and pixel geometry | Approximate with spacing, highlights, rails, and bounded text width |
| Native browser text selection inside cards | Use the focused real-text thread view; keep source virtual rows immutable |
| Browser `i` shortcut | Never copy literally; global toggle remains a held decision |
| Per-file Viewed collapse | Adopt progress separately; do not copy automatic hiding by default |
| Review inbox enhancements | Companion-owned; basic query/pagination already exist, so not a new core backlog |
| Reactions, moderation, merge controls, notifications | Lower priority or out of scope until core loop is complete |
| Full HTML rendering or a general terminal widget framework | Not required to achieve these interactions |

## Implementation and validation guidance

Extract only the card attachment/renderer seam needed by these stories. Keep
semantic message IDs and action targets in Revue's view model; keep credentials,
native lifecycle, and conversation storage in the backend. Do not make a large
library extraction a prerequisite for fixing UX-26 or improving the composer.

For each slice, demonstrate an end-to-end interaction in real Vim using the rich
three-author fixture, overlapping anchors, base-side ranges, and a non-Git
backend fixture. Add targeted regression coverage when behavior changes.
Include a terminal screenshot for visual changes; a headless test cannot prove
readability. Use failure/restart tests for new write paths, and preserve the
existing no-duplicate-write and immutable-anchor guarantees.

This document refines the broad packages in [PLAN.md](../PLAN.md): R08 maps to
UX-06/08/14, R09 to UX-04/09/15, R10/H05 to UX-07/08/16/21/26, R11 to UX-12, and E01
to UX-17/19/23. It does not mark those older packages complete or change their
release gates. Use these UX IDs for interaction-level discussion and small PRs.
