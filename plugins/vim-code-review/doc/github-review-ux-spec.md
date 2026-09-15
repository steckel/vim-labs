# GitHub review UX reference and Revue comparison

Research date: **2026-09-14**. Scope: GitHub.com web review surfaces, including
the classic and newer Files changed experiences. This is a reference for
discussion and planning, not an instruction to implement every GitHub feature.

The immediate Revue decision is to remove manual collapse/expand of individual
inline threads. A global comments visibility control is **verified on GitHub's
classic diff page, but not approved for implementation in Revue**.

Current comparison: the [UX gap audit](review-ux-gap-audit.md) summarizes the
implemented interactions and ordered remaining work.

Follow-up: the [Revue interaction audit and backlog](interaction-backlog.md)
compares this reference with the current code and defines prioritized,
Vim-oriented implementation stories. Use its UX IDs for actionable work and
the IDs in this document for the supporting GitHub behavior.

## Reading this specification

Evidence labels:

- **Observed:** inspected in a live browser during this audit.
- **Documented:** described by GitHub's official documentation or changelog.
- **Proposed:** our interpretation, design decision, or suggested acceptance test.
- **Unverified:** behavior requiring an authenticated account, another rollout,
  a destructive action, or a state absent from the inspected examples.

Direct observation used signed-out public pages in the Codex browser, dark
appearance, desktop viewport and a temporary 390 × 844 viewport. No review,
comment, reaction, resolution, suggestion, or repository setting was submitted.
The narrow viewport is a browser layout probe, not a test of native GitHub
Mobile, iOS Safari, touch interactions, or a software keyboard.

The public Files changed example served the **classic** page. Its newer Commits
and Checks headers differed from the classic diff header within the same PR.
The newer authenticated composer and docked panels were researched through
official sources; their presence is not inferred from the signed-out page.
Negative observations mean “not present in this inspected state,” not proof
that no account or rollout can expose a control.

Use the stable IDs below when discussing changes, for example: “C04 quote
reply,” “V02 global visibility,” or “G05 unchanged-line anchors.”

### Navigation

