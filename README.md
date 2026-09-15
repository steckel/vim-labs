# Vim Labs

Experimental Vim plugins and MCP tools by Curtis Steckel. This repository is
a home for alpha and beta work: interfaces can change, and each component has
its own requirements and validation limits.

## Components

| Component | What it does | Status |
| --- | --- | --- |
| [Revue](plugins/vim-revue) | Diff review, inline discussion cards, durable local reviews, and agent assignments | Alpha |
| [ReviewHub](plugins/vim-reviewhub) | GitHub PR discovery and the GitHub backend for Revue | Alpha |
| [Vim9 MCP](plugins/vim9-mcp) | MCP access to live Vim sessions, buffers, selections, and editing tools | Alpha |

Revue and ReviewHub share one review interface. Revue can also work locally
without GitHub. Vim9 MCP is independently installable and includes both a Vim
plugin and its Node.js MCP server.

Revue also has a separate, assignment-scoped
[review MCP server](plugins/vim-revue/doc/participant-mcp.md) for agents to read
selected discussions and reply inline. It lives with Revue's Python local
backend. The live-editor MCP and the review-assignment MCP serve different
purposes; neither requires the other.

## Install selected plugins

Clone this repository once:

```sh
git clone https://github.com/steckel/vim-labs.git
cd vim-labs
```

The repository root is a collection, not a Vim plugin. Add the component
directories you want to Vim's runtime path, or symlink them into a native
package directory. For example, from the cloned repository:

```sh
mkdir -p "$HOME/.vim/pack/vim-labs/start"
ln -s "$PWD/plugins/vim-revue" "$HOME/.vim/pack/vim-labs/start/vim-revue"
ln -s "$PWD/plugins/vim-reviewhub" "$HOME/.vim/pack/vim-labs/start/vim-reviewhub"
```

Restart Vim and run `:helptags ALL`. Revue and ReviewHub require Vim 9.1+;
the local review backend needs Python 3.9+ with SQLite. ReviewHub also needs
Python 3.9+ and uses the GitHub CLI for authenticated access. See the
[component setup](plugins/vim-reviewhub/README.md#install).

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

With ReviewHub installed and GitHub authentication configured, `:Reviews
owner/repo` opens the pull-request browser. GitHub publication uses explicit
review actions and confirmation; local drafts are distinct from posted comments.

For a fixture-only walkthrough, run:

```sh
python3 plugins/vim-revue/tools/ux_trial.py
```

This creates an isolated trial and opens a separate Vim instance. It does not
publish comments. The [trial guide](plugins/vim-revue/doc/ux-trial.md) explains
the exercise and observation record.

## Design and development

- [Review architecture and backend boundary](plugins/vim-revue/doc/plugin-architecture.md)
- [GitHub UX reference](plugins/vim-revue/doc/github-review-ux-spec.md)
- [Current UX comparison and backlog](plugins/vim-revue/doc/review-ux-gap-audit.md)
- [Parity validation and remaining limits](plugins/vim-revue/doc/parity-validation.md)
- [Live-editor MCP feature catalog](plugins/vim9-mcp/docs/feature-catalog.md)

The test suites use temporary repositories and fixture transports. From the
repository root, after installing the MCP dependencies:

```sh
./scripts/test.sh
```

Use `./scripts/test.sh revue`, `reviewhub`, or `mcp` to run one component's
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
[licensing notes](plugins/vim-revue/doc/licensing.md), including the earlier MIT
versions of Revue. Third-party research material retains its owners' rights.
