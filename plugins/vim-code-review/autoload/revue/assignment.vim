" Assignment presentation stays independent of the store and participant runtime.
function! revue#assignment#Participants() abort
  let configured = get(g:, 'revue_participants', [])
  if type(configured) != v:t_list | return [] | endif
  let result = []
  let ids = []
  for item in configured
    if type(item) != v:t_dict | continue | endif
    let id = get(item, 'id', '')
    let label = get(item, 'label', '')
    if type(id) != v:t_string || type(label) != v:t_string || empty(trim(id)) || empty(trim(label)) || strchars(id) > 200 || strchars(label) > 100 || id =~# '[\r\n]' || label =~# '[\r\n]' || index(ids, id) >= 0 | continue | endif
    call add(ids, id)
    call add(result, {'id': id, 'label': label})
  endfor
  return result
endfunction

function! revue#assignment#Init(session) abort
  if !has_key(a:session, 'assignments')
    let a:session.assignments = {'items': [], 'requested': 0, 'loading': 0, 'serial': 0, 'error': '', 'detail': ''}
  endif
endfunction

function! revue#assignment#Restore(view, selected, rows) abort
  let view = deepcopy(a:view)
  if empty(a:selected) | return view | endif
  for row in sort(keys(a:rows), 'n')
    let current = a:rows[row]
    if current.assignment ==# a:selected.assignment && current.message ==# a:selected.message
      let delta = current.start - get(a:selected, 'start', view.lnum)
      let view.topline = max([1, view.topline + delta])
      let view.lnum = min([current.end, max([current.start, view.lnum + delta])])
      return view
    endif
  endfor
  let view.lnum = 1
  let view.topline = 1
  return view
endfunction

