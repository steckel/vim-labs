" Read-only backend history. Page bodies stay in memory, not the local outbox.
function! revue#timeline#Init(session) abort
  if !has_key(a:session, 'timeline')
    let a:session.timeline = {'items': [], 'cursor': '', 'complete': 0, 'loading': 0,
          \ 'requested': 0, 'serial': 0, 'seen': [], 'scope': '', 'error': ''}
  endif
endfunction

function! revue#timeline#Apply(state, data, cursor, reset) abort
  if type(a:data) != v:t_dict | return 'Invalid timeline response.' | endif
  if type(get(a:data, 'cursor', 0)) != v:t_string || a:data.cursor !=# a:cursor || type(get(a:data, 'items', 0)) != v:t_list ||
        \ index([v:t_bool, v:t_number], type(get(a:data, 'complete', ''))) < 0 ||
        \ (type(a:data.complete) == v:t_number && index([0, 1], a:data.complete) < 0) || type(get(a:data, 'next_cursor', 0)) != v:t_string ||
        \ type(get(a:data, 'scope', 0)) != v:t_string
    return 'Timeline response does not match the requested page.'
  endif
  let next = a:data.next_cursor
  if (a:data.complete && !empty(next)) || (!a:data.complete && (empty(next) || next ==# a:cursor || (!a:reset && index(a:state.seen, next) >= 0)))
    return 'Timeline did not advance. Reload history.'
  endif
  let ids = {}
  for event in a:data.items
    if type(event) != v:t_dict | return 'Invalid timeline event.' | endif
    for field in ['id', 'kind', 'title', 'actor', 'created', 'body', 'url', 'provenance']
      if type(get(event, field, 0)) != v:t_string | return 'Timeline event fields are incomplete.' | endif
    endfor
    if empty(event.id) || has_key(ids, event.id) | return 'Timeline event identity is missing or repeated.' | endif
    let ids[event.id] = 1
    if type(get(event, 'details', 0)) != v:t_list || !empty(filter(copy(event.details), {_, value -> type(value) != v:t_string}))
      return 'Invalid timeline event details.'
    endif
    if has_key(event, 'target')
      let target = event.target
      if type(target) != v:t_dict || index(['thread', 'conversation'], get(target, 'kind', '')) < 0 | return 'Invalid event discussion target.' | endif
      for field in ['message', 'message_kind'] + (target.kind ==# 'thread' ? ['thread'] : [])
        if type(get(target, field, 0)) != v:t_string || empty(target[field]) | return 'Invalid event discussion identity.' | endif
      endfor
    endif
    if has_key(event, 'reviewed_comparison')
      let reference = event.reviewed_comparison
      if type(reference) != v:t_dict || has_key(reference, 'context')
        return 'Invalid reviewed comparison; a code excerpt is not a full comparison.'
      endif
      for field in ['snapshot', 'base', 'head']
        if type(get(reference, field, 0)) != v:t_string || empty(reference[field]) | return 'Reviewed comparison identity is incomplete.' | endif
      endfor
      for field in ['base_tip', 'head_repo', 'base_repo']
        if has_key(reference, field) && type(reference[field]) != v:t_string | return 'Invalid reviewed comparison metadata.' | endif
      endfor
      if has_key(reference, 'range') && type(reference.range) != v:t_dict | return 'Invalid reviewed range.' | endif
      if type(get(event, 'comparison_provenance', 0)) != v:t_string || empty(event.comparison_provenance)
        return 'Reviewed comparison provenance is missing.'
      endif
      if has_key(event, 'reviewed_head') && event.reviewed_head !=# reference.head | return 'Reviewed head does not match its comparison.' | endif
    endif
  endfor
  let prior = a:reset ? [] : a:state.items
  let existing = {}
  for event in prior | let existing[event.id] = 1 | endfor
  let older = filter(deepcopy(a:data.items), {_, event -> !has_key(existing, event.id)})
  if !a:reset && empty(older) && !a:data.complete | return 'This page contains no older events. Reload history.' | endif
  let a:state.items = older + prior
  let a:state.cursor = next
  let a:state.complete = a:data.complete
  let a:state.scope = revue#message#OneLine(a:data.scope)
  let a:state.seen = (a:reset ? [] : a:state.seen) + [a:cursor]
  if has_key(a:state, 'total') | call remove(a:state, 'total') | endif
  if type(get(a:data, 'total', '')) == v:t_number && a:data.total >= len(a:state.items)
    let a:state.total = a:data.total
  endif
  return ''
endfunction

function! revue#timeline#View(session) abort
  let state = a:session.timeline
  let lines = ['# Review history', ':RevueOlderEvents · :RevueReloadTimeline · :RevueCancelTimeline · :RevueClose',
        \ 'Enter opens a loaded discussion · gx opens the event link · gy copies its link',
        \ printf('%d events loaded%s · newest first', len(state.items), has_key(state, 'total') ? ' / ' . state.total . ' reported' : ''),
        \ state.scope]
  if state.loading | call add(lines, 'Loading history… existing events remain readable.')
  elseif !empty(state.error) | call add(lines, 'History unavailable: ' . revue#message#OneLine(state.error))
  elseif state.complete | call add(lines, 'Oldest available event reached. Reload to check for newer activity.')
  else | call add(lines, ':RevueOlderEvents loads more history.') | endif
  call extend(lines, revue#feedback#Lines(a:session))
  if !empty(get(get(a:session.snapshot, 'feedback', {}), 'cursor', ''))
    let targeted = !empty(filter(copy(state.items), {_, event -> revue#feedback#LookupSupported(a:session.snapshot, get(event, 'target', {}))}))
    call add(lines, targeted ? ':RevueLoadEventDiscussion fetches the selected discussion when supported; otherwise one page.' : ':RevueLoadEventDiscussion loads one feedback page and follows the selected event if found.')
  endif
  let view = {'lines': lines, 'rows': {}}
  for event in reverse(copy(state.items))
    call add(view.lines, '')
    let first = len(view.lines) + 1
    call add(view.lines, '## ' . revue#message#OneLine(event.title) . ' · ' . (empty(event.actor) ? 'actor unavailable' : revue#message#OneLine(event.actor)))
    call add(view.lines, (empty(event.created) ? 'Time unavailable' : revue#message#OneLine(event.created)) . ' · ' . revue#message#OneLine(event.provenance))
    for detail in event.details | call add(view.lines, revue#message#OneLine(detail)) | endfor
    if has_key(event, 'reviewed_comparison')
      call add(view.lines, 'Source: ' . revue#message#OneLine(event.reviewed_comparison.base) . ' → ' . revue#message#OneLine(event.reviewed_comparison.head))
      call add(view.lines, revue#message#OneLine(event.comparison_provenance) . ' · :RevueEventComparison')
    endif
    if !empty(event.body) | call extend(view.lines, [''] + split(event.body, "\n", 1)) | endif
    for row in range(first, len(view.lines)) | let view.rows[string(row)] = {'id': event.id, 'first': first, 'last': len(view.lines)} | endfor
  endfor
  if empty(state.items) && !state.loading | call add(view.lines, 'No events loaded. :RevueReloadTimeline retries; local delivery receipts are in :RevueActivity.') | endif
  return view
endfunction

function! revue#timeline#Restore(view, target, rows) abort
  let view = deepcopy(a:view)
  if empty(a:target) | return view | endif
  for row in sort(keys(a:rows), 'n')
    let target = a:rows[row]
    if target.id ==# a:target.id
      let delta = target.first - a:target.first
      let view.lnum = min([target.last, view.lnum + delta])
      let view.topline = max([1, view.topline + delta])
      return view
    endif
  endfor
  let view.lnum = 1 | let view.topline = 1
  return view
endfunction
