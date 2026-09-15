" Local delivery/read metadata. Conversation bodies remain backend-owned.
function! revue#activity#Key(thread, message) abort
  let id = get(a:message, 'id', '')
  return empty(id) ? '' : json_encode([a:thread, get(a:message, 'kind', 'comment'), id])
endfunction

function! revue#activity#Messages(snapshot) abort
  let entries = []
  for thread in a:snapshot.threads
    for message in thread.comments
      let key = revue#activity#Key(thread.id, message)
      if !empty(key) | call add(entries, {'key': key, 'thread': thread.id, 'path': thread.path, 'message': message}) | endif
    endfor
  endfor
  for message in a:snapshot.conversation
    let key = revue#activity#Key('', message)
    if !empty(key) | call add(entries, {'key': key, 'thread': '', 'path': '', 'message': message}) | endif
  endfor
  return entries
endfunction

function! revue#activity#Observe(session, snapshot) abort
  let state = a:session.read_state
  let baseline = !get(state, 'initialized', 0)
  let present = {}
  for entry in revue#activity#Messages(a:snapshot)
    let present[entry.key] = 1
    if !baseline && !has_key(state.known, entry.key)
      let state.unread[entry.key] = 1
    endif
    let state.known[entry.key] = 1
  endfor
  " Missing entries cannot be navigated in this snapshot. Retain the known ID
  " so switching an immutable comparison later does not manufacture new mail.
  call filter(state.unread, {key, _ -> has_key(present, key)})
  let state.initialized = 1
endfunction

