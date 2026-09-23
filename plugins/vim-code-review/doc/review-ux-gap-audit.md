# GitHub → Revue: current interaction audit

Audited **2026-09-14** against the current Revue working tree and the adjacent
`vim-code-review-github` provider. Status describes this working tree, not a release.
The [GitHub reference](github-review-ux-spec.md) holds the detailed external
specification; the [backlog](interaction-backlog.md) retains stable UX-01–26
stories and acceptance contracts. Earlier incremental findings are preserved in
[the audit history](review-ux-gap-audit-history.md).

The [parity completion audit](parity-validation.md) maps all UX-01–26 contracts
to current evidence. The [runnable local trial](ux-trial.md) prepares the next
human discovery check; it does not replace that observation.

## Assessment

Revue already has the core comment review loop. The strongest remaining
interaction concern is **discovering how to act on a particular reply from a
code card**. The card is virtual text; selecting and quoting a particular
message happens in a real-text discussion buffer. That extra transition is
reasonable in Vim, but must be apparent to someone who did not build the plugin.

A subsequent implementation pass corrected a concrete entry mismatch: the
card's “full thread” hint had advertised the all-file list. It now advertises
focused selection/quotation, and the discussion header shows configured message
motions, actions and quote bindings. The chooser preserves a selected ID across
reordering and cancels on removed/moved targets or changed source selection.
Full-suite evidence and real Vim renders (local evidence: `../output/thread-entry/validation.json`).
This closes that defect, not the unfamiliar-user observation.

Do not restart work on replies, quoting, previews, private review batches,
resolution, reactions or narrow reading tabs: those have implemented cores.
UX-09b now removes the resolution detour: explicit Resolve/Reopen sends in
place, with waiting/failure/unknown status beside the thread. Receipt checking
is a separate action; pending operations survive restart.
Implementation evidence and terminal renders (local evidence: `../output/direct-resolution/validation.json`).
Single-suggestion workspace application is now implemented in the shared UI
and local backend, including a resulting capture and an exact-message
application annotation. [Workflow and evidence](suggestion-application.md).
The remaining feature gaps are GitHub suggestion commits/batches, some historical
source comparisons, optional service progress, complete policy enumeration, and real agent runtime validation.
The last is a product extension with its own priority, not a prerequisite for
GitHub comment parity.

**Recommended order:** validate the exact-reply journey; establish remaining
service-permission evidence; extend
historical navigation where the comparison is provable. Keep the participant
runtime track separate. Priorities below are design judgments based on the
user's emphasis on comments, context and native Vim interaction.

## Surface-by-surface comparison

“Core” means the user route exists with recorded automated coverage. It does
not mean every GitHub role, permission, rollout or failure has been exercised.
GitHub reference IDs identify sections of the external specification.

