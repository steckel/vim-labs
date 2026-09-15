" Append complete discussion units without changing source or draft identity.
function! revue#feedback#Availability(session) abort
  if !empty(get(a:session, 'refresh_read', {})) | return 'Finish or cancel the current refresh before loading older feedback.' | endif
  let snapshot = a:session.snapshot
  let rule = get(get(snapshot, 'capabilities', {}), 'feedback_page', {})
  if !get(rule, 'enabled', 0)
    let reason = get(rule, 'reason', '')
    return empty(reason) ? 'This backend does not provide incremental feedback.' : reason
  endif
  let page = get(snapshot, 'feedback', {})
  if type(page) != v:t_dict || type(get(page, 'cursor', 0)) != v:t_string || empty(page.cursor)
    for name in ['threads', 'conversation']
      if revue#inventory#Entry(snapshot, name).state !=# 'complete'
        return 'No continuation is available; refresh the review or inspect the backend.'
      endif
    endfor
    return 'All available feedback is loaded.'
  endif
  if get(a:session, 'busy', 0) | return 'Wait for the review refresh.' | endif
  if get(get(a:session, 'feedback_read', {}), 'loading', 0) | return 'Feedback is already loading.' | endif
  return ''
endfunction

function! revue#feedback#Lines(session) abort
  if !get(get(get(a:session.snapshot, 'capabilities', {}), 'feedback_page', {}), 'enabled', 0) && !get(get(get(a:session.snapshot, 'capabilities', {}), 'feedback_lookup', {}), 'enabled', 0) | return [] | endif
  let state = get(a:session, 'feedback_read', {})
  let lines = []
  if get(state, 'snapshot', '') ==# a:session.snapshot.snapshot
    if get(state, 'loading', 0)
      call add(lines, (get(state, 'mode', '') ==# 'lookup' ? 'Loading selected discussion…' : 'Loading more feedback…') . ' :RevueCancelFeedback keeps existing discussions.')
    elseif !empty(get(state, 'error', ''))
      call add(lines, (get(state, 'mode', '') ==# 'lookup' ? 'Discussion unavailable: ' : 'Feedback page unavailable: ') . revue#message#OneLine(state.error))
    endif
  endif
  if !empty(get(get(a:session.snapshot, 'feedback', {}), 'cursor', ''))
    call add(lines, 'More feedback available · :RevueLoadMoreFeedback')
  endif
  return lines
endfunction

function! s:Messages(messages) abort
  if type(a:messages) != v:t_list | return 0 | endif
  let seen = {}
  for message in a:messages
    if type(message) != v:t_dict | return 0 | endif
    for field in ['id', 'author', 'body', 'created']
      if type(get(message, field, 0)) != v:t_string | return 0 | endif
    endfor
    if empty(message.id) || type(get(message, 'kind', 'comment')) != v:t_string | return 0 | endif
    let key = revue#activity#Key('', message)
    if has_key(seen, key) | return 0 | endif
    let seen[key] = 1
  endfor
  return 1
endfunction

function! revue#feedback#Merge(snapshot, data, cursor) abort
  let data = a:data
  if type(data) != v:t_dict || type(get(data, 'cursor', 0)) != v:t_string || data.cursor !=# a:cursor ||
        \ get(data, 'snapshot', '') !=# a:snapshot.snapshot || type(get(data, 'next_cursor', 0)) != v:t_string ||
        \ index([v:t_bool, v:t_number], type(get(data, 'complete', ''))) < 0 ||
        \ (type(data.complete) == v:t_number && index([0, 1], data.complete) < 0)
    throw 'Feedback page does not match this comparison or request.'
  endif
  if (data.complete && !empty(data.next_cursor)) || (!data.complete && (empty(data.next_cursor) || data.next_cursor ==# a:cursor))
    throw 'Feedback page did not advance. Refresh the review.'
  endif
  if type(get(data, 'threads', 0)) != v:t_list || !s:Messages(get(data, 'conversation', 0))
    throw 'Feedback page contains invalid discussions.'
  endif
  let seen = {}
  for thread in data.threads
    if type(thread) != v:t_dict | throw 'Invalid feedback thread.' | endif
    for field in ['id', 'path', 'side']
      if type(get(thread, field, 0)) != v:t_string | throw 'Incomplete feedback thread.' | endif
    endfor
    if empty(thread.id) || has_key(seen, thread.id) || !s:Messages(get(thread, 'comments', 0)) || empty(thread.comments)
      throw 'Feedback thread identity or messages are invalid.'
    endif
    for field in ['line', 'start']
      if type(get(thread, field, '')) != v:t_number || thread[field] < 0 | throw 'Invalid feedback anchor.' | endif
    endfor
    if index(['', 'base', 'head'], thread.side) < 0 || thread.start > thread.line | throw 'Invalid feedback anchor.' | endif
    if index([v:t_number, v:t_bool], type(get(thread, 'outdated', ''))) < 0 | throw 'Missing feedback anchor state.' | endif
    let seen[thread.id] = 1
  endfor
  let snapshot = deepcopy(a:snapshot)
  let added = 0
  for name in ['threads', 'conversation']
    let positions = {}
    for index in range(len(snapshot[name]))
      let item = snapshot[name][index]
      let positions[name ==# 'threads' ? item.id : revue#activity#Key('', item)] = index
    endfor
    for item in data[name]
      let key = name ==# 'threads' ? item.id : revue#activity#Key('', item)
      if has_key(positions, key)
        " The backend supplies complete units, including current message metadata.
        let snapshot[name][positions[key]] = deepcopy(item)
      else
        call add(snapshot[name], deepcopy(item))
        let added += 1
      endif
    endfor
  endfor
  let looked_up = get(get(a:snapshot, 'feedback', {}), 'lookups', [])
  let lookup_overlap = empty(data.conversation) && !empty(data.threads) && empty(filter(copy(data.threads), {_, t -> index(looked_up, t.id) < 0}))
  if !data.complete && added == 0 && !lookup_overlap | throw 'Feedback page contains no additional discussions. Refresh the review.' | endif
  if has_key(data, 'pending_reviews')
    let snapshot.pending_reviews = revue#pending#Merge(snapshot, data.pending_reviews)
  endif
  let snapshot.feedback = {'cursor': data.next_cursor}
  let page_ids = map(copy(data.threads), {_, t -> t.id})
  let remaining = filter(copy(looked_up), {_, id -> index(page_ids, id) < 0})
  if !empty(remaining) | let snapshot.feedback.lookups = remaining | endif
  let inventory = get(data, 'inventory', {})
  if type(inventory) != v:t_dict | throw 'Invalid feedback coverage.' | endif
  let snapshot.inventory = get(snapshot, 'inventory', {})
  for name in ['threads', 'conversation', 'thread_state']
    if has_key(inventory, name)
      let snapshot.inventory[name] = deepcopy(inventory[name])
    elseif name !=# 'thread_state'
      let snapshot.inventory[name] = {'state': data.complete ? 'complete' : 'partial'}
    else
      let snapshot.inventory[name] = {'state': 'unknown', 'reason': 'Resolution coverage was not supplied for this page.'}
    endif
  endfor
  return snapshot
endfunction

function! revue#feedback#LookupSupported(snapshot, target) abort
  let rule = get(get(a:snapshot, 'capabilities', {}), 'feedback_lookup', {})
  return get(rule, 'enabled', 0) && get(a:target, 'kind', '') ==# 'thread' &&
        \ (!get(rule, 'current_only', 0) || (!has_key(a:snapshot, 'context') && !has_key(a:snapshot, 'range'))) &&
        \ (!get(rule, 'requires_token', 0) || (type(get(a:target, 'lookup', 0)) == v:t_string && !empty(a:target.lookup)))
endfunction

function! revue#feedback#LookupAvailability(session) abort
  if !empty(get(a:session, 'refresh_read', {})) || get(a:session, 'busy', 0) | return 'Finish or cancel the current refresh before loading a discussion.' | endif
  if get(get(a:session, 'feedback_read', {}), 'loading', 0) | return 'Feedback is already loading.' | endif
  return ''
endfunction

function! revue#feedback#LookupMerge(snapshot, data, target, reference) abort
  let data = a:data
  if type(data) != v:t_dict || get(data, 'key', '') !=# a:snapshot.key || get(data, 'reference', {}) !=# a:reference || get(data, 'target', {}) !=# a:target
    throw 'Discussion lookup does not match this review, source or target.'
  endif
  let thread = get(data, 'thread', {})
  if type(thread) != v:t_dict || get(thread, 'id', '') !=# a:target.thread || !s:Messages(get(thread, 'comments', 0)) ||
        \ empty(filter(copy(get(thread, 'comments', [])), {_, m -> get(m, 'id', '') ==# a:target.message && get(m, 'kind', 'comment') ==# a:target.message_kind}))
    throw 'The requested message is unavailable in the returned discussion.'
  endif
  " Reuse complete-unit validation, then restore the independent page inventory.
  let result = revue#feedback#Merge(a:snapshot, {'snapshot': a:snapshot.snapshot, 'cursor': 'lookup', 'next_cursor': '', 'complete': v:true,
        \ 'threads': [thread], 'conversation': []}, 'lookup')
  let result.feedback = deepcopy(get(a:snapshot, 'feedback', {}))
  let result.inventory = deepcopy(get(a:snapshot, 'inventory', {}))
  if empty(filter(copy(a:snapshot.threads), {_, t -> t.id ==# thread.id}))
    let result.feedback.lookups = get(result.feedback, 'lookups', []) + [thread.id]
    for name in ['threads', 'thread_state']
      if get(get(result.inventory, name, {}), 'state', '') ==# 'complete'
        let result.inventory[name] = {'state': 'unknown', 'reason': 'Targeted lookup found additional feedback. Refresh for full coverage.'}
      endif
    endfor
  endif
  return result
endfunction
