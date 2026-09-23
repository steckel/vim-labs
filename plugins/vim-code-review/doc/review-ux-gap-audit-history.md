> **Historical record.** Superseded for planning by the [current audit](review-ux-gap-audit.md).
> Retained verbatim below; intermediate status and sequencing may be obsolete.

# GitHub → Revue: current UX gaps and delivery backlog

Audited **2026-09-14**, against the current uncommitted Revue and adjacent
`vim-code-review-github` working trees. This is the current planning view; the
[26-story backlog](interaction-backlog.md) retains detailed contracts and
implementation history. Its UX IDs remain stable. This audit proposes work;
it does not authorize publishing feedback or implement these proposals.

## Assessment

**Latest implementation reconciliation:** small-terminal reading now has a
full-area core, leaving exact-reply action discovery as the next UX validation.
Discussions, composers and previews use managed reading tabs on narrow screens;
source windows retain their identities and layout. The 80×24 assignment fixture
gains two reading-window rows (19 → 21), including after discussion navigation
and return. Hidden refresh preserves actual Insert mode and text; user splits
and tabs survive cleanup. Explicit split mode remains available.
Evidence and paired renders (local evidence: `../output/reading-tabs/validation.json`).
The existing card, quote, composition, pending-review and recovery foundations
should be retained. UX-15b now has a verified targeted-history core: exact reply,
complete thread, independent paging coverage, cancellation and stable return.
A 501-thread local fixture reduces ten continuation actions to one targeted
action; a current public GitHub thread also passed a live read. Private/mixed
GitHub threads retain paging. Evidence (local evidence: `../output/feedback-lookup/validation.json`).
Participant runtime remains partially integrated. The
[latest audit record](research/ux-backlog-audit-2026-09-14.json) records fresh
focused checks for the preceding documentation pass; implementation evidence is
linked separately above.

**Implementation follow-up — UX-22b:** reactions now execute explicit Add/Remove
actions in the chooser, without another composer or confirmation. The durable
operation remains recoverable; unknown outcomes expose a receipt check even
after reaction-read permission disappears. The full Revue suite passes,
including local backend integration and two-process Vim recovery. Live GitHub
mutation validation remains separate.
Evidence and real Vim cell renders (local evidence: `../output/direct-reactions/validation.json`).

**Implementation follow-up — UX-18d:** compact assignment metadata and the
read-only `:ReviewAssignmentDetails` view now have a verified core. The full
Revue suite passes. Paired terminal renders place the first body at row 14
instead of 15 and the second outcome heading at row 20 instead of 22 in the
80×24 fixture. A naive full-area tab clone gains two window rows but rebuilds
four panes after discussion navigation, so it remains an unadopted UX-18c
prototype. Evidence (local evidence: `../output/assignment-density/validation.json`).

### Current audit: interaction parity, not pixel parity

The preceding documentation audit re-inspected the working tree and reran
focused interaction checks; its [record](research/ux-backlog-audit-2026-09-14.json)
remains separate from the implementation evidence linked above. The comparison
below incorporates those completed increments. Later implementation narratives
retain historical context.

**Recommendation:** continue with exact-message action discovery in the comment
reading/action loop. The narrow reading-tab increment, compact assignment
metadata and direct acknowledgements now have implemented cores. Keep the local agent loop
as a separate product track. Its backend work should not be mistaken for a
finished Vim interaction or a prerequisite for improving comment reading.

| Journey / GitHub reference | Current Revue behavior | Difference and disposition |
| --- | --- | --- |
| Understand the review · S02/S06 | Review identity, comparison, purpose/conversation and action guide | Core present. Preserve a compact identity/return cue; checks/readiness remain separate. |
| Read inline comments · F02/C01/C02 | High-contrast cards, gutter boundary, flat replies, metadata and independent discussion identities | Preserve. Terminal prose need not copy HTML pixels or avatars. Manual individual collapse is removed. |
| Act on reply 2 · C01/C02/W04 | Source cards are virtual rows; open the real-text discussion, select the message, then use its menu or mapped action | Functional, with an extra navigation step. UX-06/18: observe discovery and clarify that route if needed; do not add fake clickable controls. |
| Quote and copy · C03/C04 | Whole/selected quotes, optional attribution, original Markdown copy and semantic links | Implemented. Preserve registers and exact reply identity; full HTML/media is outside this milestone. |
| Add feedback · W01 | Source/Visual-range, file and general feedback; native composer and preview | Implemented. Visual selection replaces drag/Shift selection. GitHub creation outside hunks still needs API evidence. |
| Collect then publish · W02/W03 | Local drafts, native private reviews, editing, selected staging, batch preview and publication | Implemented core. Keep local/private/published distinctions. Verify actual service permissions and unsupported deletion scopes. |
| Correct a message · W04 | Supported edits, exact-message deletion and edit-history reading | Implemented core; root deletion with replies is restricted. Preserve siblings and unknown-result recovery. |
| Resolve a concern · C06/V04 | Explicit resolve/reopen, state cues and durable recovery | Implemented core. Keep resolution independent of visibility, outdated anchors, review decisions and agent outcomes. Do not copy resolution-driven collapse. |
| Read on a small terminal · F02 | Full-area reading tabs for discussions, editors and previews; source windows retained; split mode optional | UX-18c core implemented and paired at 80×24. Actual Insert-mode refresh and source/outcome return pass; unfamiliar-user observation remains. |
| Scan assignment/history detail · F02/C01 | Compact outcome metadata with exact identifiers in a read-only details view | UX-18d core implemented; paired 80×24 renders gain space. Broader readability observation remains. |
| Acknowledge with a reaction · C03/W04 | Chooser executes labeled Add/Remove; Waiting, Retry and Check outcome preserve durable intent | UX-22b core implemented. Reaction membership and live service-role verification remain separate. |
| Find all feedback · S03/S06/V07 | Discussion index, literal search/filter, typed history, coverage and continuation; exact history-thread lookup | UX-15b targeted-history core verified. Search still covers loaded content; private/mixed GitHub threads use paging. |
| Read originally reviewed code · S07 | Retained local comparisons; verified GitHub original-file context and history return | Partial parity. UX-12d/20b: reconstruct only when both endpoints are known; preserve labeled fallback when the original PR base cannot be proven. |
| Refresh while composing · S05 | Bounded reads, cancellation, retained drafts/focus, unread markers and receipt recovery | Core present. Broader cold-open/tail responsiveness needs measurements. Fixture gains are not a service latency guarantee. |
| Use a suggested change · C05 | Render, author and preview suggested replacement | Application is missing. UX-23a must distinguish workspace edits from service commits. |
| Track progress/readiness · F03/S08 | Local content-bound Viewed; no checks/readiness surface | Server Viewed and head-bound readiness remain optional, UX-14/24. Viewed must not hide comments or imply approval. |
| Ask an agent, review its work · Revue extension | Assignment selection, saved scope, outcomes, inline replies, result navigation and cancellation | UX-25c is unfinished: runtime scaffolding/helpers exist, but no mapped/session start-resume action is wired. Real runtime validation remains. |

Reference IDs link to the [GitHub specification](github-review-ux-spec.md).
GitHub's current Comments panel brings general and anchored discussion beside
code and supports quote replies; this supports one conversation model across
Revue's views. [Comments panel](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/),
[docked panels](https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/).
GitHub suggestion application creates commits, so a Revue action needs an
explicit destination and consequence.
[Applying feedback](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request).

**Current observations, with limits:** the paired compact 80-column assignment
render now removes the source panes from the reading tab, preserving them in
their original tab. Native `layout#Focus` still resizes windows in split mode.
These renders establish a space gain, not discoverability. `session#React` executes an explicit
chooser action with durable recovery; the older draft/confirmation description
below is historical. No fresh authenticated GitHub reaction walkthrough or
unfamiliar-user observation was performed.

**Keep deliberately different:** native editing and Visual selection; configured
commands and exact-message motions; searchable discussion buffers; expanded
inline conversations; and identity-based return. Do not copy hover dependence,
HTML geometry, automatic thread collapse, or GitHub-specific storage into the
shared renderer. Global visibility and unified/split remain deferred.

### Established implementation baseline

Revue already supports the central review loop: anchored cards with multiple
replies, exact-message actions, quoting, contextual composition, preview,
review submission, resolution, and return to the original source. Private
GitHub reviews now support creation, individual additions/replies, editing,
publication, whole-review discard and sequential staging of selected drafts.
Treating these as missing would produce the wrong backlog.

The typed history core now loads, pages and returns to exact discussions.
Feedback continuation and per-message edit history also exist in the shared UI
and both backends. Supported exact-message deletion now has an implemented
core. Explicit local draft re-anchoring also has a verified core. The remaining architecture increment is **the participant runtime loop** over
the existing local/MCP core. The narrow-reading presentation increment now has
a verified core; exact-message action discovery remains the next observation.
Changed-content parsing and body reuse have measured improvements; broader cold
opening and tail latency remain validation work. Reviewed-comparison
navigation now has a verified shared/local core; GitHub original-base recovery
remains limited by available evidence. Private deletion scope and
unfamiliar-user discoverability need validation alongside those additions.
Rich reply reading/quoting now has an
implemented core alongside the other completed slices below. Contextual action
discovery, compact common composers and sequential private staging now have
implemented cores; their remaining validation is tracked separately below.
GitHub's interaction hierarchy is a useful reference. Its browser geometry is
not a requirement for a modal editor.

The code/card contrast, full-width boundary into the gutter, and reply
separators are established strengths. Preserve them. Individual inline
discussion collapse remains removed. Unified versus split presentation and a
global comments visibility control remain deferred decisions.

## Discussion-ready shortlist

