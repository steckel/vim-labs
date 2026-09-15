# vim9-mcp

A Vim9-script plugin and local MCP server for collaborating in live **Vim 9+** sessions. No Neovim dependency. Buffer snapshots, locations, findings, and change sets are shared across the tools so capabilities compose:

```text
selection → snapshot → search → targets → preview → apply → verify → undo
                                  ↑                     ↓
                         diagnostics / jobs ←────────────┘
```

The implementation includes the foundation and editing loop, project search, target algebra, transformations, quickfix/location lists, provider and job interfaces, macros, editor inspection, and workflow recipes. See the [feature catalog](docs/feature-catalog.md) for the complete prioritized inventory and [roadmap](docs/roadmap.md) for dependency order and acceptance gates.

## Requirements

- macOS or Linux, Vim **9.0.0000+** with `+vim9script`, `+channel`, `+job`, and `+timers`.
- Node.js **22+**, with `node` on Vim's PATH (or configure `g:vim9_mcp_node`).
- Python 3 and a C toolchain are only needed for the terminal tests and optional baseline-Vim build respectively.

## Install locally

From this project directory:

```sh
npm ci
```

Add the project to your Vim runtime path in your vimrc, before plugins load:

```vim
set runtimepath^=/absolute/path/to/vim9-mcp
```

Alternatively, symlink the project into a native Vim `pack/*/start/` directory. Restart Vim. The plugin automatically starts the local broker and connects. Use `:VimMCPStatus` to inspect the connection.

Configure an MCP client to launch:

```json
{
  "mcpServers": {
    "vim9": {
      "command": "node",
      "args": ["/absolute/path/to/vim9-mcp/bin/vim9-mcp.js"]
    }
  }
}
```

The exact surrounding configuration depends on the MCP client; the command and arguments are the server entry point. No user configuration is modified by `npm ci` or by the tests.

For a selection-sharing mapping in your vimrc:

```vim
xmap <leader>ms <Plug>(VimMCPShareSelection)
```

Select text, invoke that mapping, then ask the agent to explain or transform the shared selection. The agent should start with `list_sessions` and `get_context`.

## The editing contract

1. **Read live content.** `read_buffer` returns text and a revision, including unsaved changes.
2. **Target precisely.** Positions use 1-based lines and 0-based UTF-8 byte offsets, with an exclusive end. Search results already carry this representation.
3. **Prepare before applying.** `prepare_changes` and `transform` return a stored change ID, hunk IDs, and a diff without editing buffers.
4. **Apply against the same revision.** User changes invalidate the proposal. Applications report per-buffer outcomes and leave edits unsaved.
5. **Undo or save deliberately.** `undo_change` checks both revision and undo history. `save_buffer` checks the revision and external file changes.

A single edit batch creates one undo step per changed buffer. Multi-buffer changes are **not atomic**. The plugin preflights requested buffers, then stops and reports results if an application fails.

Mutations wait while the user is typing or in an interactive prompt. A timeout may mean an operation is still queued or already ran: inspect `request_status` using the returned request ID. Do not replay a mutation blindly. `cancel_request` can remove an operation still in Vim's queue.

The full wire and behavior contract is in [capabilities.md](docs/capabilities.md).

## Vim commands and settings

| Command | Purpose |
|---|---|
| `:VimMCPStatus` | Connection, session ID, queue length, socket, last error |
| `:VimMCPConnect` / `:VimMCPDisconnect` | Explicit connection control; disconnect also disables retry |
| `:VimMCPShareSelection` | Capture the last visual selection; normally invoked through the mapping |
| `:VimMCPReview change-1` | Open before/after scratch buffers in diff mode |
| `:VimMCPHistory` | Inspect the latest 100 editor operation outcomes |

Settings belong in your vimrc, before the plugin loads:

```vim
let g:vim9_mcp_autoconnect = v:true
let g:vim9_mcp_node = 'node'
let g:vim9_mcp_advanced = v:false
```

Set `VIM9_MCP_RUNTIME` to the same private directory in Vim and the MCP client to isolate a broker. `g:vim9_mcp_runtime` overrides that directory for Vim only. The directory must be owned by the current user with mode `0700`; the broker socket uses `0600`. The default is `$TMPDIR/vim9-mcp-<uid>` (or `/tmp` when unset). Every editor connection receives a new session ID; reconnecting never restores pending mutations.

`node bin/vim9-mcp.js broker` runs the broker in the foreground. `node bin/vim9-mcp.js ensure` starts it if needed. The default `stdio` mode is the MCP server. Protocol output goes to stdout; diagnostics go to stderr. A broker intentionally outlives individual Vim/MCP clients.

## Extend your setup

### Typed Vim9 providers

Register a function from a Vim9 script after adding this project to `runtimepath`. The public module is `autoload/vim9mcp/editor.vim`:

