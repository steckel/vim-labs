" Coverage describes the supplied data, never an inferred remote total.
function! revue#inventory#Count(snapshot, name) abort
  if a:name ==# 'private'
    return len(get(get(a:snapshot, 'pending_reviews', {}), 'items', []))
  elseif a:name ==# 'thread_state'
    return len(filter(copy(a:snapshot.threads), {_, t -> has_key(t, 'resolved') && get(get(get(t, 'comments', []), 0, {}), 'publication', '') !=# 'pending'}))
  endif
  return len(get(a:snapshot, a:name, []))
endfunction

function! revue#inventory#Entry(snapshot, name) abort
  let inventory = get(a:snapshot, 'inventory', {})
  let raw = type(inventory) == v:t_dict ? get(inventory, a:name, {}) : {}
  let loaded = revue#inventory#Count(a:snapshot, a:name)
  let result = {'state': 'unknown', 'loaded': loaded, 'reason': '', 'scope': ''}
  if type(raw) != v:t_dict | let result.reason = 'Invalid coverage metadata.' | return result | endif
  let states = ['complete', 'loading', 'partial', 'failed', 'unsupported', 'unknown']
  if index(states, get(raw, 'state', 0)) >= 0 | let result.state = raw.state | endif
  for field in ['reason', 'scope']
    if type(get(raw, field, 0)) == v:t_string | let result[field] = revue#message#OneLine(raw[field]) | endif
  endfor
  if has_key(raw, 'total')
    if type(raw.total) != v:t_number || raw.total < loaded || (result.state ==# 'complete' && raw.total != loaded)
      let result.state = 'unknown'
      let result.reason = 'Coverage count does not match loaded data.'
    else
      let result.total = raw.total
    endif
  endif
  return result
endfunction

function! revue#inventory#Lines(session, names) abort
  let labels = {'files': 'Files', 'threads': 'Threads', 'conversation': 'Conversation', 'private': 'Private reviews', 'thread_state': 'Resolution states'}
  let lines = []
  let metadata = get(a:session.snapshot, 'inventory', {})
  for name in a:names
    if index(['private', 'thread_state'], name) >= 0 && (type(metadata) != v:t_dict || !has_key(metadata, name)) | continue | endif
    let entry = revue#inventory#Entry(a:session.snapshot, name)
    let amount = string(entry.loaded) . (has_key(entry, 'total') ? '/' . entry.total : '')
    let state = entry.state ==# 'unknown' ? 'completeness unknown' : entry.state
    call add(lines, labels[name] . ': ' . amount . ' loaded · ' . state . (empty(entry.scope) ? '' : ' · ' . entry.scope))
    if !empty(entry.reason) | call add(lines, '  ' . entry.reason) | endif
    if index(['loading', 'partial', 'failed'], entry.state) >= 0 &&
          \ !(entry.state ==# 'partial' && !empty(get(get(a:session.snapshot, 'feedback', {}), 'cursor', '')))
      call add(lines, '  :RevueRefresh retries the review; loaded feedback stays readable.')
    endif
  endfor
  return lines
endfunction

function! revue#inventory#RefreshLines(session) abort
  let refresh = get(a:session, 'refresh_state', {})
  let status = get(refresh, 'status', '')
  if status ==# 'refreshing'
    return ['Refreshing review… searching previously loaded feedback. :RevueCancelRefresh cancels.']
  elseif status ==# 'partial refresh'
    return ['Refresh needs another page; searching previously loaded feedback.',
          \ '  :RevueContinueRefresh reads one page · :RevueCancelRefresh keeps this view.']
  elseif status ==# 'interrupted'
    return ['Previous refresh was interrupted. :RevueRefresh starts a new read.']
  elseif status ==# 'cancelled'
    return ['Refresh cancelled; searching previously loaded feedback. :RevueRefresh starts again.']
  elseif status ==# 'failed'
    return ['Refresh failed; previously loaded feedback retained. :RevueRefresh retries.',
          \ '  ' . revue#message#OneLine(get(refresh, 'error', 'Review unavailable.'))] +
          \ (has_key(get(a:session, 'refresh_read', {}), 'candidate') ? ['  :RevueContinueRefresh retries the page; :RevueCancelRefresh cancels.'] : [])
  elseif status ==# 'new revision available'
    return ['Newer comparison available; this view searches the displayed comparison. :RevueLatest opens latest.']
  endif
  return []
endfunction
