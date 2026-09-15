" Private queues use backend-owned single-save operations and durable steps.
function! revue#stage#Binding(snapshot) abort
  let inventory = get(a:snapshot, 'pending_reviews', {})
  if !get(inventory, 'available', 0) || empty(get(inventory, 'actor', ''))
    return {'error': 'Refresh to verify the actor and private reviews.'}
  endif
  let reviews = get(inventory, 'items', [])
  if len(reviews) > 1 | return {'error': 'Inspect the available private reviews before staging feedback.'} | endif
  let review = get(reviews, 0, {})
  return {'actor': inventory.actor, 'pending_review': get(review, 'id', ''),
        \ 'pending_head': get(review, 'head', a:snapshot.head), 'private_mode': empty(review) ? 'create' : 'add'}
endfunction

function! revue#stage#Availability(snapshot) abort
  let rule = get(get(a:snapshot, 'capabilities', {}), 'stage_batch', {})
  if !get(rule, 'enabled', 0)
    let reason = get(rule, 'reason', '')
    return empty(reason) ? 'This backend does not support private staging queues.' : reason
  endif
  if get(rule, 'mode', '') !=# 'sequential' | return 'This private staging mode is unsupported.' | endif
  return ''
endfunction

function! revue#stage#Error(snapshot, items, binding) abort
  let availability = revue#stage#Availability(a:snapshot)
  if !empty(availability) | return availability | endif
  let rule = a:snapshot.capabilities.stage_batch
  if has_key(a:binding, 'error') | return a:binding.error | endif
  if empty(a:items) | return 'Select at least one draft to save privately.' | endif
  let inventory = get(a:snapshot, 'pending_reviews', {})
  if !get(inventory, 'available', 0) || get(inventory, 'actor', '') !=# a:binding.actor
    return 'Private review actor or availability changed. Refresh before continuing.'
  endif
  let shadow = deepcopy(a:snapshot)
  if a:binding.private_mode ==# 'create'
    let error = revue#capabilities#Error(a:snapshot, {'kind': 'start_pending', 'pending_mode': 'create', 'actor': a:binding.actor}, 0)
    if !empty(error) | return error | endif
    let shadow.pending_reviews.items = [{'id': '__planned__', 'head': a:snapshot.head, 'actor': a:binding.actor}]
  elseif empty(revue#pending#Find(a:snapshot, a:binding.pending_review))
    return 'The selected private review is unavailable. Refresh to inspect it.'
  endif
  let ids = {}
  for item in a:items
    if has_key(ids, item.id) | return 'Each selected draft must have a distinct identity.' | endif
    let ids[item.id] = 1
    if index(get(rule, 'kinds', []), item.kind) < 0
      return 'Keep ' . revue#suggestion#Label(item) . ' outside this queue; review decisions are chosen when publishing.'
    endif
    if !empty(get(item, 'pending_mode', '')) | return 'A prepared private-save draft must be completed separately before staging a new queue.' | endif
    if index(['draft', 'failed'], item.state) < 0 | return 'A selected draft is frozen or needs receipt recovery.' | endif
    if item.snapshot !=# a:snapshot.snapshot || item.head !=# a:snapshot.head || item.base_tip !=# get(a:snapshot, 'base_tip', a:snapshot.base)
      return 'All selected drafts must belong to the latest loaded comparison.'
    endif
    let child = extend(deepcopy(item), {'pending_mode': 'add', 'pending_review': a:binding.private_mode ==# 'create' ? '__planned__' : a:binding.pending_review,
          \ 'pending_head': a:binding.pending_head, 'actor': a:binding.actor})
    let error = revue#capabilities#Error(shadow, child, 1)
    if empty(error) | let error = revue#anchor#Error(shadow, child) | endif
    if !empty(error) | return error | endif
  endfor
  return ''
endfunction

function! revue#stage#View(batch) abort
  let lines = []
  for step in a:batch.steps
    let title = empty(step.item) ? 'Create private review' : revue#suggestion#Label(step.draft) . ' · ' . get(step.draft, 'path', get(step.draft, 'thread', ''))
    let state = get({'accepted': 'saved', 'waiting': 'not saved', 'submitting': 'saving'}, step.state, step.state)
    call add(lines, '[' . state . '] ' . title)
    if !empty(get(step, 'error', '')) | call add(lines, '  ' . step.error) | endif
  endfor
  return lines
endfunction

function! revue#stage#Receipt(draft, receipt) abort
  let r = a:receipt
  if type(r) != v:t_dict || get(r, 'id', '') !=# a:draft.id || get(r, 'actor', '') !=# a:draft.actor || get(r, 'pending_mode', '') !=# a:draft.pending_mode || type(get(r, 'pending_review', 0)) != v:t_string || empty(get(r, 'pending_review', ''))
    return 'No matching private-save receipt; check the outcome before continuing.'
  endif
  if a:draft.pending_mode ==# 'add' && r.pending_review !=# a:draft.pending_review | return 'Receipt belongs to another private review.' | endif
  if a:draft.kind ==# 'reply' && get(r, 'thread', '') !=# a:draft.thread | return 'Receipt belongs to another reply thread.' | endif
  return ''
endfunction
