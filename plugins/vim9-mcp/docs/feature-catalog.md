# Prioritized feature catalog

This is the implementation inventory for the approved Vim9-only roadmap. Priorities describe dependency/build order, not separate incompatible APIs. Every implemented capability below shares the [capability contract](capabilities.md); provider-specific behavior remains the responsibility of the registered adapter.

## How priority is assigned

Evaluate **reach** (distinct downstream workflows), **reuse** (shared inputs/outputs), **reliability** (trust gained by dependent operations), and **cost** (implementation/maintenance). Dependencies decide what can be built next; multiplicative value ranks ready work. Avoid speculative numerical scores.

Foundational identities and revisions have the highest reach because every operation depends on them. Targets connect discovery to action. Change sets connect every transformation to review, application, and undo. Quickfix makes findings from many sources inspectable. Providers and workflow recipes multiply these established contracts rather than creating a competing API for every plugin.

## Foundation: trustworthy shared primitives

| ID / feature | User outcome and interface | Prerequisites / unlocks | Contract and acceptance |
|---|---|---|---|
| **F1 Sessions and capabilities** | `list_sessions`, `get_context`, status commands, broker startup | None → every tool | Explicit session targeting; reconnect gets a new ID. Two editors with identical buffer names coexist; no global selected session. |
| **F2 Buffer lifecycle and snapshots** | `read_buffer`, buffer metadata, revisioned pages | F1 → C1–C5, W2–W6 | Live unsaved text wins. Unload invalidates IDs. Reads expose pagination and byte limits. Unicode, empty, hidden and unnamed buffers work. |
| **F3 Locations, selections, target sets** | Captured selection, canonical byte ranges | F2 → C2/C3/C6/C7, W1/W5 | End-exclusive, character-aligned ranges with provenance through revision and source. Preserve visual shape; reject ambiguous partial-cell targets. |
| **F4 Request results and recovery** | Request IDs, `request_status`, `cancel_request`, `get_history` | F1 → every multi-step workflow | Actual outputs/errors; bounded retained deduplication; unknown timeout outcomes; late response tracking; cancellation before dispatch in Vim. |
| **F5 Mutation scheduling** | Shared editor queue and structured operation wrapper | F1/F4 → safe concurrent use | Defer while typing/in prompts, serialize mutations, preserve focus/view/registers for structured edits. Never merge agent changes into surrounding user undo blocks. |

**Status:** implemented. Foundation scenarios are covered by broker, real-Vim integration, target-algebra, and real-terminal tests.

## Release 1: the complete reusable editing loop

| ID / feature | User outcome and interface | Prerequisites / unlocks | Contract and acceptance |
|---|---|---|---|
| **C1 Compact context** | `get_context`: current text neighborhood, cursor, mode, buffers, windows, selection | F2/F3 → focused explanations and edits | Bounded context; buffer list pagination. Captured selection keeps its original revision even after typing. |
| **C2 Scoped search** | `search`: literal/Vim-regex query + targets → findings | F2/F3 → C3, W1/W3 | Match byte ranges feed other tools directly; zero-width matches progress; no register/cursor mutation. |
| **C3 Change-set preparation** | `prepare_changes`, `review_changes`, native diff command | F2/F3 → all transformation review | Validate revisions, original text, ranges, and overlaps before constructing stored proposals; preparation leaves buffers unchanged. |
| **C4 Guarded apply and undo** | `apply_changes`, `undo_change` | C3/F4/F5 → generated edits, fixes, formatting | Preflight, then apply per buffer; actual content verification; one undo block per changed buffer. Reject stale application or undo; report partial failure. |
| **C5 Explicit save** | `save_buffer` | C4 → deliberate persistence and disk-based validation | Named writable buffer, revision check, disk fingerprint check, normal Vim write. External edits are not silently overwritten. |
| **C6 Location navigation** | `navigate(location)` / `navigate(back)` | F3/F5 → inspection of every result | Resolve revision before navigating; restore prior view; report missing buffers/windows. |
| **C7 Owned findings lists** | `publish_findings` → quickfix or location list | F3/C6 → reviews, search, diagnostics, jobs | Keep previous lists accessible; retain finding metadata; reject stale live locations. |

**Status:** implemented. The primary acceptance composition is selection/snapshot → search → preview → apply → verify → undo. Integration tests also verify hidden-buffer application while a wipe-on-hide diff review is visible.

## Release 2: connect discovery, transformation, and verification

