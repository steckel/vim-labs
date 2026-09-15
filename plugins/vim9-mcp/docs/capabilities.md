# Capability contract

## Architecture and boundaries

```text
MCP client
    │ MCP JSON-RPC on stdio (official TypeScript SDK)
Node adapter: schemas, project I/O, target algebra, diffs, recipes
    │ private Unix socket, newline-delimited JSON
Local broker: explicit sessions, request correlation, deduplication, status
    │ same socket protocol, separate registered editor connection
Vim9 plugin: bounded snapshots, mutation queue, native editor operations
```

The Vim plugin is the authority on live content, revisions, and whether an editor operation actually completed. The adapter never overwrites disk files to simulate an editor change. An explicit save uses Vim's write machinery. Structured operations and unrestricted provider/Ex/macro operations have different guarantees.

## Shared representations

### Sessions and buffers

- `session`: opaque UUID issued by the broker for one editor connection. Every editor-targeting tool requires it. It changes on reconnect.
- `buffer`: opaque ID derived from a buffer number and lifecycle generation. It is valid only within its session and loaded lifetime. Paths are descriptive, not identities. Unnamed buffers are supported.
- `revision`: opaque buffer identity plus `b:changedtick`. It is compared for equality immediately before dependent work; never infer chronological order from it.
- `Snapshot`: `buffer`, `revision`, path/name, modified/filetype metadata, line count, `start_line`, `lines`, and `next_line` (`0` means finished).

Buffer unload/wipe invalidates its ID even if Vim later reuses the same buffer number. The registration protocol has a separate version (`1`) from the MCP protocol negotiated by the SDK.

### Locations and targets

```json
{
  "buffer": "b1-1",
  "revision": "b1-1:4",
  "start": {"line": 1, "byte": 0},
  "end": {"line": 1, "byte": 5}
}
```

Line numbers are 1-based; columns are 0-based UTF-8 byte offsets; ends are exclusive. Ranges must lie on character boundaries. The `(line_count + 1, 0)` sentinel denotes EOF (not an additional newline). Vim's final-file-newline option is preserved separately by normal buffer saving.

A target set is a list of locations. `combine_targets` supports union (merging overlapping/adjacent ranges), intersection, difference, and buffer filtering. Mixing revisions for the same buffer is an error, not an implicit rebase. Target algebra manipulates metadata; a later Vim operation still validates the live revision.

A captured selection contains its shape (`character`, `line`, `block`), targets, display text, raw Vim marks, selection option, and tabstop. Blocks also preserve virtual column bounds. If a rectangle selects part of a tab/wide character or virtual whitespace, `editable` is false, `targets` is empty, and `covering_targets` describes the enclosing characters. Covering ranges must not be treated as exact edits. Vim 9.1's `getregion` is used when available; Vim 9.0 has a display-aware fallback.

### Findings

```json
{
  "location": {"buffer":"b1-1","revision":"b1-1:4","start":{"line":1,"byte":0},"end":{"line":1,"byte":5}},
  "message": "Review this call",
  "source": "my-review",
  "severity": "warning"
}
```

Severity is `error`, `warning`, `info`, or `hint`. Source and severity are optional for publication. Findings can feed navigation, quickfix, location lists, and subsequent edits. Publication checks revisions and creates a new owned list; existing lists remain in Vim's list stack.

Disk search and unbound job output use `disk_location` instead of pretending to have a live revision. Open/load the file, then read and resolve its location before editing. Job diagnostics carry job-start revisions for buffers already loaded at launch, and expose `stale` when that revision is no longer current. They do not prove a disk-based compiler analyzed unsaved text.

### Change sets

`prepare_changes` takes up to 20 unique buffers, each with its revision and edits. Each edit has `start`, `end`, replacement `text`, and optional `expected` original text. Preparation:

1. Resolves live buffers and checks revisions and byte boundaries.
2. Rejects overlaps and duplicate insertion positions.
3. Verifies supplied expected text and computes the result in memory.
4. Stores immutable before/after text, edits, and hunk IDs in Vim.
5. Returns a change ID and bounded diffs from the adapter.

`apply_changes` accepts a stored change ID and optional hunk IDs. It preflights selected buffers, rechecks each immediately before applying, and returns `results` per buffer. Applying only some hunks consumes that buffer's proposal: prepare a fresh proposal for the remainder. A second application is rejected. A no-op returns `changed: false` and creates no undo step.

Edits replace only the common-prefix/common-suffix-delimited changed region. Setting/deleting/inserting lines avoids register-based normal commands. A batch closes undo blocks before and after; internal operations are joined. The active buffer/view, alternate-buffer intent, jumplist intent, and search register are preserved by the structured edit path. Existing plugins can still react to subsequent normal editor events.

