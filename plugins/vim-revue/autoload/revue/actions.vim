" Contextual outcomes, backed by the commands already installed in this view.
function! revue#actions#Items(context) abort
  let c = a:context
  let result = []
  let definitions = [
        \ ['service-progress', 'Read', 'Inspect personal service Viewed state'],
        \ ['mark-service-viewed', 'Review', 'Mark this file viewed on service'],
        \ ['unmark-service-viewed', 'Review', 'Mark this file unviewed on service'],
        \ ['check-service-viewed', 'Read', 'Check uncertain service Viewed outcome'],
        \ ['run-participant', 'Review', 'Start participant'],
        \ ['abandon-run', 'Review', 'Abandon an unstarted prepared run'],
        \ ['assignments', 'Read', 'Inspect assignments and per-comment outcomes'],
        \ ['open-assignment', 'Read', 'Read this assignment’s comment outcomes'],
        \ ['assignment-details', 'Read', 'Inspect full assignment identifiers and source references'],
        \ ['reload-assignments', 'Read', 'Reload current assignment outcomes'],
        \ ['cancel-assignments-read', 'Read', 'Cancel the assignment read; retain loaded results'],
        \ ['assignment-discussion', 'Read', 'Open this outcome’s original discussion message'],
        \ ['assignment-reply', 'Read', 'Open the latest loaded participant reply to this message'],
        \ ['assignment-comparison', 'Read', 'Inspect the comparison assigned to this participant'],
        \ ['assignment-result', 'Read', 'Inspect this outcome’s resulting comparison'],
        \ ['cancel-assignment', 'Review', 'Preview revoking this assignment’s MCP access'],
        \ ['assign', 'Review', 'Select feedback to assign to a participant'],
        \ ['assignment-toggle', 'Review', 'Select or remove this message'],
        \ ['assignment-prepare', 'Review', 'Choose a participant and preview the assignment'],
        \ ['open', 'Read', 'Open selected file or local draft'],
        \ ['thread', 'Read', 'Select or quote a message in this discussion'],
        \ ['apply-suggestion', 'Write', 'Preview applying this suggestion to the workspace'],
        \ ['resolve', 'Review', 'Resolve this thread'],
        \ ['reopen', 'Review', 'Reopen this thread'],
        \ ['check-thread-state', 'Review', 'Check this thread’s uncertain resolution outcome'],
        \ ['actions', 'Read', 'Actions for the selected message'],
        \ ['reactions', 'Read', c.role ==# 'reactions' ? 'Reload reaction counts and your state' : 'Inspect reactions on the selected message'],
        \ ['react', 'Write', 'Execute the selected reaction action'],
        \ ['message-history', 'Read', 'Inspect this message’s edit history'],
        \ ['reload-message-history', 'Read', 'Reload this message’s edit history'],
        \ ['older-message-edits', 'Read', 'Load older message edits'],
        \ ['cancel-message-history', 'Read', 'Cancel this edit-history read'],
        \ ['history-message-link', 'Read', 'Open the original message on its service'],
        \ ['verify-pending', 'Read', 'Load and verify the complete private review'],
        \ ['cancel-verify-pending', 'Read', 'Cancel private review verification'],
        \ ['open-pending', 'Read', 'Open selected private comment'],
        \ ['open-discussion', 'Read', 'Open selected search result'],
        \ ['close', 'Read', 'Return to the previous view'],
        \ ['conversation', 'Read', 'Read review purpose and general conversation'],
        \ ['refresh', 'Read', 'Refresh review feedback'],
        \ ['continue-refresh', 'Read', 'Continue refresh by one feedback page'],
        \ ['cancel-refresh', 'Read', 'Cancel refresh and keep current feedback'],
        \ ['discussions', 'Read', 'Find feedback across this review'],
        \ ['load-more-feedback', 'Read', 'Load more review feedback'],
        \ ['cancel-feedback', 'Read', 'Cancel this feedback read'],
        \ ['timeline', 'Read', 'Inspect review history'],
        \ ['readiness', 'Read', 'Inspect checks and review requirements'],
        \ ['reload-readiness', 'Read', 'Reload readiness for the current head'],
        \ ['more-checks', 'Read', 'Load the next page of checks'],
        \ ['cancel-readiness', 'Read', 'Cancel readiness read; keep prior observations'],
        \ ['readiness-link', 'Read', 'Open selected readiness details'],
        \ ['copy-readiness-link', 'Read', 'Copy selected readiness link'],
        \ ['older-events', 'Read', 'Load older review events'],
        \ ['reload-timeline', 'Read', 'Reload recent review history'],
        \ ['cancel-timeline', 'Read', 'Cancel this history read'],
        \ ['event-discussion', 'Read', 'Open this event’s loaded discussion'],
        \ ['event-comparison', 'Read', 'Read this event’s source comparison'],
        \ ['load-event-discussion', 'Read', 'Load next feedback page and follow this event if found'],
        \ ['event-link', 'Read', 'Open this event’s web link'],
        \ ['copy-event-link', 'Read', 'Copy this event’s web link'],
        \ ['comparisons', 'Read', 'Choose a comparison'],
        \ ['open-comparison', 'Read', 'Open the selected comparison'],
        \ ['load-history', 'Read', 'Load comparison history'],
        \ ['range-start', 'Read', 'Use selected head as range start'],
        \ ['range-end', 'Read', 'Use selected head as range end'],
        \ ['open-range', 'Read', 'Open the selected range'],
        \ ['clear-range', 'Read', 'Clear selected range endpoints'],
        \ ['latest', 'Read', 'Return to the latest comparison'],
        \ ['previous-comparison', 'Read', 'Return to the previous comparison'],
        \ ['thread-comparison', 'Read', 'Read this discussion’s original code'],
        \ ['return-context', 'Read', 'Return to the discussion or history event before inspecting code'],
        \ ['draft-comparison', 'Read', 'Read this draft’s original code'],
        \ ['viewed', 'Read', 'Mark this file Viewed locally'],
        \ ['unviewed', 'Read', 'Mark this file unviewed locally'],
        \ ['verify-viewed', 'Read', 'Recheck unverified file progress'],
        \ ['reanchor-draft', 'Write', 'Choose a new location for this local draft'],
        \ ['reanchor-here', 'Write', 'Preview moving the selected draft here'],
        \ ['accept-reanchor', 'Write', 'Accept this local draft move; send nothing'],
        \ ['cancel-reanchor', 'Write', 'Cancel the move and return to the original draft'],
        \ ['comment', 'Write', 'Comment on this source line'],
        \ ['suggest', 'Write', 'Suggest a replacement for this line'],
        \ ['file-comment', 'Write', 'Comment on the whole file'],
        \ ['reply', 'Write', 'Compose a reply'],
        \ ['reply-pending', 'Write', 'Compose a private reply'],
        \ ['new-conversation', 'Write', 'Write review-wide feedback'],
        \ ['preview', 'Write', 'Preview this draft'],
        \ ['save-local', 'Write', 'Save draft locally'],
        \ ['save-pending', 'Write', 'Prepare private save and preview'],
        \ ['delete-message', 'Write', 'Preview deletion of this message'],
        \ ['delete-pending-comment', 'Write', 'Preview deletion of this private comment'],
        \ ['edit-pending', 'Write', 'Edit selected private feedback'],
        \ ['batch', 'Review', 'Choose local drafts for a review batch'],
        \ ['stage-batch', 'Review', 'Choose drafts to save privately'],
        \ ['pending', 'Review', 'Continue a review saved privately'],
        \ ['start-pending', 'Review', 'Prepare a new private review'],
        \ ['review', 'Review', 'Prepare a review decision'],
        \ ['publish-pending', 'Review', 'Prepare publication of this private review'],
        \ ['discard-pending', 'Review', 'Preview deletion of this entire private review'],
        \ ['send', 'Review', revue#actions#Delivery(get(c, 'draft', {}), c.snapshot)],
        \ ['batch-send', 'Review', 'Submit the selected review batch'],
        \ ['check-receipt', 'Review', 'Check an uncertain outcome'],
        \ ['activity', 'Review', 'Inspect delivery outcomes']]
  for [id, group, label] in definitions
    if index(get(c, 'hidden', []), id) >= 0 | continue | endif
    let bindings = filter(copy(c.bindings), {_, b -> b.id ==# id})
    if id ==# 'save-local' && c.role ==# 'draft' && index(['thread_state', 'capture', 'reaction', 'discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], get(c.draft, 'kind', '')) < 0
      let binding = {'command': 'write', 'key': ':w'}
    elseif empty(bindings)
      continue
    else
      let binding = bindings[0]
    endif
    if id ==# 'pending' && c.role ==# 'pending' | continue | endif
    if id ==# 'batch' && c.role ==# 'batch' | continue | endif
    if id ==# 'stage-batch' && !has_key(get(c.snapshot, 'capabilities', {}), 'stage_batch') | continue | endif
    if index(['pending', 'start-pending'], id) >= 0 && !has_key(c.snapshot, 'pending_reviews') | continue | endif
    if id ==# 'start-pending' && !empty(get(get(c.snapshot, 'pending_reviews', {}), 'items', [])) | continue | endif
    if id ==# 'save-pending' && (index(['comment', 'file_comment', 'reply'], get(c.draft, 'kind', '')) < 0 || !has_key(get(c.snapshot, 'capabilities', {}), 'save_pending')) | continue | endif
    if id ==# 'save-pending' && !empty(get(c.draft, 'pending_mode', '')) | let label = 'Review private-save target and preview' | endif
    if id ==# 'check-receipt' && get(c.draft, 'state', '') !=# 'unknown' | continue | endif
    let reason = get(c.reasons, id, '')
    if id ==# 'save-local' && index(['draft', 'failed'], get(c.draft, 'state', '')) < 0 | let reason = 'This operation is frozen; check its receipt.' | endif
    let key = substitute(get(binding, 'key', ''), '\c<LocalLeader>', '\=get(g:, "maplocalleader", "\\")', 'g')
    let key = substitute(key, '\c<Leader>', '\=get(g:, "mapleader", "\\")', 'g')
    call add(result, {'id': id, 'group': group, 'label': label, 'command': binding.command, 'key': key, 'reason': reason})
  endfor
  return result
endfunction

function! revue#actions#Delivery(draft, snapshot) abort
  let kind = get(a:draft, 'kind', '')
  if get(a:draft, 'state', '') ==# 'unknown' | return 'Check receipt; do not resend' | endif
  if kind ==# 'apply_suggestion' | return 'Apply suggestion to workspace (confirmation)' | endif
  if kind ==# 'participant_run' | return revue#runtime#Label(a:draft) . ' (confirmation)' | endif
  if kind ==# 'cancel_assignment' | return 'Revoke assignment MCP access (confirmation)' | endif
  if kind ==# 'assignment' | return 'Save assignment locally (confirmation)' | endif
  if !empty(get(a:draft, 'pending_mode', '')) || (kind ==# 'edit' && !empty(get(a:draft, 'pending_review', '')))
    return 'Save privately (confirmation)'
  endif
  if kind ==# 'submit_pending' | return 'Publish this private review (confirmation)' | endif
  if kind ==# 'delete_message' | return 'Delete this message (confirmation)' | endif
  if kind ==# 'delete_pending_comment' | return 'Delete this private comment (confirmation)' | endif
  if kind ==# 'discard_pending' | return 'Delete this entire private review (confirmation)' | endif
  if kind ==# 'capture' | return 'Capture saved workspace files (confirmation)' | endif
  if kind ==# 'service_viewed' | return 'Update personal service Viewed state (confirmation)' | endif
  if kind ==# 'reaction' | return 'Update your reaction (confirmation)' | endif
  if kind ==# 'thread_state' | return get(a:draft, 'resolved', 0) ? 'Resolve thread' : 'Reopen thread' | endif
  if kind ==# 'edit' | return 'Save changes to this message (confirmation)' | endif
  let verb = has_key(a:snapshot, 'pending_reviews') ? 'Publish' : get(a:snapshot, 'submit_label', 'Send')
  let target = get(a:snapshot, 'submit_target', '')
  return verb . ' ' . (kind ==# 'review' ? 'review decision' : 'feedback') . (empty(target) ? '' : ' to ' . target) . ' (confirmation)'
endfunction

function! revue#actions#Lines(items, numbered) abort
  let lines = []
  let group = ''
  let ordinal = 0
  for item in a:items
    if group !=# item.group
      let group = item.group
      call extend(lines, ['', group])
    endif
    let ordinal += 1
    let key = empty(item.key) ? ':' . item.command : item.key
    call add(lines, (a:numbered ? ordinal . '. ' : '') . item.label . ' · ' . key)
    if !empty(item.reason) | call add(lines, '   Unavailable: ' . revue#message#OneLine(item.reason)) | endif
  endfor
  return lines
endfunction