| ID / feature | User outcome and interface | Prerequisites / unlocks | Contract and acceptance |
|---|---|---|---|
| **W1 Target algebra** | `combine_targets`: union, intersection, difference, buffer filtering | F3/C2 → reusable precise scopes | Reject mixed revisions for the same buffer; preserve inputs; produce normalized unions. |
| **W2 Project discovery and search** | `discover_files`, `project_search`, `open_buffer` | C2/W1 → cross-file workflows | Bounded project traversal; no symlink traversal; loaded text overrides disk. Disk-only findings require explicit loading and re-resolution. |
| **W3 Deterministic transformations** | `transform`: substitution, uppercase, lowercase, trim, sort | C2–C4/W1 → reusable edit recipes | Always emits a standard change set. Literal replacement is literal; regex replacement supports backreferences but not expressions. |
| **W4 Invalidation events** | `get_events(after)`, buffer listeners and lifecycle hooks | F2/F4 → refresh and stale-context detection | Bounded event cursor journal; `gap` requires resync. Never mutate from text-locked listener callbacks. Polling is available to every MCP client. |
| **W5 Native navigation sources** | `inspect_editor`: tags, marks, jumps, closed folds | F3/C6 → target discovery using Vim setup | Folds provide live locations; native tag/mark/jump metadata must be resolved/read before edit. Does not require LSP. |
| **W6 Provider interface** | Vim9 `Register`; `invoke_provider` | Shared contracts/C3/C7 → diagnostic, formatter, code-action adapters | Advertise configured providers and validate input schemas. No assumed LSP plugin. Providers return standard findings or proposed changes for composition. |
| **W7 Build/test/lint integration** | Named `start_job`, `get_job`, `stop_job` | F4/C7 → edit/validate/fix loop | Direct configured argv, bounded output, exit status, `errorformat` parsing. Preserve job-start revisions and distinguish disk-based findings. |
| **W8 Selective review** | Hunk IDs in previews, `apply_changes(hunks)`, buffer-specific diff view | C3/C4 → manageable multi-file changes | Revalidate at apply time. Applying selected hunks consumes that buffer's preview; prepare remaining edits again. |

**Status:** implemented as composable capabilities. Language-specific provider adapters and project-specific job configurations are supplied by users. The implementation does not create an independent language server, parser, or compiler.

## Release 3: extend the established contracts

| ID / feature | User outcome and interface | Prerequisites / unlocks | Contract and acceptance |
|---|---|---|---|
| **E1 Typed registered functions** | `Register(name, inputSchema, Fn, kind)` | Shared contracts/W6 → custom integrations | Explicit local registration; discoverable schemas; generic invocation; trusted callbacks must remain responsive. |
| **E2 Setup/help discovery** | `inspect_editor` for mappings, commands, registers, options; `help` excerpts | F1/F2 → agent understanding of the user's Vim | Bounded results; installed help includes plugin help; lookup does not take over a window. |
| **E3 Macro authoring/execution** | `record_macro`, `execute_macro` | E2/F4/F5 → existing editing idioms | Storage and execution are separate. Registers `a`–`z`; literal control characters. Execution requires advanced opt-in and has weaker guarantees. |
| **E4 Ex escape hatch** | `execute_ex` | F4/F5 → otherwise unavailable operations | Actual command output and exceptions. Advanced opt-in. No generic preview, rollback, or interactive-command completion guarantee. |
| **E5 Workspace operations** | `workspace`: split/vsplit/tabnew/close/tabclose/unload | F1/F5/C6 → deliberate layouts and lifecycle management | Explicit requests, no forced discard, modified buffers reject unload. Normal Vim close behavior applies. |
| **E6 Workflow recipes** | `run_workflow`, `get_workflow`, `g:vim9_mcp_workflows` | E1 + stable shared operations → repeatable compositions | Up to 12 sequential steps, prior-result JSON Pointer references, no recursion, stop-on-error with completed results retained. No automatic rollback/retry. |

**Status:** implemented. Configured providers and recipes are extension points, not a bundled inventory of third-party plugin integrations.

## Worked compositions

| Workflow | Composition | Why the primitives multiply capability |
|---|---|---|
| Explain selected text | F3 → F2 → C1 | The same capture can later scope search, diagnostics, or editing. |
| Replace selected matches | C2 → W1 → W3 → C3 → C4 | Search/selection supply targets; all transformations reuse validation and undo. |
| Review unsaved work | F2 → findings → C7 → C6 | Findings can come from an agent, search, compiler, or plugin without changing navigation. |
| Fix a diagnostic | W6 → finding → F3 → C3 → C4 → W6 | Fix providers reuse the same edit and freshness guarantees. |
| Format selected code | F3 → W6 → proposed changes → C3 → C4 | The formatter does not need its own preview or apply system. |
| Repair a build | W7 → findings → C6 → C4 → C5 → W7 | The job adapter does not need to own editing or file persistence. |
| Reuse a custom operation | E2 → E1 → shared results → E6 | New plugins/functions join existing workflows without new orchestration machinery. |

## Boundaries and follow-on work

The feature families are implemented; several deliberately narrower choices remain explicit: Unix-local transport, polling events rather than push subscriptions, literal project search, whole-character editable targets, bounded buffers/caches/output, no `.gitignore` parsing, and user-supplied provider adapters. See [capabilities.md](capabilities.md) for exact limits.

Potential follow-ons should be justified by composition gain: richer file-ignore policy, provider adapter packages, client-supported event subscriptions, and exact partial-display-cell edits. None should weaken revision checks or duplicate the change-set pipeline. Chat UI, model orchestration, remote hosting, Neovim compatibility, and a new language server are outside the approved scope.
