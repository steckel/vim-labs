# Vim Code Review

The shared review interface in Vim Labs, formerly packaged as `vim-revue`.
The `vim-code-review-*` integrations represent review counterparties: GitHub
today, with Codex and Claude planned. Change capture, conversation persistence,
and assignment transport are supporting internals. Commands use `:Review*`
exclusively; update command mappings and restart Vim after upgrading.
Configuration keys and stored review identities are retained.

One review interface for Git, jj, and GitHub: immutable diffs, inline comment
cards, autosaved pending feedback, and Markdown export for your agent.

## Install

Install the `plugins/vim-code-review` directory from Vim Labs using native Vim
packages or your plugin manager, then `:helptags ALL` once
to pick up `doc/revue.txt`. Requires Vim 9.1+.
The [Vim Labs setup](../../README.md#install-selected-plugins) includes package
symlink examples. Add the component directory, not the collection root.

## Usage

For a GitHub PR tree, conversations, and inline replies, install the companion
[vim-code-review-github](../vim-code-review-github) and run `:Reviews` inside a GitHub checkout.
Use `c` in a code pane (or `V` then `c` for a range), `t` to read threads,
and `r` in a thread to reply. `C` opens the conversation. Drafts are saved
locally; Ctrl-S or `:ReviewSend` in the composer publishes after confirmation.
The provider UI shows immutable PR revisions and does not modify the checkout.

For saved workspace changes, use the same comment cards:

```vim
:Review                " Git defaults to HEAD; jj defaults to @-
:Review HEAD           " Saved Git changes against HEAD
:Review @-             " jj working copy against its parent
:Review! HEAD          " Git: include untracked files (excluding ignored files)
:ReviewSaved           " List saved reviews; Enter reopens one
:ReviewResume <id>     " Resume one exact saved review
```

Use `c` to comment, `r` to reply, and `C` for the conversation. Comments autosave
as you edit and appear immediately as **Pending** cards. `:w` explicitly saves;
`:ReviewClose` returns to the code. Ctrl-S or `:ReviewSend` also saves and returns,
without a separate submission. Use `:ReviewEditFeedback` on the source line to
edit a pending card. Pending feedback survives restarting Vim.

`:ReviewBatch` (or `:ReviewExport`) collects pending feedback and previously
saved comments. Space selects an item, `a` selects all loaded items, `u` clears
the selection, and Enter edits pending feedback or reads a saved discussion.
Press `m` (or run `:ReviewExportMarkdown`) to open the selection in one editable Markdown
buffer, with exact comment text, file/line locations and comparison references.
Use `ggVG"+y` to copy it to your agent, or `:w /path/feedback.md` to save it.
Export leaves the feedback and its Pending status intact; the export buffer
survives closing the review. If more saved feedback is available, load it with
`:ReviewLoadMoreFeedback` before selecting it. No export posts or starts an agent.

Previously submitted local comments remain saved discussions and are included
in the picker; no storage migration or resubmission is needed. The displayed files
are frozen at capture time; `R` refreshes discussion. Run `:Review` again
to capture newer edits as a separate review, or use `:ReviewCapture` within the
current review. Git capture does not stage or commit changes; jj performs its
normal working-copy snapshot.

The workspace backend requires Python 3.9+ with SQLite and captures Git or jj.
jj requires diff-template support (tested with jj 0.45). In colocated
repositories, jj takes precedence. jj captures its working-copy
revision, including new files automatically tracked by jj; ignored/untracked
files are excluded. jj symlinks, submodules, and conflicts are shown as unavailable
source rather than editable text. It stores reviews under `~/.vim/revue-local`; configure
`g:revue_local_dir` or `g:revue_python` if needed. Unsaved buffers are excluded.
Scoped local assignments and MCP replies now have a [backend/transport core](doc/participant-mcp.md).
`:ReviewRunParticipant` previews starting or resuming a configured participant
from assignment outcomes. `:ReviewAbandonRun` releases an unstarted preparation
through the same preview and receipt-recovery flow. See [runtime setup and validation limits](doc/participant-runtime.md).
Vim message selection, assignment preview and durable creation now work through `:ReviewAssign`.
`:ReviewAssignments` reads per-comment outcomes and opens their discussions/code;
`:ReviewAssignmentDetails` exposes full identifiers and source references while
the outcome reader keeps metadata compact.
`:ReviewCancelAssignment` previews revoking MCP access with durable recovery.
Agent execution adapters and Git notes export remain planned; the capture slice
provides durable local conversations through the shared backend contract.

`:Review` always opens this persistent card interface. `g:revue_default_base`
overrides the repository-specific default. `<Plug>(revue-open)` opens the same
interface and can be mapped to a key of your choice.

| Key | Action |
|-----|--------|
| `<CR>` | Open file under cursor in the file list |
| `]f` / `[f` | Next / previous file |
| `c` / `V` then `c` | Comment on a line / selected range |
| `r` | Reply at a discussion |
| `:ReviewBatch`, then `m` | Export selected feedback to a Markdown buffer |
| `q` | Close the current review view |
| `g?` | Commands and actual bindings |

## Diff appearance

Both source panes keep line numbers and a separate diff gutter: green **+**
for added head lines, red **−** for removed base lines. Unchanged context is
unmarked. The review palette restores the dark diff backgrounds and brighter
changed-word highlighting; comment cards and moved-block markers remain visible.
Vim's global diff colors are restored when the last review closes, unless you
changed them while it was open. Set `let g:revue_diff_colors = 0` to retain your
colorscheme's diff palette. `ReviewDiffAdd` and `ReviewDiffDelete` style the signs.

## Moved code

Git, jj, and GitHub reviews mark matching removed and added blocks. The base side
shows **M> / Moved to path:lines**; the head side shows **<M / Moved from
path:lines**, with a distinct line highlight. Moves can cross files when both
files' patches are available in the review. Comment anchors stay unchanged.

Whole-file renames reported by Git or jj appear as **R old → new** in the
file list, with the original file in the base pane and the renamed
file in the head pane. Any edits made during the rename stay visible
in the diff. Restart Vim after updating the plugin so already-loaded review
code is replaced.

Matching allows a consistent change in leading indentation and requires a
unique changed-line seed, with at least 20 letters/digits across the block.
Reindented moves include **(indentation changed)** in their labels; both panes
retain the actual source text. Only leading spaces and tabs are ignored;
all other text must match.
Tiny matches, ambiguous repeated blocks, copies without a deletion, and
rewritten code remain ordinary diffs. Reindentation within the same replacement
is treated as formatting, not a move, even when inserted lines shift its position.
Incomplete provider patches can limit detection. Source panes retain their
captured comparison; `:ReviewCapture` captures newer saved changes within the
same review. **R** refreshes discussion.

Set `let g:revue_moved_lines = 0` to disable marking. Themes can customize
`ReviewMoved`, `ReviewMovedLine`, and `ReviewMovedLabel`.

## Configuration

```vim
g:revue_default_base    " empty/default: HEAD for Git, @- for jj
g:revue_diff_colors    " review diff palette while a review is open; default 1
g:revue_moved_lines    " mark relocated blocks in diffs; default 1
g:revue_thread_separators " emphasize provider comment anchors in the number gutter; default 1
g:revue_local_dir      " local backend data, default '~/.vim/revue-local'
g:revue_python         " Python executable for the local backend, default 'python3'
```

Provider reviews show comments as framed, wrapped cards beneath their source
line. Inline discussions stay expanded. At the anchor, **r** composes a reply.
The card's “Select / quote a message” hint opens the discussion at that code;
when several discussions share an anchor, choose one first. These are virtual
display rows; source-line numbers and visual comment selections stay unchanged.

In rich review sessions, `]c`/`[c` keep Vim's diff navigation, and `]t`/`[t`
move between discussion anchors. `?` remains backward search; `g?` shows the
actions and actual bindings for the current view. `:ReviewThread` (or
`<LocalLeader>t`) focuses a discussion from any line in its range; `t` lists all
threads on the file. In a discussion, `]m`/`[m` move between messages, `a` opens
message actions, `Q` quotes the message or visual selection, and `gy` copies its
body. `:ReviewCopyLink a` copies its permalink into register `a` when available.
The discussion header shows the configured message motions, action menu and
quote binding. Refresh may update replies while the discussion chooser is open;
it retains the chosen thread ID. A removed/moved thread or changed source
selection cancels that choice instead of following a stale target.
Use `:ReviewReviewActions` (or `<LocalLeader>a`) for a contextual chooser grouped
into Read, Write and Review. It shows configured keys, unavailable reasons and
the selected file, comparison, message or draft. Read actions include the review
purpose/general conversation, unloaded history discussions, comparison
selection, latest/previous return, original discussion/draft code and local
Viewed progress. Only relevant return/progress actions appear; unavailable
original code explains the backend limitation. In a composer, Save draft locally, Prepare
private save, and Publish feedback are distinct choices; existing confirmations
still apply. A refresh or selection change while the menu is open cancels the
choice. `a` remains the selected message's own action menu, and `g?` includes
the same outcome-oriented guide above the complete command list.
`:ReviewBodyLinks` lists labeled message links and their full destinations before
opening or copying. GitHub resolves them from its rendered comment HTML; other
backends can supply explicit relative-link mappings. `:ReviewBodyURLs` retains
the raw URL finder, including code examples. Neither has a default key.
`:ReviewQuoteAttributed` appends a quote with an escaped author and source permalink
to the matching reply draft. Plain `Q` retains its existing behavior; set
`g:revue_quote_attribution = 1` to include attribution by default.
When the backend permits it, `:ReviewEditMessage` edits the selected published
message. Preview compares the original, current and proposed text. Conflicts
retain your draft; `:ReviewEditBase` accepts a refreshed base without replacing
your text. Unknown outcomes only check receipts. Local edits check versions
atomically; GitHub uses a preflight check with a remaining concurrent-write race.
`:ReviewMessageHistory` opens the selected message's available edits in a read-only
view. Headers and body surfaces stay distinct from code, with ordinary Vim
wrapping and unchanged recorded text. Use the action guide for older entries,
reload, cancellation and the original-service link; close returns to the same
reply. Local history shows retained before/after changes. GitHub supplies recorded
edit content for supported published messages, which may include creation and
is not necessarily a reconstructed patch. Redacted content remains unavailable.
`:ReviewDeleteMessage` previews deletion of one saved message when its backend
supports that scope. Close the preview, then use `:ReviewSend` to confirm; local
draft discard is a separate action. Refresh preserves neighboring-message focus.
An uncertain outcome only checks receipts or verified absence, never resends.
Local review comments, replies and general feedback are supported; audit events
remain in local storage. GitHub supports your published inline/general comments,
with current service permission checks. Review summaries and roots with replies
remain unavailable. GitHub preflight does not guarantee atomic conflict protection.
Reaction counts appear below message text, with `[you]` when your state is known.
`:ReviewReactions` loads the selected message's choices; Enter executes the labeled
Add or Remove action without a separate composer or confirmation. Unknown outcomes
offer a receipt check using the same operation ID. Only your reaction can be removed, and reacting never
resolves a thread or changes a review decision.

`:ReviewPending` resumes a GitHub review saved privately in the browser. Open its
exact comments with Enter, or use `:ReviewPublishPending` to prepare publication.
Preview includes every server comment and excludes local outbox drafts. If the
review changed, `:ReviewPendingBase` accepts refreshed contents while retaining
your summary. `:ReviewDeletePendingComment` previews deletion of one selected
private comment, from the pending inventory or focused discussion. Close the
preview and use `:ReviewSend` to confirm. GitHub roots with replies remain
unavailable until their deletion scope is verified. `:ReviewDiscardPending` previews the entire private review for
explicit deletion; unrelated local drafts are retained. Uncertain deletion checks
server state without repeating the write. `:ReviewEditPending` edits the selected
private summary/comment with the same conflict preview as published edits;
`:ReviewEditMessage` also works in a private discussion. Unfinished private edits
are surfaced before publication. `:ReviewStartPending` prepares a private review;
`:ReviewSavePending` prepares private delivery of an inline/suggestion draft,
creating a review or adding to the existing one. Whole-file drafts can be added
to an existing pending review. Preview first, then confirm Save privately; `:w`
remains a local save. Replies and quotes on private feedback stay private.
Use `:ReviewReplyPending` to keep a reply to a published thread private, or
`:ReviewSavePending` to convert an editable reply draft. Existing text and unknown
outcomes are retained. Use `:ReviewStageBatch` to select several local drafts for
private delivery. It can create a private review or add to the existing one.
Space selects items, Enter edits, and `:ReviewSendBatch` confirms the exact set.
Inline comments, suggestions, file feedback and replies save one at a time.
The queue retains each receipt and stops on failure. `:ReviewCheckReceipt` only
checks an uncertain step; continuing the remaining saves needs confirmation.
`:ReviewUnpackBatch` returns only unsaved items when all outcomes are known.
Review-decision drafts stay in the outbox; publication is a separate action.

Composers show source/thread context as non-editable display rows. Use
`:ReviewPreview` to inspect rendered Markdown and `:ReviewClose` to return to the
originating view. Preview never publishes or changes the draft body. Composer
`q` keeps native macro recording. These actions also have buffer-local commands
and `<Plug>(revue-...)` mappings. Set `g:revue_no_default_mappings = 1` to disable
shipped rich-session keys, or customize actions, for example:

```vim
let g:revue_mappings = {'reply': 'gr', 'next-thread': ']r', 'help': '<Leader>?'}
```

These settings affect rich sessions; the original `:Review` keymap is unchanged.

Common comment/reply composers keep a compact target, source excerpt and delivery
summary above the text. Their preview puts the full review context after the
rendered body, while unavailable/stale-source disclosures remain beside it.
Preview cards follow `g:revue_comment_width`. When focusing a pane, minimized
review status bars become quiet; restoring the layout restores their labels.
Normal Vim scrolling remains available for tall threads.

Use `:ReviewFocus` (or `<LocalLeader>z`) to maximize the current code, discussion,
composer, or preview pane. `:ReviewRestoreLayout` restores split sizes, or returns
from a single-window reading tab to its previous view.
Focused discussions can be searched and scrolled through normally, even when a
thread is taller than the terminal. Reply and preview carry that focus forward;
closing them returns to the prior view and sizing. `:ReviewFiles` hides or reopens
the file sidebar. In a focused source pane, `:ReviewClose` restores the layout
first; invoke it again to close the review.

Narrow terminals open discussions, composers and previews in their own reading
tabs (below 120 columns or 32 rows). Each uses the full available area while the
source windows remain in their original tab. Closing follows the same reply →
discussion → code return path. Native tabs have readable buffer labels, and
refreshing a hidden discussion preserves the active tab, text and Insert mode.
User-created splits and tabs survive review cleanup.

`g:revue_reading_layout` defaults to `'auto'`; use `'split'` for the earlier
split-only layout or `'tab'` to use reading tabs at any size. This controls newly
opened views; existing views are not moved on terminal resize.
Set `g:revue_auto_focus = 0` to manage sizing yourself, or adjust
`g:revue_narrow_columns`. `g:revue_comment_width` defaults to a 100-column reading
layout for cards; `0` uses all available width. Their background still spans
the code pane. Source Focus and split mode use native Vim maximization, retaining
other windows at their minimum sizes and preserving diff navigation. It does not
hide individual comments or change the diff format.

Backends can restrict actions and specify whether a review decision needs a
message. Unavailable decisions show a reason; losing access keeps your drafts.
The GitHub adapter checks the current actor and supports approval without an
extra summary. GitHub still authorizes the actual write. An unknown submission
can check its receipt even when new writes are no longer available.

For provider reviews, use `:ReviewBatch` to collect saved drafts into one review. Space checks or
unchecks an item; Enter reopens it for editing. The queue shows the selected
count, review decision, comparison, and full message text. `:ReviewSendBatch`
submits the checked items after confirmation. GitHub batches support inline
comments and one optional review decision; replies and conversation messages
are sent separately. Local batches save all supported feedback atomically.
Unselected drafts stay in the outbox. A rejected batch can be unpacked with
`:ReviewUnpackBatch`; an uncertain batch stays frozen until receipt recovery,
including after restarting Vim. Native GitHub pending reviews use the separate private-save workflow described
above; `:ReviewStageBatch` selects private delivery with per-item outcomes.

Select a suggestion message and use `:ReviewApplySuggestion` to preview applying
it when the backend supports that action. The local backend saves the exact
replacement to the workspace and captures the resulting saved files, without
committing or resolving the thread. Unsaved target buffers and stale source
block application. `:ReviewLatest` opens the result; interrupted writes use the
original receipt. [Application workflow and limits](doc/suggestion-application.md).

Use `:ReviewResolve` or `:ReviewReopen` on a thread, or choose the action from its
message menu. The explicit action sends in place, with waiting and failure status
beside the thread; all replies stay expanded. There is no separate composer or
second confirmation. The local and GitHub backends provide state and permissions.
Unknown state remains explicit. `:ReviewCheckThreadState` checks an uncertain resolution;
a failed lookup keeps the operation frozen, including after restarting Vim.
Activity retains optional operation details and receipt recovery when the thread
is no longer loaded.
GitHub recovery may report that the requested state is observed, which does not
attribute the change to a particular actor. Acceptance remains visible if the
following refresh fails.

`:ReviewActivity` shows durable delivery outcomes, receipts, and refresh errors.
Open a pending operation with Enter; use `:ReviewCopyReceipt [register]` to copy
a receipt. `NOT SAVED` means local persistence needs attention; an interrupted
submission remains recoverable without reposting. History retains 200 outcomes
by default (`g:revue_activity_limit`), independently of pending drafts.

Refresh marks newly observed messages with `[new]` and adds per-file counts.
`:ReviewNextUnread` visits them; `:ReviewMarkRead` acknowledges one message and
`:ReviewMarkThreadRead` acknowledges a selected thread. Reading and refresh do
not clear markers automatically. These are local cues based on stable message
IDs, including your own newly observed messages, rather than GitHub notification
state. The first snapshot establishes the baseline; refresh remains manual.

Large local reviews initially load 50 complete discussions or conversation
messages. `:ReviewLoadMoreFeedback` loads the next page without changing the
selected result or unsaved text; `:ReviewCancelFeedback` ignores an outstanding
read. Loaded discussions include all their replies. Paging does not mark older
feedback as newly arrived. Changed local feedback invalidates the cursor and
offers refresh. Capable backends refresh one feedback page at a time. Signed-in
GitHub reviews load up to 20 complete threads and 50 general comments per page,
alongside published review summaries. Private feedback now uses the same
complete-thread pages, with explicit per-review comment coverage. Signed-out
access and unavailable or incomplete GraphQL paging use the complete reader. GitHub cursors verify the
actor, source and PR update marker; changes require refresh. Timeline paging is
a separate read. File thread counts and filters describe loaded feedback.

`:ReviewRefresh` keeps the current inventory until fresh pages cover its previously
loaded message IDs, or the fresh inventory is exhausted. When more is needed,
`:ReviewContinueRefresh` reads one page; `:ReviewCancelRefresh` retains the current
view. The status bar and action guide expose these actions while reading or
composing. Errors retain the draft and selection; a changed source is offered as
Latest. Cancelled/late callbacks cannot replace a newer read. After restart,
an interrupted refresh starts again. Identical snapshots leave rich discussion
and draft buffers intact while updating refresh indicators. The GitHub adapter
overlaps independent file/review, merge-base and actor reads; successful paging
uses its final source/actor/private-state guard without a duplicate REST check.
This bounds outer feedback pages, not the
complete file/review lists, nested replies or local SQLite object read. Private
review headers are checked across pages; unavailable GitHub paging retains the
complete-reader fallback.

`:ReviewPending` shows loaded private comments and their known total. Individual
comments retain their private identity and permissions inside code threads.
`:ReviewVerifyPending` loads and verifies the complete selected review before
publication, discard or summary editing; it sends nothing. Those actions remain
separate and unavailable until verification succeeds. Reading all thread pages
alone does not establish a complete publication version. Cancellation, refresh,
actor changes and restart retain local drafts without accepting stale results.

`:ReviewDiscussions [text]` searches the loaded review's threads, replies,
general conversation, and local drafts. Enter opens the exact message or its
owning draft/batch; closing returns to the selected result. Use
`:ReviewDiscussionFilter state unresolved`, `author morgan`, `anchor outdated`,
or `kind draft` to narrow results, and `clear` to reset. Arguments are literal,
case-insensitive substrings for text/path/author; native `/` searches the visible
buffer text. The explicit query searches full message bodies, beyond excerpts.
The index names its search scope and displays loaded/known-total counts with
complete, partial, loading, failed, unsupported or unknown coverage. Missing
coverage metadata never means an empty complete review. Private-review and
resolution coverage are separate from readable comments. `:ReviewRefresh` retries
the review; failed reads preserve loaded feedback, selected results and drafts.

`:ReviewFileFilter path src/` narrows the file list; status, threads and viewed
filters are also available. Next/previous file follows the visible list.
Filtering leaves the current code in place. Opening feedback in a hidden file
reveals it with a label; setting another file filter clears those exceptions.

`:ReviewViewed` and `:ReviewUnviewed` acknowledge the selected tree file or current
source file. Progress is local and survives restarting Vim. Both sides of the
compared content determine whether a mark still applies: changed files become
unviewed, while unchanged files retain their marks after verification. A pending
read shows `[checking]`; unavailable content shows `[unverified]`.
`:ReviewVerifyViewed` retries verification. Closing before a pending mark finishes
cancels that intent. Viewed neither hides comments nor moves to another file,
and does not sync GitHub's Viewed state or imply approval/resolution.

When refresh finds newer code, the current comparison stays in place.
`:ReviewComparisons` lists saved references and loads backend history when
supported; Enter opens a comparison. `:ReviewLatest` opens the latest and `:ReviewPreviousComparison` returns.
Each comparison keeps its own source cache and file positions. Closing a composer
or discussion returns to its original file, side, comparison, and message.
Drafts keep their anchors; old inline/review drafts cannot be sent against a
known newer comparison. `:ReviewResumeComparison` retrieves the last saved
comparison after restarting Vim; `:ReviewDraftComparison` inspects an open draft's
original comparison. `:ReviewLoadHistory` reloads the inventory, and
`:ReviewCopyComparison [register]` copies its immutable reference.
GitHub supplies the PR comparison and reachable first-parent commit comparisons;
a local review supplies its retained frozen captures. Saved references and positions stay
local; conversation content is fetched from the backend.

To compare versions, select a row and use `:ReviewRangeStart [base|head]`, then
select another row and use `:ReviewRangeEnd [base|head]` (both default to head).
Inspect the endpoints and backend semantics above the list, then
`:ReviewOpenRange`. `:ReviewClearRange` clears the selection. The action guide also
offers these choices. Endpoints and opened ranges survive restart; existing
drafts retain their original targets. New source feedback requires Latest;
replies still target the existing discussion.

Local ranges compare retained contents against their shared captured baseline,
including reversed ranges, without rereading Git or the workspace. Renames
appear as removal/addition. GitHub ranges currently require the start to be the
comparison's merge base (ancestor); unsupported or capped ranges explain the
limitation. Non-ancestor GitHub ranges and complete abandoned-history discovery
remain pending. Reading history never moves feedback.

To move an unsent line, suggestion or whole-file draft, open its composer and
use `:ReviewReanchorDraft`. Choose a file or source range in Latest, then use
`:[range]ReviewReanchorHere`. The read-only preview shows old and new locations,
available code, and the unchanged draft text. `:ReviewAcceptReanchor` saves the
move locally; `:ReviewCancelReanchor` returns to the original draft. Closing the
preview lets you choose another location. Nothing is sent by moving a draft.
The accepted draft retains its previous anchor and gets a fresh submission ID.
Replies, published comments, private-review operations and uncertain submissions
keep their targets. An unavailable old source is labeled, never reconstructed.

From a discussion, `:ReviewThreadComparison` opens its original code. Local
reviews retain the original comparison. GitHub verifies the original commit,
path and excerpt, then shows that file against the commit's first parent.
The view labels this as original code context: its base is **not a verified
original PR base**. A base-side excerpt must match the parent; otherwise the
discussion retains its original diff and explains why source is unavailable.
`:ReviewReturnContext` returns to the exact message and position before the jump,
even if its managed panel was closed. After restarting Vim, saved original
context can reopen with `:ReviewResumeComparison`; the earlier return position
is session-only, so use `:ReviewLatest` for current code. Reading history never
moves a comment or draft to newer lines.

`:ReviewReadiness` opens a read-only view of backend checks and review
requirements. It shows the observed head, required check classification,
loading/failure states and source links. Reload or page checks without losing
your draft; stale observations remain labeled. The GitHub companion supports
this view; local reviews explain that CI/policy data is unavailable.
[Readiness workflow and limits](doc/readiness.md).

`:ReviewTimeline` opens typed backend history with authors, timestamps and event
links. For an unloaded discussion, `:ReviewLoadEventDiscussion` fetches that
complete thread directly when supported, then opens the exact message. Otherwise
it loads one feedback page and opens the message if found. It preserves the event on failure,
supports `:ReviewCancelFeedback`, and leaves focus alone if you move elsewhere.
Repeat explicitly for another page; `:ReviewLoadMoreFeedback` remains available
when a targeted read cannot complete. Unavailable targets retain the browser route.
Targeted loading does not advance paging or claim the entire review is loaded.
`:ReviewOlderEvents` loads earlier history pages; `:ReviewReloadTimeline` checks for
new activity. `:ReviewCancelTimeline` stops accepting the current read while
retaining existing entries. Enter opens an event's discussion when its exact
message is loaded; closing returns to the same event. `gx` opens the event link
and `gy` copies it. GitHub history requires sign-in; unavailable detail remains
labeled. Local history shows retained captures and current messages, not an edit
or resolution log. History is separate from delivery receipts in Activity and
is not copied into the outbox. `:ReviewEventComparison` opens a verified retained
source comparison, and `:ReviewReturnContext` returns to the same history event.
Local captures/reviews supply these references, including older reviews recovered
from saved receipts. GitHub's reviewed-head ID alone cannot establish its original
PR base; those events explain the limitation and retain their browser link.

For local reviews, `:ReviewCapture` prepares another capture of saved workspace
files against the same fixed base. Inspect its settings and use `:ReviewSend`
to save it. `:ReviewCapture all` (or `!`) includes untracked files;
`:ReviewCapture tracked` excludes them. With no argument, it retains the last
capture's setting. `:ReviewLatest` opens the result when you are ready.
Discussion, earlier source, and old drafts survive. No code is staged or committed,
and no thread is resolved automatically. From a discussion, `:ReviewThreadComparison`
opens its original file/range when the backend provides that reference.

Cards separate replies and show the review author plus backend-provided role,
bot, update/edit, and publication cues. Generic timestamp changes say Updated;
Edited requires an explicit backend flag. Local accepted comments say Saved
locally; a known native pending comment says Pending review.

Nested blockquotes retain inset fenced code. Lists preserve nesting, numbering,
and task checkboxes; headings have a distinct highlight. Inline code and link
syntax remain readable as Markdown, and unsupported markup remains visible.
Very narrow cards retain quote text when there is insufficient room for nested
insets. The focused discussion keeps original Markdown for normal Vim selection,
search, copy and quote; `RevueMessageFocus` highlights the selected message's
header independently of card borders.

Cards also render `suggestion` blocks. Suggestions show a read-only red/green
comparison with the anchored snapshot; they do not apply changes. Quoted
suggestions render as quoted code, without comparing against the current anchor.
Use `:ReviewSuggest` on a head-side diff line, or `:'<,'>ReviewSuggest` on a
selected range, to seed an editable proposal from the immutable source. Keep
explanation outside the fenced replacement. An empty replacement proposes a
deletion. Repeating the command at the same anchor reopens the saved draft.
There is no default key; `<Plug>(revue-suggest)` supports normal/visual mappings.
The backend must explicitly support suggestions. Send or add the draft to a
review batch using the existing workflow; neither action applies the change.
An old draft preview uses its original cached source, including after switching
comparisons; unavailable source is explicit and never replaced with newer code. The thread
panel retains the original Markdown. Try the local specimen with
`:source test/preview-comments.vim` from this repository (no publishing).

Use `:ReviewFileComment` from the file list or a source pane for feedback about
the whole file. It needs no line selection or source-content fetch, so it works
for binary, deleted, and unavailable files when the backend supports it.
`:ReviewFileThreads` opens that file's discussions, with file comments first;
reply, quote, resolve, search, and return use the usual discussion workflow.
File cards appear above source, with an explicit File discussion label. Neither
command has a default key. Repeating FileComment reopens the existing draft.
Local review batches accept file comments; the current GitHub adapter sends
them individually. Unsupported backends explain the conversation alternative.

Local reviews also accept line comments and suggestions outside diff hunks,
anywhere in a changed file's captured text. Use the same Comment/Suggest range
commands. The composer shows the original source context; no code is changed.
Other backends declare their anchor scope. GitHub currently keeps creation within
returned hunks because broader API support is unverified, while received comments
outside hunks still render and accept replies. Thread navigation opens native
code folds hiding the selected anchor. Unsupported ranges retain existing drafts
and explain the whole-file/browser alternatives.

Customize `RevueCardBorder`, `RevueCardHeader`, `RevueCardHeading`, `RevueCardBody`,
and `RevueCardAction` to style the cards. Preview cards render inline code,
emphasis, strike-through and labeled links with `RevueInlineCode`,
`RevueInlineStrong`, `RevueInlineEmphasis`, `RevueInlineStrongEmphasis`,
`RevueInlineStrike` and `RevueInlineLink`. Discussion buffers retain raw Markdown
with styled spans for native copy/search; preview cards omit formatting markers.
Source virtual rows retain markers because Vim supplies one highlight per virtual
row. They use the same readable link labels and keep the established contrast.
Quotes and nested code use `RevueCardQuote`, `RevueCardInset`, `RevueCardCode`,
`RevueCardAdd`, and `RevueCardDelete`; `RevueCardMeta` styles secondary controls.
`RevueCardGutter` marks their line-number gutter without adding a sign column;
set `g:revue_thread_separators = 0` to disable this gutter emphasis.

The [GitHub review UX reference](doc/github-review-ux-spec.md) documents review
surfaces, interaction states, screenshots, and priorities for comparing our UI.
The [current UX gap audit](doc/review-ux-gap-audit.md) compares the working
implementation by user journey and prioritizes the remaining interactions.
The [detailed backlog](doc/interaction-backlog.md) retains stable UX story IDs,
acceptance criteria and implementation history.

## Integrations and VCS capture

Providers open the shared interface through `revue#review#OpenReview()` or the
[backend contract](doc/provider-api.md). The workspace backend captures Git and
jj into the same retained-source and conversation store. jj reads immutable
commit IDs and machine-readable rename/copy paths; source buffers are read-only.

The former callback/clipboard quick-review implementation has been removed.
Use `:ReviewBatch` and `:ReviewExportMarkdown` to copy feedback to an agent.

## Testing

`test/run.sh` runs every `Test()` function under `autoload/`.
`python3 test/regressions.py` exercises hostile filenames and active visual
selections in temporary Git repositories. The companion's integration suite
tests the complete remote-review UI and draft recovery across Vim processes.

## Origin

Originally extracted from vim-ai-code's Cutout review mode. The current
interface uses persistent review sessions and explicit feedback export.

## License

Revue is **source-available** under the Apache License 2.0 with the
Commons Clause 1.0 condition. It is not OSI open source or plain Apache-2.0.
You can use it for personal projects and at work, and modify it. The combined
license restricts selling products or services whose value derives entirely or
substantially from Revue, including hosting and certain consulting/support.
See [LICENSE](LICENSE) for the controlling terms and
[licensing notes](doc/licensing.md) for examples and earlier-version scope.

## Development evidence

The [parity audit](doc/parity-validation.md) records the tested behavior and
remaining human/service validation. References labeled `local evidence` point
to generated files retained in the development workspace, not included in this
repository. Source, test fixtures, the runnable [UX trial](doc/ux-trial.md), and
public GitHub research screenshots are included; trial sessions and raw logs
are excluded.