`undo_change` requires the applied revision and recorded undo sequence still to be current. Manual Vim undo remains available. No API promises cross-buffer atomicity or arbitrary rollback after user edits. Unexpected partial application reports an inspectable per-buffer result and stops remaining work.

`save_buffer` requires a live revision, named writable buffer, and an unchanged disk fingerprint relative to the last observed load/save. It uses `:write` without forcing. Write autocommands may run; the result reports the actual resulting revision/modified state. The disk check is not an OS-level atomic compare-and-swap against another process writing at the same instant.

## Execution, cancellation, and state

- Tool schemas reject unknown fields and invalid ranges/types before dispatch; source of truth is `src/schema.js`.
- Every request has an opaque `request_id`. Internal transport IDs cannot be overwritten by result-domain fields.
- The broker deduplicates identical request IDs/arguments across clients while its record is retained; conflicting arguments return `request_id_conflict`.
- Vim processes requests through one queue. Mutations wait during insert/replace/select/operator/interactive command modes and prompts. Reads can run between queued operations; text-locked callbacks only emit invalidations.
- The broker returns an unknown-outcome timeout after 15 seconds; the adapter has a 20-second fallback. Neither automatically resends. Late responses update `request_status`.
- `cancel_request` requests removal from the Vim queue. Once an operation begins, cancellation is not guaranteed. Cancelling is not rollback.
- Disconnect discards the old editor queue and invalidates the session. Dispatched unresolved operations return `editor_disconnected` with unknown outcome.
- Request results are retained in process memory: up to 2,000 records, pruning completed records toward 1,500. `unknown_request` after eviction/restart requires inspecting live state, not assuming no execution.
- Recent editor outcomes (`get_history`, 100 entries) record IDs, method, status, and timestamps without retaining complete file contents.

Operation results have `ok`, optional `code`/`message`, domain-specific fields, and `request_id`. MCP errors also set `isError`. Expected errors include `stale_revision`, `expected_text_mismatch`, `invalid_range`, `invalid_byte_boundary`, `buffer_not_found`, `buffer_not_writable`, `external_file_changed`, `change_not_found`, `already_applied`, `partial_application`, `advanced_disabled`, and `provider_unavailable`.

## Composition and extensions

- Literal/Vim-regex search returns exact match locations; zero-width matches advance without looping forever.
- `transform` produces ordinary change sets for substitution, upper/lowercase, trim, and line sorting. Literal substitutions use literal replacement text; regex substitutions support Vim replacement syntax, excluding expression replacements (`\=`).
- Project discovery walks the session's current cwd with a 20,000-entry/20-level cap, excludes `.git`, `.hg`, `.svn`, `node_modules`, `vendor`, `target`, `.cache`, and `coverage`, and skips symlink traversal. It does not interpret ignore files. File listing is paginated; skipped/large/binary search files are reported. Live buffer matches supersede disk matches.
- Provider registration is local trusted Vim9 code. JSON Schema validation happens at the MCP adapter boundary. The private broker protocol is a trusted same-user transport, not a security boundary for plugin functions. Provider functions return dictionaries; diagnostic/formatter/code-action adapters should use the shared shapes. Every provider invocation is conservatively scheduled as a mutation.
- Jobs are configured named argument arrays, capped at four concurrent jobs and 32 retained jobs. Output is limited to 1,000 lines/128 KB. `errorformat` parsing does not replace the user's quickfix list and respects the configured job directory.
- `run_workflow` runs at most 12 steps. A sole `{"$ref":"step#/json/pointer"}` value references a prior result; there is no expression evaluator. Step IDs are unique, nested workflows are forbidden, and execution stops on failure. Named recipes come from `g:vim9_mcp_workflows`. They inherit the specified session when omitted; explicitly different sessions must be stated in the recipe.
- `execute_ex` and `execute_macro` require explicit advanced mode. They may affect windows, registers, disk, jobs, or prompts. They are not wrapped in the structured edit guarantees. The caller is responsible for using noninteractive commands if completion is needed.

## MCP resources and bounds

`vim9://sessions` lists sessions; `vim9://session/<id>/context` reads compact context. Tools provide the complete capability surface. `get_events(after)` is the portable invalidation interface; MCP resource push subscriptions are not advertised.

Read pages: 1,000 lines / 1 MB maximum. Whole-buffer structured operations: 50,000 lines / 2 MB maximum. Prepared set: 4 MB text; cache: 32 sets / 16 MB. Search/findings: 500 per call. Transport frames: 8 MB; Vim responses: 7 MB. Event journal: 256. Queue: 128. Clients must honor pagination, `truncated`, and event `gap` fields.