function! revue#activity#Unread(session, ...) abort
  let entries = filter(revue#activity#Messages(a:session.snapshot), {_, entry -> has_key(a:session.read_state.unread, entry.key)})
  return a:0 ? filter(entries, {_, entry -> entry.path ==# a:1}) : entries
endfunction

function! revue#activity#Target(draft) abort
  if a:draft.kind ==# 'apply_suggestion' | return 'apply suggestion · ' . a:draft.path . ' · message ' . a:draft.message | endif
  if a:draft.kind ==# 'participant_run' | return revue#runtime#Label(a:draft) . ' · ' . a:draft.participant.label | endif
  if a:draft.kind ==# 'cancel_assignment' | return 'cancel assignment ' . a:draft.assignment | endif
  if a:draft.kind ==# 'assignment' | return printf('%d messages → %s', len(a:draft.targets), a:draft.participant.label) | endif
  if a:draft.kind ==# 'refresh' | return 'review discussions' | endif
  if a:draft.kind ==# 'discard_pending' | return 'discard pending review ' . a:draft.pending_review | endif
  if a:draft.kind ==# 'submit_pending' | return 'pending review ' . a:draft.pending_review . ' · ' . a:draft.event | endif
  if a:draft.kind ==# 'service_viewed' | return a:draft.path . ' · service ' . (a:draft.viewed ? 'viewed' : 'unviewed') | endif
  if a:draft.kind ==# 'reaction' | return a:draft.message_kind . ' message ' . a:draft.message . ' · ' . (a:draft.present ? 'add ' : 'remove ') . a:draft.reaction_label | endif
  if a:draft.kind ==# 'delete_message' | return 'delete ' . a:draft.message_kind . ' message ' . a:draft.message . (empty(a:draft.thread) ? ' · conversation' : ' · thread ' . a:draft.thread) | endif
  if a:draft.kind ==# 'edit' | return a:draft.message_kind . ' message ' . a:draft.message . (empty(a:draft.thread) ? ' · conversation' : ' · thread ' . a:draft.thread) | endif
  if a:draft.kind ==# 'batch' | return len(a:draft.items) . ' selected items' | endif
  if a:draft.kind ==# 'file_comment' | return a:draft.path . ' · whole file' | endif
  if a:draft.kind ==# 'capture' | return 'saved workspace files · ' . (a:draft.untracked ? 'include untracked' : 'exclude untracked') | endif
  if a:draft.kind ==# 'comment'
    return a:draft.path . ' · ' . a:draft.side . ':' . a:draft.start . '-' . a:draft.end
  endif
  return has_key(a:draft, 'thread') ? 'thread ' . a:draft.thread : get(a:draft, 'event', 'review conversation')
endfunction

function! s:Receipt(source) abort
  let receipt = {}
  for key in ['applied', 'result_snapshot', 'capture_error']
    if has_key(a:source, key) | let receipt[key] = deepcopy(a:source[key]) | endif
  endfor
  for key in ['viewed', 'path', 'review_id', 'id', 'url', 'draft', 'thread', 'resolved', 'observed', 'recovered', 'snapshot', 'previous_snapshot', 'changed', 'message', 'message_kind', 'actor', 'reaction', 'present', 'pending_review', 'pending_mode', 'event', 'discarded', 'deleted', 'delete_scope', 'expected_version', 'assignment', 'participant', 'reference', 'targets', 'cancelled', 'version']
    if has_key(a:source, key) | let receipt[key] = deepcopy(a:source[key]) | endif
  endfor
  return receipt
endfunction

function! revue#activity#Record(session, draft, outcome, message, receipt) abort
  let operation = get(a:draft, 'id', '')
  let sequence = empty(a:session.activity) ? 1 : get(a:session.activity[-1], 'sequence', 0) + 1
  " Acceptance recovered twice is still one outcome for this operation.
  if index(['accepted', 'observed'], a:outcome) >= 0
    call filter(a:session.activity, {_, e -> !(e.operation ==# operation && index(['accepted', 'observed'], e.outcome) >= 0)})
  endif
  let receipt = s:Receipt(a:receipt)
  if has_key(a:receipt, 'items') | let receipt.items = map(copy(a:receipt.items), {_, item -> s:Receipt(item)}) | endif
  let targets = map(copy(get(a:draft, 'items', [])), {_, item -> {'operation': item.id, 'kind': item.kind, 'target': revue#activity#Target(item)}})
  call add(a:session.activity, {'sequence': sequence, 'operation': operation, 'kind': a:draft.kind,
        \ 'target': revue#activity#Target(a:draft), 'comparison': get(a:draft, 'snapshot', a:session.snapshot.snapshot),
        \ 'outcome': a:outcome, 'message': a:message, 'receipt': receipt, 'targets': targets,
        \ 'at': strftime('%Y-%m-%d %H:%M:%S')})
  let limit = max([1, get(g:, 'revue_activity_limit', 200)])
  if len(a:session.activity) > limit | call remove(a:session.activity, 0, len(a:session.activity) - limit - 1) | endif
endfunction

function! revue#activity#View(session) abort
  let refresh = a:session.refresh_state
  let lines = ['# Review activity · ' . get(a:session.snapshot, 'display_id', a:session.snapshot.key),
        \ ':RevueOpenOperation · :RevueCopyReceipt · :RevueNextUnread · :RevueClose',
        \ printf('%d retained outcomes · %d pending operations · %d new messages', len(a:session.activity), len(a:session.drafts), len(revue#activity#Unread(a:session))),
        \ 'Local delivery history; conversation content belongs to the review backend.',
        \ 'Last refresh: ' . get(refresh, 'status', 'not requested') . ' · ' . get(refresh, 'at', ''),
        \ 'Last successful refresh: ' . get(refresh, 'success_at', 'not recorded')]
  if !empty(get(refresh, 'error', '')) | call add(lines, 'Refresh error: ' . refresh.error) | endif
  if !empty(get(a:session, 'persistence_error', '')) | call add(lines, 'NOT SAVED: ' . a:session.persistence_error) | endif
  let view = {'lines': lines, 'operations': {}}
  for draft in a:session.drafts
    call add(view.lines, '')
    call add(view.lines, '## Pending · ' . draft.kind . ' · ' . draft.state)
    call add(view.lines, revue#activity#Target(draft))
    call add(view.lines, 'Operation ' . draft.id . ' · :RevueOpenOperation to inspect')
    let first = len(view.lines) - 2
    for row in range(first, len(view.lines)) | let view.operations[string(row)] = {'operation': draft.id, 'receipt': {}} | endfor
  endfor
  for entry in reverse(copy(a:session.activity))
    call add(view.lines, '')
    let first = len(view.lines) + 1
    call extend(view.lines, ['## ' . toupper(entry.outcome) . ' · ' . entry.kind . ' · ' . entry.at,
          \ entry.target, entry.message, 'Comparison ' . entry.comparison])
    if !empty(entry.operation) | call add(view.lines, 'Operation ' . entry.operation) | endif
    if !empty(get(entry.receipt, 'id', '')) | call add(view.lines, 'Receipt ' . entry.receipt.id) | endif
    if !empty(get(entry.receipt, 'url', '')) | call add(view.lines, entry.receipt.url) | endif
    if !empty(get(entry.receipt, 'items', [])) | call add(view.lines, printf('%d item receipts retained', len(entry.receipt.items))) | endif
    for target in get(entry, 'targets', [])
      call add(view.lines, '  ' . target.kind . ' · ' . target.target . ' · operation ' . target.operation)
    endfor
    for row in range(first, len(view.lines)) | let view.operations[string(row)] = entry | endfor
  endfor
  if empty(a:session.activity) && empty(a:session.drafts) | call add(view.lines, 'No delivery outcomes recorded yet.') | endif
  return view
endfunction