| User journey / reference | GitHub interaction | Current Revue interaction | Gap or deliberate adaptation |
| --- | --- | --- | --- |
| Open and understand a review · S01/S02/S06 | Review list, identity, description and reviewer context; overview alongside code | Companion discovery, review identity, comparison and conversation/purpose view | Core. Keep service inbox behavior in the companion and context accessible from the action guide. |
| Read a thread beside code · F02/C01/C02 | Root and flat replies grouped inside a bordered conversation, with author/date and message actions | Contrasting cards, gutter-spanning boundary, reply separators, metadata and independent thread identities | Preserve the contrast and hierarchy. Terminal cells need not reproduce avatars or HTML dimensions. |
| Act on the second reply · C01/C02/W04 | Each message owns its menu | Source card → real-text discussion → message motion/selection → action | Focused card entry and message-action hints are now aligned; UX-06/18 remains the highest-priority discovery check. Do not treat a virtual row as cursor-selectable text. |
| Quote or copy · C03/C04 | Quote reply, selected quotation, links and rendered Markdown | Whole/selected and attributed quotes, raw Markdown copy, semantic links | Core. Keep native Visual selection, registers and exact message identity. Full HTML/media is outside this milestone. |
| Comment on code · W01/R03 | Gutter action and dragged/Shift-selected range | Source command or Visual range; contextual composer and preview | Core. Verify API support separately for GitHub creation outside changed hunks; received outside-hunk feedback remains readable. |
| Comment on a file or review · S03/W01 | File-level discussion and general comments | File feedback and conversation surface | Core. General and anchored discussion share message behavior without pretending to have the same anchor. |
| Draft, collect and publish · W02/W03 | Private pending comments, review summary/decision, then publication | Persistent local drafts, native private review operations, selected staging, batch preview and publication | Core. Local draft, backend-private and published remain visibly distinct. Permission/scope validation remains. |
| Edit or remove feedback · W04 | Permission-dependent per-message actions and edit history | Exact-message editing, supported deletion and read-only edit history | Core subset. GitHub roots with replies and other unsupported message kinds remain restricted; verify actual service scope. |
| Resolve or reopen · C06/V04 | Conversation action; GitHub documents collapse on resolution | Capability-aware command → in-place waiting/result; explicit receipt checking | UX-09b core implemented. Deliberately keep the thread visible after resolution. |
| Read on a narrow screen · F02/A02 | Responsive prose, alternate comments panel | Managed reading tabs in narrow flows; original source windows retained; explicit split mode available | UX-18c core. Paired 80×24 assignment fixture gains two reading-window rows. Observe the complete task separately. |
| Acknowledge a message · C03/W04 | Lightweight reaction interaction | Chooser with explicit Add/Remove, waiting, retry and receipt recovery | UX-22b core. Participant names now appear below the choices; live GitHub write-role validation remains separate. |
| Find feedback · S03/S06/V07 | Central comments surface and conversation filters | Discussion index, loaded-content search/filter, paging, typed history, targeted history-thread lookup | UX-15b history core. Search is not global service search; private/mixed GitHub threads may require paging. |
| Inspect the code originally reviewed · S07/R02 | Navigate from review/discussion to historical changes | Retained local comparisons, verified original-file context and exact return; GitHub context reads now use initial feedback plus target lookup/paging | Partial. Later-page original-file inspection and saved-reference reopening are verified; a historical head alone cannot prove the original PR base. UX-12d/20b retains explicit fallback. |
| Continue while data changes · S05 | Refresh/loading while preserving work context | Bounded reads, cancellation, unread markers, preserved drafts/focus and uncertain-write recovery | Core. Large-body refresh improvements are measured; broader repeated sampling separates service wait from adoption. Identified rendering refinements are delivered; further optimization needs a concrete workflow problem. |
| Track progress · F03 | Viewed state tied to reviewed files | Local content-bound Viewed, independent of visibility | Intentional subset. Explicit per-file service Viewed reads/updates now exist; local marks remain independent. [Contract](service-progress.md). |
| Propose and apply a change · C05 | Suggestion block, then single/batch application creating commits | Authoring/rendering plus explicit local workspace application, capture and receipt recovery | UX-23a workspace core implemented. Native service application lacks an established public API contract; generic commit creation does not close that gap. [Assessment](github-suggestion-service-contract.md). |
| Assess readiness · S08 | Checks, requirements, merge status and alerts | Head-bound read-only checks, required classification, review/merge facts, paging and source links | UX-24a observation core implemented. Full policy and unreported requirements remain explicitly unavailable; no merge action. |
| Ask an agent to address comments · Revue extension | Related remote agent/re-review workflows | Saved assignments, scoped MCP, inline participant replies, outcomes, result navigation and cancellation | UX-25a/b core; start/resume UI and supervisor/MCP recovery now have a fixture-verified core. Prepared-run abandonment is also implemented. Real adapter and extended iteration validation remain. |

GitHub's newer Comments panel brings general and anchored discussion beside
code and supports quote replies. The design implication is one conversation
model across our views, with predictable return to code.
[Comments panel](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/),
[docked panels](https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/).

GitHub documents pending review privacy, multiline/file feedback and Viewed
behavior. Revue should match their useful outcomes while keeping Visual
selection and content-bound progress native to Vim.
[Review workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/reviewing-proposed-changes-in-a-pull-request).
Suggestion application creates a commit on GitHub; a local workspace edit needs
a different explicit consequence.
[Applying feedback](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request).
Historical navigation must identify the code that was actually reviewed.
[Viewing a review](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/viewing-a-pull-request-review).

## Interaction friction to address

These are inspected routes, not measured task times. A command, a chooser and a
window transition are different costs; raw keystroke counts alone would conceal
whether the user still understands the target.

### Which differences deserve work?

Judge parity by whether someone can finish the review task, understand its
target and consequence, and return to their code. Browser control count and
pixel similarity are secondary. These dispositions keep the implementation
backlog bounded:

