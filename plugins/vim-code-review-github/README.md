# Vim Code Review · GitHub

The GitHub counterparty integration for `vim-code-review`, formerly packaged
as `vim-reviewhub` (ReviewHub). Existing `:Reviews` and `:ReviewOpen` commands
and configuration remain available.

A tree-style GitHub pull-request browser for Vim 9.1+. Expand a PR, read its
conversation, and open code in [vim-code-review](../vim-code-review) to read and respond
to inline discussions. Both panes show the PR's exact revisions; opening a
review does not switch your branch or edit your checkout.

## Install

Install the `plugins/vim-code-review-github` and `plugins/vim-code-review`
directories from Vim Labs using your Vim package manager, or symlink both
under `~/.vim/pack/plugins/start/`. See the [collection setup](../../README.md#install-selected-plugins).
Requires Python 3.9+
and Vim with `+job`, `+channel`, `+textprop`, and `+diff`.

Install [GitHub CLI](https://cli.github.com/) and authenticate:

```sh
gh auth login --hostname github.com --web
```

Public browsing also works without authentication, subject to GitHub's lower
anonymous API limits. Posting and private repository access require login.
Credentials are read from the CLI's credential store (or `GH_TOKEN` /
`GITHUB_TOKEN` for github.com) and are never stored in Vim draft files.

## Review a repository

```sh
git clone https://github.com/tpope/vim-fugitive.git
cd vim-fugitive
vim
```

Run `:Reviews`. The origin remote identifies the repository. You can also use
`:Reviews owner/repo`, `:Reviews https://github.example/owner/repo`, or
`:ReviewOpen https://github.com/owner/repo/pull/123` from any directory.

Signed-in reviews initially load up to 20 complete discussions and 50 general
comments, plus all review summaries. `:ReviewLoadMoreFeedback` loads the next
page; `:ReviewCancelFeedback` keeps existing feedback and ignores the pending
read. Every loaded thread includes all readable replies. Counts and filters
describe loaded feedback, with separate totals/completeness. Private pending
reviews and unavailable GraphQL paging retain the full reader. `R` in Revue
also performs a full feedback refresh. A changed actor, source, update marker
or reported inventory count requires refresh before continuing. These reads
do not publish or resolve anything.

| Where | Key | Action |
| --- | --- | --- |
| PR tree | `j` / `k` | Navigate |
| PR tree | Enter / `o` / `l` | Expand a PR, open a conversation, or open a file |
| PR tree | `h` | Collapse the selected PR |
| PR tree | `/` | Search, e.g. `is:open review-requested:@me`, `is:closed`, `author:@me` |
| PR tree | Enter on Load more | Load the next page |
| PR tree | `R` | Refresh PR list |
| Code | `]f` / `[f` | Next / previous file |
| Code | `t` | Open file's code threads |
| Code | `]t` / `[t` | Next / previous code thread |
| Code | `c` | Comment on the current line |
| Code | `V`, select lines, `c` | Comment on a range on either diff side |
| Thread panel | `r` | Reply to the thread under the cursor |
| Thread panel | Enter | Jump to the thread's source line |
| Revue | `C` | Open the PR conversation |
| Conversation panel | `c` | Add a conversation message |
| Revue | `s` | Compose a comment, approval, or request-changes review |
| Composer | `:w` | Save draft locally |
| Composer | Ctrl-S / `:ReviewSend` | Confirm destination and publish the draft |
| Composer | `:ReviewDiscard` | Discard a local draft |
| Revue | `R` | Refresh discussions |
| Read-only views | `q` | Close panel or review; drafts remain saved |
| Composer | `:ReviewClose` | Return while retaining text; native `q` is unchanged |

Write messages in the normal Vim editor. Draft text is saved as you edit and
when leaving its buffer. Reopen a draft from Revue's file sidebar. A failed
submission retains your text. An unknown outcome remains locked; sending it
again looks for a server receipt without reposting. Small invisible receipt
markers are included in posted messages to support this recovery.

If the PR changes, refresh reports that a new revision is available. Use
`:ReviewLatest` to inspect it, or `:ReviewComparisons` to choose a retained version. Drafts retain the revision they were written against;
new inline comments cannot be posted against a stale comparison.

## Configuration

```vim
let g:reviewhub_python = 'python3'
let g:revue_draft_dir = expand('~/.vim/revue-drafts')
```

Drafts are local JSON files with restrictive permissions, stored outside the
checkout. Each draft is keyed by provider host/repository/PR and pins its code
revision. The current implementation uses the active GitHub CLI account for
the selected hostname; finish or discard pending drafts before switching
accounts. A conflict with another Vim's saved draft stops submission rather
than overwriting that draft.

GitHub is the first provider. The bridge supplies normalized snapshots and a
session callback to Revue; an internal CL provider can implement that boundary
without changing its renderer. Resolution controls, patchset migration, binary
previews, and merge/land actions are not implemented. Binary/non-UTF-8 files,
missing content, and files above the viewing limit are shown explicitly.

## Tests

```sh
python3 -m unittest discover -s test -p 'test_*.py' -v
python3 test/run_integration.py
```

The second command expects the sibling `../vim-code-review` checkout. It starts
real Vim in a PTY against a deterministic provider fixture and tests the
tree, discussion panels, mappings, draft recovery and send outcomes. HTTP
tests use a loopback server and never post to GitHub.

## License

Source-available under Apache License 2.0 **with the Commons Clause 1.0**.
Personal and workplace use are permitted; selling products or services whose
value derives entirely or substantially from this software is restricted.
This is not plain Apache-2.0 or OSI open source. See [LICENSE](LICENSE) and
the [Vim Labs licensing notes](../../plugins/vim-code-review/doc/licensing.md).
