# GitHub suggestion application: service boundary

Checked 2026-09-14 against official documentation and the authenticated public
GitHub.com GraphQL schema. This supplements the [workspace application
contract](suggestion-application.md); it does not change the application UI or
authorize a remote commit.

## Decision

Retain the selected comment's GitHub link for native single/batch suggestion
application. A supported review-suggestion application API has not been
established. Do not repeatedly treat the absent implementation as an ordinary
missing renderer or command: the next prerequisite is a supported service
contract or a separately designed, explicitly named generic-commit feature.

The working local application remains available through its backend capability.
It saves a workspace replacement, captures the result and preserves the original
conversation. It does not claim GitHub native application semantics.

## Evidence

A read-only introspection query returned **275 public Mutation fields, including deprecated fields**. Its
suggestion-named mutations concern repository topics and pending issue metadata;
none applies a pull-request review comment. `PullRequestReviewComment` exposes
no suggestion-named field in this response. In particular, the previously
mentioned `viewerCanApplySuggestion` field is **not present in the inspected
public schema**. The earlier reference to it is not usable API evidence.
Exact schema response (local evidence: `../output/service-suggestion-contract/schema.json`).

GitHub's browser workflow applies one or multiple suggestions as a commit on
the PR's compare branch and credits the suggestion authors. The person applying
it is also credited. Fork application depends on maintainer-edit permission.
[Official workflow](https://docs.github.com/en/pull-requests/how-tos/review-pull-requests/incorporating-feedback-in-your-pull-request).

`createCommitOnBranch` exists and accepts a branch, expected head, file changes
and commit message. Its documented author is the owner of the authenticating
credential; callers cannot directly supply author/committer fields. It advances
the branch and can produce GitHub-signed commits. Its public input has no review
comment or suggestion identifier. This establishes generic commit creation,
not native association of that commit with an accepted review suggestion.
[Commit API](https://docs.github.com/en/graphql/reference/commits#createcommitonbranch).

The REST review-comment reference covers creating, reading, updating, replying
to and deleting comments. It does not establish a native application operation.
[Review comment API](https://docs.github.com/en/rest/pulls/comments).

This is a bounded inspection of public interfaces, not a claim that GitHub's
browser has no private endpoint or that every enterprise schema is identical.
No undocumented endpoint, browser submission, commit mutation or push was used.

## Comparing the possible actions

| Requirement | Native GitHub browser | Generic commit API | Current Revue workspace action |
| --- | --- | --- | --- |
| Destination | PR compare branch | Explicit repository branch | Explicit saved workspace file |
| Proposal identity | Browser operates on a suggestion | Caller must parse/verify a message; input has no suggestion ID | Exact message version and original body |
| Source currency | Service checks eligibility | Caller verifies range/blob; expected head guards branch advancement | Complete saved-file hash plus reviewed capture |
| Attribution | Documented suggestion co-authorship | Credential owner authors commit; any trailers need a separate verified contract | No commit/authorship claim |
| Applied indicator | Native suggestion workflow | Not established by commit creation alone | Backend application annotation on exact message version |
| Fork maintainers | Documented browser permission path | Not proven equivalent to branch-write permission | Not applicable |
| Lost response | Service/browser workflow | Need durable intent and read-only commit/branch reconciliation | Existing durable intent, file observation and capture receipt |
| Batch | Native single-commit batch | Caller must detect overlap and construct one atomic branch update | Not yet supported |

## Entry criteria for an in-Vim service implementation

For native application, obtain a supported API contract that binds suggestion
IDs, reviewed source, permissions, attribution, result identity and recovery.
Verify one suggestion before adding batches.

A generic commit feature would be a different explicit action. Its design must
show repository/branch, expected head, exact complete-file replacement, commit
message, verified attribution, and what happens to native suggestion state.
It must handle stale heads, protected/fork branches, missing author identity,
no-op suggestions, newline/mode preservation and lost responses without blind
replay. The generic mutation's `clientMutationId` is not documented here as an
idempotency guarantee. Such a feature cannot be labeled native suggestion
application merely because the final file bytes match.

The shared UI should remain backend agnostic. An eventual service destination
can extend the application contract, but unsupported service behavior must not
be enabled by a renderer branch on the name GitHub.
