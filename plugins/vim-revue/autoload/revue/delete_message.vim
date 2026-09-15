" Published deletion is separate from private deletion and local draft discard.
function! revue#delete_message#Fields(snapshot, target) abort
  let message = revue#edit#Message(a:snapshot, a:target)
  let rule = get(get(message, 'capabilities', {}), 'delete_message', {})
  let thread = get(filter(copy(get(a:snapshot, 'threads', [])), {_, t -> t.id ==# get(a:target, 'thread', '')}), 0, {})
  return extend(deepcopy(a:target), {'kind': 'delete_message', 'body': '',
        \ 'path': get(thread, 'path', ''), 'anchor_label': empty(thread) ? '' : revue#anchor#Label(thread),
        \ 'message_author': get(message, 'author', ''), 'message_publication': get(message, 'publication', 'published'), 'delete_scope': 'message',
        \ 'actor': get(rule, 'actor', ''), 'expected_version': get(message, 'version', ''),
        \ 'original_body': get(message, 'body', '')})
endfunction

function! revue#delete_message#Error(snapshot, draft) abort
  let message = revue#edit#Message(a:snapshot, a:draft)
  if empty(message) || get(message, 'publication', '') ==# 'pending' || !empty(get(a:draft, 'pending_review', ''))
    return 'Select an available published message; private feedback uses its own deletion action.'
  endif
  let rule = get(get(message, 'capabilities', {}), 'delete_message', {})
  if !get(rule, 'enabled', 0) || get(rule, 'scope', '') !=# 'message'
    return empty(get(rule, 'reason', '')) ? 'This backend has not verified deletion scope for this message.' : rule.reason
  endif
  if get(a:draft, 'delete_scope', '') !=# 'message' || get(a:draft, 'body', '') !=# '' || empty(get(rule, 'actor', '')) || get(a:draft, 'actor', '') !=# rule.actor
    return 'The deletion actor or scope changed. Cancel this operation and inspect the message again.'
  endif
  if empty(get(message, 'version', '')) || get(a:draft, 'expected_version', '') !=# message.version || get(a:draft, 'original_body', '') !=# message.body
    return 'The message changed. Cancel this local operation, refresh and inspect the current message.'
  endif
  return ''
endfunction

function! revue#delete_message#Preview(snapshot, draft) abort
  let lines = ['## Exact ' . (get(a:draft, 'message_publication', '') ==# 'local' ? 'local review' : 'published') . ' message to delete', ''] + split(a:draft.original_body, "\n", 1)
  let error = revue#delete_message#Error(a:snapshot, a:draft)
  if !empty(error) | call extend(lines, ['', 'Unavailable: ' . error]) | endif
  let message = revue#edit#Message(a:snapshot, a:draft)
  if !empty(message) && message.body !=# a:draft.original_body
    call extend(lines, ['', '## Current message changed', ''] + split(message.body, "\n", 1))
  endif
  return lines
endfunction

function! revue#delete_message#Receipt(draft, receipt) abort
  if type(a:receipt) != v:t_dict || get(a:receipt, 'deleted', 0) isnot v:true | return 0 | endif
  for key in ['id', 'message', 'message_kind', 'thread', 'actor', 'delete_scope', 'expected_version']
    if type(get(a:receipt, key, 0)) != v:t_string || a:receipt[key] !=# get(a:draft, key, '') || (key !=# 'thread' && empty(a:receipt[key])) | return 0 | endif
  endfor
  return 1
endfunction
