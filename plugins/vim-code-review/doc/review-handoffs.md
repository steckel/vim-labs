# Agent reviews and GitHub handoff: deferred workflows

Status: discussion backlog, not implemented behavior. The public plugin family
is organized around counterparties: GitHub, Codex, and Claude. A review can
involve more than one of them over time. These workflows should be designed
after the first working agent-counterparty loop; the package rename does not
add PR creation, comment forwarding, or agent execution.

## UX-25d — A Codex review evolves into a GitHub PR

Trigger: a person has iterated locally with Codex, reviewed successive changes,
and wants to create a GitHub PR or associate the work with an existing PR.

Desired experience: continue the review with its useful context intact. Opening
the PR should not make the earlier discussion or source snapshots disappear.
The GitHub integration owns native PR objects; a link to the originating agent
review connects their histories without pretending the objects are identical.

Questions to resolve:

- Is the entry point “Create PR,” “Publish change,” or “Continue on GitHub”?
- How are repository, branch, base, and workspace selected and verified?
- What becomes the PR description, and which review material stays local?
- Does the existing Codex session continue, and how is its workspace kept in
  step with the PR head as other people contribute?
- How are old anchors, resolved concerns, and successive captures presented
  once a native PR exists?

Acceptance boundaries for a future implementation:

- Preserve source review/message identities, original authorship, and the
  reviewed revisions. Record the associated PR identity and published head.
- Preview the public material and intended GitHub operation. Private drafts,
  local conversations, and agent transcripts do not become public implicitly.
- Keep local and GitHub delivery receipts distinct. Interrupted PR creation
  needs reconciliation before a retry can create a duplicate.
- Linking reviews does not itself resolve concerns, approve changes, or erase
  the local history. Support reopening both sides after restarting Vim.

## UX-25e — Quote a GitHub comment and send it to Codex

Trigger: while reading a PR, select an exact comment or passage and choose a
future “Quote and send to Codex” action, optionally adding instructions.

Desired experience: Codex receives the selected feedback with enough source
context to work on it, and the reviewer can follow the result back to the
original PR thread. This is a handoff to Codex, not a normal GitHub reply.

Questions to resolve:

- Reuse the Codex session associated with this change, choose another, or start
  one? How is the matching checkout/worktree selected?
- Send only the quote, the entire comment, or a bounded thread context? How is
  that scope shown before sending?
- Where do agent progress, requests for clarification, and final replies appear?
- After reviewing a fix, does the person push changes, draft a GitHub response,
  or both? Which steps can be combined without obscuring their destinations?

Acceptance boundaries for a future implementation:

- Preserve the source repository/PR/thread/message IDs, author, link, observed
  comment version, selected text, and original comparison/anchor where known.
- Preview the exact quote and added instructions. Mark copied comment text as
  review data, and label unavailable or outdated source context accurately.
- Bind editing to an explicitly selected workspace matching the reviewed code.
  Reading a PR must not select an unrelated checkout for an agent run.
- Return agent results to the linked assignment with source/result references.
  Keep agent work state separate from the PR thread's resolution state.
- Sending to Codex does not automatically post a reply, resolve the PR thread,
  commit, push, or approve the PR. Any later GitHub action has its own explicit
  target and delivery state.
- Retry and restart retain the selected message and handoff identity, avoiding
  duplicate runs or posted replies after an uncertain outcome.

Claude should reuse the eventual handoff contract where supported. Shared UI
and storage contracts should accommodate these links without embedding
Codex-specific behavior in comment rendering. No new persistence schema or
service API is chosen by this backlog entry.