| Difference | User cost | Disposition |
| --- | --- | --- |
| Inline virtual rows versus selectable HTML messages | Acting on reply 2 requires a transition to Discussion | Highest-priority usability check. Preserve the reader; refine the cue or selected-message context only when a missed transition is observed. |
| Rich card versus Markdown-visible reader | Quotes and suggestions can look different after entering Discussion | Validate visual continuity with identical content. Preserve native text selection and exact suggestion bytes; do not require an HTML renderer. |
| Many explicit commands versus browser buttons | A user may know the desired action but not its command or scope | Keep the existing contextual guide as the discovery route. Check default, remapped and disabled-default configurations before adding controls. |
| Local draft, private service review and published feedback | An ambiguous label can send feedback to the wrong audience | Preserve distinct delivery labels and payload preview. Test whether the reader can predict who sees the next action; current implementation exists. |
| Initial rendering of every expanded message | Long threads can pause entry into a review | Identified cache, wrapping and duplicate-layout refinements are delivered. Preserve complete content and selection; investigate further when a concrete workflow cost warrants it. |
| Incomplete historical comparison evidence | A plausible-looking diff could show code other than that originally reviewed | Extend only where both endpoints are proven; keep the original-file or service-link fallback. |
| Local suggestion application versus GitHub commit application | The same-looking suggestion has different consequences | Missing service capability. Say explicitly whether the action saves workspace files or creates a commit; implement through the backend contract. |
| Resolution, Viewed and visibility are coupled in parts of GitHub | Copying that coupling would hide discussion the user wants to read | Deliberate divergence: keep states independent and comments expanded. |