function! revue#assignment#Find(session, id) abort
  return get(filter(copy(get(get(a:session, 'assignments', {}), 'items', [])), {_, item -> item.id ==# a:id}), 0, {})
endfunction

function! s:ReferenceValid(reference) abort
  if type(a:reference) != v:t_dict || sort(keys(a:reference)) !=# sort(['snapshot', 'base', 'head', 'base_tip']) | return 0 | endif
  for value in values(a:reference)
    if type(value) != v:t_string || empty(value) | return 0 | endif
  endfor
  return 1
endfunction

function! revue#assignment#Apply(session, data) abort
  let backend = get(a:session.snapshot, 'backend', {})
  try
    for [field, key] in [['backend', 'id'], ['connection', 'connection'], ['review', 'review']]
      if empty(get(backend, key, '')) || get(a:data, field, '') !=# backend[key] | throw 'Assignment response belongs to another review.' | endif
    endfor
    if type(get(a:data, 'items', 0)) != v:t_list | throw 'Assignment inventory is unavailable.' | endif
    let seen = []
    for item in a:data.items
      for [field, key] in [['backend', 'id'], ['connection', 'connection'], ['review', 'review']]
        if get(item, field, '') !=# backend[key] | throw 'Assignment identity does not match this review.' | endif
      endfor
      for field in ['id', 'version', 'created']
        if type(get(item, field, 0)) != v:t_string || empty(item[field]) | throw 'Incomplete assignment identity.' | endif
      endfor
      if index(seen, item.id) >= 0 | throw 'Duplicate assignment identity.' | endif
      call add(seen, item.id)
      if type(get(item, 'participant', 0)) != v:t_dict || type(get(item.participant, 'id', 0)) != v:t_string || empty(item.participant.id) || type(get(item.participant, 'label', 0)) != v:t_string || empty(item.participant.label) | throw 'Assignment participant is unavailable.' | endif
      if type(get(item, 'cancelled', 0)) != v:t_bool || !s:ReferenceValid(get(item, 'reference', {})) || type(get(item, 'targets', 0)) != v:t_list || empty(item.targets) || len(item.targets) > 50 || type(get(item, 'outcomes', 0)) != v:t_dict | throw 'Incomplete assignment state.' | endif
      let messages = []
      for target in item.targets
        for field in ['thread', 'message', 'message_kind', 'expected_version', 'original_body', 'author']
          if type(get(target, field, 0)) != v:t_string || (index(['original_body', 'author'], field) < 0 && empty(target[field])) | throw 'Incomplete assigned message.' | endif
        endfor
        if index(messages, target.message) >= 0 | throw 'Duplicate assigned message.' | endif
        call add(messages, target.message)
        let outcome = get(item.outcomes, target.message, {})
        if index(['assigned', 'working', 'needs_input', 'addressed', 'failed'], get(outcome, 'state', '')) < 0 | throw 'Unknown assignment outcome.' | endif
        for field in ['summary', 'run_id']
          if has_key(outcome, field) && type(outcome[field]) != v:t_string | throw 'Invalid outcome details.' | endif
        endfor
        if has_key(outcome, 'result_reference') && !s:ReferenceValid(outcome.result_reference) | throw 'Invalid result comparison.' | endif
      endfor
      if sort(keys(item.outcomes)) !=# sort(messages) | throw 'Outcome scope differs from selected messages.' | endif
      if has_key(item, 'runs')
        if type(item.runs) != v:t_list | throw 'Invalid runtime inventory.' | endif
        let run_ids = []
        for run in item.runs
          if !revue#runtime#Valid(run, item) || index(run_ids, run.id) >= 0 | throw 'Invalid runtime state.' | endif
          call add(run_ids, run.id)
        endfor
      endif
    endfor
    let a:session.assignments.items = deepcopy(a:data.items)
    return ''
  catch
    return 'Assignment read rejected: ' . v:exception . ' Loaded assignments retained.'
  endtry
endfunction

function! revue#assignment#View(session, detail) abort
  let state = a:session.assignments
  let lines = [empty(a:detail) ? '# Assignments' : '# Assignment outcomes',
        \ (state.loading ? 'Loading assignments… existing results retained' : empty(state.error) ? 'Saved locally · reload for updates' : state.error) . ' · addressed ≠ resolved', '']
  let rows = {}
  let items = empty(a:detail) ? state.items : filter(copy(state.items), {_, item -> item.id ==# a:detail})
  if empty(items) | call add(lines, state.requested && !state.loading ? 'No assignments reported for this view.' : 'Waiting for assignments…') | endif
  for item in items
    let first = len(lines) + 1
    call extend(lines, ['## ' . item.participant.label . (item.cancelled ? ' · Cancelled' : ' · Active assignment'),
          \ printf('%d messages · created %s · #%s', len(item.targets), strpart(item.created, 0, 10), strcharpart(item.id, 0, 8))])
    let run = get(get(item, 'runs', []), -1, {})
    if !empty(run)
      call add(lines, 'Runtime: ' . run.state . (run.process_held ? ' · process still owned' : ''))
      if !empty(a:detail)
        if !empty(run.error) | call add(lines, run.error) | endif
        if !empty(run.summary) | call extend(lines, ['Run summary:'] + split(run.summary, "\n", 1)) | endif
        call add(lines, 'Process completion does not resolve or approve feedback.')
      endif
    endif
    if empty(a:detail)
      let counts = {}
      for outcome in values(item.outcomes) | let counts[outcome.state] = get(counts, outcome.state, 0) + 1 | endfor
      call add(lines, join(map(sort(keys(counts)), {_, name -> name . ': ' . counts[name]}), ' · '))
      for row in range(first, len(lines)) | let rows[string(row)] = {'assignment': item.id, 'message': '', 'start': first, 'end': len(lines)} | endfor
    else
      call add(lines, 'Assigned source ' . strpart(item.reference.base, 0, 12) . ' → ' . strpart(item.reference.head, 0, 12))
      if item.cancelled | call add(lines, 'MCP access revoked. Existing replies retained; process status is unknown.') | endif
      for target in item.targets
        let first = len(lines) + 1
        let thread = get(filter(copy(a:session.snapshot.threads), {_, t -> t.id ==# target.thread}), 0, {})
        let outcome = item.outcomes[target.message]
        call extend(lines, ['', '## ' . substitute(outcome.state, '_', ' ', 'g') . ' · ' . get(thread, 'path', 'Thread ' . target.thread),
              \ target.author . ' · original feedback', ''] + split(target.original_body, "\n", 1))
        if has_key(outcome, 'summary') | call extend(lines, ['', 'Outcome:'] + split(outcome.summary, "\n", 1)) | endif
        if has_key(outcome, 'result_reference') | call add(lines, 'Result source: ' . strpart(outcome.result_reference.head, 0, 12)) | endif
        for row in range(first, len(lines)) | let rows[string(row)] = {'assignment': item.id, 'message': target.message, 'start': first, 'end': len(lines)} | endfor
      endfor
    endif
    call add(lines, '')
  endfor
  let decorations = map(copy(lines), {_, text -> {'text': text, 'type': text =~# '^#' ? 'RevueCardHeader' : 'RevueCardBody'}})
  return {'lines': lines, 'rows': rows, 'decorations': decorations}
endfunction

" Exact metadata is ordinary, copyable text, separate from outcome reading.
" The caller freezes the loaded record; this is not a current-state request.
function! revue#assignment#Details(item, target) abort
  let item = a:item
  let lines = ['# Assignment details', 'Loaded record · return and reload outcomes for updates',
        \ 'Participant: ' . item.participant.label, 'Participant ID: ' . item.participant.id,
        \ 'Assignment: ' . item.id, 'Version: ' . item.version, 'Created: ' . item.created,
        \ 'Backend: ' . item.backend, 'Connection: ' . item.connection, 'Review: ' . item.review,
        \ 'Access: ' . (item.cancelled ? 'revoked' : 'active'),
        \ 'Addressed is the participant’s claim; resolution and process state are separate.']
  call extend(lines, s:ReferenceDetails('Assigned source', item.reference))
  for run in get(item, 'runs', [])
    call extend(lines, ['', '## Runtime ' . run.id, 'State: ' . run.state,
          \ 'Adapter: ' . run.runtime.adapter, 'Executable: ' . run.runtime.executable,
          \ 'Workspace: ' . run.workspace, 'Sandbox: ' . run.runtime.sandbox,
          \ 'Native session: ' . run.thread, 'Process ownership: ' . (run.process_held ? 'held' : 'not held'),
          \ 'Execution started: ' . (run.execution_started ? 'yes' : 'no')])
    if !empty(run.error) | call add(lines, 'Error: ' . run.error) | endif
  endfor
  let targets = empty(a:target) ? item.targets : [a:target]
  for target in targets
    let outcome = item.outcomes[target.message]
    call extend(lines, ['', '## Message ' . target.message, 'Thread: ' . target.thread,
          \ 'Kind: ' . target.message_kind, 'Assigned version: ' . target.expected_version,
          \ 'Author: ' . target.author, 'Outcome: ' . outcome.state])
    if !empty(get(outcome, 'run_id', '')) | call add(lines, 'Run: ' . outcome.run_id) | endif
    if has_key(outcome, 'result_reference') | call extend(lines, s:ReferenceDetails('Result source', outcome.result_reference)) | endif
  endfor
  return lines
endfunction

function! s:ReferenceDetails(label, reference) abort
  return ['', '## ' . a:label, 'Snapshot: ' . a:reference.snapshot,
        \ 'Base: ' . a:reference.base, 'Head: ' . a:reference.head, 'Base tip: ' . a:reference.base_tip]
endfunction

function! revue#assignment#CancelError(snapshot, draft) abort
  if !get(get(get(a:snapshot, 'capabilities', {}), 'cancel_assignment', {}), 'enabled', 0) | return 'Assignment cancellation is unavailable.' | endif
  for field in ['assignment', 'expected_version']
    if type(get(a:draft, field, 0)) != v:t_string || empty(a:draft[field]) | return 'Select a versioned assignment first.' | endif
  endfor
  return ''
endfunction

function! revue#assignment#CancelPreview(draft) abort
  return ['# Cancel assignment', a:draft.participant.label . ' · #' . a:draft.assignment,
        \ printf('%d selected messages', a:draft.count),
        \ 'Revoke this assignment’s MCP access, including reads and future replies.',
        \ 'Keep the conversation, existing replies and recorded outcomes.',
        \ 'This does not stop an operating-system process or change source or resolution.']
endfunction

function! revue#assignment#CancelReceipt(draft, receipt) abort
  if type(a:receipt) != v:t_dict || get(a:receipt, 'cancelled', 0) isnot v:true || type(get(a:receipt, 'version', 0)) != v:t_string || empty(a:receipt.version) | return 0 | endif
  for field in ['id', 'assignment', 'expected_version']
    if get(a:receipt, field, '') !=# a:draft[field] | return 0 | endif
  endfor
  return 1
endfunction

function! revue#assignment#Reference(snapshot) abort
  return {'snapshot': a:snapshot.snapshot, 'base': a:snapshot.base,
        \ 'head': a:snapshot.head, 'base_tip': get(a:snapshot, 'base_tip', a:snapshot.base)}
endfunction

function! revue#assignment#Candidates(snapshot) abort
  let result = []
  for thread in get(a:snapshot, 'threads', [])
    for message in get(thread, 'comments', [])
      if empty(get(message, 'version', '')) || get(message, 'publication', '') ==# 'pending' | continue | endif
      call add(result, {'target': {'thread': thread.id, 'message': message.id,
            \ 'message_kind': get(message, 'kind', 'comment'), 'expected_version': message.version},
            \ 'path': thread.path, 'anchor': revue#anchor#Label(thread),
            \ 'author': message.author, 'body': message.body})
    endfor
  endfor
  return result
endfunction

function! revue#assignment#Key(target) abort
  return json_encode([a:target.thread, a:target.message, a:target.message_kind])
endfunction

function! revue#assignment#Error(snapshot, draft) abort
  if !get(get(get(a:snapshot, 'capabilities', {}), 'assignment', {}), 'enabled', 0)
    return 'This backend does not support comment assignments.'
  endif
  if get(a:draft, 'reference', {}) !=# revue#assignment#Reference(a:snapshot)
    return 'The comparison changed. Prepare a new assignment after inspecting the current code.'
  endif
  if index(revue#assignment#Participants(), get(a:draft, 'participant', {})) < 0
    return 'Participant unavailable or changed. Configure g:revue_participants and prepare a new assignment.'
  endif
  let targets = get(a:draft, 'targets', [])
  if type(targets) != v:t_list || empty(targets) || len(targets) > min([50, get(a:snapshot.capabilities.assignment, 'max_targets', 50)])
    return 'Select between 1 and 50 saved line/file messages.'
  endif
  let candidates = map(revue#assignment#Candidates(a:snapshot), {_, c -> c.target})
  let seen = []
  for target in targets
    if index(candidates, target) < 0 | return 'A selected message changed or is unavailable. Prepare a new assignment.' | endif
    let key = revue#assignment#Key(target)
    if index(seen, key) >= 0 | return 'Select each message only once.' | endif
    call add(seen, key)
  endfor
  return ''
endfunction

function! revue#assignment#Preview(draft) abort
  let lines = ['# Assignment preview',
        \ 'Participant: ' . a:draft.participant.label . ' · ' . a:draft.participant.id,
        \ printf('%d selected messages · saved locally; no agent is started', len(a:draft.targets)),
        \ 'Source: ' . a:draft.reference.base . ' → ' . a:draft.reference.head,
        \ 'The participant can read these entire threads, including later replies.',
        \ 'Comments, resolution and source files are unchanged by assignment.']
  for item in a:draft.selection
    call extend(lines, ['', '## ' . item.path . ' · ' . item.anchor,
          \ item.author . ' · message #' . item.target.message, ''] + split(item.body, "\n", 1))
  endfor
  return lines
endfunction

function! revue#assignment#Receipt(draft, receipt) abort
  if type(a:receipt) != v:t_dict || type(get(a:receipt, 'assignment', 0)) != v:t_string || empty(a:receipt.assignment) | return 0 | endif
  for key in ['id', 'participant', 'reference', 'targets']
    if !has_key(a:receipt, key) || a:receipt[key] !=# a:draft[key] | return 0 | endif
  endfor
  return 1
endfunction
