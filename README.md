# Vim Labs

Experimental Vim plugins and MCP tools by Curtis Steckel. This repository is
a home for alpha and beta work: interfaces can change, and each component has
its own requirements and validation limits.

The code-review family uses **`vim-code-review`** as its base name, with
integrations organized around who you review with: GitHub, Codex, or Claude.
Git comparisons and local conversation storage are shared implementation
details. See the [architecture](plugins/vim-code-review/doc/plugin-architecture.md).

## Components

| Component | What it does | Status |
| --- | --- | --- |
| [Code Review](plugins/vim-code-review) | Shared diff review, inline discussion cards, composers, and supporting session machinery | Alpha |
| [Code Review · GitHub](plugins/vim-code-review-github) | GitHub PR discovery, conversations, and review actions | Alpha |
| [Vim9 MCP](plugins/vim9-mcp) | MCP access to live Vim sessions, buffers, selections, and editing tools | Alpha |

Planned integrations are **`vim-code-review-codex`** and
**`vim-code-review-claude`**. They will combine shared change capture and durable
review conversations with their agent runtime. These packages are not yet
implemented. There are no separate Git, local-storage, or local-agent packages
to install.

Code Review and its GitHub integration share one interface. The bundled local
review commands remain available while agent integrations are developed.
Vim9 MCP is independently installable and includes both a Vim plugin and its
Node.js MCP server.

Code Review also has a separate, assignment-scoped
[review MCP server](plugins/vim-code-review/doc/participant-mcp.md) for agents to read
selected discussions and reply inline. It lives with the shared Python local
backend. The live-editor MCP and the review-assignment MCP serve different
purposes; neither requires the other.

The package directories were renamed from `vim-revue` and `vim-reviewhub`.
Existing installations should update runtime-path entries or package symlinks
to the directories below. Vim commands now use `:Review*` (with `:Reviews` for
the GitHub inbox); the former command names are removed. Update command mappings
and restart Vim after upgrading. Configuration and persisted identities retain
their existing names, preserving draft and review recovery. Replace the old
installation entries instead of loading both copies of a plugin.

## Install selected plugins

Clone this repository once:

```sh
git clone https://github.com/steckel/vim-labs.git
cd vim-labs
```

To install all three components as native Vim packages:

```sh
python3 scripts/install.py
```

This creates symlinks in `~/.vim/pack/vim-labs/start`, installs the MCP's locked
Node.js dependencies with `npm ci`, and generates Vim help tags. It requires
Vim, Python 3, and Node.js 22+ with npm. Restart Vim afterward. It does not edit
your vimrc or MCP client configuration.

For local development, run the same command from your development checkout;
the symlinks use that checkout directly. To switch explicitly:

```sh
python3 scripts/install.py --source /path/to/your/vim-labs
```

Use `--vim-dir /path/to/vim-directory` for another Vim installation, or
`--skip-deps` to keep dependencies you have already installed. Conflicting
real plugin directories are left untouched and stop installation. Existing
Vim Labs symlinks and legacy Revue/ReviewHub package symlinks are backed up
under `~/.vim/vim-labs-backups` before switching, with a manifest recording
their original paths and targets. The source checkouts are never moved.

For a manual installation of selected components instead:

The repository root is a collection, not a Vim plugin. Add the component
directories you want to Vim's runtime path, or symlink them into a native
package directory. For example, from the cloned repository:

```sh
mkdir -p "$HOME/.vim/pack/vim-labs/start"
ln -s "$PWD/plugins/vim-code-review" "$HOME/.vim/pack/vim-labs/start/vim-code-review"
ln -s "$PWD/plugins/vim-code-review-github" "$HOME/.vim/pack/vim-labs/start/vim-code-review-github"
```

