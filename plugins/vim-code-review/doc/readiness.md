# Read-only review readiness

`:RevueReadiness` opens checks and review requirements through the backend's
readiness capability. It is also available from `:RevueReviewActions`.
There is no default key for opening the view. `:RevueReloadReadiness` reloads
from the first page, `:RevueMoreChecks` loads one more page, and
`:RevueCancelReadiness` stops adopting the active read. `:RevueClose` returns
to the originating view. On a fact or check, `gx` opens its source link and
`gy` copies it; these bindings are configurable.

The view separates code-review state, service merge status, conflict state,
and check outcomes. Checks retain required/not-required/unknown classification;
skipped, neutral and cancelled results remain distinct from passed results.
The result is an observation, not a merge permission or a complete repository
policy evaluation. There is no merge, rerun-check, branch-update or review
submission action here.

## Identity and refresh

Reads start from the latest full comparison. Historical, range and original-file
contexts explain how to return to the latest comparison. Each response echoes
the requested comparison and identifies the service head and base tip. A newer
service head or changed base tip is visibly stale for the selected comparison.
A refresh that discovers a newer comparison also makes retained observations
stale, even if the user continues reading the previous comparison.

Cancellation, transport exceptions and malformed responses retain the last good
observations. A cancelled, duplicate or superseded response cannot replace the
view. Reloading restarts the check inventory; paging preserves check identity
and rejects repeated cursors, overlapping pages and inconsistent totals.
Returning from Help follows the same check after reordering. Responses preserve
another draft's bytes, Insert mode and window focus. Readiness data stays in
session memory, outside the durable outbox.

## Backend contract

Advertise `snapshot.capabilities.readiness = {enabled, reason}`. The shared UI
never branches on a backend name. The local backend currently supplies a
specific unavailable reason because it does not supply CI or merge policy.

The read request is:

```json
{"op":"readiness","reference":{"snapshot":"comparison-id","base":"base","head":"head"},"cursor":""}
```

Return the normal `{ok, data}` envelope. `data` contains:

| Field | Meaning |
| --- | --- |
| `reference` | Exact request reference, including any optional reference fields |
| `head`, `base_tip` | Observed live head and base-branch tip; nonempty strings |
| `observed_at` | Observation timestamp |
| `url`, `scope` | Service source and honest coverage explanation |
| `facts` | List of `{id, name, value, detail, url}` strings; unique IDs |
| `checks` | List of `{id, name, state, required, detail, url}` |
| `cursor`, `next_cursor` | Requested and next opaque cursor; empty next cursor at completion |
| `complete`, `total` | Boolean inventory completion and integer reported check total |

`state` is one of `pending`, `passed`, `failed`, `cancelled`, `skipped`, `neutral`,
or `unknown`. `required` is a Boolean or JSON null; numeric 0/1 is rejected.
An empty inventory means no checks reported, not no requirements. A failed read
uses `{ok:false,error}` and must not convert inaccessible data into zero checks.
Completeness covers the reported check connection, not the repository's full
requirements. Check pages may have different observation times; reload when a
fresh assessment is needed.

## GitHub adapter

The companion uses the documented PullRequest `reviewDecision`,
`mergeStateStatus`, `mergeable`, state/draft flags, and both branch OIDs.
It reads the current head commit's `statusCheckRollup.contexts`, 50 entries per
page, including CheckRun and StatusContext. Required classification uses the
**global PR ID**, so fork checks do not accidentally use a PR number in the
wrong repository. The adapter checks review metadata before and after reading
the page; changed metadata requires a reload.
[Pull-request schema](https://docs.github.com/en/graphql/reference/pulls),
[check schema](https://docs.github.com/en/graphql/reference/checks),
[commit/status schema](https://docs.github.com/en/graphql/reference/commits).

Each page uses three read-only GraphQL queries: metadata, checks, metadata
verification. Cursors bind connection/review, requested comparison, PR ID and
both live branch tips. Reads do not hold a server-side snapshot or prevent
changes after the observation. Authentication/schema failures remain explicit.

The view does **not** enumerate every branch protection/ruleset requirement,
missing check that has never reported, required reviewer, deployment gate,
merge queue or bypass permission. GitHub's reported review/merge state and
source links remain available, with incomplete policy coverage stated near the
top. Null `reviewDecision` displays unavailable. A clean merge status or no
reported conflicts is never converted into a Revue “ready to merge” assertion.

## Verification

Evidence and terminal captures (local evidence: `../output/readiness/validation.json`) record
real Vim fixture checks, provider tests and read-only public GitHub reads.
The public Neovim sample exercised 45 reported checks, including skipped and
passed outcomes; the Fugitive sample exercised an empty check report and null
review decision. Fixture tests cover multi-page checks, required/optional/unknown
classification, failures and stale reads. These samples do not prove all GitHub
roles, enterprise schemas or repository policies.

The 80×24 and 120-column images render an isolated real Vim terminal screen.
They use a labeled interaction fixture and are not OS or iTerm screenshots.
