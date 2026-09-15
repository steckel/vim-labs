" A deletion operation binds one message, its private owner and exact contents.
function! revue#delete#Fields(snapshot, target) abort
  let message = revue#edit#Message(a:snapshot, a:target)
  let review = revue#pending#Find(a:snapshot, get(message, 'pending_review', ''))
  let threads = filter(copy(get(a:snapshot, 'threads', [])), {_, t -> t.id ==# get(a:target, 'thread', '')})
  let thread = get(threads, 0, {})
  return extend(deepcopy(a:target), {'kind': 'delete_pending_comment', 'body': '',
        \ 'path': get(thread, 'path', ''), 'anchor_label': empty(thread) ? '' : revue#anchor#Label(thread),
        \ 'message_author': get(message, 'author', ''),
        \ 'delete_scope': 'message', 'pending_review': get(review, 'id', ''),
        \ 'pending_head': get(review, 'head', ''), 'actor': get(review, 'actor', ''),
        \ 'expected_version': get(message, 'version', ''), 'original_body': get(message, 'body', '')})
endfunction

function! revue#delete#Error(snapshot, draft) abort
  let message = revue#edit#Message(a:snapshot, a:draft)
  let review = revue#pending#Find(a:snapshot, get(a:draft, 'pending_review', ''))
  if empty(message) || empty(review) || get(message, 'publication', '') !=# 'pending' || get(message, 'pending_review', '') !=# review.id
    return 'Select an available private comment; published feedback and review summaries use separate actions.'
  endif
  if get(a:draft, 'message_kind', '') !=# 'comment' || empty(get(a:draft, 'thread', '')) || get(a:draft, 'delete_scope', '') !=# 'message'
    return 'This operation must identify exactly one inline private message.'
  endif
  if get(a:draft, 'actor', '') !=# review.actor || get(message, 'actor', '') !=# review.actor || get(a:draft, 'pending_head', '') !=# review.head
    return 'Private review ownership or source changed. Refresh before deleting.'
  endif
  let rule = get(get(message, 'capabilities', {}), 'delete', {})
  if !get(rule, 'enabled', 0) || get(rule, 'scope', '') !=# 'message'
    let reason = get(rule, 'reason', '')
    return empty(reason) ? 'This backend has not verified individual deletion for this message.' : reason
  endif
  if empty(get(message, 'version', '')) || get(a:draft, 'expected_version', '') !=# message.version || get(a:draft, 'original_body', '') !=# message.body
    return 'The message changed. Cancel this local operation, refresh and inspect the current message.'
  endif
  return ''
endfunction

function! revue#delete#Preview(snapshot, draft) abort
  let lines = ['## Exact private message to delete', ''] + split(a:draft.original_body, "\n", 1)
  let error = revue#delete#Error(a:snapshot, a:draft)
  if !empty(error) | call extend(lines, ['', 'Unavailable: ' . error]) | endif
  let current = revue#edit#Message(a:snapshot, a:draft)
  if !empty(current) && current.body !=# a:draft.original_body
    call extend(lines, ['', '## Current message changed', ''] + split(current.body, "\n", 1))
  endif
  return lines
endfunction

function! revue#delete#Receipt(draft, receipt) abort
  if type(a:receipt) != v:t_dict || get(a:receipt, 'deleted', 0) isnot v:true | return 0 | endif
  for key in ['id', 'message', 'message_kind', 'thread', 'pending_review', 'actor', 'delete_scope']
    if type(get(a:receipt, key, 0)) != v:t_string || empty(a:receipt[key]) || a:receipt[key] !=# get(a:draft, key, '') | return 0 | endif
  endfor
  return 1
endfunction
