# Parity completion audit

Checkpoint: 2026-09-14 working trees of Revue and the adjacent Reviewhub provider.
This checks the current [backlog](interaction-backlog.md) without treating
optional features, implementation evidence and human/service validation as the
same kind of completion. The overall parity goal is **not yet proven complete**.

## Requirements and current evidence

| Backlog IDs | Requirement | Current evidence / remaining boundary |
| --- | --- | --- |
| UX-01 | Explicit views own their action targets | Panel/action-guide and message-selection regressions; no stale Help target. |
| UX-02 | Native navigation and configurable actions | Keymap/guide tests; the new service commands and trial exercise remapped keys. Human discovery is still unobserved. |
| UX-03 | Predictable focus and exact return | Reader tabs, layout, thread-entry, source selection and service-progress tests cover window/cursor and draft preservation. |
| UX-04 | Select an exact message in an overlapping thread | Thread-entry chooser race and stable-ID tests; the runnable trial covers root versus second reply. |
| UX-05 | Quote/copy/link the selected message | Rich-reply, selected quote, raw-copy and link tests; external service links depend on backend metadata. |
| UX-06 | Contextual composer/preview and durable draft | Existing draft/restart tests and trial mechanics pass. The unfamiliar-user discovery and delivery-expectation observation is missing. |
| UX-07 | Capability-aware actions | Shared rules and provider permission fixtures; real actor/role behavior needs authorized service validation. |
| UX-08 | Pending work, batches and publication | Local and native-private core, paging/staging/deletion/receipt tests. Real private/public service validation is pending. |
| UX-09 | Resolve/reopen independently of visibility | Direct in-place commands and uncertain-outcome recovery; all comments remain expanded. Live actor-role evidence pending. |
| UX-10 | Feedback beyond loaded hunks | Shared/local flow and received outside-hunk feedback tested. GitHub write scope remains capability-limited; browser capability alone is insufficient evidence. |
| UX-11 | File-level comments | Creation, file targets, inaccessible source and replies have fixture coverage. |
| UX-12 | New comparisons and historical return | Local retained comparisons/ranges, verified original-file fallback, late-page lookup and saved-reference reopen. A historical head does not prove the original PR base. |
| UX-13 | Filter file navigation | Stable file identity, empty results and deliberate reveal covered by inventory/navigation tests. |
| UX-14 | Content-based Viewed and optional service progress | Local byte/content identity is separate from explicit service read/mark/unmark. Live read succeeds; service writes use fixtures. No atomic expected-head guarantee from GitHub. |
| UX-15 | Discussion index/search and coverage | Loaded-content search, filters, paging and targeted history lookup exist. They do not promise a global service-wide search. |
| UX-16 | Refresh without disrupting work | Changed/unchanged refresh, Insert-mode retention, identity/cancellation and bounded loading regressions; measured refinements recorded separately. |
| UX-17 | Readable metadata/Markdown | Flat replies, quotes, links, suggestions, Unicode and distinct delivery states covered by rich-render tests and retained real terminal renders. Human readability comparison remains unobserved. |
| UX-18 | Narrow reading and return | Actual 80×24 / 120×40 tests and renders, managed tabs and explicit split mode. The unfamiliar-user trial is prepared but not performed. |
| UX-19 | Author suggestions from selected source | Seed, exact ranges/replacement, parse/preview, stale source and delivery fixtures. GitHub scope follows UX-10. |
| UX-20 | Typed history and review navigation | Paging, exact discussion entry, lookup and original source fallback. Do not fabricate full original comparisons. |
| UX-21 | Edit/delete exact feedback | Shared and provider fixtures preserve siblings, versions and unknown receipts. Real own/foreign/private/public scope still needs service evidence. |
| UX-22 | Lightweight reactions and participants | Direct Add/Remove, stable own state, participant details, deleted accounts, paging and restart recovery. Real reads verified; live write roles remain separate. |
| UX-23 | Deliberate suggestion application | Local workspace application/capture/recovery works. Native GitHub single/batch application retains a browser fallback; current public schema does not establish an application mutation. |
| UX-24 | Read-only checks and requirements | Head-bound readiness with source links/paging and incomplete-policy disclosure. Full policy inventory and merge/land are outside the bounded core. |
| UX-25 | Local human–agent review process | Assignment/MCP/outcomes and supervisor fixture core exists. Model-backed runtime validation remains on the separate architecture track, not closed by GitHub UI parity. |
| UX-26 | Preserve uncertain outcomes | Existing single/batch and new service-progress restart/receipt regressions; unsuccessful receipt reads do not turn into fresh writes. |

Every row above is an evidence scope, not a blanket declaration of release
readiness. The checkpoint record (local evidence: `../output/parity-validation/validation.json`)
records exact suite results and source hashes. Detailed case contracts remain
in the linked backlog and feature documents.

## Remaining inputs that code cannot substitute for

1. **Human observation:** run the [prepared local discovery trial](ux-trial.md)
   with someone unfamiliar with Revue. Automated navigation cannot supply a
   person's wrong turns, comprehension or delivery expectation.
2. **Authorized service writes:** the private GitHub fixture plan (local evidence: `../output/github-validation/plan.md`)
   is prepared; authorization to create its PR/comments/review is pending. One
   account can establish own-message behavior only. Foreign-author/read-only
   roles and private visibility need a separately authorized second actor.
3. **Service contracts/source evidence:** native suggestion application and
   complete original-PR comparisons cannot be asserted from generic commit APIs
   or a historical head. Use the existing explicit fallbacks until the missing
   evidence exists. These are recorded service boundaries, not unfinished
   rendering tasks to reimplement.

Individual comment collapsing remains removed. Global visibility and unified
versus split diff selection stay deferred by the user's direction. Full HTML,
avatars, moderation, rich binary previews, repository administration and merge
controls remain outside the comment-focused scope. No new exclusion is added
by this checkpoint.