```vim
vim9script
import autoload '/absolute/path/to/vim9-mcp/autoload/vim9mcp/editor.vim' as MCP

def ExplainSetting(input: dict<any>): dict<any>
  return {ok: true, value: &shiftwidth, requested_by: input.label}
enddef

MCP.Register('my.setting', {
  type: 'object',
  properties: {label: {type: 'string'}},
  required: ['label'],
  additionalProperties: false,
}, ExplainSetting, 'custom')
```

`get_context` advertises providers. `invoke_provider` validates their JSON Schema at the MCP boundary. Provider functions run locally in Vim and are trusted user code; keep them short. Formatter and code-action providers should return standard proposed changes; diagnostic providers should return standard findings. They can import `model.vim` to obtain live buffer identities and revisions. No language-server plugin is assumed or bundled.

### Named build/test/lint jobs

```vim
let g:vim9_mcp_jobs = {
      \ 'test': {'argv': ['npm', 'test'], 'errorformat': '%f:%l:%c:%m'},
      \ 'lint': {'argv': ['make', 'lint'], 'errorformat': &errorformat},
      \ }
```

The agent calls `start_job` with a configured name, then polls `get_job`. Arguments go directly to `job_start`, without shell interpolation. Job findings retain the buffer revisions observed at job start; a later edit makes them stale. Jobs may validate disk content rather than unsaved buffers, so saving is a separate explicit step.

### Named workflow recipes

```vim
let g:vim9_mcp_workflows = {
      \ 'read-current': [
      \   {'id': 'context', 'tool': 'get_context', 'arguments': {}},
      \   {'id': 'read', 'tool': 'read_buffer', 'arguments': {
      \     'buffer': {'$ref': 'context#/current/buffer'}}},
      \ ],
      \ }
```

Call `run_workflow` with `{"session":"…","name":"read-current"}`. A step's arguments can reference previous results using JSON Pointers. The session is inherited when omitted. Inline `steps` are also supported. Recipes stop on the first error, do not retry or roll back, and cannot recursively call themselves. Clients must select a session explicitly.

### Advanced automation

`record_macro` stores keys without executing them. `execute_macro` and `execute_ex` require `g:vim9_mcp_advanced = v:true`. These unrestricted operations can invoke mappings, autocommands, shell commands, or prompts. They return actual output/exceptions, but do not have structured edit preview, undo, rollback, or cancellation guarantees. Recording keys accepts literal control characters; it does not expand strings such as `<Esc>`.

## Limits and current boundaries

- Structured search/transformation/application is capped at 2 MB / 50,000 lines per buffer; reads are paginated up to 1,000 lines / 1 MB. Saving files above 2 MB is left to manual Vim saves.
- A prepared change set holds at most 4 MB of before/after text; the editor keeps at most 32 sets / 16 MB. Prepare again after an ID expires.
- Events are polled through `get_events`; the latest 256 are retained. A `gap` requires resynchronizing snapshots. This is not a background agent or an MCP push subscription.
- A rectangular selection that cuts a display cell or extends beyond EOL returns display text and covering ranges, but no directly editable targets. Refine it to whole characters before editing.
- Project discovery excludes VCS/dependency/cache directories and symlink traversal. It does **not** currently interpret `.gitignore`; explicit caps and exclusions are documented in the capability contract.
- Files discovered only on disk return `disk_location`; call `open_buffer` and search/read again before editing. Project search is literal; live-buffer search supports Vim regex.
- Provider adapters are user-supplied. Tags/marks/jumps retain Vim's native metadata where a trustworthy live revision is not available; resolve and read the target before editing.
- Broker request history is bounded and process-local. After a broker restart or history eviction, an unknown ID is not evidence that the operation never ran.
- If the broker process dies, restart the MCP connection and reconnect Vim. In-flight requests are not replayed; existing disconnected adapters report `broker_disconnected`.
- Windows and remote-host brokers are not implemented.

## Develop and test

```sh
npm ci
npm run check
npm test
VIM=/path/to/another/vim npm test
```

Tests use temporary files, isolated broker sockets, real headless Vim processes, an interactive pseudo-terminal, and the official MCP client. They do not load your vimrc or edit your working files. The GitHub Actions matrix builds Vim 9.0.0000 and runs against a current packaged Vim. The [roadmap](docs/roadmap.md) lists the scenarios exercised by each release gate.

## License

Source-available under Apache License 2.0 **with the Commons Clause 1.0**.
Personal and workplace use are permitted; selling products or services whose
value derives entirely or substantially from this software is restricted.
This is not plain Apache-2.0 or OSI open source. See [LICENSE](LICENSE) and
the [Vim Labs licensing notes](../../plugins/vim-revue/doc/licensing.md).