- [Product surfaces](#1-product-surfaces)
- [Review objects and state](#2-review-objects-and-state)
- [Files changed layout](#3-files-changed-layout)
- [Comment and thread anatomy](#4-comment-and-thread-anatomy)
- [Composing and submitting](#5-composing-and-submitting)
- [Visibility and collapse](#6-visibility-and-collapse)
- [Revision and feedback loop](#7-revision-and-feedback-loop)
- [Permissions and unavailable actions](#8-permissions-and-unavailable-actions)
- [Keyboard, responsive layout, and accessibility](#9-keyboard-responsive-layout-and-accessibility)
- [Revue comparison and priorities](#10-revue-comparison-and-priorities)
- [Acceptance scenarios](#11-acceptance-scenarios)
- [Evidence and follow-up](#12-evidence-and-follow-up)

## 1. Product surfaces

### S01 — Discovery and review inbox

**Observed:** repository pull-request navigation is separate from a particular
review. **Documented:** review-requested search supports both a person and a
team. A September 10, 2026 listing preview adds assisted filtering, boolean
queries, a collapsible common-filter sidebar, compact density, check counts,
stack indicators, and unread-update indicators. At announcement, it lacks
saved custom views, bulk updates, and visible milestones. Treat these as
preview-specific constraints, not capabilities of every listing.
[Review discovery](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/viewing-a-pull-request-review),
[listing preview](https://github.blog/changelog/2026-09-10-refreshed-repository-pull-requests-page-in-public-preview/).

**Proposed Revue comparison:** discovery belongs to the backend/companion. A
review result should identify the connection, review, author, update status,
and reason it is relevant. Opening a review should preserve its identity when
moving between the tree, discussion, and source panes.

### S02 — Shared PR identity and navigation

**Observed:** title and number, Open status, author, source/target branches,
commit count, changed-line summary, and tab counts establish context before
the diff. Branch and commit links open other representations of the change.
A compact sticky header replaces some of the full header while scrolling.

**Documented:** the surface map includes Conversation, Commits, Checks, Files
changed, and, where available, Findings. Merge readiness is a separate summary
of requirements. A draft PR cannot merge and has a readiness transition;
it is distinct from a reviewer having unpublished comments.
[PR reference](https://docs.github.com/en/pull-requests/reference/pull-requests).

**Proposed:** preserve review title, selected comparison, and local/remote
ownership in every Revue view. Distinguish “review is open,” “draft feedback,”
“agent is running,” and “change is ready.”

### S03 — Conversation timeline

**Observed:** description first; general comments and review events interleave
with commits and other activity. Entries have individual authors, dates,
permalinks, optional badges and edit-history indicators. Long timelines can
have a “hidden items” loading control. This is pagination/compaction of the
timeline, not a user folding a particular inline thread.

The two public examples also show that a bot review can be moderation-hidden,
and that email replies can appear as general timeline comments. Neither
example supports treating the timeline as merely a concatenation of all
currently visible code cards. [Observed examples](#evidence-atlas).

**Proposed:** the Revue conversation view should preserve entry types and
chronology, support general feedback, and link anchored discussions to code.
Loading older entries needs an explicit continuation indicator.

### S04 — Files changed: classic experience

**Observed controls:** commit-range selection, File filter, Conversations,
Jump to, Diff settings, per-file disclosure, context expansion, file actions,
and inline discussions. The specimen has one file, so it does not establish
large-file-tree behavior by itself. The diff table uses old/new line-number
columns, change signs, syntax highlighting, hunk boundaries, and inserted
discussion rows. [Classic specimen](https://github.com/tpope/vim-fugitive/pull/2474/files).

File filter exposes extension selection and a Viewed files filter in this
state. The classic settings popover offers unified/split and whitespace
controls with an Apply and reload action. These are independent choices:
file inclusion, diff presentation, and discussion visibility are different
dimensions of the review.

### S05 — Files changed: newer experience

**Documented:** the January 2026 default rollout retains a familiar diff while
adding a resizable tree with comment/diagnostic indicators, pending-comment
preview, local browser recovery for draft comments/replies, refresh without
full-page reload, and spacing/accessibility improvements. Large-review
virtualization can mean browser search, printing, select-all, and extensions
see only rendered content. These are documented rollout behaviors rather than
an exhaustive guarantee for every account.
[January rollout](https://github.blog/changelog/2026-01-22-improved-pull-request-files-changed-page-on-by-default/).

**Proposed:** use the newer experience when evaluating feature parity, and the
classic screenshots when discussing the specific card appearance the user
selected. Do not preserve an older limitation merely because it appears in
that screenshot.

### S06 — Discussion and context panels

**Documented:** newer Files changed has docked panels for Comments, Overview,
Merge status, and Alerts. Comments combines anchored review discussion with
general PR conversation and supports adding comments. Overview keeps the
description beside code. Merge status exposes requirements and blockers.
Alerts brings security feedback alongside the diff.
[Docked panels and official screenshots](https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/).

The February update specifically added general conversation and quote replies
to the Comments panel and corrected resolved/unresolved filtering.
[Comments panel update](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/).

**Proposed:** Revue's thread panel is a useful starting point. Treat it as an
alternate presentation of the same thread IDs, with a clear jump back to its
source. Opening/closing a panel should not change a thread's state or hide its
inline card. “Comments” on a toolbar may open this panel; it is not evidence
of a global hide/show action.

### S07 — Commits and an individual review's comparison

**Observed:** commits are grouped by date and expose description disclosure,
author/co-author information, short SHA links, a full-SHA copy action, and
browsing the repository at that revision. The commit list is distinct from
the Files changed commit-range picker.

**Documented:** View reviewed changes opens the version seen by the reviewer.
This is valuable for understanding feedback whose anchor has since changed.
[Viewing a review](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/viewing-a-pull-request-review).

### S08 — Checks, annotations, findings, and merge readiness

**Observed:** the Checks page includes commit selection, a check-suite region,
and a summary region. The specimen has no jobs; its empty state explicitly
says so. It does not show a passing check as a substitute for missing data.

**Documented:** checks can provide logs, summaries, annotations, and external
details. Commit statuses are a simpler mechanism and do not alone populate
the Checks tab. Line annotations can also appear near code. Running, failed,
cancelled, skipped, and completed-with-conclusion are meaningfully different.
[Status checks](https://docs.github.com/en/pull-requests/reference/status-checks).

Security annotations can have their own details, dismissal, comments, and
remediation actions. Findings/alerts should retain their provenance and
severity. A scanner result and a human review comment are different objects
even if both appear beside a source line.
[Alert review](https://docs.github.com/en/code-security/how-tos/manage-security-alerts/manage-code-scanning-alerts/triage-alerts-in-pull-requests).

**Proposed:** show backend-provided checks and readiness when supported, with
links to full diagnostics. Do not synthesize “ready to merge” from an empty
thread list or an agent reporting completion. Merge/land remains an explicit
backend action separate from reviewing code.

## 2. Review objects and state

This taxonomy is **our comparison model**. It avoids mapping several GitHub
concepts to one overloaded “comment” or “done” flag.

| Object | Meaning | Identity/context needed in Revue |
| --- | --- | --- |
| Reviewable change | PR, CL, or local captured change | Backend, connection, review ID |
| Comparison | Exact versions currently being examined | Source/base/head or equivalent opaque IDs |
| File entry | Changed file, including rename/deletion | Old/new path, type, available content |
| Anchor | Source location for discussion | Comparison, side, inclusive source range |
| Thread | Root concern plus ordered replies | Stable thread ID and anchor |
| Comment | One authored message | Comment ID, author, body, dates, edit state |
| Pending review | Feedback collected before publication | Selected comments and draft summary |
| Submitted review | Published review event and decision | Review-event ID, reviewed revision, decision |
| General conversation | Unanchored discussion | Timeline position and message IDs |
| Suggestion | Proposed replacement inside a message | Target range, replacement, application status |
| Check/alert | Automated evidence or diagnosis | Producer, revision, status/severity, details |
| Agent assignment | Work requested from a participant | Scope, run identity, progress, result revision |

### Independent state axes

| Axis | Examples | Must not imply |
| --- | --- | --- |
| Publication | Editor draft, pending review, published | Published means resolved |
| Thread resolution | Unresolved, resolved | Resolved means the code changed |
| Anchor currency | Current, outdated | Outdated means resolved |
| Presentation | Visible, globally hidden, filtered | Hidden means deleted or addressed |
| Moderation | Normal, minimized with reason | Minimized is a personal display preference |
| Suggestion execution | Proposed, applicable, applied, unavailable | A code fence was applied |
| Review decision | Comment, approve, request changes, dismissed | Approval itself merges the change |
| Agent work | Queued, running, needs input, completed, failed | Completed resolves every assigned concern |

A thread can be outdated and unresolved, resolved with visible replies, or
published while temporarily hidden by a display command. The backend owns
publication and lifecycle state; the view owns transient navigation/display.

## 3. Files changed layout

### F01 — File container and gutter

**Observed:** the file header is a persistent visual unit with path, change
summary, disclosure, copy, and an action menu. The code gutter is visually
continuous through change rows; addition/deletion colors include a stronger
number-gutter fill. Hunk-expansion controls occupy a distinct band.

**Proposed invariants for Revue:**

- Source numbers identify source lines, never card rows or diff filler.
- A comment's side and multiline range remain stable when panels resize.
- File headers and comment headers need distinguishable visual roles.
- Absent, binary, large, and unavailable content need explicit states.
- Context expansion must not silently switch the comparison.

### F02 — Code versus conversation

**Observed:** code is dense and monospaced. Discussion has a more spacious
prose rhythm, an avatar/author header, muted metadata, body padding, and a
bordered card. Suggestions create a second bounded surface inside the card.
At desktop width, a discussion card occupies a bounded reading column inside
the wider diff; it need not stretch prose across the entire code width.

The blue outline in the targeted-comment screenshot follows a permalink
selection. It should not be copied as the default border of every card.
The screenshots establish visual relationships; no universal pixel or color
token values were measured in this audit.

**Proposed adaptation:** retain the pronounced contrast and gutter boundary
the user liked. Compare our stronger header band with GitHub's quieter
author row intentionally. Preserve breathing room around messages, clear
reply separators, and inset suggestion surfaces even in a monospaced terminal.
An expandable-looking chevron is inappropriate when a card has no disclosure
action.

### F03 — File-level progress and large diffs

**Documented:** marking a file Viewed collapses that file; subsequent changes
can reset its viewed state. This tracks review progress rather than approving
the file. [Review workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/reviewing-proposed-changes-in-a-pull-request).

Single-file mode and virtualized multi-file mode are distinct large-review
strategies. The September 2025 single-file update added next/previous controls
and raised its then-current file limit; avoid treating those historical
numbers as today's permanent limits.
[Single-file mode](https://github.blog/changelog/2025-09-11-pull-request-files-changed-public-preview-experience-september-11-updates/).

**Proposed:** keep navigation responsive and expose loading/omission explicitly.
Revue already loads a selected file, but viewed progress and filtered traversal
require their own design. This work does not choose unified versus split.

## 4. Comment and thread anatomy

### C01 — Root comment

**Observed anatomy:** author/avatar; optional role or AI badge; timestamp as a
permalink; message-level overflow menu; Markdown body; reactions/feedback where
available. The inspected signed-out overflow menu offers Copy link. Its
limited contents do not describe the menu for an author or maintainer.

The root comment is visually associated with a precise source range. The
timestamp targets a message, while file navigation targets code. Preserve
both destinations when translating this to a terminal.

### C02 — Replies

**Observed:** a reply has its own author/date/menu and can show an Author badge.
The root and reply remain in a shared discussion region, separated vertically.
The root's focused outline does not turn every reply into a separate toggle.
GitHub displays an ordered conversation rather than progressively indenting
each reply into a Reddit-style tree. [Reply specimen](research/github-review/07-outdated-thread.png).

**Proposed:** retain a flat ordered sequence, independent message identities,
and a reply target. Multiple messages share one code anchor; a reply does not
need to duplicate the source excerpt. Multiple independent threads at one line
must remain separately selectable for replying.

### C03 — Message body and rich content

**Observed:** paragraphs, inline code, links, lists, fenced code, quotes,
reactions, and edited metadata appear in the sample discussions. Rich text
belongs inside the comment body rather than replacing its author/context.

**Documented:** Markdown supports headings, emphasis, links, lists, task lists,
quotes, and code formatting. Selecting text and pressing `R` can quote it in a
reply. The exact Markdown remains useful when editing or copying a message.
[Writing syntax](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax).

**Proposed:** provide readable rendering plus access to original Markdown.
Unsupported markup should remain legible. Links, task checkboxes, and embedded
media need explicit interaction semantics before being presented as actionable.

### C04 — Quotes and quote replies

**Observed:** a quotation is indented and distinguished by a muted vertical
rail; the response continues beneath it with normal body styling. Code inside
the quote retains code semantics. Quoted text is not a new code anchor.
[Quote specimen](research/github-review/08-quoted-discussion.png).

**Documented:** the newer Comments panel supports quote replies.
[Panel update](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/).

**Proposed:** a quote action should seed a reply with selected text and retain
the intended thread. A rendered quote alone does not imply we already support
that action. Decide later whether attribution/permalink is inserted along
with the quote; do not infer a new nested thread.

### C05 — Suggestions

**Observed:** Suggested change labels an inset mini-diff. Removed and proposed
content have separate sign/gutter/color treatment. Explanation appears outside
the inset. Several suggestions can be part of a discussion without replacing
the surrounding messages. [Suggestion specimen](research/github-review/01-classic-inline-suggestion.png).

**Documented:** authorized users can commit a suggestion or collect suggestions
into a batch, then commit them together. Applying suggestions changes the PR
branch and creates a commit. This is a different operation from submitting
review comments. Fork permissions affect availability.
[Applying feedback](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request).

**Proposed:** our current red/green suggestion rendering remains read-only.
An Apply action would require validated content/range, an explicit workspace
or remote branch target, stale-content handling, and backend receipts. Empty
replacement means deletion and must remain distinguishable from no suggestion.
Do not compare an old suggestion against unrelated current source.

### C06 — Thread footer

**Documented:** an authenticated reply composer belongs to an existing thread;
resolving a conversation is a separate action with permissions. Resolution
collapses the whole conversation in GitHub's documented workflow.
[Commenting and resolving](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/commenting-on-a-pull-request).

**Proposed:** present Reply clearly, with thread-level actions separated from
message-level actions. An unavailable action should not appear to succeed.
For this iteration, keep Revue's reply/full-thread affordances and remove its
manual-collapse affordance. Native resolution remains future backend work.

## 5. Composing and submitting

### W01 — Enter the composer

**Documented:** comments can target a line, an inclusive multiline selection,
a file, or the general conversation. The line-number/plus interaction supports
dragging and Shift selection. A file-level comment is useful for non-text
files and feedback without a meaningful line range.
[Comment entry points](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/commenting-on-a-pull-request).

**Proposed composer contract:** show the target and comparison; retain text on
navigation or failed submission; expose Write/Preview or an equivalent readable
preview; keep save-draft and publish actions distinguishable; return focus to
the source/thread that opened it. Source selection must be visible before
publication. Authentication and permissions should be checked by the backend.

### W02 — Single comment versus pending review

**Documented:** a comment may be submitted individually or collected into a
review. Pending review comments are visible only to the reviewer until the
review is submitted. The reviewer can edit them or discard the pending review.
[Pending-review workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/reviewing-proposed-changes-in-a-pull-request).

**Proposed:** model three distinct steps: editor draft, accepted pending review,
and published feedback. Revue's local outbox is not automatically equivalent
to a server-side pending GitHub review. A local backend's Save operation
accepts a message into its local conversation; it does not mean GitHub publish.

### W03 — Review submission

**Documented:** review decisions include Comment, Approve, and Request changes.
The newer UI previews pending comments before submission. The February 2026
update permits Request changes without a summary when inline feedback already
exists. Do not require redundant summary text solely to fill a field.
[Review quickstart](https://docs.github.com/en/pull-requests/get-started/reviewing-pull-requests-quickstart),
[submission update](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/).

**Proposed:** a batch preview should state the backend/review, selected comment
versions, reviewed comparison, decision, and what becomes visible. Keep
partial/uncertain writes recoverable. Publishing feedback must not silently
start an agent or apply a suggestion unless that workflow explicitly says so.

### W04 — Existing-message actions

**Observed/documented:** available actions vary by authorship, permission,
moderation status, and authentication. Separate permalink copying, quote reply,
editing, deleting, and moderator hiding. An edited marker may reveal history;
it is not equivalent to replacing all traces of the original message.
[Comment management](https://docs.github.com/en/communities/moderating-comments-and-conversations/managing-disruptive-comments).

**Proposed:** implement edits/deletions only when backend capabilities and
conflict behavior are defined. Preserve comment IDs across edits and keep the
reviewer's in-progress text if the remote version changes.

## 6. Visibility and collapse

This is the decision-critical distinction. “Toggle comments” can describe
several operations with very different scopes and side effects.

| ID | Mechanism | Scope and effect | Evidence | Revue decision |
| --- | --- | --- | --- | --- |
| V01 | Arbitrary per-thread fold | Hide one open thread for personal convenience | No such control found in inspected classic thread/menu; authenticated/new variants not exhaustively excluded | Remove our implementation |
| V02 | Show/hide diff comments | Diff-page presentation; affects comments together | `i` documented and observed hiding/restoring current inline comment headings | Discuss later; do not implement now |
| V03 | Resolve conversation | Shared thread lifecycle; conversation collapses | Official documentation | Separate future backend action |
| V04 | Show/hide resolved or outdated conversation | Disclosure of state-associated historical discussion | Official shortcut docs include bulk Option/Alt-click behavior | Separate design; no generic open-thread fold implied |
| V05 | Hide/minimize a comment | Moderation with a reason and permissions | Official documentation; moderation-hidden review observed | Do not map to a personal UI toggle |
| V06 | Collapse a file / mark Viewed | File content and progress | File disclosure observed; Viewed behavior documented | Unaffected by this removal |
| V07 | Expand context | Additional source lines around a hunk | Observed | Unaffected |
| V08 | Open/close Comments panel | Alternate discussion surface | New experience documented | Unaffected |
| V09 | Load hidden timeline items | Additional timeline entries | Observed on long conversation | Treat as loading, not thread state |
| V10 | Hide annotations | Diagnostic display | Separate `a` shortcut documented | Do not conflate with comment visibility |

Sources: [keyboard reference](https://docs.github.com/en/get-started/accessibility/keyboard-shortcuts),
[resolution](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/commenting-on-a-pull-request#resolving-conversations),
[moderation](https://docs.github.com/en/communities/moderating-comments-and-conversations/managing-disruptive-comments).

### Exact V02 observation

On the classic all-commits view of `tpope/vim-fugitive#2474`, with focus outside
an editor, pressing `i` changed the number of exposed current Copilot comment
headings from **5 to 0**. Pressing it again restored **5**. The source diff
remained visible. No publication or lifecycle operation was invoked. Images
[01](research/github-review/01-classic-inline-suggestion.png) and
[02](research/github-review/02-classic-comments-hidden.png) illustrate the two
presentation states; scroll position shifts as discussion rows disappear.

This establishes the classic control, not its persistence across reload,
its behavior with pending composers, or its parity in the newer experience.
The keyboard reference's `i` entry is under source-code browsing, so the live
PR check is useful confirmation of its applicability to this surface.

### V01 removal contract

**Approved by the user for this iteration:**

1. Remove the code-pane Enter mapping for collapsing an inline thread.
2. Remove per-thread collapsed state and the collapsed rendering branch.
3. Remove disclosure arrows, collapsed-card styling, and collapse instructions.
4. Keep every applicable inline thread expanded, including all replies.
5. Preserve gutter delineation, rich content, reply targeting, source ranges,
   thread navigation, and the full-thread panel.
6. Preserve Enter in the file list and Enter-to-jump in the discussion panel.
7. Introduce no global replacement toggle or automatic resolution behavior.

This removes Revue's per-anchor/thread toggle. Revue did not previously have
a separate fold for each individual reply inside the thread.

**Implemented in this working tree:** the mapping, toggle function, per-thread
state, compact renderer, disclosure chevron, and collapsed highlight are removed.
Help, card footer, README, and the card-library architecture reflect this choice.
The comment tests verify expanded rendering, Enter navigation, reply targeting,
multiple threads at one anchor, refresh, and unchanged source coordinates.
The full Revue suite and companion remote-review integration suite pass.

### V02 discussion criteria for later

Before adding a global control, decide its scope: selected file, entire review,
or all open review tabs. Specify whether drafts remain visible, what count or
indicator warns that comments are hidden, whether jumping to a thread reveals
it, and whether the choice persists. Any eventual action should affect view
state only, preserve code focus, and work identically across compatible
backends. GitHub's `i` cannot simply be copied into Vim, where it means Insert.

## 7. Revision and feedback loop

### R01 — Comparison semantics

**Documented:** GitHub PR diffs use the merge base to show what the topic branch
introduces (three-dot comparison). A direct comparison of two tips answers a
different question. A local pre-commit review should label its selected
baseline rather than implying every comparison has GitHub's semantics.
[Branch comparisons](https://docs.github.com/en/pull-requests/reference/branches).

### R02 — Outdated anchors and historical context

**Observed:** the Conversations menu listed seven unresolved conversations,
including two marked Outdated. Selecting the case-sensitivity thread navigated
to `/files/7bb9a03…#r3140841349`; the toolbar changed to a one-commit comparison
and the root plus author reply became readable. It did not resolve the thread.

**Proposed:** retain original comparison identity. A historical jump should
make the older revision obvious, preserve a route back, and avoid silently
reattaching a discussion to similarly numbered current code.

### R03 — Commenting beyond changed hunks

**Documented:** the newer UI permits comments and suggestions on unchanged
lines within a changed file after expanding context. This does not extend to
arbitrary unchanged files. The rollout announcement warned about classic-view
visibility gaps and limited API support at that time.
[Unchanged-line commenting](https://github.blog/changelog/2025-09-25-pull-request-files-changed-public-preview-now-supports-commenting-on-unchanged-lines/).

**Proposed:** Revue's present patch-range validation is a known compatibility
gap. Investigate current backend support before widening it. Do not discard a
received thread merely because it lies outside a locally cached hunk. This is
a separate change from removal of folding.

### R04 — Respond, re-review, and finish

**Documented:** authors can apply suggestions, push follow-up changes, and
re-request review. Review dismissal requires a reason and changes the review
decision. Branch protection can invalidate stale approvals and restrict who
may dismiss them.
[Feedback loop](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request),
[dismissal](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/dismissing-a-pull-request-review),
[protected branches](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches).

**Proposed:** local agent iteration needs an equivalent review-next-revision
loop while keeping the local backend's own lifecycle. Marking an assignment
addressed, resolving a thread, approving a revision, and committing are four
distinct operations. None should be triggered by a disclosure gesture.

## 8. Permissions and unavailable actions

| Role/state | Evidence-backed behavior | Design implication |
| --- | --- | --- |
| Signed out on public PR | Read public code/discussion; some actions absent or disabled; sign-in prompts | Absence of a control is not universal absence of the feature |
| Reviewer with read access | Can review/comment when authenticated | Draft/publish workflow must retain viewer identity |
| PR author | Cannot approve own PR | Do not offer a generic always-enabled Approve action |
| Required-review participant | Whether approval counts depends on repository rules and role | Separate displayed opinion from merge requirement satisfaction |
| Resolver | PR author or someone with repository write access in the documented workflow | Resolution is a backend mutation |
| Suggestion applier | Needs appropriate write/fork permissions | Rendered suggestion and executable action are independent |
| Moderator | Can hide with a reason; visibility changes for readers | Personal collapse cannot implement moderation |
| Dismissal actor | May be restricted by repository protection rules | Require reason and reconcile backend outcome |

Sources: [review permissions and self-approval](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/approving-a-pull-request-with-required-reviews),
[commenting](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/commenting-on-a-pull-request),
[suggestions](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request),
[moderation](https://docs.github.com/en/communities/moderating-comments-and-conversations/managing-disruptive-comments).

**Proposed unavailable/error states:** loading, no results, insufficient access,
unsupported action, stale comparison, network failure, partially published
batch, and unknown write outcome each need a distinct explanation and recovery
path. This list is a Revue acceptance requirement, not a claim that every
GitHub screen was exercised in every failure mode.

## 9. Keyboard, responsive layout, and accessibility

### A01 — Keyboard behavior

**Documented examples:** `?` opens shortcut help; `C` accesses commit filtering;
`T` focuses changed-file filtering; modifier shortcuts submit comments/review
comments and switch Write/Preview; `R` quotes selected text. Context matters:
editor focus, page variant, and disabled character shortcuts can change what
is active. [Keyboard reference](https://docs.github.com/en/get-started/accessibility/keyboard-shortcuts).

**Proposed:** preserve native Vim editing keys, expose contextual help, and
give source navigation, thread navigation, and submission distinct commands.
Opening a composer should move focus predictably; closing it should return
to its origin. Removing Enter's code-pane mapping restores its normal Vim
behavior; it must not publish, resolve, or hide anything.

### A02 — Responsive layout

**Observed at 390 × 844:** the compact review toolbar wraps; the file header
retains identity and overflow actions; prose and long code/suggestion lines
wrap in a narrow reading column. Gutter widths consume a substantial share
of the available space. Sticky controls can cover part of a permalink target,
so scroll placement deserves explicit testing.
[Narrow layout](research/github-review/06-mobile-inline.png).

**Proposed:** test a single readable code/comment column at narrow widths,
panel transitions, long author names, Unicode, and multiline suggestions.
Keep text and action labels legible; a separate panel may be preferable to
compressing code and discussion side-by-side. This does not settle the future
unified/split layout choice.

### A03 — Semantic and visual accessibility

**Observed:** navigation landmarks, labeled buttons, checkboxes, headings,
line-number table columns, and named empty-state regions expose structure.
**Proposed:** contrast alone is insufficient: status needs words/icons,
suggestions need addition/deletion signs, source anchors need line identity,
and focus needs a visible indication. A chevron should only advertise a real
disclosure. Resizing must not change source coordinates or reply targets.

## 10. Revue comparison and priorities

**Historical baseline:** the Revue column below records the initial research
checkpoint and predates subsequent implementation. For current feature status
and the next-work queue, use the [interaction audit and backlog](interaction-backlog.md).
The GitHub reference IDs remain stable.

The Revue column describes the working tree at that initial audit, including the
local-backend slice. Proposed priorities below do not authorize implementing
all items; only the per-thread-toggle removal is selected in this request.

| ID | Capability | GitHub reference | Revue now / gap | Priority |
| --- | --- | --- | --- | --- |
| G01 | Inline discussion | Bordered root/replies beside code | Strong contrast, virtual cards, gutter boundary | Preserve |
| G02 | Individual manual collapse | Not found for ordinary open thread in inspected UI | Enter toggle and collapse state removed | **P0 completed** |
| G03 | Global comments visibility | Classic `i` observed; official shortcut | No global control | Discuss only |
| G04 | Quote replies | Rendered quotes and quote-reply entry points | Quote rendering; no selected-text quote action | Candidate P1 |
| G05 | Unchanged-line anchors | New UI supports within changed files | Creation restricted to patch ranges | Candidate P1 compatibility investigation |
| G06 | Draft/pending review distinction | Private pending review then publish | Persistent local outbox; one draft per remote mutation | Candidate P1 |
| G07 | Batch preview | Preview pending feedback and decision | Proposed, not implemented across backends | Candidate P1 |
| G08 | Resolution and state filters | Native resolved/unresolved discussion | No native resolution action in current contract | Candidate P1 |
| G09 | Historical discussion | Review-version and outdated-thread navigation | Outdated messages readable in panel; revision switching limited | Candidate P1 |
| G10 | Suggestions | Inset diff plus authorized application | Read-only rendering | Preserve; applying is separate P2 |
| G11 | Alternate discussion panel | Comments + general conversation near code | Existing thread/conversation splits | Candidate P1 refinement |
| G12 | Viewed progress | File-level progress independent of approval | Not implemented in rich session | Candidate P2 |
| G13 | Message edit/reactions | Permission-dependent actions | Mostly display/reply subset | Candidate P2 |
| G14 | File-level comments | Supported including non-text files | Conversation fallback; no first-class file anchor | Candidate P2 |
| G15 | Diagnostics/readiness | Checks, findings, merge requirements | Backend/companion expansion needed | Candidate P2 |
| G16 | Local agent participation | Related Copilot workflows exist | Local store implemented; MCP/runners planned | Separate architecture track |
| G17 | Diff presentation | Unified/split/rich and whitespace modes | Current side-by-side review | Deferred by user |

### Ownership implications

- **Cards:** layout, wrapping, semantic body rendering, borders, and attachment.
- **Shared Revue UX:** selection, navigation, composer, draft recovery, and
  future display preferences. No per-thread fold state after this change.
- **Backend:** comments/replies, publication, native lifecycle, revisions,
  permissions, and receipts. Reads and writes use the same backend contract.
- **Participant integration:** agent execution and correlation of its replies.

An agent reply should look like an authored reply, with provenance where
useful. It should not force the card library to know about GitHub, Codex,
Claude, or local SQLite. Local pre-commit iteration remains a peer backend.

## 11. Acceptance scenarios

### Selected change: remove individual toggling

| Scenario | Expected result |
| --- | --- |
| Press Enter at a current thread anchor | Card remains fully rendered; normal code-pane key behavior |
| Press Enter on a reply's source anchor | Same; no per-message/per-thread collapse state |
| Refresh or resize | Root, replies, quote rails, code, and suggestions remain visible |
| Reply from source | Correct root thread ID reaches the composer |
| Two threads share an anchor | Both render; reply selection remains unambiguous through the panel |
| Multiline visual comment | Uses unchanged source coordinates |
| Enter in sidebar | Opens selected file, discussion, or draft as before |
| Enter in discussion panel | Jumps to source as before |
| Inspect available help/rendered footer | No collapse instruction or disclosure affordance |
| Backend requests during Enter | No mutation, resolution, or visibility RPC |

### Planning fixtures for later work

1. One thread with three authors, a quote, code fence, suggestion, and long text.
2. Two independent threads on one line, plus a multiline base-side thread.
3. Current unresolved, current resolved, outdated unresolved, and outdated
   resolved threads in the same file.
4. A pending review with replies and summary; reload before and after publication.
5. A changed file with a comment outside currently loaded hunks.
6. Renamed/deleted/binary/unavailable files with file-level feedback.
7. A suggestion whose target changed after it was written.
8. A remote write accepted before the connection drops; reconcile without repost.
9. A local agent result attached to a newer comparison while discussion remains
   anchored to the original capture.
10. Narrow viewport/terminal and Unicode content; source selection stays stable.

These scenarios are proposals for discussion and test coverage, not assertions
that all corresponding features exist in Revue today.

## 12. Evidence and follow-up

### Evidence atlas

All local images below are actual browser captures, not reconstructed mockups.
Some intentionally show portions of long cards; the links identify the exact
surface rather than implying the complete thread fits in one viewport.

| Image | Surface / observation |
| --- | --- |
| [01 Inline suggestion](research/github-review/01-classic-inline-suggestion.png) | Classic diff, targeted root, nested suggestion, sticky file header |
| [02 Comments hidden](research/github-review/02-classic-comments-hidden.png) | Same PR with `i` visibility off; source remains |
| [03 Comment menu](research/github-review/03-classic-comment-menu.png) | Signed-out message menu; Copy link |
| [04 Commits](research/github-review/04-commits.png) | Date-grouped history and revision links |
| [05 Checks empty](research/github-review/05-checks-empty.png) | Selected commit, empty check-suite/summary surface |
| [06 Narrow inline layout](research/github-review/06-mobile-inline.png) | 390 × 844 browser viewport; wrapping and sticky controls |
| [07 Historical thread/reply](research/github-review/07-outdated-thread.png) | Outdated-thread navigation selects historical comparison; author reply |
| [08 Quoted conversation](research/github-review/08-quoted-discussion.png) | General timeline quote and code formatting |
| [09 File filter](research/github-review/09-file-filter.png) | Classic extension and viewed-file filtering |

Live specimen URLs:

- [Current review diff](https://github.com/tpope/vim-fugitive/pull/2474/files).
- [Historical thread with reply](https://github.com/tpope/vim-fugitive/pull/2474/files/7bb9a03ba3229b4cefa5888eaa238920f3f1b69b#r3140841349).
- [Timeline with quotes](https://github.com/vim/vim/pull/6932#issuecomment-691117172).

Official newer-layout references with screenshots:

- [2026-01-22 Files changed rollout](https://github.blog/changelog/2026-01-22-improved-pull-request-files-changed-page-on-by-default/).
- [2026-02-19 Comments panel](https://github.blog/changelog/2026-02-19-access-all-pull-request-comments-without-leaving-the-new-files-changed-page/).
- [2026-03-05 Merge status](https://github.blog/changelog/2026-03-05-quick-access-to-merge-status-in-pull-requests-in-public-preview/).
- [2026-03-19 Docked panels](https://github.blog/changelog/2026-03-19-view-code-and-comments-side-by-side-in-pull-request-files-changed-page/).
- [2026-09-10 PR listing preview](https://github.blog/changelog/2026-09-10-refreshed-repository-pull-requests-page-in-public-preview/).

### Remaining direct-interaction verification

The specification covers these through documentation and explicit planning
requirements, but does not claim an authenticated end-to-end exercise:

- New Files changed: global visibility behavior, pending-composer interaction,
  panel docking persistence, and keyboard parity with classic.
- Author/reviewer/maintainer menu differences; editing/deleting published
  messages; permission loss while a composer is open.
- Resolution/reopening and bulk resolved/outdated disclosures on a fixture
  containing both states; no real conversation was modified for this audit.
- Pending-review publication, suggestion commits, native batch application,
  review dismissal, and rerequest notifications.
- Populated checks/findings, merge blockers, rich binary/dependency previews,
  and very large virtualized diffs.
- Native mobile application behavior, touch selection, screen-reader output,
  and an on-screen keyboard; viewport resizing alone cannot establish these.

Use an authenticated disposable review fixture for those checks when needed.
Until then, retain the evidence labels and avoid presenting every published
rollout detail as a live-observed invariant.
