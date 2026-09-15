" Native pending reviews are backend conversation state, not local drafts.
function! revue#pending#Find(snapshot, id) abort
  let pending = get(a:snapshot, 'pending_reviews', {})
  if !get(pending, 'available', 0) | return {} | endif
  let matches = filter(copy(get(pending, 'items', [])), {_, r -> r.id ==# a:id})
  return len(matches) == 1 ? matches[0] : {}
endfunction

function! revue#pending#Error(snapshot, draft) abort
  let review = revue#pending#Find(a:snapshot, get(a:draft, 'pending_review', ''))
  if empty(review) | return 'The pending review is unavailable or already published. Refresh to inspect its state.' | endif
  let complete_error = revue#pending#CompleteError(review)
  if !empty(complete_error) | return complete_error | endif
  if get(a:draft, 'actor', '') !=# review.actor | return 'The pending review belongs to a different actor.' | endif
  if get(a:draft, 'expected_version', '') !=# review.version || get(a:draft, 'pending_head', '') !=# review.head
    if a:draft.kind ==# 'discard_pending' | return 'The pending review changed. Cancel this local operation, refresh and inspect the review before discarding.' | endif
    return 'The pending review changed. Your summary is retained; refresh and prepare publication from the updated review.'
  endif
  return ''
endfunction

function! revue#pending#Comments(comments) abort
  let lines = []
  for comment in a:comments
    call add(lines, '### ' . revue#message#OneLine(comment.path) . ' · ' . (get(comment, 'subject_type', '') ==# 'file' ? 'whole file' : comment.side . ':' . comment.start . '-' . comment.line))
    call extend(lines, split(comment.body, "\n", 1) + [''])
  endfor
  return lines
endfunction

function! revue#pending#Publication(snapshot, draft) abort
  let lines = ['## Comments included in publication', ''] + revue#pending#Comments(a:draft.pending_comments)
  let current = revue#pending#Find(a:snapshot, a:draft.pending_review)
  if !empty(current) && current.version !=# a:draft.expected_version
    call extend(lines, ['## Current pending review changed', 'Refresh retained your prepared publication. :RevuePendingBase accepts these current contents.',
          \ '### Current server summary'] + split(current.body, "\n", 1) + [''] + revue#pending#Comments(current.comments))
  endif
  return lines + ['## Your review summary', '']
endfunction

function! revue#pending#View(snapshot) abort
  let pending = get(a:snapshot, 'pending_reviews', {})
  let view = {'lines': ['# Private reviews · saved on backend', ':RevueReviewActions · :RevueClose'], 'rows': {}, 'styles': {'1': 'RevueCardHeading', '2': 'RevueCardAction'}}
  if !get(pending, 'available', 0)
    call add(view.lines, 'Pending review state unavailable: ' . get(pending, 'error', 'This backend does not expose native pending reviews.'))
    return view
  endif
  for review in get(pending, 'items', [])
    let start = len(view.lines) + 1
    call extend(view.lines, ['## Pending review #' . review.id . ' · ' . revue#message#OneLine(review.author),
          \ 'Not published · source ' . strpart(review.head, 0, 12) . ' · ' . len(review.comments) . (has_key(review, 'total') ? '/' . review.total : '') . ' comments loaded'])
    let view.styles[string(start)] = 'RevueCardHeader'
    let view.styles[string(start + 1)] = 'RevueCardMeta'
    if !empty(review.body) | call extend(view.lines, split(review.body, "\n", 1)) | endif
    if !get(review, 'complete', 1)
      call add(view.lines, 'Incomplete · :RevueVerifyPending before publication/discard')
      let view.styles[string(len(view.lines))] = 'RevueCardAction'
    endif
    for row in range(start, len(view.lines)) | let view.rows[string(row)] = {'review': review.id} | endfor
    for comment in review.comments
      let start = len(view.lines) + 1
      call extend(view.lines, revue#pending#Comments([comment]))
      let view.styles[string(start)] = 'RevueCardHeader'
      for row in range(start, len(view.lines)) | let view.rows[string(row)] = {'review': review.id, 'target': deepcopy(comment)} | endfor
    endfor
  endfor
  if empty(get(pending, 'items', [])) | call add(view.lines, 'No pending reviews for the verified actor.') | endif
  return view
endfunction

function! revue#pending#DiscardPreview(snapshot, draft) abort
  let lines = ['## Private summary and comments to discard', ''] + split(a:draft.pending_body, "\n", 1) + [''] + revue#pending#Comments(a:draft.pending_comments)
  let current = revue#pending#Find(a:snapshot, a:draft.pending_review)
  if !empty(current) && current.version !=# a:draft.expected_version
    call extend(lines, ['## Current pending review changed', 'Cancel this local operation; inspect the refreshed contents before preparing another discard.', ''] + split(current.body, "\n", 1) + [''] + revue#pending#Comments(current.comments))
  endif
  return lines
endfunction

function! revue#pending#SaveError(snapshot, draft) abort
  let inventory = get(a:snapshot, 'pending_reviews', {})
  if !get(inventory, 'available', 0) || empty(get(inventory, 'actor', ''))
    return 'Refresh to verify the actor and native pending reviews before saving privately.'
  endif
  if inventory.actor !=# get(a:draft, 'actor', '') | return 'Private review actor changed. Draft retained.' | endif
  let mode = get(a:draft, 'pending_mode', '')
  if mode ==# 'create'
    if !empty(get(inventory, 'items', [])) | return 'A pending review already exists. Refresh and use :RevueSavePending to explicitly select it.' | endif
    if index(['file_comment', 'reply'], a:draft.kind) >= 0 | return 'Use :RevueStartPending before saving whole-file feedback or replies privately.' | endif
  elseif mode ==# 'add'
    let review = revue#pending#Find(a:snapshot, get(a:draft, 'pending_review', ''))
    if empty(review) | return 'The selected pending review is unavailable or published. Draft retained.' | endif
    if review.head !=# get(a:draft, 'pending_head', '') || (a:draft.kind !=# 'reply' && review.head !=# get(a:draft, 'head', a:snapshot.head))
      return 'The pending review concerns another source revision. Inspect it before adding feedback.'
    endif
  else
    return 'Choose whether this private save creates or adds to a pending review.'
  endif
  return ''
endfunction

function! revue#pending#ReplyFields(snapshot, thread) abort
  let inventory = get(a:snapshot, 'pending_reviews', {})
  let reviews = get(inventory, 'items', [])
  if !get(inventory, 'available', 0) || len(reviews) != 1
    return {'error': 'A private reply needs one verified pending review. Use :RevueStartPending or inspect :RevuePending first.'}
  endif
  let review = reviews[0]
  return {'kind': 'reply', 'thread': a:thread, 'pending_mode': 'add', 'pending_review': review.id,
        \ 'pending_head': review.head, 'actor': get(inventory, 'actor', '')}
endfunction

function! revue#pending#PrivateThread(snapshot, id) abort
  let threads = filter(copy(get(a:snapshot, 'threads', [])), {_, t -> t.id ==# a:id})
  return !empty(threads) && !empty(threads[0].comments) && get(threads[0].comments[0], 'publication', '') ==# 'pending'
endfunction

" Page headers describe all private reviews; comments cover only loaded threads.
function! revue#pending#Merge(snapshot, pending) abort
  if type(a:pending) != v:t_dict || !get(a:pending, 'available', 0) || type(get(a:pending, 'actor', 0)) != v:t_string || empty(a:pending.actor) || type(get(a:pending, 'items', 0)) != v:t_list
    throw 'Private feedback identity is unavailable.'
  endif
  let previous = get(a:snapshot, 'pending_reviews', {})
  if get(previous, 'actor', '') !=# a:pending.actor | throw 'Private feedback actor changed. Refresh.' | endif
  let old = {}
  for review in get(previous, 'items', []) | let old[review.id] = review | endfor
  let ids = {}
  let result = deepcopy(a:pending)
  for review in result.items
    if type(review) != v:t_dict || type(get(review, 'id', 0)) != v:t_string || empty(review.id) || has_key(ids, review.id) || !has_key(old, review.id)
      throw 'Private review inventory changed. Refresh.'
    endif
    let ids[review.id] = 1
    let before = old[review.id]
    for key in ['actor', 'head', 'body', 'read_version', 'total']
      if !has_key(review, key) || get(before, key, v:null) !=# review[key] | throw 'Private review changed while paging. Refresh.' | endif
    endfor
    if type(review.total) != v:t_number || review.total < 0 || type(get(review, 'comments', 0)) != v:t_list || empty(review.read_version) || review.actor !=# result.actor
      throw 'Invalid private review coverage.'
    endif
    let comments = deepcopy(before.comments)
    let positions = {}
    for index in range(len(comments)) | let positions[comments[index].message] = index | endfor
    let seen = {}
    for target in review.comments
      if type(target) != v:t_dict || type(get(target, 'message', 0)) != v:t_string || has_key(seen, target.message)
        throw 'Repeated or invalid private comment identity.'
      endif
      let seen[target.message] = 1
      let message = revue#edit#Message(a:snapshot, target)
      if empty(message) || get(message, 'pending_review', '') !=# review.id || get(message, 'actor', '') !=# review.actor || get(message, 'publication', '') !=# 'pending' || get(target, 'body', 0) !=# message.body
        throw 'Private comment does not match its loaded thread.'
      endif
      if has_key(positions, target.message)
        if comments[positions[target.message]].body !=# target.body | throw 'Private comment changed during paging. Refresh.' | endif
      else
        let positions[target.message] = len(comments)
        call add(comments, target)
      endif
    endfor
    if len(comments) > review.total | throw 'Private comment coverage exceeds its verified total.' | endif
    if get(before, 'complete', 0)
      call extend(review, deepcopy(before))
    else
      let review.comments = comments
      let review.complete = v:false
      let review.version = ''
    endif
  endfor
  if sort(keys(ids)) !=# sort(keys(old)) | throw 'Private review inventory changed. Refresh.' | endif
  return result
endfunction

function! revue#pending#CompleteError(review) abort
  return get(a:review, 'complete', 1) ? '' : 'Load the complete private review with :RevueVerifyPending before publication or discard.'
endfunction

function! revue#pending#RowKey(row) abort
  let target = get(a:row, 'target', {})
  return [get(a:row, 'review', ''), get(target, 'message', ''), get(target, 'message_kind', ''), get(target, 'thread', '')]
endfunction

function! revue#pending#ValidateComplete(review) abort
  let review = a:review
  if type(get(review, 'summary', 0)) != v:t_dict || get(review.summary, 'id', '') !=# review.id || get(review.summary, 'pending_review', '') !=# review.id || get(review.summary, 'actor', '') !=# review.actor || get(review.summary, 'body', v:null) !=# review.body || get(review.summary, 'publication', '') !=# 'pending' || empty(get(review.summary, 'version', ''))
    throw 'Verified private summary does not match the review.'
  endif
  for comment in review.comments
    for key in ['message', 'message_kind', 'thread', 'path', 'side', 'body', 'author']
      if type(get(comment, key, 0)) != v:t_string | throw 'Incomplete private comment target.' | endif
    endfor
    if empty(comment.message) || empty(comment.thread) || empty(comment.path) || comment.message_kind !=# 'comment' || index(['', 'base', 'head'], comment.side) < 0
      throw 'Invalid private comment target.'
    endif
    if type(get(comment, 'start', '')) != v:t_number || type(get(comment, 'line', '')) != v:t_number || comment.start < 0 || comment.start > comment.line
      throw 'Invalid private comment range.'
    endif
  endfor
endfunction
