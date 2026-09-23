" Local pending feedback is backed by the existing durable draft store.
" These projections never change delivery state or backend discussion identity.
function! revue#local_feedback#Enabled(session) abort
  return get(get(a:session.snapshot, 'backend', {}), 'id', '') ==# 'local'
endfunction

function! revue#local_feedback#IsFeedback(draft) abort
  return index(['comment', 'file_comment', 'reply', 'conversation', 'review'], get(a:draft, 'kind', '')) >= 0
endfunction

function! revue#local_feedback#Items(session) abort
  let items = []
  let snapshot = a:session.snapshot
  for draft in a:session.drafts
    if !revue#local_feedback#IsFeedback(draft) || empty(trim(draft.body)) | continue | endif
    let item = deepcopy(draft)
    let item.key = 'draft:' . draft.id
    let item.pending = 1
    let item.status = draft.state ==# 'draft' ? 'Pending' : 'Pending · ' . draft.state
    if draft.kind ==# 'reply'
      let parent = get(filter(copy(snapshot.threads), {_, t -> t.id ==# draft.thread}), 0, {})
      for field in ['path', 'side', 'start', 'line', 'outdated', 'subject_type']
        if has_key(parent, field) | let item[field] = parent[field] | endif
      endfor
      let item.end = get(item, 'line', 0)
    endif
    call add(items, item)
  endfor
  for thread in snapshot.threads
    for message in thread.comments
      let item = extend(deepcopy(message), {'key': 'message:' . message.id, 'pending': 0, 'status': 'Saved',
            \ 'thread': thread.id, 'path': thread.path, 'side': thread.side,
            \ 'start': thread.start, 'end': thread.line, 'outdated': thread.outdated,
            \ 'snapshot': get(thread, 'snapshot', snapshot.snapshot)})
      call add(items, item)
    endfor
  endfor
  for message in snapshot.conversation
    call add(items, extend(deepcopy(message), {'key': 'message:' . message.id, 'pending': 0,
          \ 'status': 'Saved', 'snapshot': get(message, 'snapshot', snapshot.snapshot)}))
  endfor
  return items
endfunction

function! revue#local_feedback#Cards(session) abort
  if !revue#local_feedback#Enabled(a:session) | return [] | endif
  let threads = []
  for item in revue#local_feedback#Items(a:session)
    if !item.pending || !has_key(item, 'path') || item.snapshot !=# a:session.snapshot.snapshot || get(item, 'outdated', 0) | continue | endif
    let file = item.kind ==# 'file_comment' || get(item, 'subject_type', '') ==# 'file'
    call add(threads, {'id': item.key, 'path': item.path, 'side': get(item, 'side', 'head'),
          \ 'start': get(item, 'start', 0), 'line': get(item, 'end', 0), 'outdated': v:false,
          \ 'subject_type': file ? 'file' : 'line', 'local_pending': 1,
          \ 'comments': [{'id': item.key, 'author': 'You', 'created': '', 'body': item.body,
          \ 'publication': 'local_pending', 'pending_status': item.status, 'kind': item.kind}]})
  endfor
  return threads
endfunction

function! revue#local_feedback#Location(item) abort
  if !has_key(a:item, 'path') | return get(a:item, 'kind', '') ==# 'review' ? 'Review summary' : 'Conversation' | endif
  let location = a:item.path
  if get(a:item, 'start', 0) > 0
    let location .= ':' . a:item.start . '-' . get(a:item, 'end', a:item.start) . ' (' . get(a:item, 'side', '') . ')'
  endif
  return location . (get(a:item, 'outdated', 0) ? ' · original location' : '')
endfunction

function! revue#local_feedback#Markdown(session, items) abort
  let snapshot = a:session.snapshot
  let workspace = get(get(snapshot, 'capture_context', {}), 'workspace', '')
  let lines = ['# Review feedback', '', 'Review: ' . revue#message#OneLine(snapshot.title)]
  if !empty(workspace) | call add(lines, 'Workspace: ' . revue#message#OneLine(workspace)) | endif
  call extend(lines, ['Base: ' . snapshot.base, 'Comparison: ' . snapshot.snapshot, '',
        \ 'Please address the feedback below. Answer questions and explain proposed changes before editing where requested.', ''])
  for item in a:items
    call extend(lines, ['## ' . revue#message#OneLine(revue#local_feedback#Location(item)), '',
          \ 'Status: ' . item.status, 'Feedback ID: ' . item.key, 'Comparison: ' . item.snapshot, ''])
    if !empty(get(item, 'author', '')) | call extend(lines, ['Author: ' . revue#message#OneLine(item.author), '']) | endif
    call extend(lines, split(item.body, "\n", 1) + ['', '---', ''])
  endfor
  return lines
endfunction