The detailed [remaining delivery queue](interaction-backlog.md#remaining-delivery-queue--reconciled-september-14)
now supplies triggers, acceptance criteria, dependencies and scope. It supersedes
older sequencing in the implementation history below. This audit distinguishes
missing interactions from completed foundations and from release validation.

| Priority / ID | Actual remaining difference | Disposition |
| --- | --- | --- |
| P1 · UX-06/18 | GitHub exposes a menu at each message; Revue's virtual source cards require opening a real-text discussion before selecting a reply | Validate source → reply 2 → quote → preview → return with unfamiliar users; refine the specific missing cue if needed |
| Implemented · UX-18c | Full-area reading tabs replace minimized sibling panes in narrow reading flows | Two additional reading rows at 80×24; preserve source windows, exact return and user splits; keep split mode available |
| Implemented · UX-18d | Compact outcomes with explicit full-details access | Preserve exact identity and return; observe usability separately |
| Implemented · UX-22b | Explicit Add/Remove in chooser with durable receipt recovery | Preserve exact identity; validate live service roles separately |
| P1 · UX-08b/21a/09 | Implemented mutations have limited live actor/scope evidence | Validate permissions, private/public deletion and resolution in an authorized disposable review; keep unsupported root deletion disabled |
| P1 · UX-13/15/16 | Cold opening and broader tail responsiveness lack sufficient evidence | Measure separately from the completed changed-refresh/body-cache optimizations; preserve typing and exact targets |
| P2 · UX-25a/b/c | Assignment/MCP, selection and outcomes exist; runtime scaffolding is partly integrated | Wire and verify one start/resume adapter; a separate product extension |
| Implemented · UX-15b | Exact history-thread lookup with paging retained | Measured fixture cost, focused Vim/provider checks and public GitHub read pass; search lookup remains outside this increment |
| P2 · UX-12d/20b | Some original GitHub comparisons have no provable base | Extend only where evidence supports both endpoints; preserve labeled fallback and exact return |
| P3 · UX-23a/24a | Suggestions cannot be applied; checks/readiness are absent | Separate optional capabilities for deliberate application and read-only head-bound readiness |
| P3 · UX-14/22 | Viewed is local; reaction membership is unavailable | Independent optional server synchronization/membership views |

**What does not need rebuilding:** cards/replies/quotes, contextual action guide,
composition/preview, private staging and batches, resolve/reopen, paged feedback
and history, supported message edits/deletes, local draft movement, recovery,
and the measured rendering optimizations. “Implemented core” does not claim
complete service parity, every permission case or released functionality.

**Baseline for the density increment:** the retained 80×24 Pending and history
captures show the concrete costs:
Pending reaches its first comment body at terminal row 15; history reaches its
first recorded body at row 11 and repeats provenance below each entry. Those
measurements describe these fixtures, not every review. Action-discovery
observation remains a separate validation task.

**Implemented density follow-up:** Pending now brings the first comment body
from row 15 to row 11 in that same 80×24 fixture. The title states backend-private
ownership, each review keeps its unpublished state and loaded/total count, and
the incomplete-review verification cue stays visible. Continuation remains in
the contextual guide. History now places identical source/details once after
the loaded entries; different per-entry details remain attached to their own
revision. The second recorded body moves from row 18 to row 16 in the retained
history fixture. These are measured presentation improvements, not evidence of
unfamiliar-user discoverability. Current renders and validation (local evidence: `../output/auxiliary-density/validation.json`)
retain before/after references. Minimized source windows still occupy rows;
window geometry is unchanged by this refinement.

**Keep deliberately different:** Visual selection instead of hover/drag,
native buffers instead of browser textboxes, configured commands instead of
mouse menus, and exact identity-based return instead of browser Back. Keep
individual comments expanded. Global visibility and unified/split diff choices
stay deferred. Backend and destination remain one concept; GitHub and local
agent reviews use the same interaction contracts with different capabilities.

## Evidence and confidence

**Earlier reconciliation (historical):** inspected actual action maps/guide, focus/restore
mechanics, owner assignment API and MCP limitations; revisited retained narrow
history and inline-agent renders. Rechecked GitHub's official Comments panel,
docked panels and feedback-incorporation documentation. Five focused checks were
rerun for this audit; the [record](research/parity-audit-reconciliation.json)
separates those results from inherited full-suite evidence. No fresh authenticated
GitHub walkthrough, remote mutation, OS screenshot or unfamiliar-user study is
claimed. This pass changes planning documents only.


**Participant/MCP follow-up — UX-25 backend core:** the local backend now stores
versioned selected-comment assignments alongside its existing conversation,
events and receipts. A scoped stdio MCP connection reads assigned threads and
retained original code, saves attributed inline replies, and records per-comment
outcomes with optional run/result references. Actor identity is connection-bound;
cancellation and foreign-thread requests are rejected. Identical retries recover
the original receipt. A synthetic client exercises actual stdio and two Vim
reopens; [contract and limitations](participant-mcp.md) and
validation (local evidence: `../output/participant-mcp/validation.json`) describe the supported core.
Vim selection/preview/creation now has a verified core (evidence (local evidence: `../output/assignment-ui/validation.json`)).
Outcome/cancel UI now has a verified core (evidence (local evidence: `../output/assignment-outcomes/validation.json`)); actual agent launch/resume adapters remain required for the complete UX-25 loop. No real agent or GitHub write was invoked.

**Large-thread rendering follow-up:** the next trace showed repeated rendering
of 99 unchanged bodies when one of 100 messages changed. Inline cards now reuse
exact body rows when source/anchor, width and Markdown context match. Discussion
buffers similarly reuse body-relative Markdown spans. Metadata, reactions,
permission cues and actions are rebuilt from current state. Retention is bounded
and memory-only: up to eight displayed threads, 128 bodies and 1 MiB of serialized
body data per thread, plus 128 bodies / 1 MiB of parsed data per discussion buffer.
These are retention budgets, not total Vim heap limits or comment limits.

Five serial before/after typing runs per case show median changed-refresh adoption
at 216 → 42 ms for 100 general comments and 540 → 97 ms for a 100-message
thread. Exact text, Insert mode, focus and reply return pass. Context/width/source
changes compare equal to uncached rendering; removed entries and changed panel
roles release their retained data. Evidence (local evidence: `../output/thread-rendering/validation.json`)
records fixture timing, not remote latency or OS paint. Broader tail latency,
cold opening and very large inventories remain outside this five-sample result.

**Changed-refresh responsiveness follow-up:** scoped timings identified inline
Markdown parsing as the dominant part of rebuilding a rich conversation. The
parser now copies ordinary text runs at once and keeps the existing syntax
handling at Markdown markers and backslashes. Full parser results match the
retained implementation in 1,212 deterministic comparisons, including Unicode,
escapes, references, links, formatting spans and fences.

Five actual Vim typing samples per scenario show median changed-snapshot
application at 1.310 → 0.220 s for 100 general comments and 2.727 → 0.583 s
for one 100-message thread. The largest observed timer gaps also decrease;
exact draft text, buffer/window, Insert mode and selected-reply return pass.
The full Revue suite passes. Reproducible evidence (local evidence: `../output/changed-refresh/validation.json`)
uses delayed fixture callbacks without service writes; these are not remote
latency percentiles or OS paint measurements. The remaining ~0.58 s nested-thread
pause keeps large-discussion rendering on the backlog.

**Latest audit refresh:** the [inspection record](research/ux-audit-latest.json)
records action availability, mappings, unchanged
refresh handling and the proposed MCP boundary; re-opened the retained 80×24
Pending and history renders. Rechecked GitHub's official Comments panel,
docked-layout and feedback-incorporation sources. Reconciled the shortlist with
the completed full-suite log and provider evidence rather than scheduling
implemented features again. This refresh does not establish a new user study,
authenticated browser walkthrough, OS screenshot or live mutation test.

**Remote-responsiveness follow-up:** request traces identified serial merge-base
and actor lookups plus a duplicate final PR check after the successful feedback
guard. The adapter now overlaps independent reads, keeps four-worker concurrency,
and uses that final guard as the last remote read; complete-reader fallbacks
retain REST revalidation. The full returned snapshot fingerprint is identical.
One provider sample improved from 4.805 s / nine reads to 3.965 s / eight reads.

An actual Vim PTY/bridge/GitHub refresh while typing exposed unnecessary rich
conversation rebuilding on an unchanged snapshot. The UI now updates only
status-dependent views in this case. Observed adoption improved from 357.6 ms to
11.2 ms and maximum timer gap from 376.2 ms to 46.0 ms, preserving exact draft
text, buffer, window and Insert mode. Evidence and reproducible probes (local evidence: `../output/remote-latency/validation.json`)
separate service time from local adoption. These single observations do not
establish tail latency or OS paint performance. Changed content still follows
the normal repaint path; changed-page rendering is the next measurement target.

**Private paging follow-up:** UX-13/15/16 cut B now loads private comments within
complete feedback threads, retaining private parent/actor/native permissions and
per-review loaded/total counts. `:ReviewVerifyPending` retrieves the complete
selected review before publication, discard or summary editing. Partial records
cannot prepare whole-review mutations. Stale, cancelled and malformed reads
retain loaded data; restart obtains fresh headers. The Pending view now uses
shared card surfaces and a compact action-guide header. Validation (local evidence: `../output/private-pages/validation.json`)
and 80×24 partial view (local evidence: `../output/private-pages/80-partial.png`) record the core.
The full Revue suite (36 local tests), 131 provider tests and companion
integration pass. The live schema/public check has no pending review; private live-state coverage
and root-with-replies deletion remain release checks. Remote latency targets,
large nested-thread cost and unfamiliar-user observation remain open.

**Bounded-refresh follow-up:** UX-13/15/16 cut A now stages one outer feedback
page per explicit action, retaining the displayed inventory until previously
loaded message IDs are covered or the fresh inventory ends. Continue/cancel,
retry, stable selection, actual Insert-mode callback delivery and restart
interruption are verified. Local and GitHub transport fixtures exercise the
workflow. Private GitHub paging subsequently gained cut B above. Status cues remain visible
in focused source/discussion/composer views. Evidence (local evidence: `../output/bounded-refresh/validation.json`)
and 80×24 capture (local evidence: `../output/bounded-refresh/80-waiting.png`) record the core.
The final Revue suite passes with 36 local tests, alongside 124 provider tests
and companion integration. A live public sample (local evidence: `../output/bounded-refresh/live-read.json`)
matched all bodies, versions and anchors: full refresh 2.843 s; bounded initial
4.670 s; one continuation 1.400 s. It establishes equivalence, not a speedup.
This bounds feedback-page acquisition, not all HTTP requests or local storage
work; files, review summaries and nested replies can still be large. Cut B is implemented above; broader latency validation remains. Captures render isolated real Vim cells.

**Current planning pass:** reconciled implemented draft movement, saved-message
deletion and history styling with the remaining queue. Inspected current
refresh routing, provider paging, action maps and real-text surface rendering;
re-opened the latest 80×24 history and draft-move renders. Final implementation
suite completion is confirmed in the retained log (local evidence: `../output/reanchor/suite.log`).
The [planning evidence record](research/current-parity-planning.json) separates
this inspection from earlier tests and live reads. No new user study or
authenticated browser walkthrough was performed.


**Draft-move follow-up:** UX-12c now supports explicit movement of local line,
suggestion and file-comment drafts. Selection and old/new preview do not alter
the original; acceptance atomically saves the moved draft with unchanged text,
a fresh submission ID and its previous anchor. The workflow rejects private,
frozen and uncertain operations, changed text, stale previews and unsupported
anchors. Save failure rolls back. A real Vim/local-backend scenario moves to a
renamed file, submits once and verifies the result after restart. The full Revue
suite, 124 provider tests and companion integration pass; focused edge cases
also cover Help cancellation, file targets and suggestions. Validation (local evidence: `../output/reanchor/validation.json`)
and 80×24 preview (local evidence: `../output/reanchor/80-preview.png`) record the supported core.
The capture is an isolated Vim fixture terminal render, not an OS screenshot.
Original source can be unavailable and is labeled; remote messages are never moved.

**Deletion follow-up:** `:ReviewDeleteMessage` previews exact saved-message scope,
checks permission/content and confirms before sending. Accepted deletion returns
to a neighboring message; unknown outcomes remain frozen and only reconcile.
Local deletion is atomic with receipts/audit events and covers replies, roots,
file and general comments. GitHub covers own published inline/general comments
with native permission checks. Roots with replies and published review summaries
remain unavailable; live service writes and atomic GitHub conflict protection
are not established. See validation (local evidence: `../output/published-deletion/validation.json`)
and the 80×24 preview (local evidence: `../output/published-deletion/80-preview.png`). The preview
is an isolated Vim fixture terminal render, not an OS screenshot. The final
suite result is recorded in the validation artifact; no real GitHub deletion
was performed.

**Auxiliary-surface follow-up:** UX-18b now has a history-reading refinement.
History uses contrasting full-width headers/body surfaces and muted provenance;
repeated command rows moved to the existing action guide. The shared painter is
also used by previews. Literal history text is unchanged by wrapping, resizing
or decoration. At 80 columns, the first recorded body moved from terminal row
18 to row 11; the new capture is 80×24. Captures and validation (local evidence: `../output/auxiliary-surfaces/validation.json`)
record a full Revue suite pass, including 33 local backend tests. Focused cases
cover Help cleanup, raw tabs/Unicode/fences, resize, exact reply return and stale
reads. These are isolated real Vim terminal renders, not OS screenshots.
Unfamiliar-user observation and broader auxiliary-view refinement remain open;
this does not mark all UX-18 work complete. Published deletion subsequently gained the supported core described below.

**Earlier planning refresh:** ten focused checks passed against the then-current
working tree: expanded cards, message actions, compact layout, action guide,
rich replies, private deletion, edit history, discovery, feedback continuation
and history navigation. [Commands and results](research/interaction-backlog-refresh.json)
are reproducible. This pass changes planning documents only; it does not rerun
the full suites, conduct an unfamiliar-user study or submit GitHub feedback.
Earlier evidence below is retained with its original scope.

**Edit-history correction:** UX-21b has a supported core. The selected message's
history opens read-only, pages, cancels/retries and returns to that same reply.
Local storage supplies retained before/after edits. GitHub supplies native edit
content for supported published messages; this is not guaranteed to be a
reconstructed patch and may include initial creation. Redacted content stays
unavailable. The retained public read record (local evidence: `../output/message-history/live-read.json`)
covers a general comment, an inline comment and a published review summary.
Private-message history and revision deletion are not claimed. This is separate
from the review-wide timeline's incomplete lifecycle projection.
GitHub also limits retained edit history for the content types listed in its
[history documentation](https://docs.github.com/en/communities/moderating-comments-and-conversations/tracking-changes-in-a-comment).
A complete page inventory means all currently reported entries, not an unlimited
archive of every edit.

**Reviewed-comparison follow-up:** UX-20b now opens an event's verified full
comparison and returns to its exact history position. Local captures expose
retained references; new reviews save their submitted reference and legacy
reviews can recover it from saved receipts. The full Revue suite passes,
including 31 local tests and two real Vim processes against the local backend.
Focused cases cover source failures, malformed files/references, conflicting
identities, changed focus/history, already-current and empty comparisons.
History (local evidence: `../output/event-comparison/80-history.png`) and
source (local evidence: `../output/event-comparison/120-source.png`) are isolated Vim fixture
terminal renders, not OS screenshots. GitHub reviewed heads without verified
original PR bases retain explicit unavailability/browser access; no guessed
parent comparison is presented as the reviewed PR. Full GitHub recovery and
historical event persistence remain separate limitations.

**Navigation follow-up:** UX-06d and the bounded UX-20c continuation journey
are implemented. The full Revue suite passes; focused guide/history cases
also cover custom/disabled keys, cancellation, a later page containing reply 2,
exhaustion, malformed reads, changed selection, history reload, Help and typing
during retrieval. No backend or remote mutation changed. Actual isolated Vim
terminal renders show loading (local evidence: `../output/history-navigation/80-loading.png`)
and the selected reply (local evidence: `../output/history-navigation/120-reply.png`); these are
fixtures, not OS screenshots. Exact-target backend fetching remains an optional
refinement; each current action reads just one page.

- **Current inspection:** action definitions, buffer-local mappings, card and
  Markdown highlights, timeline targets, both feedback adapters and remaining
  story contracts. [Actions](../autoload/revue/actions.vim),
  [maps](../autoload/revue/maps.vim), [timeline](../autoload/revue/timeline.vim),
  [local backend](../python/revue_local.py), and
  [GitHub adapter](../../vim-code-review-github/python/reviewhub.py) are the code basis.
- **Earlier audit verification:** nine focused local checks cover comments, messages,
  interactions, layout, compact chrome, action discovery, discussion discovery,
  feedback continuation and timeline. Exact commands and outcomes are in the
  [audit record](research/current-interaction-audit.json). These are fixture
  checks, not an unfamiliar-user study or live GitHub write verification. The
  full Revue/provider suites were not rerun for this documentation refresh.
- **Retained implementation evidence:** the latest feedback implementation
  records a full Revue pass (29 local-backend tests), 109 provider tests and
  companion integration/restart. Live public reads loaded 20 + 14 complete
  threads; all 77 messages, anchors and versions matched the full reader.
  Feedback evidence (local evidence: `../output/github-feedback/validation.json`) and
  timeline evidence (local evidence: `../output/timeline/live-github-read.json`) are separate
  inventories. The old timeline Boolean defect is repaired; its
  [pre-repair report](research/ux-gap-refresh-results.json) is historical.
- **Earlier visual inspection:** re-opened the saved
  80-column preview (local evidence: `../output/chrome/80-reply.png`) and
  message history (local evidence: `../output/message-history/80-history.png`); the retained
  rich reply preview (local evidence: `../output/rich-replies/120-preview.png`) supplies additional context. The dark card,
  distinct header, quote rails and suggestion inset supply strong hierarchy.
  Surrounding minimized panes still consume scarce rows. These render real Vim
  terminal cells from fixtures; they are not new OS screenshots. GitHub's
  earlier [browser atlas](github-review-ux-spec.md#evidence-atlas) remains the
  visual reference.
- **External verification:** the current planning pass re-opened the official review
  workflow, feedback incorporation, Comments panel and docked-layout sources.
  The earlier refresh also checked comment edit history. Classic
  and newer GitHub surfaces remain distinct in the reference spec. There was
  no new authenticated browser walkthrough and no remote mutation in this pass.
- **Confidence:** implemented means a working-tree capability with evidence,
  not a released feature. Priority and discoverability findings are design
  judgments. Earlier counts in delivery notes describe earlier checkpoints.

GitHub documents private pending comments, editing and review submission with
a decision; these support the assembly flow proposed below.
[Review workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/reviewing-proposed-changes-in-a-pull-request).
Its newer Comments panel and docked layout support review-wide discovery beside
code, for which Revue's discussion index and native splits are appropriate
equivalents.
[Comments panel](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/),
[docked layout](https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/).

## Surface-by-surface comparison

“Core” means an implementation exists with recorded coverage; it does not imply
complete GitHub parity or live verification for every role and repository rule.

| Journey | GitHub reference | Current Revue | Difference and disposition |
| --- | --- | --- | --- |
| Discover/open a review | Inbox/list, identity, author, reviewer context (S01–02) | Companion discovery; backend identity and immutable source | Keep service-specific inbox filtering in the companion. Contextual action guide exists; validate discoverability with users. |
| Consult review purpose | Overview beside code (S02/06) | `C` / `:ReviewConversation` includes description and requested reviewers; now exposed in the outcome guide | UX-06d implemented; custom keys and return after refresh verified. |
| Read code and discussions | Anchored cards, distinct message headers, replies, nested content (C01–05) | Core cards, full replies, gutter boundaries, quote/code/suggestion insets | Inline spans, labeled/reference links and attributed quotes implemented. Virtual rows retain formatting markers; real buffers support span styling. |
| Choose a message | Per-message menu and permalink (C01/04) | `]m`/`[m`, `a`, quote/copy/link/edit/reactions in real-text discussion | Core equivalent. Source virtual rows are display-only; contextual guide exposes the route; user discoverability remains to validate. |
| Write feedback | Line/range/file composer with preview (W01–03) | Visual selection, real Markdown buffer, contextual rows and preview | Core equivalent. Compact context implemented; validate unfamiliar-user workflow at 80 columns. |
| Accumulate a review privately | Pending comments, then submit a decision (W02–03) | Individual saves, browser-review resume and selected-draft private staging; separate public atomic batch | Core sequential staging exists with per-item outcomes. Live provider verification remains. |
| Maintain private feedback | Edit pending feedback; discard review (W04) | Summary/comment/reply edits and whole-review discard | Individual private-comment deletion core implemented. GitHub roots with replies and live mutation verification remain. |
| Find a discussion anywhere | Comments panel, filters, code links (S06) | Full-body query over loaded feedback, filters, exact-message return, coverage counts, continuation and refresh recovery | Shared/local/GitHub paging core implemented. Bounded replacement refresh and private thread paging are implemented. Whole-review actions require full verification; remote responsiveness needs broader measurement. |
| Track reviewed files | Viewed tied to file changes (G12) | Local content-bound Viewed with checking/unverified states | Deliberate local-only implementation; optional GitHub sync later. No automatic file collapse required. |
| Resolve/revisit feedback | Resolution and outdated context (V03/R01) | Explicit resolve/reopen, historical anchors, all text remains expanded | Core equivalent; resolution is separate from read/Viewed/publication. |
| Review another version | Commit/range choice, outdated context (R01–03) | Immutable comparisons, supported range selection, first-parent GitHub history, retained local captures and verified original GitHub source lookup | Local original comparison is retained. GitHub lookup verifies a one-file original-commit context with an unverified PR base; exact return and restart are tested. Full original-base recovery remains limited; explicit local draft re-anchoring is implemented separately. |
| Read PR history | Mixed typed timeline and review events (S03/07) | Typed paged history, exact message return and one-page load/follow for unloaded targets | UX-20c bounded continuation implemented. Exact-target fetching is optional. UX-20b shared/local comparison navigation works; unverified GitHub bases and retained edit/lifecycle history remain. |
| Correct published feedback | Edit/delete/history subject to permission (W04) | Exact-message edits, conflict preservation and read-only edit history | Deletion supports local comments and own public GitHub inline/general comments; GitHub roots with replies, review summaries and live-write verification remain. History supports local retained edits and supported public GitHub messages; native content/redaction limits remain explicit. |
| Acknowledge | Reactions and participant details (C01/G13) | Counts and own add/remove with exact targets | Core subset; participants and additional GitHub message kinds need capability verification. |
| Apply a proposed change | Single or batch suggestion commit (C05/G10) | Create, render and send suggestions only | Missing; distinguish local workspace edit from GitHub commit before implementing. |
| Assess readiness | Checks/findings and review requirements (S08) | Discussion state, decisions and delivery receipts | Missing; start read-only and revision-specific. Unresolved count is not readiness. |
| Delegate feedback/iterate | Remote agent/re-review workflows (R04) | Durable local conversation, retained captures, assignment storage and scoped MCP replies/outcomes | Backend/transport and Vim selection/creation cores exist; outcome/cancel UI is implemented; actual participant launch/resume remains. |

GitHub's Viewed control collapses a file and becomes unmarked after changes;
Revue intentionally tracks the content without moving or hiding the discussion.
[Viewed behavior](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/reviewing-proposed-changes-in-a-pull-request).
Applying GitHub suggestions creates a commit, including when batching them;
this is materially different from saving a review comment or editing a local
workspace. GitHub also documents delegating comments and requesting another
review, useful references for our future participant flow.
[Feedback incorporation](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request).

GitHub's reviewed-changes action restores the version seen by the reviewer.
Revue's displayed reviewed-head hash is useful evidence but cannot establish
the original comparison base by itself.
[Viewing a review](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/viewing-a-pull-request-review).

## Reasonable parity in Vim

Match the user's outcome and preserve context; adapt the mechanics to ordinary
buffers, motions and commands. The following differences are intentional unless
a concrete task becomes harder because of them.

| Browser mechanism | Revue contract |
| --- | --- |
| Hover gutter button and drag a range | Source command or Visual selection; display exact file, side and range before composing. |
| Message ellipsis menu | Stable message selection, `a`, and a contextual outcome guide; respect configured mappings. |
| Inline textbox and preview tab | Editable Markdown buffer plus read-only preview, returning to the exact reply/source position. |
| Docked comments/overview panels | Native managed splits and focused narrow views; make existing routes discoverable. |
| Full HTML, avatars and proportional text | Strong card/code contrast, readable metadata, quotes, code and suggestions; copy original Markdown and offer supported links. |
| Individual/resolved disclosure and Viewed collapse | Keep individual discussions expanded, including resolved ones. Viewed changes progress only. |
| Browser Back and deep links | Explicit origin/return by comparison, file, side and message identity; browser fallback names the unavailable native operation. |
| Server-saved feedback | Label local drafts, private backend comments, publication and uncertain delivery separately. Agent completion, resolution and approval remain separate. |

Global comment visibility and unified/split diff selection remain deferred.
Rich binary previews, moderation tools, dependency visualizations, repository
administration and merge/land controls can use native browser routes; they are
outside this comment-focused parity milestone. The local agent workflow is a
product extension owned by a backend, using the same conversation UX.

## Concrete interaction and presentation findings

These findings distinguish missing behavior from implemented behavior that
needs refinement. Visual observations use saved, real Vim terminal renders;
they are not a fresh iTerm or authenticated GitHub walkthrough.

| Finding | Evidence in our UX | GitHub comparison and practical consequence | Backlog |
| --- | --- | --- | --- |
| Inline comments have the right visual weight | Dark card surfaces, gutter-wide rules, message headers and inset quotes/suggestions | Preserve the thread as a prominent reading surface within code; the user's requested contrast is already present | Preserve UX-01/17; no redesign of the core card required |
| Auxiliary hierarchy is improved, with remaining density costs | Current history has contrasting headers/body surfaces; identical provenance is now shared after entries. Narrow history and draft-move views still keep source-pane remnants above them | Preserve the new hierarchy; compare a more spacious managed reading view while keeping scope, target and return clear | UX-18b refinement; history styling is implemented |
| Narrow views still spend scarce rows on chrome | Current 80-column views retain minimized sibling panes; history moved command rows into the guide, but coverage/scope and minimum sibling-pane geometry still consume rows | Focus is implemented, but the next improvement should increase readable message space and keep a concise return cue | UX-06/18 validation, then UX-18b |
| Actions require knowing which surface owns the message | Source cards are virtual rows; `t`/focus opens real text; `]m`/`[m` and `a` select and act on messages there | A browser's per-message menu is spatially obvious. Vim should make the code → exact reply → action → return path discoverable through its existing guide | UX-06/18 validation; do not duplicate the menu |
| Message, thread and review states are usefully separate | Read/unread, Viewed, resolve/reopen, private save and public submission have distinct actions | Preserve this separation when simplifying wording. A run finishing, a reply arriving or a file being Viewed cannot mean the review is approved | Invariant across UX-08/14/16/25 |
| Finding feedback is bounded by what has loaded | Index/search has coverage labels and continuation; a timeline target may need several explicit page loads | GitHub offers a review-wide comments surface. Our scope is honest but finding a distant reply may take extra steps | UX-13/15/16; direct target fetch is an optional measured improvement |
| Historical code is not universally recoverable | Local retained comparisons work; some GitHub original views have a verified head/excerpt but unknown original PR base | Viewing the code a reviewer saw needs proven comparison identity. Never replace missing history with today's diff | UX-12 / UX-20b backend refinement |

The reference behaviors are documented in GitHub's
[docked comments layout](https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/)
and [comment edit history](https://docs.github.com/en/communities/moderating-comments-and-conversations/tracking-changes-in-a-comment).
Priority, proposed geometry and Vim mechanics above are our design judgments.

## Ordered backlog of remaining interactions

History and shared/local evaluated-comparison navigation now have verified
cores; GitHub original-base recovery remains limited. Inventory coverage, loaded-search scope, range selection, original
thread context and the measured repeated-scan optimization already have
implemented cores. Do not schedule those foundations again as missing.

The compact queue above and detailed delivery queue are the current recommendation.
This table retains broader story status; validation can run independently
of feature delivery. Each row retains its original UX ID; implementation
contracts and Vim-specific acceptance follow below.

| Order / story | Interaction | Status / priority / size | Owner | Dependency or decision |
| --- | --- | --- | --- | --- |
| ✓ · UX-20a | Open history, load older events, follow a discussion and return | Core verified | Revue + backends | First-page defect fixed; fixtures, live pagination and terminal captures verified |
| 1 · UX-06/18 | Quote, preview and return at 80×24 without prior instruction | Validation / P1 / S | Revue | Overview guide route UX-06d is implemented; observe unfamiliar users for other changes |
| 2 · UX-08b | Remove exactly one private message | Verify limited scope / P1 / M | Revue + backend | Core exists; root-with-replies semantics and live permissions remain |
| 3 · UX-18b | Read auxiliary views with consistent contrast and less chrome | History and Pending refinement implemented; broader refinement / P1 / M | Revue | Shared painter, shared history metadata and compact Pending verified; unfamiliar-user workflow and other views remain |
| ✓ · UX-20b | Open an old review's evaluated comparison and return | Shared/local core verified; GitHub limited | Both layers | Verified references and exact event return; unknown original PR base keeps browser fallback |
| ✓ · UX-20c | Follow a history message that is not loaded yet | Bounded continuation implemented | Revue | Loads one page per action, follows exact target if found; optional direct backend lookup later |
| ✓ · UX-21b | Inspect a message's edits or open the original message | Supported core verified | Revue + backends | Exact-message paging/return; local retained edits and supported public GitHub histories; presentation refinement is UX-18b |
| ✓ · UX-21a | Delete one saved message with explicit scope and recovery | Supported core implemented; release checks remain | Revue + backends | Local atomic deletion and own GitHub inline/general comments; root-with-replies scope and live writes remain unverified |
| 4 · UX-13/15/16 | Refresh a large review without disrupting reading or typing | Shared/local/GitHub core; refinement / P1 / M | Both layers | Bounded refresh and private paging exist; full-verification gates and unchanged-refresh fast path exist; changed-content parser/body reuse improvements exist; cold-open and broader tail evidence remain |
| ✓ · UX-12c | Retarget an outdated local draft deliberately | Supported core implemented | Revue + backend capability | Explicit location/preview/accept, atomic outbox replacement and retained origin; published/private messages stay anchored |
| 5 · UX-12 | Inspect broader historical comparisons | Limited scope / P2 / L | Backend + Revue | Non-ancestor GitHub ranges and unknown original bases must stay explicit |
| 6 · UX-25 | Assign selected feedback, follow inline responses, review new capture | Backend/MCP core; UI/runtime extension / P2 / L | Local backend + integrations | Durable selection, participant replies/outcomes and MCP exist; selection/preview/creation is implemented; outcome/cancel views are implemented; add one runtime adapter next |
| 7 · UX-14/22 | Sync Viewed or inspect reaction participants | Optional / P3 / M | Backend + Revue | Separate capabilities and state provenance |
| 8 · UX-23 | Preview and apply one suggestion | Optional / P3 / L | Capable backend + Revue | Explicit choice of workspace edit versus remote commit |
| 9 · UX-24 | Inspect revision-specific checks and readiness | Optional / P3 / L | Companion/backend + Revue | Read-only first; distinguish old-head results |

P1 closes the main reading/writing workflow; P2 completes follow-up and history;
P3 adds optional service features. Sizes are relative scope (S/M/L), not dates.
Suffixes identify delivery slices within existing UX stories, not new competing
story numbers. Sequence is recommended; API-dependent items can move after
evidence gathering. Detailed acceptance criteria follow the implemented-slice
checkpoint.

### Next implementation cuts

Historical cut descriptions are retained below. Use the current
[remaining delivery queue](interaction-backlog.md#remaining-delivery-queue--reconciled-september-14)
for sequencing and the latest assignment, density and responsiveness status.

These cuts clarify the remaining work without assigning new top-level UX IDs.
Cuts A and B have implemented cores; latency measurement follows them; the narrow-layout work and validation can
proceed independently. Completed rows above are reference material, not work
waiting to be implemented again.

| Cut / priority | Trigger → outcome | First deliverable and acceptance | Dependencies / limits |
| --- | --- | --- | --- |
| UX-13/15/16 · A · implemented core | Refresh while reading reply 2 or typing → keep working while fresh feedback arrives | Bound refresh to an explicit page/request budget; retain loaded content until coherent replacement is ready. Preserve draft bytes, mode, cursor, selected message and scroll. Failed/cancelled/stale responses keep the last good view with a retry cue. A removed target gets an explicit nearby fallback. | Measure network wait separately from Vim rendering before selecting a budget. Existing paging and coverage are reused. No automatic comparison switch. |
| UX-13/15/16 · B · implemented core | Open a large review with pending feedback → see correct private/public coverage and continue | Add bounded private inventory retrieval with complete threads and distinct coverage. Partial loading must never enable publishing or discarding an incomplete review; obtain and validate the full affected inventory for those operations. Cover permissions changing and private feedback published elsewhere. | Backend contract first; follows A. Current full private reader remains the fallback until coherent paging is proven. |
| UX-18b · P1 | Open history, preview or draft-move view at 80×24 → reach the content quickly → return | Compare current and proposed renders with long paths, quotes and replies. Reduce repeated metadata and managed-pane chrome only where measured; preserve target, publication state, incomplete coverage and return access. Keep real text copyable and user-owned windows intact. | History card colors and compact commands already exist. Record content rows gained; do not invent an unfamiliar-user result. |
| UX-12 / UX-20b · P2 | Follow an old review after rebase → inspect what was actually reviewed | Recover a full historical comparison only when both original base and head are verified. Show provenance and supported range type; otherwise retain the verified one-file view and a precisely labeled service link. Test non-ancestor ranges, missing objects and exact reply/event return. | Backend evidence determines feasibility. Draft movement is already separate and implemented. |
| UX-25 · P2, extension | Select comments → assign a local agent → read replies inline → inspect a new capture | First ship one participant adapter and a shared MCP contract over backend-owned sessions/messages. Persist selected IDs, comparison, run ID, authored replies and per-item outcomes; reconnect after interruption without duplicating work. | Backend and destination remain one concept. Adapter follows shared contracts; no second conversation store. Completion never implicitly resolves, approves or commits. |
| UX-14/22 · P3 | Mark Viewed across clients or inspect reaction members → know whose state is shown | Separate opt-in capabilities for remote Viewed and reaction participants. Show local/server provenance and unknown membership; verify revision invalidation and permission loss. | Independent enhancements. Neither action hides a comment. |
| UX-23 · P3 | Choose a suggestion → inspect affected code → apply deliberately | Start with one suggestion, exact revision/range validation and an explicit workspace-edit or service-commit action. Stale/conflicting source preserves the suggestion. Show resulting file/revision and return to the discussion. | Decide mutation ownership before implementation. Batch application comes later. |
| UX-24 · P3 | Inspect review readiness → distinguish current checks from stale results | Read-only, head-bound checks and review requirements with pending/failed/unknown states, supported service links and refresh. | Companion/backend supplies facts. Unresolved comments, approvals and merge eligibility remain distinct; merge controls are outside this milestone. |

Two validation tracks accompany delivery: **UX-06/18**, observe a new user's
code → second reply → quote → preview → return journey with default and custom
mappings at 80×24; **UX-08b/21a**, verify GitHub role/permission and
root-with-replies deletion semantics in an explicitly authorized disposable
review. Existing fixtures do not substitute for either observation. Any resulting
fix should name the failed journey rather than adding a speculative control.

### Interaction patterns to pick up individually

These are implementation-sized cuts through the queue above. “Validation” does
not mean add another control. Preserve the original UX IDs and use the evidence
below to decide whether a cut is ready to ship.

| Story / status | User trigger → intended interaction | Acceptance / first useful increment |
| --- | --- | --- |
| UX-06d · implemented | Open the action guide from code → consult purpose and requested reviewers → return | Existing Conversation appears as a Read outcome with its actual key and is omitted inside that view. Custom/disabled keys and source return after refresh pass. |
| UX-12b · supported core verified | From reply 2, inspect original code → see verified source and confidence → return to reply 2 | Both Vim processes, malformed/stale responses and a live read/reopen now pass. Original head, matching parent excerpt and unavailable original PR base are distinct. Closed managed panels can be recreated. Full original PR reconstruction remains limited. |
| UX-08b · validation + limited scope | Select one private message → preview its deletion → see remaining review | Verify roots with replies separately from leaf replies; preserve summary and siblings. Unknown outcome offers receipt checking. Existing exact-message deletion is not a new feature. |
| UX-13/15/16 · coverage/retry core implemented | Open/search feedback while inventory is incomplete → see what is loaded and how to retry | Complete/loading/partial/failed/unsupported/unknown coverage, known totals and loaded-search scope are implemented. Failed refresh retains previous feedback and exact selection. Shared/local/GitHub continuation and bounded replacement refresh are implemented; private paging now has the supported core above. |
| UX-13/15/16 · measured improvement | Jump/search through a large review → retain selection without disruptive redraw | The 500-file / 2,000-message fixture now runs in real Vim. Sidebar aggregation reduced cold open from 25.8 s to 0.54 s and message jump from 17.6 s to 0.62 s. These are local single observations; broader interactive/remote latency targets and private live-state validation remain. |
| UX-20a · core verified | Open review history → follow authored reviews and system events in time order | JSON Boolean completion, first/older pages, deduplication, cancellation, malformed/stale reads, exact event/reply return and draft retention are verified. Keep receipts in Activity; label unavailable event details and local history scope. |
| UX-20b · shared/local core | Select an old review → inspect verified source → return | Event references preserve full base/head and provenance. Saved local receipts recover older reviews; unknown GitHub bases remain explicit. Empty/current comparisons, late reads and restart pass. |
| UX-20c · implemented bounded journey | Select a history entry whose reply is unloaded → load one page → follow if found → return | All replies arrive together; cancellation, identity/focus guards, exhaustion and retained typing pass. Repeat explicitly for another page; missing target does not imply deletion. Direct lookup is optional. |
| UX-18b · refinement | Open preview/history at 80 columns → read the content → inspect secondary details → return | Prioritize content, compact repeated metadata, retain visible identity/state/return cue, and use consistent surface separators. Available actions remain in the configured guide. Long bodies scroll in real text; no individual collapse. |
| UX-21b · supported core | Select reply 2 → inspect edits → load older entries → return to reply 2 | Version-bound target, read-only bodies, scope/provenance, redacted/unavailable states, cancellation and exact return are implemented. Empty history means no entries reported, not proof the message was never edited. |
| UX-21a · supported core | Select a published reply → preview deletion → inspect outcome | Separate capability and exact scope; preview deletion and reconcile uncertainty. Local discard never deletes remote text. |
| UX-12c · implemented | Select an outdated local draft → choose new code → compare old/new anchors | Preserve body and old reference until explicit acceptance. Distinguish moving an editable local draft from creating a linked follow-up; no generic move of a published GitHub comment. |
| UX-25 · UI/runtime missing; backend core implemented | Select comments → assign participant → follow authored replies → review a new capture | Persist IDs, comparison and run identity in the backend; MCP uses the same operations. Partial completion and failures remain inspectable. Completion does not resolve, approve or commit. |
| UX-14/22 · optional | Mark file Viewed across clients; inspect reaction participants | Independent capabilities, server/local provenance and unknown membership states. Do not make either action hide the thread. |
| UX-23 · optional | Select suggestion → preview replacement → apply | Start with one suggestion. Explicitly identify a workspace edit or remote commit; reject stale/overlapping targets and show resulting comparison/receipt. |
| UX-24 · optional | Open readiness → inspect current-head checks → jump to finding | Read-only revision-bound results; old-head, running, failed and unavailable states remain distinct. Browser fallback for unsupported details. |

Two existing workflows need observation rather than feature duplication:

- **UX-06/18, reading and composition:** an unfamiliar user should find message
  actions, quote one reply, save privately, preview and return at 80×24 without
  consulting the README. Record wrong turns and wasted rows; adjust contextual
  wording or pane presentation only in response to those findings.
- **UX-08, publication:** verify the no-summary path when a native review already
  contains comments. GitHub documents it; Revue's pending capability calculation
  already exempts nonempty pending reviews. Include that case in provider release
  verification rather than adding a second review-submission flow.
  [GitHub review update](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/).

### Concrete delivery cuts and current status

**UX-06d — Implemented: find purpose without leaving the review.** The guide
now exposes Conversation, which renders the description and reviewers. It omits
the redundant action in that view, honors custom/disabled keys and preserves
source return after refresh. This fixes the code-inspected missing route;
unfamiliar-user validation remains separate.

**UX-20b — Implemented shared/local core: inspect reviewed source.** Use a
retained, verified comparison reference when the backend has one. Display base/head and provenance before
opening. Return to the exact history event and relative position, including
after a delayed response or temporary source-window closure. For GitHub,
`reviewed_head` alone is insufficient: an original commit's first parent is
not necessarily the PR's original base. Unsupported cases keep the event
visible and explain the browser fallback. Test a retained local capture,
unknown base, unavailable revision and focus changing during retrieval.

**UX-20c — Implemented: follow a history link across page boundaries.**
`:ReviewLoadEventDiscussion` loads one complete feedback page and follows the
exact message if found. Further pages require another explicit action. The
callback retains the event/target, source epoch and history serial; changed
selection or focus prevents automatic navigation. Failure, cancellation and
exhaustion keep the history readable. Unsupported/exhausted retrieval offers
refresh or the event URL without claiming deletion. Exact-target backend lookup
can follow independently. A source jump still uses the verified message anchor.

**UX-18b — Refine auxiliary reading surfaces.** History contrast and command
compaction are implemented and verified above. For further changes, use the 80×24 workflow to decide
which repeated command/provenance rows can move into the guide or an explicit
details view. Keep target, publication/read-only state, coverage when partial,
and a return cue visible. Apply the established card contrast to history entries
and previews without adding folding. Test 80×24 and 120-column views with long
quotes, multiple revisions and redacted content; compare the number of content
rows before/after. Preserve `:ReviewFocus`, opt-out, custom keys, source position
and exact reply return. Do not silently delete or rebuild user-owned splits.

**UX-21b — Supported read core implemented.** `:ReviewMessageHistory` opens
available edits for the selected message; its original-service link names the
message rather than promising a direct history URL. Reload/older/cancel and
version checks are implemented. Keep local before/after changes distinct from
GitHub-provided content. Browser fallback and per-message capability reasons
remain for unsupported cases. Revision deletion is outside this story.

**UX-21a — Supported core implemented.** Deletion now exists for message
kinds with verified scope. A second reply must remain the target through
preview, permission loss, refresh and restart. Unknown deletion outcomes use
receipt checks; successful deletion restores a sensible adjacent message.
Keep private root-with-replies verification as a separate release task.

**UX-13/15/16 — Bounded refresh and measured unchanged-refresh refinement implemented.**
The traces above establish the independent-read scheduling and unchanged-buffer
improvements. Next profile changed-page adoption and nested-thread cost; retain
separate provider, callback, main-thread and OS-paint claims. Record remote open, continuation, search,
message jump and refresh timings while typing in a draft. Distinguish network
wait from main-thread rendering. Scope the first improvement to a measured
bottleneck; show loading/partial/error without replacing good data or moving
the selection. Existing complete-thread paging and coverage labels are the
starting point, not work to implement again.

## Implemented slices: validation and refinement

### UX-06a / UX-07 — Discover the next action (P1, M; Revue)

**Implementation follow-up:** the core chooser is implemented as
`:ReviewReviewActions` / `<LocalLeader>a`. It groups outcomes, displays actual
bindings and reasons, identifies the message/draft, and retains separate
local/private/public actions. Contextual Help includes the same guide.
`test/action_guide.py` verifies real Vim menu selection, permissions changing
during a prompt, exact second-message actions, private preparation/rebinding,
existing reply retention after permission loss, outbox return and custom maps.
The full suite passed; follow-up guide cases passed after refinement.
80-column chooser (local evidence: `../output/actions/80-local-draft.png`) and
120-column private chooser (local evidence: `../output/actions/120-private-draft.png`) are real
Vim ANSI renders. User testing and further narrow-layout refinement remain;
the criteria below retain the original audit intent.

**Original gap (core addressed):** many useful actions have no default key. Contextual Help lists commands,
but the user must understand Pending, StartPending, SavePending, PublishPending
and Batch to choose the right journey. This is discoverability debt, not an
absence of private review support.

**Original implementation contract:** a concise contextual action summary/menu grouped by reading,
writing and finishing the review. Name outcomes: Save locally, Save privately,
Publish review. Show actual configured keys and backend availability. Reuse
existing commands and permissions; do not add another storage/delivery mode.

**Validation criteria:** from source, a second reply, and the outbox, a user can discover
the valid next action without reading the README. Private/public intent and
target review are explicit. Capability changes retain text; custom/disabled
maps work; selecting an action after refresh cannot target another message.

#### UX-06c — Expose existing navigation in the guide (P1, S)

**Implemented core:** the guide now includes comparison selection/open/history,
latest/previous return, original discussion/draft code, and local Viewed/recheck
actions. It omits irrelevant returns and the opposite Viewed action, displays
actual configured bindings, and explains missing original references or
unavailable backend retrieval. The prompt identifies its file/comparison target.
Comparison-reference and progress changes join the existing prompt guard.

`test/navigation_guide.vim` exercises real menu selection, a second reply's
original-code jump, cached history without backend support, unavailable history,
refresh during selection, local mark/unmark, asynchronous verification recovery
and cancellation of a pending Viewed mark,
custom/disabled mappings, and preserved original drafts. The existing delivery
guide suite also passes. Real terminal captures at
80 columns (local evidence: `../output/navigation-guide/80-source.png`) and
120 columns (local evidence: `../output/navigation-guide/120-comparisons.png`) were inspected.
These render actual Vim ANSI cells, not OS screenshots. Long native chooser
lists still scroll; unfamiliar-user validation remains.

The full Revue suite passed for the guide implementation. The subsequent
pending-mark cancellation refinement passed the real Vim action/navigation
suite; no provider code or live remote feedback was changed.

**Original gap:** `maps.vim` installs Comparisons, Latest, PreviousComparison,
ThreadComparison and Viewed-related commands, but `actions.vim`'s grouped
chooser does not list those journeys. Help can expose commands, so this is a
discovery gap rather than missing navigation. GitHub presents version and file
progress controls on its review surface; the Vim equivalent can be a concise
contextual chooser rather than a persistent toolbar.

**Implementation contract:** include valid outcomes for choosing a comparison, returning to
latest/original code, and marking/checking file progress. Show actual configured
bindings. Avoid listing inapplicable actions or duplicating the message menu.

**Validation criteria:** from a source file, an outdated reply and a historical comparison,
the guide exposes the appropriate existing command with its availability reason.
The existing target guard still prevents a refresh from changing the selection
while the menu is open. Range selection itself remains UX-12.

### UX-06b / UX-18 — Quiet the chrome around the comment (P1, M; Revue)

**Implementation follow-up:** common editable drafts now use compact source,
target and delivery context. Preview places full context after the card while
retaining unavailable/missing-source disclosures above it. Repeated preview
delivery labels are removed; preview reading width follows the existing setting.
Minimized review status bars are quiet during focus and restore their labels
with the layout. Full edit/publication/deletion context is retained.
`test/chrome.vim` covers 80×24/120×40, exact reply return, source preservation,
long quoted paths, private intent and permission loss. Real ANSI captures are
in output/chrome (local evidence: `../output/chrome/80-reply.png`). Native minimum-size pane
contents and tab labels still appear; tall quoted threads require scrolling.
This improves common composition, not arbitrary split-topology reconstruction.
The full Revue suite passes with these changes.

**Original gap (core addressed):** the earlier 80-column preview contains several compressed surrounding pane
bars plus repeated Save privately/private wording. The comment itself has
contrast, but competing context reduces reading space.

**Original implementation contract:** prioritize a short action/target header, wrap essential identity
in readable content, and move secondary commands to contextual Help. Refine
managed focus/return within Vim's window minimums. Keep the gutter boundary
and root/reply hierarchy. Do not require restoration of arbitrary user splits.

**Validation criteria:** at 80×24 and 120×40, long paths/authors and private/public states
remain identifiable, message 2 is clearly selected, and reply→preview→return
preserves text and position. Record real terminal captures. No individual
thread hiding and no source line-number changes.

### UX-08a — Stage selected drafts privately (P1, L; Revue + GitHub backend)

**Implementation follow-up:** :ReviewStageBatch now prepares a sequential private
queue for new or existing native reviews. Exact selected bodies, actor and target
are previewed; decisions remain separate. Steps retain independent receipts and
stop on failure. Unknown requests recover without starting waiting writes;
unpacking returns only known-unsaved drafts. Four-process Vim coverage includes
interrupted creation, mixed kinds, partial results, permissions, disk failure and
wrong-review receipts. See paused queue (local evidence: `../output/staging/120-paused.png`).
GitHub's actual save methods are reused with a one-second interval. Live
GitHub write verification remains outstanding; this is not an atomic operation.

**Original gap (core addressed):** the public batch could publish selected
drafts but could not stage them privately. A separate private queue now handles
that journey; public batch validation still rejects prepared private operations.

**Original implementation contract:** reuse selection/full preview with a distinct private-staging
action and verified native review identity. Declare supported item kinds and
delivery guarantees. Creating a review and adding to an existing one may need
different backend plans; never present multiple writes as atomic. Preserve
review-decision intent rather than silently dropping it during staging.

**Validation criteria:** select three drafts, exclude one, inspect exact contents and save
privately; only selected supported items enter the intended review, with no
publication. Test an existing review, permission/revision changes and restart.
If delivery is per-item, show accepted/failed/unknown separately; receipt checks
cannot repost accepted or uncertain items. Publication later previews the
actual server inventory. Depends on existing UX-06/07/08 foundations.

### UX-17 / UX-05 — Read and quote rich replies (P1, M; cards + Revue)

**Implementation follow-up:** shared inline parsing now supplies code/emphasis/
strike/link spans to real discussion and preview buffers. Preview cards omit
format delimiters, while virtual source rows preserve markers and shorten links
to labels. Raw message text remains unchanged for copy/quote/edit. Optional
attributed quoting escapes authors, links to the selected message and appends to
existing drafts. Semantic links include references; GitHub uses read-only
rendered HTML for authoritative destinations. Explicit URLs including code remain
available separately. Tests cover a root plus three replies, second-reply
selection, Unicode widths, nested quoted suggestions, malformed/stale backend
links and late callbacks. Real Vim captures are in
output/rich-replies (local evidence: `../output/rich-replies/120-preview.png`).
The full Revue suite, 72 provider tests and companion integration/restart pass.
Authenticated read-only checks also passed against a public conversation comment
(with three attachment links) and a public inline comment (no links). Exact
message versions matched; see [live evidence](research/rendered-links-live.json).
Private-message and enterprise rendering remain fixture-covered. Full GFM/HTML
fidelity is not required for this terminal adaptation.

**Original gap (core addressed):** block rendering works; inline code/link syntax is still mostly raw
Markdown. Explicit HTTP(S) body links already have a picker. Quote attribution
and semantic/reference/relative-link handling remain incomplete.

**Original implementation contract:** terminal-appropriate inline code/emphasis/link spans, consistent
nested quote styling, optional attribution/permalink for selected-message
quotes, and explicit backend resolution of relative links. Keep original
Markdown available for native selection/copy and unsupported constructs.

**Validation criteria:** a root plus three replies with nested quotes, Unicode, code,
links and suggestions is readable at 80/120 columns. Quoting the second reply
preserves an existing draft and correct author/body; quoted suggestions never
become proposals against the current source. Renderer styling cannot mutate
copied text. Full HTML/GFM rendering is not a release requirement.

## Remaining delivery contracts

### UX-08b / UX-21 — Remove one private comment (P1, M; Revue + backend)

**Implementation follow-up:** `:ReviewDeletePendingComment` works from the native
pending inventory and focused discussion/message actions. It previews exact
contents, retains a read-only operation and requires explicit confirmation.
Per-message scope, actor, native review, message version and body are checked;
unknown outcomes reconcile through read-only inventory checks after restart.
Two-process Vim coverage verifies exact second-reply targeting, stale contents,
permissions, root rejection, unrelated drafts and review-summary preservation.
The full Revue suite, 66 provider tests and companion integration/restart pass.
80-column (local evidence: `../output/private-delete/80-preview.png`) and
120-column (local evidence: `../output/private-delete/120-preview.png`) previews are real Vim ANSI
renders. GitHub roots with replies stay disabled pending verified semantics;
there were no live GitHub deletions. This slice is partial until those checks.

**Implement:** exact-message delete capability and preview of scope/contents.
Resolve root-with-replies semantics from the backend before offering deletion;
do not assume a root deletion preserves replies.

**Done when:** deleting selected reply 2 cannot delete the root, review summary,
other drafts or entire review. Publication/ownership changes prevent stale
private deletion. Failure preserves context; uncertain deletion reconciles
without repeating the mutation. This requires endpoint/permission validation,
not merely a new menu item.

### UX-12 / UX-10 — Inspect changes since an earlier review (P2, L; both layers)

**UX-12a implemented core:** the picker now selects explicit base/head endpoints
through RangeStart/RangeEnd and displays their identities and backend semantics
before OpenRange. Selections, derived references and source positions persist;
clear/change/navigation supersedes a pending open. Comparison selection now
survives header growth and history repaint by stable identity.

Local ranges use retained captures without Git/workspace reads, support both
directions and base/head endpoints, and show renames as removal/addition.
GitHub supports exact endpoints where the start is the merge base (ancestor),
including fork-side source routing. Non-ancestor GitHub ranges and inventories
at the 300-file compare cap remain explicit limitations. Existing drafts retain
anchors; new source feedback/review creation requires Latest; replies retain
their original discussion identity. Range reads do not re-anchor messages.

The full Revue suite, 79 provider tests and companion integration/restart passed.
Range tests include both a defensive fixture transport and the actual local
backend across separate Vim processes, plus local backend cases for restored
files, reversed ranges, renames, binary/newline-only changes and shared replies.
The final full suite includes the stable-selection refinement.
Live read evidence (local evidence: `../output/ranges/live-github-read.json`) verifies a
public GitHub two-commit range, both source files, and exact reopening; zero
remote writes. Captures show 80-column endpoint selection (local evidence: `../output/ranges/80-endpoints.png`)
and 120-column source (local evidence: `../output/ranges/120-source.png`), rendered from actual
isolated Vim terminal cells. GitHub original-context recovery remains below.

**UX-12b supported core implemented:** `ThreadComparison` uses the local
backend's retained `original_comparison`, or GitHub's new lazy `thread_context`
lookup. GitHub verifies original coordinates against immutable source and the
stored excerpt. Its derived view is one file at the original commit and first
parent, with an explicit original-PR-base warning; a matching parent excerpt
does not prove the original PR base. Missing/mismatched source retains the
discussion and excerpt. `ReturnContext` records an exact transient origin;
saved source references can reopen after restart, but the earlier transient
return origin is not persisted.

The seven context-specific provider tests pass, as do both real Vim processes
covering reply 2, exact return, closed-panel recreation, draft retention,
malformed/stale reads, changed focus and restart. The original test expectation
was corrected to match its two message motions; no navigation behavior was
changed to fit it. File entries are validated before extracting their paths.
The full Revue suite, all 86 provider tests and companion integration/restart pass.

Live read evidence (local evidence: `../output/original-context/live-github-read.json`) verifies
the public GitHub thread `3140841349` at head lines 2404–2410 in commit
`7bb9a03ba3229b4cefa5888eaa238920f3f1b69b`, reads both file sides and reopens the
same source/descriptor. Zero remote mutations. The 80-column discussion (local evidence: `../output/original-context/80-discussion.png`)
and 120-column source (local evidence: `../output/original-context/120-source.png`) render real
isolated Vim terminal cells using downloaded public source, not OS screenshots.
Commands and the backend contract are documented in the README, Vim help and
provider API. The panel status now identifies original code context explicitly.

GitHub's original commit/line/hunk fields
support a verified source lookup; they do not by themselves identify a complete
original PR comparison.
[Review comment API](https://docs.github.com/en/rest/pulls/comments).

**Deliver separately:**

1. **UX-12a — Select endpoints (core implemented).** Choose an earlier version and an end version
   from backend-provided history, inspect their identities and comparison
   semantics, then open. Cancel retains the current source and drafts. The
   backend declares supported combinations; no silent merge-base substitution.
2. **UX-12b — Return to original code (supported core implemented).** From a selected message, open its exact
   original comparison/path/side/range where provable, then return to the prior
   file and position. If unavailable, show why and retain excerpt/permalink.
   Test a base-side anchor, rename, deleted file and force-pushed revision.
3. **UX-12c — Implemented local draft move.** The separately capability-gated
   workflow previews old and selected new context, then explicitly accepts a
   local outbox replacement with unchanged body and a fresh submission ID.
   Replies, published/private comments and uncertain submissions retain targets.
   Reading history never performs this action.
4. **UX-10 — Widen GitHub creation scope only after API verification.** This is
   independent of range selection: preserve received outside-hunk threads now;
   enable new unchanged-line comments only with verified support.

**Done when:** renamed/deleted files, a force-pushed or unavailable revision and
an outdated discussion have understandable outcomes. Same line numbers in new
code never silently retarget a draft. Original context remains accessible or
explicitly unavailable. New anchors name both revisions and require selection.

### UX-20 / UX-21 — Inspect remote history and manage published text (P2, L; both layers)

**UX-20a core verified:** `:ReviewTimeline`, older-page/reload/cancel commands,
stable event targets and GitHub/local projections are implemented. Boolean
completion validation now accepts real JSON pages and rejects malformed values.
The full timeline scenario passes, including delayed and overlapping reads,
Help/reply return, preserved typing and unchanged outbox ownership. Provider
contracts cover foreign cursors, duplicate IDs, stalled pages, unknown event
kinds, inconsistent totals, typed targets and common system metadata. Local
contracts cover restart, changed inventory, exact reply kinds and excluding
derived ranges from capture events. Tests and live evidence are linked above.

**Remaining:** full GitHub original-base recovery remains limited within UX-20b;
published deletion has a supported core in UX-21a; UX-21b edit-history reading has a
supported core. Shared/local
reviewed-comparison navigation and exact history return are implemented. Unknown GitHub event kinds
remain visible with an explicit detail fallback. The local projection is not
a durable edit/lifecycle ledger. Newer events require explicit reload.

**Scope and provenance:** GitHub's projection uses typed remote events; the
local projection reconstructs retained captures and current authored messages.
The timeline does not project every edit, resolution or historical body. The
separate local message-history reader uses retained before/after edit events;
this does not make the timeline a complete lifecycle ledger. Present that
scope in the UI. Unavailable event details must remain explicit. Conversation,
backend history and local delivery Activity serve different user questions;
loading history must not publish, resolve or mark a discussion read.

**Implement:** deliver separately: typed timeline with continuation and
reviewed-comparison links and available edit history have implemented cores;
published deletion now has a supported core with explicit backend limits.
Keep local delivery Activity and backend events visibly distinct.

**Done when:** an old approval opens the source it reviewed; loading older
events preserves selection; absent event kinds/history are labeled unavailable.
Message deletion identifies exact scope and permission, and cannot masquerade
as local draft discard. GitHub edit reads are verified for the supported
published-message scope; do not broaden this to private histories or guarantee
reconstructed patches. Provide a browser fallback where necessary.

**Delivery boundaries:** UX-20a adds typed read-only events and continuation;
UX-20b links a review event to its reviewed comparison (depends on UX-12b).
UX-21a now provides permission-aware exact saved-message deletion and recovery.
UX-21b now exposes available edit history or an explicit browser route. These are
independent stories; a readable timeline need not wait for deletion support.

### UX-13 / UX-15 / UX-16 — Keep large reviews navigable (P2, M; both layers)

**Shared/local continuation follow-up:** `:ReviewLoadMoreFeedback` and
`:ReviewCancelFeedback` now page complete discussions/messages, retain exact
selection and typing, and expose retry without replacing earlier feedback.
Loaded pages become searchable without manufacturing new-arrival markers.
Refresh invalidates outstanding page callbacks even if the source is unchanged.
Large local reviews open with 50 complete units; cursors bind the review,
comparison and current feedback fingerprint and survive restart when unchanged.
Small reviews retain their complete shape; manual refresh still reads the full
local inventory. Source pages and message bodies remain outside the outbox.

**GitHub continuation core implemented:** signed-in public reviews load 20
complete threads and 50 general comments per page, with all review summaries.
Nested replies finish before rendering a thread. Existing private inventories,
signed-out access and unsupported GraphQL use the complete reader; a pending
review appearing during paging requires refresh. Message versions, anchors,
native permissions and reaction counts remain compatible with the full reader.
The companion bridge routes continuation and keeps manual refresh as a full
replacement read. Thread counts/filters explicitly describe loaded feedback.

The full Revue suite, 109 provider tests and companion restart integration pass;
a separate actual Vim/ReviewHub subprocess fixture verifies cursor/source routing
and full-refresh dispatch. Live reads loaded 50 + 37 conversation messages and
20 + 14 threads. All 34 threads / 77 messages in the latter matched REST anchors,
bodies and versions; the reference PR's 7 threads / 8 messages also matched.
Live evidence and captures (local evidence: `../output/github-feedback/`) record zero mutations.
Private transitions, nested paging failures and changed identities are fixture
verified; no live private write was performed.

**Remaining at that checkpoint:** bounded refresh, private-review paging and remote latency budgets. Bounded replacement refresh subsequently gained the core above.
Timeline paging remains a separate inventory. Local SQLite still reads the
retained review object in full, so this slice bounds UI/transport inventory
rather than storage I/O.

`test/feedback_pages.py` covers failures, cancellation, stale refresh callbacks,
complete-unit overlap, exact search/jump, retained composer text and outbox
ownership. Local tests cover 52 full threads plus conversation, restart and
changed/foreign cursors; a real Vim process uses the actual local asynchronous
transport to load its second page. Terminal captures and validation evidence
are in output/feedback-pages (local evidence: `../output/feedback-pages/`).

**Coverage/retry core implemented:** discussion and file indexes now disclose
loaded/known-total inventory counts and explicit scope. Missing or malformed
metadata stays unknown; matching-message counts are separate from loaded counts.
Private-review access and resolution-state coverage are independent of message
body coverage. GitHub keeps its pagination/cap checks and marks unavailable-root
or failed-private feedback partial. Local retained-source reads report the
current shared conversation's coverage.

The index shows refresh progress/failure while retaining prior data, exact
selection and unsent text. `:ReviewRefresh` is the replacement-read retry path;
this increment does not provide an append-page/cursor protocol. A failed read
cannot look like an empty complete review. `test/inventory.py` exercises all
coverage states, invalid counts, delayed refresh, partial-to-complete retry,
newly searchable text, exact result selection and editing during a read.
The full Revue suite (including 23 local-backend tests), all 89 provider tests
and companion integration/restart pass. Live GitHub coverage (local evidence: `../output/inventory/live-github-read.json`)
reports 1 file, 7 threads, 4 conversation/review messages, 0 private reviews and
7 known resolution states; zero mutations. 80-column partial (local evidence: `../output/inventory/80-partial.png`)
and 120-column failed refresh (local evidence: `../output/inventory/120-failed.png`) are real
isolated Vim terminal-cell captures from fixtures, not OS screenshots.

**Implement:** establish a measured large-review fixture and optimize only
observed bottlenecks. Make loading/completeness and search scope explicit.

**Done when:** exercise 500 changed files and 2,000 messages, record filter,
search, redraw and refresh timings on a named environment, and set an agreed
latency budget before declaring completion. Delayed/failed pages cannot look
like no discussions. Full-body search finds text outside excerpts; refresh
retains exact selection and unsaved text. Polling is a separate option.

**Implemented first increment:** distinguish complete, loading, partial, failed and
unsupported inventories in the index, with loaded/known-total counts where
available and a retry/continue route. Benchmark cold open, warm filter,
search, message jump and redraw. The 500-file fixture is a synthetic/local
scale target; it must also verify GitHub's explicit comparison-cap outcome,
not assume every backend can retrieve that many files through one endpoint.

**Measured performance follow-up:** the first full 500-file / 2,000-message
benchmark exceeded its 60-second deadline. A diagnostic run with a longer
deadline identified repeated per-file scans of all messages. The sidebar now
aggregates thread and unread counts once per redraw, without hiding feedback
or introducing a persistent cache. A focused test verifies counts after a new
thread arrives; activity/discovery suites preserve read markers and navigation.

Same fixture, observed milliseconds (single baseline and follow-up runs):

| Interaction | Before | After |
| --- | ---: | ---: |
| Cold open | 25,817.5 | 541.5 |
| Warm file filter | 69.9 | 52.9 |
| Full-body search | 42.2 | 42.3 |
| Exact message jump | 17,642.5 | 618.1 |
| Refresh | 17,883.1 | 692.8 |
| All-feedback view | 174.5 | 169.6 |

Reproducible fixture (local evidence: `../output/inventory/benchmark.py`),
baseline (local evidence: `../output/inventory/benchmark-baseline.json`), and
follow-up (local evidence: `../output/inventory/benchmark.json`) record Vim 9.1 on macOS 26.5.1
arm64. The synchronous synthetic backend excludes network/source-retrieval
latency; headless redraw is not an OS-paint measurement. These observations
identify a meaningful improvement, not a statistical performance guarantee.

**Remaining:** set agreed latency targets and measure interactive/remote cases.
The shared continuation/cancellation/merge contract now exists, with local and
GitHub adapters. Private-review paging remains; bounded replacement refresh is implemented above. Legacy/full-reader
retries honestly in the meantime. GitHub's explicit comparison cap remains a
supported limitation, not a prompt to silently return fewer files.

### UX-25 — Assign a feedback set to a participant (P2, L; local backend + integrations)

**Implement:** versioned selection of comment IDs and comparison, participant
choice, assignment/run state, authored inline responses and proposed new
comparison. Expose the same objects/actions through MCP. Dependencies: existing
batch/revision foundations; participant capability and identity contract.

**Done when:** an agent addresses one selected comment, the human replies in
that thread, and resulting edits are reviewed as a new capture. Restart keeps
conversation and assignment identity. Completion neither auto-resolves nor
commits. Backend owns storage; MCP is another client. Git notes export may be
additive; this workflow must not depend on it.

### UX-14 / UX-22 — Optional shared progress and acknowledgement (P3, M; backend + Revue)

**Implement:** independently capability-gated GitHub Viewed sync and reaction
participant details/additional message kinds, after verifying API support.

**Done when:** local versus server state is named; stale content invalidates
Viewed correctly; missing actor/membership is unknown rather than zero; only
the current actor's reaction is removed. No automatic hiding or resolution.

### UX-23 — Apply a suggestion (P3, L; capable backend + Revue)

**Implement:** single exact-target application before batch application, with
replacement preview and an explicit workspace-edit or remote-commit outcome.

**Done when:** stale source, overlapping suggestions and permissions are checked;
only the previewed replacement is applied; outcome has a receipt/new comparison.
Sending, rendering or quoting a suggestion never applies it.

### UX-24 — Read checks and readiness (P3, L; companion/backend + Revue)

**Implement:** revision-bound summary, diagnostic detail/source jumps and
browser fallback, initially read-only.

**Done when:** loading/unavailable/running/failed/completed are distinct; a check
for an old head cannot imply current readiness. Approval, unresolved discussion,
agent completion and merge eligibility remain separate. Merge/land UI is outside
this queue.

## Cross-cutting interaction acceptance

| Situation | Required behavior |
| --- | --- |
| Root plus three replies; second reply selected | Header/focus identifies that message; quote/edit/link/reaction targets its stable ID, not the root or its visual row. |
| Tall source card clips at a viewport edge | Focus discussion gives scrollable real text and a predictable return. Do not solve virtual-row clipping by restoring individual collapse. |
| Reply → preview → edit → source | Body, comparison, selection and return position survive; target context is readable at 80×24 and 120×40. |
| Local save versus native private save versus publication | Name the destination state and scope before sending; pending feedback must not look published. |
| Permission or source changes while composing | Keep the body; explain which action is unavailable and how to revisit its target. |
| Request accepted but response lost | Show unknown delivery; reconcile the same operation without duplicate publication. |
| Resolve, read, Viewed, outdated, agent completed | Each remains independently represented. None implies approval or merge readiness. |
| Keyboard-only reading and low-color terminal | Native motions/search/registers remain usable; textual status and selected-message identity do not depend only on color. |

These are release scenarios, not new parallel feature projects. Reuse existing
fixtures and focused tests where coverage already exists. For usability, have
someone unfamiliar with the commands find a reply, quote it, save privately,
return to code and inspect an older comparison; record wrong turns before
adding more persistent chrome. No unfamiliar-user study was run in this audit.

## Deliberate Vim differences and deferred decisions

- Real text buffers for editing, selection and search; virtual rows for source
  cards. Use motions, registers, commands and configurable mappings rather than
  imitating clickable HTML controls in fake source lines.
- Preserve native diff motions, `/` and `?`, and composer macro recording.
  Focus/restore is the responsive layout; avatars, hover menus and pixel-perfect
  browser spacing are optional decoration.
- Keep all individual inline threads expanded, including resolved discussions.
  Global comments visibility requires a separate product decision. Diff format
  remains deferred. Neither is required to finish the comment UX backlog.
- Local drafts, backend-private comments, published feedback, resolution,
  unread markers and Viewed are separate states. Backend capabilities define
  actions; GitHub-specific operations need not exist on local/Piper backends.
- Local agent assignment is a product extension rather than a GitHub parity
  percentage. It uses the shared conversation instead of a second destination
  or an MCP-owned message store.
- Native review rerequests, dismissal, moderation and issue creation can use
  explicit browser routes initially. They affect participants or repository
  policy and are not prerequisites for this comment-focused queue. Any later
  in-editor action needs a separately declared backend capability and scope.

### Visual details: preserve, refine, or adapt

| GitHub pattern | Vim disposition | Remaining check |
| --- | --- | --- |
| Bordered conversation container interrupts the code surface | Preserve the high-contrast card and boundary extending into the gutter | Themes, low-color terminals and resize must retain a visible boundary without changing source coordinates. |
| Distinct author/header for each reply | Preserve message headers and per-message selection | Long authors/roles and overlapping anchors must identify reply 2 unambiguously. |
| Inset quotes, inline code and suggestion diff | Shared semantic formatting already exists | Keep quoted suggestions visibly quoted; never imply they are executable. Native prose selection and copied Markdown must agree. |
| Hovered message menu and small reaction toolbar | Adapt to focused-message actions and actual configured keys | Help should explain the route from a virtual card into selectable discussion text. Do not add permanent toolbars to every reply. |
| Docked Comments panel beside code | Adapt to native splits with focus/restore | At 80×24, prioritize the active text buffer; preserve origin on return. Existing preview captures still show minimum-size panes and tab bars competing with the comment. |
| Browser scrolling through very tall cards | Adapt to a full, searchable discussion buffer | Virtual rows may clip at the viewport edge. The escape is focusable text, not individual thread collapse. |
| Rendered HTML, avatars and proportional typography | Approximate semantic hierarchy in terminal cells | Full HTML/CSS fidelity and image avatars are not acceptance criteria for Vim parity. |

The preview and GitHub reference captures reviewed above support these design
judgments; they do not establish screen-reader usability or unfamiliar-user
success. Add those observations to the existing validation work rather than
claiming visual similarity proves interaction parity.

## Delivery checks

For each slice, show the full journey with a multi-reply specimen, exact-message
targets, pending/public states, long names/paths, 80/120-column captures and
native keys. Exercise permission loss, refreshed data, draft retention and
restart for stateful operations. Run the relevant existing regression suite;
do not count a command's presence as completion of its workflow.

Authenticated GitHub mutation verification remains an outstanding release
check. Fixture/provider tests cannot establish every role, policy or rollout.
No GitHub writes were performed. Implementation follow-ups, including the
original-context validation and handling changes, are identified above with
their evidence; earlier implementation reports retain their historical scope.
