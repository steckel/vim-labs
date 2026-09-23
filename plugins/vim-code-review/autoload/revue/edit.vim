" Backend-message targets are distinct from thread and draft identities.
function! revue#edit#Message(snapshot, draft) abort
  if get(a:draft, 'message_kind', '') ==# 'PENDING' && !empty(get(a:draft, 'pending_review', ''))
    let review = revue#pending#Find(a:snapshot, a:draft.pending_review)
    let summary = get(review, 'summary', {})
    return get(summary, 'id', '') ==# get(a:draft, 'message', '') ? summary : {}
  endif
  let messages = get(a:snapshot, 'conversation', [])
  if !empty(get(a:draft, 'thread', ''))
    let threads = filter(copy(get(a:snapshot, 'threads', [])), {_, t -> t.id ==# a:draft.thread})
    if empty(threads) | return {} | endif
    let messages = threads[0].comments
  endif
  let matches = filter(copy(messages), {_, m -> !empty(get(m, 'id', '')) && m.id ==# get(a:draft, 'message', '') && get(m, 'kind', 'comment') ==# get(a:draft, 'message_kind', '')})
  return len(matches) == 1 ? matches[0] : {}
endfunction

function! revue#edit#Error(snapshot, draft) abort
  let message = revue#edit#Message(a:snapshot, a:draft)
  if empty(message) | return 'The original message is unavailable; edit text is retained.' | endif
  if !empty(get(a:draft, 'pending_review', ''))
    let review = revue#pending#Find(a:snapshot, a:draft.pending_review)
    if empty(review) || get(message, 'publication', '') !=# 'pending' || get(message, 'pending_review', '') !=# a:draft.pending_review
      return 'This private review is unavailable or already published. Your edit is retained.'
    endif
    if review.actor !=# get(a:draft, 'actor', '') | return 'The pending review actor changed. Your edit is retained.' | endif
    if !get(get(get(a:snapshot, 'capabilities', {}), 'edit_pending', {}), 'enabled', 0)
      return 'This backend does not currently allow editing private pending feedback.'
    endif
  elseif get(message, 'publication', '') ==# 'pending'
    return 'Select this private message again to bind its pending review before editing.'
  endif
  let rule = get(get(message, 'capabilities', {}), 'edit', {})
  if !get(rule, 'enabled', 0) | return get(rule, 'reason', 'Editing this message is unavailable.') | endif
  if empty(get(message, 'version', '')) | return 'This backend has not supplied a message version.' | endif
  if get(a:draft, 'expected_version', '') !=# message.version || get(a:draft, 'original_body', '') !=# message.body
    return 'The message changed. Refresh and inspect :ReviewPreview; :ReviewEditBase accepts the current version without replacing your text.'
  endif
  return ''
endfunction

function! revue#edit#Before(snapshot, draft) abort
  let lines = ['## Original message · ' . a:draft.message_kind . ' #' . a:draft.message]
  call extend(lines, split(a:draft.original_body, "\n", 1))
  let current = revue#edit#Message(a:snapshot, a:draft)
  if empty(current)
    call extend(lines, ['', '## Current message unavailable'])
  elseif get(current, 'version', '') !=# a:draft.expected_version || current.body !=# a:draft.original_body
    call extend(lines, ['', '## Current message · changed since editing began'] + split(current.body, "\n", 1))
  endif
  return lines + ['', '## Proposed replacement', '']
endfunction
