# Personal service Viewed state

Revue's local Viewed mark acknowledges the exact compared file content. GitHub's
Viewed state is personal service data and has different revision semantics.
This optional UX-14 extension exposes the service state explicitly; it does not
silently synchronize the two meanings.

## Interaction

From a selected source file or file-list row, use `:RevueServiceProgress`.
The read-only view shows the path, service actor, state and observed head.
`dismissed` is displayed as “changed since last viewed.” Unknown/failed reads
never appear as unviewed. Repeating the command reloads; close returns to source.
No default keys were added. The contextual action guide lists the commands.

- `:RevueMarkServiceViewed` explicitly marks this file viewed on the service.
- `:RevueUnmarkServiceViewed` explicitly marks it unviewed on the service.
- `:RevueCheckServiceViewed` checks an uncertain saved intent without repeating
  the write. It does nothing for a merely failed or absent operation.

The normal mark/unmark path acts in place. It saves an outbox intent before
sending and shows submitting, failed or unknown state. Repeated activation
cannot issue a second concurrent write to the same file. A known failure can
retry the same intent; choosing the opposite state opens the saved operation
for inspection/discard first. An unknown intent must be checked before another
state change. Activity retains receipt inspection and recovery after restart,
even if the current service capability or file disappears.

Local `:RevueViewed` / `:RevueUnviewed`, file filtering, resolution, unread state
and comment visibility are unaffected. This does not automatically import
service Viewed into a content-based local mark, export all local marks, hide
files, fold comments, or change a review decision.

## Backend contract

Advertise `capabilities.service_progress.enabled` for reads and separately
`capabilities.service_viewed.enabled` (`body_required: false`) for writes.

Read `op: "service_progress"` with `{path, reference}`. The reference is the
latest full comparison. Return `{path, reference, actor, actor_label, review_id,
state, url?}`. Actor and review IDs are stable backend identifiers; `state` is
`viewed`, `unviewed` or `dismissed`. The UI validates target/reference and rejects
late reads after comparison changes. A newer latest comparison invalidates a
read even when the user deliberately retains the older comparison on screen.

The durable `service_viewed` draft contains `{id, state, body: "", path,
reference, actor, actor_label, review_id, viewed}` plus usual captured
snapshot/head/base fields. `viewed` is a Boolean. Mutation uses the existing
bound backend `mutate` operation. Receipt checking sends the same operation
with `reconcile: true`.

An accepted receipt repeats `{id, path, reference, actor, review_id, viewed}`
and has `observed: true`. The UI requires exact values and types. “Observed”
means the requested state was seen for this actor and source at read time; it
does not identify which client caused that state. A matching state can settle
an uncertain intent; a different state, missing file, lost permission or changed
source keeps it uncertain. Recovery never invokes the mark/unmark mutation.

This uses the existing outbox and Activity, not a separate service-state store.
The local backend does not advertise the optional service capabilities.

## GitHub implementation and limits

The adapter queries `viewer { id login }` and the PR's file connection, with
head/base-tip and PR identity checks. It scans up to 100 pages to locate the
exact current path, stops at the target, and rechecks identity/source before
returning. It reports missing, unknown and incomplete state explicitly. The
read does not fetch discussion bodies or changed-file contents.

GitHub supplies `VIEWED`, `UNVIEWED` and `DISMISSED`. Its mark/unmark mutations
accept PR ID, path and client mutation ID; they do **not** accept an expected
commit ID. [Official API](https://docs.github.com/en/graphql/reference/pulls#markfileasviewed),
[state definitions](https://docs.github.com/en/graphql/reference/pulls#fileviewedstate).

The adapter verifies current actor/review/head/base tip before writing and reads
again afterward. A detected change after submission produces an unknown outcome;
it cannot be labeled successful for the reviewed content. These checks do not
provide an atomic compare-and-swap: a branch update can race the service's
path-based mutation, including one that changes back between observations.
The mutation may already have occurred when a post-write read fails. Revue never
tries to roll it back or replay it automatically. This is why service marks
remain separate from local content acknowledgements.

## Evidence

Validation record and actual Vim terminal renders (local evidence: `../output/service-progress/validation.json`).
The real GitHub probe is read-only. Mark/unmark, source races, denied state,
receipt recovery and restart use controlled fixtures. Live writes and broader
role coverage remain unverified; the previously prepared GitHub comment test
plan does not authorize additional Viewed mutations implicitly.