Restart Vim and run `:helptags ALL`. Both review components require Vim 9.1+;
the local review backend needs Python 3.9+ with SQLite. The GitHub integration also needs
Python 3.9+ and uses the GitHub CLI for authenticated access. See the
[component setup](plugins/vim-code-review-github/README.md#install).

To install the live-editor MCP as well, with Node.js 22+ available:

```sh
npm ci --prefix plugins/vim9-mcp
ln -s "$PWD/plugins/vim9-mcp" "$HOME/.vim/pack/vim-labs/start/vim9-mcp"
```

Configure your MCP client to launch `node` with the absolute path to
`plugins/vim9-mcp/bin/vim9-mcp.js`. The [MCP setup guide](plugins/vim9-mcp/README.md)
includes a configuration example, Vim requirements, and the editing contract.

## Try a review

In a Git checkout, `:ReviewLocal HEAD` captures saved changes into a local
review. Use `c` to comment, `t` to read threads, and `r` to reply. New feedback
autosaves as Pending cards; `:ReviewClose` returns to the code. `:ReviewBatch`
collects feedback: Space selects items, `a` selects all loaded, and `m` exports
one Markdown buffer for your agent. Pending and saved feedback survive restarts.

With the GitHub integration installed and authentication configured, `:Reviews
owner/repo` opens the pull-request browser. GitHub publication uses explicit
review actions and confirmation; local drafts are distinct from posted comments.

Diffs also mark relocated code with **Moved from / Moved to** labels and
**<M / M>** gutter markers, including moves between files in the review. This
works in quick jj reviews (`:Review @-`) as well as Git and rich review views;
[matching details and settings](plugins/vim-code-review/README.md#moved-code).

For a fixture-only walkthrough, run:

```sh
python3 plugins/vim-code-review/tools/ux_trial.py
```

This creates an isolated trial and opens a separate Vim instance. It does not
publish comments. The [trial guide](plugins/vim-code-review/doc/ux-trial.md) explains
the exercise and observation record.

## Command map

The tree below groups commands by task. Opening commands are global; most
review actions exist only in the relevant review pane, composer, or picker.
Available actions also depend on the backend and its permissions. Use
`:ReviewHelp` (`g?`) for the current pane's bindings, or `:ReviewReviewActions`
for its action chooser. Keys shown below are defaults and can be remapped.

For the local feedback → agent workflow: **`:ReviewLocal HEAD` → `c` → write
feedback → `:ReviewClose` → `:ReviewBatch` → Space or `a` → `m` → `ggVG"+y`**.
The final step copies the Markdown buffer to your system clipboard; it does
not start an agent or post to GitHub.

<details>
<summary>Full command tree: local reviews, GitHub, shared review tools, and live-editor MCP</summary>

```text
Vim Labs
├── Start or resume a review
│   ├── :ReviewLocal HEAD                 Saved working tree against HEAD
│   ├── :ReviewLocal! HEAD                Include untracked, non-ignored files
│   ├── :ReviewLocalReviews               List saved local reviews; Enter resumes
│   ├── :ReviewLocalResume <id>           Resume one exact local review
│   ├── :Reviews [owner/repo]             Open the GitHub PR inbox
│   ├── :ReviewOpen <PR URL>              Open a GitHub PR directly
│   └── :Review [revision]                Quick diff / callback / clipboard workflow
│                                         Separate from persistent :ReviewLocal
├── Write feedback
│   ├── :ReviewComment                    c on a line; V then c for a range
│   ├── :ReviewFileComment                Comment on the whole file
│   ├── :ReviewSuggest                    Compose a suggested replacement; accepts a range
│   ├── :ReviewReply                      r in a discussion or at a thread's source
│   ├── :ReviewNewConversation            Write review-wide feedback
│   ├── :ReviewReview                     s; compose a review summary / decision
│   └── Composer
│       ├── :w                            Save locally; local feedback also autosaves
│       ├── :ReviewPreview                Preview the feedback and its context
│       ├── :ReviewSend                   Ctrl-S; local feedback: save Pending and return
│       │                                   Provider delivery / other operations: confirm
│       ├── :ReviewClose                  Save and return; pending feedback stays available
│       └── :ReviewDiscard                Discard the local draft after confirmation
├── Local pending cards → Markdown for an agent
│   ├── :ReviewEditFeedback               Edit a pending card at the source line
│   ├── :ReviewBatch / :ReviewExport      Collect pending and previously saved feedback
│   └── Feedback picker
│       ├── :ReviewToggleFeedback         Space; select / deselect this item
│       ├── :ReviewSelectFeedback         a; select all loaded feedback
│       ├── :ReviewClearFeedback          u; clear the selection
│       ├── :ReviewEditFeedback           Enter; edit pending or read saved feedback
│       └── :ReviewExportMarkdown         m; selection → one editable Markdown buffer
│                                           ggVG"+y copies all; :w <file> saves a copy
│                                           Export preserves feedback and Pending status
├── Read and navigate shared review panes
│   ├── :ReviewOpenFile                   Enter in the file list
│   ├── :ReviewNextFile / :ReviewPreviousFile           ]f / [f
│   ├── :ReviewThread / :ReviewThreads    Focus one discussion / list file discussions
│   ├── :ReviewFileThreads                List whole-file and inline discussions
│   ├── :ReviewNextThread / :ReviewPreviousThread       ]t / [t
│   ├── :ReviewNextMessage / :ReviewPreviousMessage     ]m / [m
│   ├── :ReviewJump                       Enter in a discussion; return to its source
│   ├── :ReviewConversation               C; read the review-wide conversation
│   ├── :ReviewDiscussions [text]         Search loaded comments and drafts
│   ├── :ReviewOpenDiscussion             Enter on a search result
│   ├── :ReviewFileFilter <filter>        Filter the file list
│   ├── :ReviewDiscussionFilter <filter>  Filter discussion results
│   └── Layout and help
│       ├── :ReviewFocus / :ReviewRestoreLayout        Focus pane / restore layout
│       ├── :ReviewFiles                  Toggle the file sidebar
│       ├── :ReviewHelp                   g?; current commands and mappings
│       ├── :ReviewReviewActions          Contextual action chooser
│       └── :ReviewClose                  Return from a pane or close the review
├── Work with a saved message
│   ├── :ReviewActions                    a; message action menu
│   ├── :ReviewCopyMessage [register]     Copy the exact message body
│   ├── :ReviewCopyLink [register]        Copy its permalink, when available
│   ├── :ReviewOpenLink                   gx; open its web permalink
│   ├── :ReviewBodyLinks / :ReviewBodyURLs             Inspect links in its body
│   ├── :ReviewQuote / :ReviewQuoteAttributed          Quote into a reply; accept ranges
│   ├── :ReviewEditMessage / :ReviewEditBase           Edit / accept refreshed edit base
│   ├── :ReviewDeleteMessage              Preview deletion of a saved message
│   ├── :ReviewApplySuggestion            Preview applying a suggestion to the workspace
│   ├── :ReviewResolve / :ReviewReopen    Change thread resolution
│   ├── :ReviewCheckThreadState           Check an uncertain resolution outcome
│   ├── :ReviewReactions / :ReviewReact   Inspect reactions / execute selected action
│   └── Message edit history
│       ├── :ReviewMessageHistory         Inspect edits to this message
│       ├── :ReviewReloadMessageHistory / :ReviewOlderMessageEdits
│       ├── :ReviewCancelMessageHistory   Cancel the history read
│       └── :ReviewHistoryMessageLink     Open the original message's link
├── GitHub / provider delivery
│   ├── Public review batch
│   │   ├── :ReviewBatch                  Select drafts for submission
│   │   ├── :ReviewToggleDraft            Space; select / deselect a draft
│   │   ├── :ReviewEditDraft              Enter; edit the selected draft
│   │   ├── :ReviewSendBatch              S; confirm delivery of the selected batch
│   │   └── :ReviewUnpackBatch            Restore editable drafts when outcome is known
│   └── Private pending review
│       ├── :ReviewStartPending           Prepare a new private review
│       ├── :ReviewSavePending            Prepare private delivery of this draft
│       ├── :ReviewReplyPending           Compose a private reply
│       ├── :ReviewStageBatch             Select multiple drafts to save privately
│       ├── :ReviewPending                Inspect the backend's pending review
│       ├── :ReviewOpenPending            Open its selected comment
│       ├── :ReviewEditPending / :ReviewPendingBase    Edit / accept refreshed contents
│       ├── :ReviewVerifyPending / :ReviewCancelVerifyPending
│       ├── :ReviewDeletePendingComment   Preview removing one pending comment
│       ├── :ReviewPublishPending         Prepare publication of the pending review
│       └── :ReviewDiscardPending         Preview deleting the entire private review
├── Capture and compare versions
│   ├── :ReviewCapture [tracked|all]      Prepare a new capture in the same local review
│   │                                     :ReviewSend confirms; :ReviewLatest opens it
│   ├── :ReviewComparisons / :ReviewLoadHistory        Inspect / reload version inventory
│   ├── :ReviewOpenComparison             Open selected version
│   ├── :ReviewLatest / :ReviewPreviousComparison      Latest / previously loaded version
│   ├── :ReviewResumeComparison           Restore saved comparison context after restart
│   ├── :ReviewCopyComparison [register]  Copy the immutable comparison reference
│   ├── :ReviewDraftComparison            Inspect a draft's original comparison
│   ├── :ReviewThreadComparison           Inspect a discussion's original source
│   ├── :ReviewReturnContext              Return from a context jump
│   ├── Compare arbitrary endpoints
│   │   ├── :ReviewRangeStart [base|head] / :ReviewRangeEnd [base|head]
│   │   └── :ReviewOpenRange / :ReviewClearRange
│   └── Move a draft's anchor explicitly
│       ├── :ReviewReanchorDraft          Begin moving a draft to another source range
│       ├── :ReviewReanchorHere           Choose the new location; accepts a range
│       └── :ReviewAcceptReanchor / :ReviewCancelReanchor
├── Refresh, progress, and delivery recovery
│   ├── :ReviewRefresh                    R; refresh this review (or GitHub inbox globally)
│   ├── :ReviewContinueRefresh / :ReviewCancelRefresh
│   ├── :ReviewLoadMoreFeedback / :ReviewCancelFeedback
│   ├── :ReviewViewed / :ReviewUnviewed / :ReviewVerifyViewed
│   │                                     Local acknowledgement of exact file contents
│   ├── :ReviewServiceProgress            Inspect personal Viewed state on the service
│   ├── :ReviewMarkServiceViewed / :ReviewUnmarkServiceViewed / :ReviewCheckServiceViewed
│   ├── :ReviewNextUnread / :ReviewMarkRead / :ReviewMarkThreadRead
│   ├── :ReviewActivity                   Inspect saved delivery outcomes
│   ├── :ReviewOpenOperation              Open selected pending operation
│   ├── :ReviewCopyReceipt [register]     Copy a delivery receipt
│   └── :ReviewCheckReceipt               Check an uncertain delivery without reposting
├── Review history and readiness
│   ├── :ReviewTimeline                  Read backend history
│   ├── :ReviewOlderEvents / :ReviewReloadTimeline / :ReviewCancelTimeline
│   ├── :ReviewEventDiscussion / :ReviewLoadEventDiscussion
│   ├── :ReviewEventComparison            Open an event's retained comparison
│   ├── :ReviewEventLink / :ReviewCopyEventLink
│   ├── :ReviewReadiness                  Inspect available checks and review requirements
│   ├── :ReviewReloadReadiness / :ReviewMoreChecks / :ReviewCancelReadiness
│   └── :ReviewReadinessLink / :ReviewCopyReadinessLink
├── Local participant assignments (requires participant configuration)
│   ├── :ReviewAssign                    Select saved feedback for a participant
│   ├── :ReviewToggleAssignment / :ReviewPrepareAssignment
│   ├── :ReviewAssignments               List assignments and outcomes
│   ├── :ReviewReloadAssignments / :ReviewCancelAssignmentsRead
│   ├── :ReviewOpenAssignment / :ReviewAssignmentDetails
│   ├── :ReviewAssignmentDiscussion / :ReviewAssignmentReply
│   ├── :ReviewAssignmentComparison / :ReviewAssignmentResult
│   ├── :ReviewRunParticipant            Preview starting / resuming a configured participant
│   ├── :ReviewAbandonRun                Preview releasing an unstarted preparation
│   └── :ReviewCancelAssignment          Preview revoking assignment access
└── Live-editor MCP (separate plugin)
    ├── :VimMCPConnect / :VimMCPDisconnect
    ├── :VimMCPStatus / :VimMCPHistory
    ├── :VimMCPReview <change_id>         Review an MCP change
    └── :VimMCPShareSelection             Share a selection; accepts a range
```

</details>

For argument details and backend-specific behavior, see the
[Code Review guide](plugins/vim-code-review/README.md),
[Vim help](plugins/vim-code-review/doc/revue.txt),
[GitHub guide](plugins/vim-code-review-github/README.md), and
[MCP guide](plugins/vim9-mcp/README.md).

## Design and development

- [Review architecture and backend boundary](plugins/vim-code-review/doc/plugin-architecture.md)
- [GitHub UX reference](plugins/vim-code-review/doc/github-review-ux-spec.md)
- [Current UX comparison and backlog](plugins/vim-code-review/doc/review-ux-gap-audit.md)
- [Parity validation and remaining limits](plugins/vim-code-review/doc/parity-validation.md)
- [Future agent reviews and GitHub handoff](plugins/vim-code-review/doc/review-handoffs.md)
- [Live-editor MCP feature catalog](plugins/vim9-mcp/docs/feature-catalog.md)

The test suites use temporary repositories and fixture transports. From the
repository root, after installing the MCP dependencies:

```sh
./scripts/test.sh
```

Use `./scripts/test.sh install`, `review`, `github`, or `mcp` to run one component's
suite. Python 3, Vim, Git, and Node.js are required for the combined run.

The GitHub adapter's automated tests do not prove every real account/permission
combination. Human usability trials, some live service writes, and actual
model-backed participant runs remain validation work. Generated logs, local
sessions, and audit evidence under `output/` are excluded from the repository.

## License

**Source-available: Apache License 2.0 with Commons Clause 1.0.** Personal and
workplace use are permitted. The combined license restricts selling products
or services whose value derives entirely or substantially from this software,
including hosting and certain consulting/support services. This is not plain
Apache-2.0 or OSI open source.

See [LICENSE](LICENSE), [NOTICE](NOTICE), and the
[licensing notes](plugins/vim-code-review/doc/licensing.md), including the earlier MIT
versions of Revue. Third-party research material retains its owners' rights.
