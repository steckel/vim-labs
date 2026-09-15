" Pure batch validation and presentation. Submission stays with the session.
function! revue#batch#Error(snapshot, items) abort
  let capability = get(get(a:snapshot, 'capabilities', {}), 'batch', {})
  if !get(capability, 'enabled', 0) | return get(capability, 'reason', 'This backend does not support review batches.') | endif
  if get(capability, 'mode', '') !=# 'atomic' | return 'This batch delivery mode is not supported.' | endif
  if empty(a:items) | return 'Select at least one draft.' | endif
  let reviews = 0
  let comments = len(filter(copy(a:items), {_, d -> d.kind ==# 'comment'}))
  for draft in a:items
    if draft.kind ==# 'delete_message' | return 'Message deletions must be confirmed separately.' | endif
    if !empty(get(draft, 'pending_mode', '')) | return 'Private-save drafts must be sent separately; they cannot be published through a batch.' | endif
    if index(get(capability, 'kinds', []), draft.kind) < 0 | return 'Send ' . revue#suggestion#Label(draft) . ' drafts separately on this backend.' | endif
    if index(['draft', 'failed'], draft.state) < 0 | return 'An item is already submitting or needs receipt recovery.' | endif
    if draft.snapshot !=# a:snapshot.snapshot || draft.head !=# a:snapshot.head || draft.base_tip !=# get(a:snapshot, 'base_tip', a:snapshot.base)
      return 'All selected drafts must belong to the loaded comparison.'
    endif
    let optional = draft.kind ==# 'review' && comments && get(capability, 'review_body_optional_with_comments', 0)
    let error = revue#capabilities#Error(a:snapshot, draft, !optional)
    if !empty(error) | return error | endif
    let error = revue#anchor#Error(a:snapshot, draft)
    if !empty(error) | return error | endif
    let reviews += draft.kind ==# 'review'
  endfor
  return reviews > get(capability, 'max_reviews', 1) ? 'Select at most one review decision.' : ''
endfunction

function! revue#batch#View(items, selected, frozen) abort
  let view = {'lines': [], 'rows': {}}
  for item in a:items
    let first = len(view.lines) + 1
    let location = get(item, 'path', get(item, 'thread', get(item, 'event', '')))
    if has_key(item, 'start') | let location .= ' · ' . item.side . ':' . item.start . '-' . item.end | endif
    call add(view.lines, (a:frozen ? '[frozen] ' : get(a:selected, item.id, 0) ? '[x] ' : '[ ] ') . revue#suggestion#Label(item) . ' · ' . location)
    call extend(view.lines, split(item.body, "\n", 1) + [''])
    for row in range(first, len(view.lines)) | let view.rows[string(row)] = item.id | endfor
  endfor
  return view
endfunction