The [first iteration packet](interaction-backlog.md#first-iteration-packet)
turns these judgments into a bounded comparison and implementation handoff.

### Concrete routes to compare

These are present commands, not proposed new controls. Keys below are defaults;
the command and contextual guide remain available with custom mappings.
The source for this inventory is [action registration](../autoload/revue/maps.vim)
and [session dispatch](../autoload/revue/session.vim).

| Intent | Current Revue route | What to evaluate against GitHub |
| --- | --- | --- |
| Act on an exact reply | From code, `:ReviewThread` (`<LocalLeader>t`); choose the thread if anchors overlap; `]m` / `[m` in Discussion; `a` for message actions | The selected author and message must remain apparent. Opening all file discussions with `t` is a different route. A command's existence does not establish discoverability. |
| Quote a passage | Select real discussion text with Visual mode → `:ReviewQuote` → edit draft → `:ReviewPreview` → `:ReviewClose` to return | Preserve the selected message and quoted bytes. Preview remains optional; users should not need to navigate a virtual card as if it were source text. |
| Resolve without leaving code | `:ReviewResolve` / `:ReviewReopen`, or the selected message's available thread action | A direct action already exists. Waiting, failure and unknown delivery must be understandable at the thread; `:ReviewCheckThreadState` inspects uncertain outcomes. |
| Acknowledge a message | `:ReviewReactions` → explicit Add/Remove chooser action | Already direct. Evaluate target/count/own-state clarity; participant inspection is available below the choices, with unavailable accounts labeled. |
| Recover private work | `:ReviewPending` for backend-private review; `:ReviewActivity` for saved operation outcomes | These are distinct from the editable local draft. Keep publication scope visible rather than presenting all three as simply “pending.” |
| Follow older feedback | `:ReviewTimeline` → selected event → `:ReviewLoadEventDiscussion`; `:ReviewEventComparison` when supported | Targeted lookup already exists. Historical comparison still needs evidence of both sides; loading a message is not proof of its original base. |
| Apply a suggestion | In Discussion, `:ReviewApplySuggestion` → exact workspace preview → explicit application → `:ReviewLatest` for result | Local saved-file application exists. GitHub's commit-producing action is a distinct backend capability, still missing here. |

### Visual hierarchy: preserve and verify

The retained GitHub image and Revue renders support keeping a strong boundary
between source and discussion, a flat sequence of replies, author/state above
body, and inset quotes/suggestions. They do not justify copying browser pixel
dimensions or claiming equivalent readability on every colorscheme.
Revue's selectable discussion reader can expose Markdown syntax; the source
card and reader serve different interaction needs.

For the next visual change, compare the **same** root, two replies, nested
quote and suggestion at 80×24 and 120 columns. Check the code/card gutter
boundary, selected message, author/state, body space, wrapping and exact return.
The older GitHub and Revue images use different fixtures and cannot establish
a measured before/after improvement. This is a UX-17/18 acceptance check,
not a request to redesign the existing cards or reintroduce collapse.

| Task | Present difference | Planning decision |
| --- | --- | --- |
| Act on reply 2 | GitHub exposes actions on each message; Revue's source cards are virtual rows, with selectable text in Discussion | Preserve the real-text reader. Validate that the card hint, message motions and selected author make the transition apparent (UX-06/18). |
| Resolve a conversation | The earlier operation-buffer/confirmation detour has been removed | UX-09b now sends from the thread and exposes recovery in place; Activity retains optional details. |
| Save or publish prose | Revue has a native composer, optional preview and an additional send confirmation | Retain for this plan. Delivery scope and payload are material; the reaction/resolution simplification does not automatically apply to publication or deletion. |
| Read at 80 columns | GitHub can dock discussion beside code; Revue can give the reader a dedicated tab | Intentional Vim adaptation. Preserve source position, native selection/registers and user-created windows; check the complete return journey. |
| Read resolved feedback | GitHub documents resolution-driven collapse; Revue leaves the discussion expanded | Intentional product decision, not a missing feature. Resolution changes state, not visibility. |
| Use a suggestion | GitHub can apply it as a commit; Revue can apply it to a local workspace and capture the result | UX-23a workspace core implemented. Keep service commits explicit; no inference from a local save. |

GitHub sources: [conversation actions and resolution](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/commenting-on-a-pull-request),
[docked discussion](https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/),
[suggestion application](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request).
The resolution comparison follows the documented flow; it is not a fresh
authenticated test of every GitHub rollout or role.

## Discussion-ready shortlist

This is the remaining queue, not a list of everything the product should have.
**Validate** can close without code. **Refine** changes an existing interaction.
**Build** introduces a missing route. P1 is the current comment-focused priority;
P2 extends continuity or the local review product; P3 is optional expansion.

| Priority / story | Kind | Interaction pattern and completion criterion | Owner / dependency |
| --- | --- | --- | --- |
| P1 · UX-06/18 | Validate → refine | From code, find reply 2, quote a selected passage, preview and return without coaching. Add a short cue only at an observed missed transition; use the configured command/key and retain selected author/message. | Shared UI; existing discussion and guide |
| P1 · UX-08b/21a/09 | Validate | In an authorized disposable GitHub review, establish edit/delete/resolve scope for own/foreign, root/reply and private/public states. Preserve siblings and reconcile interrupted outcomes. | GitHub provider; real role/state fixture |
| UX-13/15/16 | Measured refinements delivered | Refresh cache cliff, wrapping and redundant layout work are addressed. Narrow discussion entry/return totals 484 ms versus 1,827 ms. Synchronous initial duplication is fixed; delayed adoption remains about 0.6 s. Further optimization needs a concrete workflow problem. | [Performance evidence](interaction-performance.md); preserve text/mode/target |
| P2 · UX-12d/20b | Extend | Historical event → verified comparison → exact discussion → return. Cover rebases/renames/missing objects; keep a labeled one-file/service fallback if the original base is unproven. | Backend revision evidence; existing comparison/history routes |
| P2 · UX-25c, separate track | Validate / finish | Saved assignment → explicit start/resume → attributed inline answer → result capture → return. Persist run identity, reconcile uncertain launch and demonstrate same-session resume. Completion is not resolution or approval. | Runtime adapter + shared UI; fixture start/resume core implemented; see [remaining limits](participant-runtime.md) |
| P3 · UX-23a | Extend | Workspace apply is implemented. Add service commit execution only with a verified API, exact commit preview, branch/role checks and co-authorship; batch later. | Service backend contract; existing application UI |
| P3 · UX-24a | Implemented core | Inspect head-bound checks, required classification and review/merge facts; reload/page/cancel with exact return. Full policy coverage is explicit. | [Contract and evidence](readiness.md); further policy enumeration remains separate |
| P3 · UX-14/22 | Optional cores delivered | Explicit personal service Viewed updates and reaction participant inspection. Local progress is independent; live Viewed writes remain unverified. | [Service progress](service-progress.md); reaction evidence (local evidence: `../output/reaction-members/validation.json`) |

For detailed triggers, recovery behavior and boundaries, use the
[remaining delivery contracts](interaction-backlog.md#remaining-delivery-queue--reconciled-september-14)
and [validation queue](interaction-backlog.md#validation-queue--separate-from-missing-features).
UX-10/19 additionally needs current API evidence before expanding GitHub
unchanged-line creation. A browser capability is not proof of an API capability.

## Reasonable parity in Vim

| Copy the interaction outcome | Adapt the mechanism | Preserve the boundary |
| --- | --- | --- |
| A comment is a distinct reading surface inside code | Contrasting background, rule into gutter, textual author/state and inset quote/suggestion | No per-comment collapse or misleading disclosure chevron |
| A message owns its actions | Exact message selection, native motions, contextual guide and configurable maps | No root substitution when a reply was selected |
| A selection becomes contextual feedback | Visual selection and native Markdown buffers | Preview file, side, range, revision and delivery consequence |
| Comments remain accessible without losing code context | Managed tabs on narrow screens, splits where appropriate | Preserve source windows, user-created layouts and exact return |
| Lightweight acknowledgements stay lightweight | Labeled chooser action with durable recovery | Opening or moving through the chooser never writes |
| Review work survives interruptions | Durable local draft/intent and receipt inspection | Unknown delivery never becomes an invitation to resend blindly |

Keep individual inline threads **fully expanded**, including after resolution.
The retained GitHub research observed a classic-page global visibility shortcut;
it did not establish universal new-layout behavior. A global control still needs
its own scope/persistence discussion, and GitHub's `i` must not replace Vim
Insert. [Visibility evidence](github-review-ux-spec.md#6-visibility-and-collapse),
[GitHub keyboard reference](https://docs.github.com/en/get-started/accessibility/keyboard-shortcuts).

Unified versus split diff remains deferred. Full HTML/avatars, rich binary and
dependency previews, moderation, repository administration and merge/land
controls are outside this comment-focused milestone. Browser links can provide
explicit fallbacks where appropriate.

The backend owns destination, persistence, permissions and receipts. Cards and
shared interaction code must not branch on GitHub/Piper/Codex/Claude. The local
pre-commit human–agent process is a peer backend; runtime adapters participate
in its conversations. Git notes may be additive transport/storage support,
not a requirement for all reviews or a second conversation source of truth.

## Cross-cutting interaction acceptance

Every changed interaction should be checked against the relevant cases below,
not just its successful path:

1. Two threads share one anchor; select the second reply, then insert an earlier
   reply during refresh. The target remains the same message.
2. Draft → preview → return at 80×24 and wider sizes, with default/custom maps.
   Preserve text, registers, cursor, window identity and user-created splits/tabs.
3. Local, private and published feedback show different delivery states;
   cancellation and unavailable actions explain their actual scope.
4. Permission/source changes or a deleted target retain the draft and explain
   recovery; a lost write response checks the original receipt.
5. Outdated anchor, unread message, Viewed file, resolved thread, approved review
   and addressed assignment remain independent states.
6. Partial pages and lookup results report coverage honestly. Not loaded does
   not mean deleted, and search of loaded content is not a whole-review search.
7. Quotes, long prose, code fences, Unicode and suggestions remain readable
   without changing underlying source coordinates or replacement text.

## Evidence and confidence

The current request-specific audit rechecked command registration, focused
thread entry, per-message actions, delivery confirmation and expanded-card
tests. Four focused checks passed: thread entry, contextual action guide,
narrow reading tabs and expanded comments. Official GitHub commenting, review,
suggestion-application, docked-panel and keyboard sources were reopened.
[Current record](research/ux-request-audit.json).

This is a planning update. It does not change application behavior. No fresh
authenticated GitHub walkthrough, remote write, OS screenshot or unfamiliar-user
study was performed. Retained images below support structural comparison only.

The performance follow-up runs five fresh Vim processes at four review sizes,
with changed/unchanged refresh while typing, plus five real GitHub runs. It
addresses the measured 128-entry cache cliff while retaining the 1 MiB byte
budget. [Methods, distributions and remaining costs](interaction-performance.md).

The cold-opening follow-up isolates wrapping and verifies unchanged text/card
output. Sixty fresh Vim processes compare before/after at verified 80×24 and
120×40 terminal sizes. The measurable improvement retains fully expanded
comments. The subsequent initial-layout pass below addresses duplicate narrow
rendering; asynchronous adoption remains a separately measured cost.
Cold-opening evidence (local evidence: `../output/cold-open/validation.json`).

The reader follow-up removes hidden-tab reflow and same-file reselection during
managed return. Its full-suite run includes a regression for native tab return
and hidden data refresh. Twenty fresh Vim processes exercise 40 complete
entry/return journeys at two verified viewports, preserving full cards and source
position. Reader evidence (local evidence: `../output/reader-entry/validation.json`).

Initial pane sizing now precedes file delivery. The synchronous narrow fixture
renders once instead of twice; 80 timing samples distinguish that gain from
asynchronous delivery, which shows no meaningful speedup. Delayed/error loading,
focus preferences and restored geometry pass in the full suite. This closes the
identified duplicate-render work, not all possible performance issues.
Initial-layout evidence (local evidence: `../output/initial-layout/validation.json`).

The historical-context refinement replaces a full GitHub feedback reload with
incremental loading plus verified target lookup or bounded paging. Fourteen
focused provider cases cover source checks, late-page lookup, saved-reference
reopening, membership/revision errors and paging bounds. A live read of
[an outdated Neovim discussion](https://github.com/neovim/neovim/pull/39723#discussion_r3415583773)
verified its original file at lines 12–17 and reopened the same saved context;
the target was absent from every initial 20-thread page. This is evidence for
one-file context, not the complete original PR base.
Current implementation evidence (local evidence: `../output/historical-context/validation.json`).

The subsequent UX-24a implementation adds read-only readiness to the shared UI
and GitHub companion. [Contract, coverage and evidence](readiness.md). It does
not establish a complete policy inventory or permission to merge.

An earlier planning recheck inspected focused-thread entry, message actions,
resolution dispatch, suggestion authoring, Viewed storage and provider scope.
**Five focused checks passed:** thread entry, action guide, suggestions, reading
tabs and thread state. Official GitHub workflow, commenting, application and
docked-panel sources were reopened. The planning UX-09b finding was traced to
`session#ChangeThreadState` and `session#Send`; the subsequent implementation
is recorded separately in direct resolution evidence (local evidence: `../output/direct-resolution/validation.json`). [Planning recheck record](research/ux-planning-audit.json).
No application behavior changed in that planning pass. The later UX-09b
implementation has dedicated interaction tests and terminal captures; it does
not establish live GitHub permission coverage or unfamiliar-user usability.

The earlier audit pass inspected action maps, action/delivery labels, session routes, layout,
card code, runtime helpers and the GitHub/local provider boundary. **Seven
focused checks passed in that pass:** action guide, rich replies, reading tabs, reactions,
targeted feedback lookup, private staging and expanded comments. Exact commands,
outputs and inspected file hashes are in the
[current audit record](research/ux-audit-reconciled-current.json).

Retained implementation evidence resolves older contradictory statuses:

- Reading tabs (local evidence: `../output/reading-tabs/validation.json`): implemented; the paired
  80×24 assignment fixture has 21 reading-window rows rather than 19. This is a
  layout gain, not a user-study result.
- Targeted history lookup (local evidence: `../output/feedback-lookup/validation.json`): implemented
  core, with local action/payload measurements and one recorded public GitHub
  read; private/mixed lookup and global search are not claimed.
- Direct reactions (local evidence: `../output/direct-reactions/validation.json`): explicit chooser
  actions and durable recovery implemented; live service-role coverage separate.

Visual inspection reopened the retained
[GitHub root/reply screenshot](research/github-review/07-outdated-thread.png),
Revue inline agent reply (local evidence: `../output/participant-mcp/80-inline-agent-reply.png`),
rich discussion (local evidence: `../output/rich-replies/120-discussion.png`) and
current narrow outcomes view (local evidence: `../output/reading-tabs/80-tab.png`).
The first is an earlier actual browser capture. Revue images are retained real
Vim terminal-cell renders, not fresh iTerm screenshots; older fixtures do not
prove current window geometry. Their useful evidence is card grouping, contrast,
quote/suggestion hierarchy and the recorded narrow reading measurements.

Earlier checks establish fixture behavior, not live permission coverage or
usability. The reference specification retains classic/new-layout and
observation limits; the current four checks do not replace implementation
evidence from the earlier passes.
