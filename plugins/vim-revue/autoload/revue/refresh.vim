" Keep a coherent displayed inventory while an explicit refresh reads pages.
function! revue#refresh#Keys(snapshot) abort
  let keys = {}
  for entry in revue#activity#Messages(a:snapshot) | let keys[entry.key] = 1 | endfor
  for review in get(get(a:snapshot, 'pending_reviews', {}), 'items', [])
    for target in get(review, 'comments', [])
      let keys[revue#activity#Key(target.thread, {'id': target.message, 'kind': target.message_kind})] = 1
    endfor
  endfor
  return keys
endfunction

function! revue#refresh#Validate(snapshot) abort
  if type(a:snapshot) != v:t_dict | throw 'Invalid refreshed review.' | endif
  for key in ['snapshot', 'head', 'base']
    if type(get(a:snapshot, key, 0)) != v:t_string || empty(a:snapshot[key]) | throw 'Missing refreshed comparison identity.' | endif
  endfor
  if type(get(a:snapshot, 'files', 0)) != v:t_list | throw 'Invalid refreshed file inventory.' | endif
  let cursor = get(get(a:snapshot, 'feedback', {}), 'cursor', '')
  let empty = extend(deepcopy(a:snapshot), {'threads': [], 'conversation': []})
  " Reuse complete-thread/message validation; retain the provider's other metadata.
  call revue#feedback#Merge(empty, {'snapshot': a:snapshot.snapshot, 'cursor': '', 'next_cursor': cursor,
        \ 'complete': empty(cursor), 'threads': get(a:snapshot, 'threads', 0), 'conversation': get(a:snapshot, 'conversation', 0)}, '')
endfunction

function! revue#refresh#Missing(state) abort
  let present = revue#refresh#Keys(a:state.candidate)
  return len(filter(copy(a:state.required), {key, _ -> !has_key(present, key)}))
endfunction

function! revue#refresh#Ready(state) abort
  " Another source is observed as a new comparison, never silently selected.
  if a:state.candidate.snapshot !=# a:state.comparison | return 1 | endif
  return empty(get(get(a:state.candidate, 'feedback', {}), 'cursor', '')) || revue#refresh#Missing(a:state) == 0
endfunction
