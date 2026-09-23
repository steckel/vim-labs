# Applying one suggestion

`UX-23a` now has a shared application UI and a working local workspace backend.
GitHub service commits and batch application remain separate work. The renderer
does not infer the destination from a backend name.

## User journey

1. Open a current head-side discussion and select the message containing one
   unquoted suggestion block. Use `:ReviewApplySuggestion` or its message action.
   The action has no default mapping; `apply-suggestion` is configurable.
2. A backend read verifies the saved file against the reviewed capture. The
   read-only preview shows the workspace path, range, comparison, message,
   original lines, replacement, line ending and file permissions.
3. `:ReviewSend` confirms the exact replacement. Closing the preview retains it;
   choosing Apply again reopens the same operation. A known failed preview can
   be discarded explicitly before preparing another one.
4. The local backend saves the replacement and captures the current saved
   workspace using the review's existing untracked-file choice. It does not
   commit, stage, push, publish feedback or resolve the thread. Unsaved Vim
   buffers are not included in the capture or reloaded by the operation.
5. `:ReviewLatest` opens the resulting comparison. The original discussion stays
   available with its original source, independent resolution state and an
   application annotation on the exact message version.

A modified Vim buffer for the target file prevents a new application. The
backend rechecks the entire saved file and message before writing; the preview
is retained if either has changed. A metadata-only application annotation is
not a comment edit, and editing a suggestion hides its previous version's
annotation.

## Backend contract

Advertise `capabilities.apply_suggestion` with `enabled`, `body_required: false`,
`destination: "workspace"` and an absolute `workspace`. Other destination modes
are unavailable in this implementation. In particular, the shared UI must not
label a workspace write as a service commit.

`suggestion_plan` is a read with `{reference, target}`. The comparison reference
contains `snapshot`, `base`, `head`, `base_tip`; the target contains `thread`,
`message`, `message_kind`, `expected_version`. The response is an application
plan with these fields:

| Fields | Meaning |
| --- | --- |
| `kind: "apply_suggestion"`, `body: ""`, `destination` | Explicit operation and effect |
| `reference`, `snapshot`, `head`, `base_tip` | Reviewed source identity |
| `thread`, `message`, `message_kind`, `expected_version`, `original_body` | Exact version of the selected proposal |
| `workspace`, `path`, `side: "head"`, `start`, `end` | Absolute workspace plus relative file and inclusive range |
| `before_hash`, `after_hash` | SHA-256 of complete file bytes |
| `before_lines`, `replacement` | Exact preview and replacement lines; an empty replacement deletes the range |
| `file_mode`, `line_ending` | File permissions and replacement LF/CRLF convention |
| `untracked` | Existing choice for the resulting saved-workspace capture |

The backend must not return an operation ID, outbox state or additional delivery
fields in the plan. Revue creates its own durable operation ID. A mutation sends
the plan plus `id` and outbox `state`, through the normal bound backend.
The backend validates the complete approved plan again before changing disk.

The receipt contains `{id, intent, applied, observed, result_snapshot,
capture_error, url}`. `intent` is the submitted operation without `state`;
Revue checks its full structure and types. `applied` and `observed` are Booleans.
`result_snapshot` is empty when no result capture was obtained. A capture error
does not hide an already successful file write; the outcome says that capture
is unavailable and retains the error. The user can capture saved files later.

Backends can annotate the exact proposal with `suggestion_application`:
`{state: "applied"|"observed", label, message_version, operation,
result_snapshot}`. The common message header displays the backend-provided label
only while `message_version` matches the current message. Execution, resolution,
source currency and approval remain independent.

## Local recovery and filesystem boundaries

The local backend commits an application intent before replacing a file. A
store-level advisory lock serializes its application workers; SQLite serializes
the associated receipts. The replacement uses an exclusive temporary file in
the verified parent directory and an atomic rename. Descriptor-relative reads
reject path traversal and symlinks. A final byte/identity check rejects a
detected intervening change. Permissions, group, ACLs and extended attributes
are preserved using native metadata APIs; old timestamps are not copied.

Supported targets are owned, singly linked regular UTF-8 files within the
capture limit (2 MiB). Symlinks, hardlinks, special files, privileged permission
bits and flagged files are rejected. Bytes outside the selected range and the
file's final-newline state remain intact. Replacement lines use the selected
range's newline convention, with a file-level fallback for a last line without
a newline. No fuzzy matching or automatic re-anchoring occurs.

An external editor need not honor Revue's advisory lock. The final check and
rename are separate system calls; this does not claim an atomic compare-and-swap
against arbitrary concurrent filesystem writers. Other applications should not
write the same file during the confirmed apply operation.

If the response is lost, `:ReviewCheckReceipt` never writes the file again:

- A saved receipt returns the original result even if the workspace changed
  later. It never reapplies the old proposal.
- With a prepared intent and a matching result hash, recovery records that the
  suggested result was observed and obtains a capture when possible.
- With the original hash, or no prepared intent while the worker lock is free,
  recovery settles the operation as not applied. A fresh preview is then allowed.
- If neither hash matches, the outcome stays unknown. The file and retained
  operation require inspection; there is no automatic overwrite or rollback.

Activity preserves access to uncertain operations after restart or after the
original message disappears. A process crash between the filesystem replacement
and the receipt transaction is covered by the saved-intent recovery path.

## Evidence and remaining scope

Validation and real Vim terminal captures (local evidence: `../output/suggestion-application/validation.json`)
cover backend application, exact receipts, restart, stale source/message,
intervening writes, metadata preservation, newline/deletion behavior, unsaved
Vim buffers, and resulting-comparison navigation. These are disposable local
repositories; no GitHub mutation was performed.

GitHub documents a different consequence: applying a suggestion creates a
commit on the PR's compare branch, including suggestion co-authorship.
[GitHub application workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request).
A subsequent live introspection of the public GitHub.com schema found no
review-suggestion application mutation and no `viewerCanApplySuggestion` field.
The earlier mention of that permission field was not reliable public API
evidence. Generic `createCommitOnBranch` exists, but does not establish native
suggestion association, eligibility or attribution semantics.
[Service-contract assessment and exact schema](github-suggestion-service-contract.md).

GitHub service application therefore retains the message's browser link. Its
remaining prerequisite is a supported native contract, or a separately designed
generic-commit action with explicit limitations. It is not an implementation-ready
UI task. Batch application follows a verified single-change contract.
