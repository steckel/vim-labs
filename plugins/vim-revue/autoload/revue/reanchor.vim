" Local draft movement never changes a backend message or submits feedback.
function! revue#reanchor#Error(snapshot, draft) abort
  let rule = get(get(a:snapshot, 'capabilities', {}), 'reanchor_draft', {})
  if !get(rule, 'enabled', 0) | return 'This backend does not support moving local drafts.' | endif
  if empty(a:draft) || index(get(rule, 'kinds', []), get(a:draft, 'kind', '')) < 0 || index(['comment', 'file_comment'], get(a:draft, 'kind', '')) < 0
    return 'Open a local line, suggestion or file-comment draft. Replies and saved messages keep their discussion identity.'
  endif
  if index(['draft', 'failed'], get(a:draft, 'state', '')) < 0
    return 'Submitting or uncertain feedback must finish receipt recovery before its anchor can change.'
  endif
  if !empty(get(a:draft, 'pending_mode', '')) || !empty(get(a:draft, 'pending_review', '')) || get(a:draft, 'delivery', '') ==# 'private'
    return 'Private-review operations keep their original target. Create a separate local draft for another location.'
  endif
  return ''
endfunction

function! revue#reanchor#Anchor(draft) abort
  let result = {}
  for key in ['snapshot', 'head', 'base', 'base_tip', 'path', 'old_path', 'side', 'start', 'end', 'range', 'context']
    if has_key(a:draft, key) | let result[key] = deepcopy(a:draft[key]) | endif
  endfor
  return result
endfunction

function! revue#reanchor#Propose(draft, snapshot, location, id) abort
  let result = deepcopy(a:draft)
  for key in ['range', 'context', 'error', 'reanchored_from']
    if has_key(result, key) | call remove(result, key) | endif
  endfor
  call extend(result, revue#comparisons#Reference(a:snapshot))
  call extend(result, a:location)
  let result.id = a:id
  let result.state = 'draft'
  let result.reanchored_from = extend(revue#reanchor#Anchor(a:draft), {'id': a:draft.id})
  return result
endfunction

function! s:Context(view, title, draft, source) abort
  call add(a:view, {'text': a:title . ' · ' . a:draft.path . (a:draft.kind ==# 'file_comment' ? ' · whole file' : ' · ' . a:draft.side . ':' . a:draft.start . '-' . a:draft.end), 'type': 'RevueCardHeader'})
  call add(a:view, {'text': 'Source ' . a:draft.head . ' · comparison ' . a:draft.snapshot, 'type': 'RevueCardMeta'})
  if a:draft.kind ==# 'file_comment' | return | endif
  if get(a:source, 'kind', '') !=# 'text' || a:draft.end > len(get(a:source, 'lines', []))
    call add(a:view, {'text': 'Original source is not loaded; its exact reference is retained.', 'type': 'RevueCardMeta'})
  else
    for row in range(a:draft.start, a:draft.end)
      call add(a:view, {'text': printf('%d │ %s', row, a:source.lines[row - 1]), 'type': 'RevueCardCode'})
    endfor
  endif
endfunction

function! revue#reanchor#View(state, error) abort
  let rows = [{'text': '# Move local draft', 'type': 'RevueCardHeading'},
        \ {'text': 'Preview only · the original draft is retained until accepted', 'type': 'RevueCardMeta'}]
  if !empty(a:error) | call add(rows, {'text': 'Unavailable: ' . a:error, 'type': 'RevueCardAction'}) | endif
  call s:Context(rows, 'From', a:state.original, a:state.old_source)
  call add(rows, {'text': '', 'type': 'RevueCardBorder'})
  call s:Context(rows, 'To', a:state.proposal, a:state.new_source)
  call add(rows, {'text': '', 'type': 'RevueCardBorder'})
  call add(rows, {'text': 'Draft text · kept exactly', 'type': 'RevueCardHeader'})
  for line in split(a:state.original.body, "\n", 1) | call add(rows, {'text': line, 'type': 'RevueCardBody'}) | endfor
  if get(a:state.original, 'suggestion', 0)
    call add(rows, {'text': 'Suggestion replacement is unchanged. Check it against the new source before sending.', 'type': 'RevueCardMeta'})
  endif
  call add(rows, {'text': 'Accept changes only this draft’s location. Its text is unchanged. Nothing is sent.', 'type': 'RevueCardMeta'})
  return rows
endfunction
