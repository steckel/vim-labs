" Backend-neutral, read-only observations. Never derive permission to merge.
function! revue#readiness#Init(session) abort
  if !has_key(a:session, 'readiness')
    let a:session.readiness = {'data': {}, 'loading': 0, 'requested': 0, 'serial': 0, 'error': '', 'seen': []}
  endif
endfunction

function! revue#readiness#Reason(session) abort
  let rule = get(get(a:session.snapshot, 'capabilities', {}), 'readiness', {})
  if !get(rule, 'enabled', 0)
    let reason = get(rule, 'reason', '')
    return empty(reason) ? 'This backend does not provide checks or review requirements.' : reason
  endif
  if a:session.snapshot.snapshot !=# a:session.latest_comparison || has_key(a:session.snapshot, 'context') || has_key(a:session.snapshot, 'range')
    return 'Open the latest comparison before loading current review readiness.'
  endif
  return ''
endfunction

function! revue#readiness#Apply(state, data, reference, cursor, reset) abort
  let data = a:data
  if type(data) != v:t_dict || type(get(data, 'reference', 0)) != v:t_dict || data.reference !=# a:reference
    return 'Readiness response does not match the requested comparison.'
  endif
  for field in ['head', 'base_tip', 'observed_at', 'url', 'scope', 'cursor', 'next_cursor']
    if type(get(data, field, 0)) != v:t_string | return 'Incomplete readiness metadata.' | endif
  endfor
  if empty(data.head) || empty(data.base_tip) || empty(data.observed_at) || data.cursor !=# a:cursor ||
        \ type(get(data, 'complete', 0)) != v:t_bool || type(get(data, 'total', '')) != v:t_number || data.total < 0 ||
        \ type(get(data, 'checks', 0)) != v:t_list || type(get(data, 'facts', 0)) != v:t_list
    return 'Invalid readiness page.'
  endif
  if (data.complete && !empty(data.next_cursor)) || (!data.complete && (empty(data.next_cursor) || data.next_cursor ==# a:cursor || (!a:reset && index(a:state.seen, data.next_cursor) >= 0)))
    return 'Readiness pagination did not advance. Reload readiness.'
  endif
  let ids = {}
  for fact in data.facts
    if type(fact) != v:t_dict | return 'Invalid readiness fact.' | endif
    for field in ['id', 'name', 'value', 'detail', 'url']
      if type(get(fact, field, 0)) != v:t_string | return 'Incomplete readiness fact.' | endif
    endfor
    if empty(fact.id) || has_key(ids, fact.id) | return 'Repeated readiness fact.' | endif
    let ids[fact.id] = 1
  endfor
  let ids = {}
  for check in data.checks
    if type(check) != v:t_dict | return 'Invalid check.' | endif
    for field in ['id', 'name', 'state', 'detail', 'url']
      if type(get(check, field, 0)) != v:t_string | return 'Incomplete check.' | endif
    endfor
    if empty(check.id) || has_key(ids, check.id) || index(['pending', 'passed', 'failed', 'cancelled', 'skipped', 'neutral', 'unknown'], check.state) < 0 ||
          \ !has_key(check, 'required') || index([v:t_bool, v:t_none], type(check.required)) < 0
      return 'Invalid check identity or state.'
    endif
    let ids[check.id] = 1
  endfor
  let prior = a:state.data
  if !a:reset && (empty(prior) || data.head !=# prior.head || data.base_tip !=# prior.base_tip || data.reference !=# prior.reference)
    return 'Readiness branches changed between pages. Reload readiness.'
  endif
  let checks = a:reset ? [] : deepcopy(prior.checks)
  let existing = {}
  for item in checks | let existing[item.id] = 1 | endfor
  " Changing inventories must not silently drop or duplicate a check.
  if !empty(filter(copy(data.checks), {_, item -> has_key(existing, item.id)}))
    return 'Check inventory overlaps earlier pages. Reload readiness.'
  endif
  call extend(checks, deepcopy(data.checks))
  if data.total < len(checks) || (data.complete && data.total != len(checks)) || (!data.complete && empty(data.checks))
    return 'Check inventory changed or is incomplete. Reload readiness.'
  endif
  let a:state.data = deepcopy(data)
  let a:state.data.checks = checks
  let a:state.seen = (a:reset ? [] : a:state.seen) + [a:cursor]
  return ''
endfunction

function! revue#readiness#View(session) abort
  let state = a:session.readiness
  let data = state.data
  let lines = ['# Review readiness', ':ReviewReloadReadiness · :ReviewMoreChecks · :ReviewClose',
        \ 'gx opens selected details · gy copies link · :ReviewCancelReadiness',
        \ 'Reported checks · policy coverage may be incomplete']
  if state.loading | call add(lines, 'Loading checks… previous observations remain readable.')
  elseif !empty(state.error) | call add(lines, 'Readiness: ' . revue#message#OneLine(state.error)) | endif
  let view = {'lines': lines, 'rows': {}}
  if empty(data)
    if !state.loading | call add(lines, 'No readiness observations loaded.') | endif
    return view
  endif
  let stale = a:session.snapshot.snapshot !=# a:session.latest_comparison || data.head !=# a:session.snapshot.head || data.reference !=# revue#comparisons#Reference(a:session.snapshot) ||
        \ (!empty(get(a:session.snapshot, 'base_tip', '')) && data.base_tip !=# a:session.snapshot.base_tip)
  call add(lines, stale ? 'STALE for the selected comparison. Refresh the review, then reload readiness.' : 'Observed for the selected head; reload to check for changes.')
  call extend(lines, ['Head: ' . revue#message#OneLine(data.head), 'Observed: ' . revue#message#OneLine(data.observed_at)])
  let view.rows[string(len(lines))] = {'id': 'source', 'first': len(lines), 'last': len(lines), 'url': data.url}
  for fact in data.facts
    call add(lines, revue#message#OneLine(fact.name) . ': ' . revue#message#OneLine(fact.value))
    let row = len(lines)
    let view.rows[string(row)] = {'id': 'fact:' . fact.id, 'first': row, 'last': row, 'url': fact.url}
  endfor
  call extend(lines, ['', printf('## Checks · %d/%d reported loaded%s', len(data.checks), data.total, data.complete ? '' : ' · more available')])
  if empty(data.checks) | call add(lines, 'No checks reported. This does not mean no checks are required.') | endif
  for check in data.checks
    let required = type(check.required) == v:t_none ? 'requirement unknown' : check.required ? 'required' : 'not required'
    call add(lines, '[' . toupper(check.state) . ' · ' . required . '] ' . revue#message#OneLine(check.name))
    let first = len(lines)
    if !empty(check.detail) | call add(lines, '  ' . revue#message#OneLine(check.detail)) | endif
    for row in range(first, len(lines))
      let view.rows[string(row)] = {'id': 'check:' . check.id, 'first': first, 'last': len(lines), 'url': check.url}
    endfor
  endfor
  call extend(lines, ['', revue#message#OneLine(data.scope)])
  for fact in data.facts
    if !empty(fact.detail) | call add(lines, revue#message#OneLine(fact.name) . ': ' . revue#message#OneLine(fact.detail)) | endif
  endfor
  call add(lines, 'Base tip: ' . revue#message#OneLine(data.base_tip))
  return view
endfunction
