" Per-message history is read-only, ephemeral and distinct from review events.
function! revue#message_history#State(target, label, url) abort
  return {'target': deepcopy(a:target), 'label': a:label, 'url': a:url,
        \ 'items': [], 'cursor': '', 'complete': 0, 'loading': 0, 'requested': 0,
        \ 'serial': 0, 'seen': [], 'scope': '', 'error': ''}
endfunction

function! revue#message_history#Apply(state, data, cursor, reset) abort
  if type(a:data) != v:t_dict || get(a:data, 'target', {}) !=# a:state.target || type(get(a:data, 'items', 0)) != v:t_list
    return 'Edit history does not match the selected message/version.'
  endif
  for item in get(a:data, 'items', [])
    if type(item) != v:t_dict || index(['available', 'redacted', 'unavailable'], get(item, 'content_state', '')) < 0
      return 'Edit history content state is missing.'
    endif
    if item.content_state !=# 'available' && get(item, 'body', '') !=# ''
      return 'Unavailable edit content must not be displayed.'
    endif
  endfor
  " Both inventories use stable chronological event pages and exact row return.
  return substitute(revue#timeline#Apply(a:state, a:data, a:cursor, a:reset), '\cTimeline', 'Edit history', 'g')
endfunction

function! s:Append(view, text, type) abort
  call add(a:view.lines, a:text)
  call add(a:view.decorations, {'text': a:text, 'type': a:type})
endfunction

function! revue#message_history#View(state) abort
  let view = {'lines': [], 'rows': {}, 'decorations': []}
  " Only share metadata when every loaded revision reports exactly the same
  " source and details. Recompute on each page: a later, different record must
  " restore per-entry attribution rather than inheriting another one's source.
  let shared = len(a:state.items) > 1
  if shared
    let source = a:state.items[0].provenance
    let details = a:state.items[0].details
    for item in a:state.items[1:]
      if item.provenance !=# source || item.details !=# details
        let shared = 0
        break
      endif
    endfor
  endif
  call s:Append(view, '# Message edit history', 'RevueCardHeading')
  call s:Append(view, revue#message#OneLine(a:state.label), 'RevueCardBody')
  let coverage = printf('%d entries loaded%s · newest first', len(a:state.items), has_key(a:state, 'total') ? ' / ' . a:state.total : '')
  call s:Append(view, 'Read-only · ' . coverage . (a:state.complete ? ' · all reported' : ' · partial'), 'RevueCardMeta')
  if !empty(a:state.scope) | call s:Append(view, a:state.scope, 'RevueCardMeta') | endif
  if a:state.loading
    call s:Append(view, 'Loading edit history… :RevueCancelMessageHistory', 'RevueCardAction')
  elseif !empty(a:state.error)
    call s:Append(view, 'History unavailable: ' . revue#message#OneLine(a:state.error), 'RevueCardAction')
  elseif a:state.complete && empty(a:state.items)
    call s:Append(view, 'No edits reported by this backend.', 'RevueCardMeta')
  endif
  for item in reverse(copy(a:state.items))
    call s:Append(view, '', 'RevueCardBorder')
    let first = len(view.lines) + 1
    let actor = empty(item.actor) ? 'editor unavailable' : revue#message#OneLine(item.actor)
    let date = empty(item.created) ? 'Time unavailable' : revue#message#OneLine(item.created)
    call s:Append(view, revue#message#OneLine(item.title) . ' · ' . actor . ' · ' . date, 'RevueCardHeader')
    if item.content_state ==# 'available'
      " Literal recorded text: do not reinterpret GitHub content as a patch or
      " Markdown suggestion, or insert wrapping/padding into copied body text.
      for line in split(item.body, "\n", 1) | call s:Append(view, line, 'RevueCardBody') | endfor
    else
      call s:Append(view, item.content_state ==# 'redacted' ? 'Revision content was redacted; it is not reconstructed.' : 'Revision content is unavailable.', 'RevueCardMeta')
    endif
    if !shared
      call s:Append(view, revue#message#OneLine(item.provenance), 'RevueCardMeta')
      for detail in item.details | call s:Append(view, revue#message#OneLine(detail), 'RevueCardMeta') | endfor
    endif
    for row in range(first, len(view.lines)) | let view.rows[string(row)] = {'id': item.id, 'first': first, 'last': len(view.lines)} | endfor
  endfor
  if shared && (!empty(source) || !empty(details))
    call s:Append(view, '', 'RevueCardBorder')
    call s:Append(view, 'Source details · all loaded revisions', 'RevueCardHeader')
    if !empty(source) | call s:Append(view, revue#message#OneLine(source), 'RevueCardMeta') | endif
    for detail in details | call s:Append(view, revue#message#OneLine(detail), 'RevueCardMeta') | endfor
  endif
  return view
endfunction
