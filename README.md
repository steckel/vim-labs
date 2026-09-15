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
to the directories below. Vim commands (`:Revue*`, `:Reviews`), configuration,
and persisted identities retain their existing names, preserving draft and
review recovery. Replace the old installation entries instead of loading both
copies of a plugin.

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

In a Git checkout, `:RevueLocal HEAD` captures saved changes into a local
review. Use `c` to comment, `t` to read threads, and `r` to reply. Drafts and
accepted local comments persist across Vim restarts.

With the GitHub integration installed and authentication configured, `:Reviews
owner/repo` opens the pull-request browser. GitHub publication uses explicit
review actions and confirmation; local drafts are distinct from posted comments.

For a fixture-only walkthrough, run:

```sh
python3 plugins/vim-code-review/tools/ux_trial.py
```

This creates an isolated trial and opens a separate Vim instance. It does not
publish comments. The [trial guide](plugins/vim-code-review/doc/ux-trial.md) explains
the exercise and observation record.

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
