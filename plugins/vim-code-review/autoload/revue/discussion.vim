" Real-text discussion rows with explicit message and thread targets.
function! revue#discussion#Append(view, comment, thread, index, ...) abort
  let first = len(a:view.lines) + 1
  let unread = a:0 ? a:1 : {}
  call add(a:view.lines, '### ' . revue#message#Header(a:comment, a:0 > 1 ? a:2 : '') . (has_key(unread, revue#activity#Key(a:thread, a:comment)) ? ' [new]' : ''))
  call add(a:view.lines, '')
  let start = len(a:view.lines) + 1
  call extend(a:view.lines, split(a:comment.body, "\n", 1))
  let end = len(a:view.lines)
  let reactions = revue#reaction#Summary(a:comment)
  if !empty(reactions) | call extend(a:view.lines, ['', reactions]) | endif
  call add(a:view.lines, '')
  let target = {'thread': a:thread, 'comment': get(a:comment, 'id', ''), 'index': a:index,
        \ 'kind': get(a:comment, 'kind', 'comment'),
        \ 'start': first, 'body_start': start, 'body_end': end, 'end': len(a:view.lines)}
  for row in range(first, len(a:view.lines))
    let a:view.messages[string(row)] = target
  endfor
endfunction

function! revue#discussion#Threads(threads, title, ...) abort
  let unread = a:0 ? a:1 : {}
  let view = {'lines': [a:title, ':ReviewReply · :ReviewQuote · :ReviewJump · :ReviewFocus · :ReviewClose', ''], 'messages': {}, 'threads': {}}
  if a:0 > 2 && !empty(a:3)
    call extend(view.lines, ['', 'Original code context: ' . a:3,
          \ a:0 > 3 && a:4 ? ':ReviewReturnContext returns to the discussion you came from.' : ':ReviewLatest opens the current review comparison.', ''])
  endif
  let resolved = len(filter(copy(a:threads), {_, t -> has_key(t, 'resolved') && t.resolved}))
  let unknown = len(filter(copy(a:threads), {_, t -> !has_key(t, 'resolved')}))
  let view.lines[2] = printf('%d threads · %d unresolved · %d resolved · %d state unknown', len(a:threads), len(a:threads) - resolved - unknown, resolved, unknown)
  for thread in revue#anchor#FileFirst(a:threads)
    let first = len(view.lines) + 1
    let state = has_key(thread, 'resolved') ? thread.resolved ? ' [resolved]' : ' [unresolved]' : ' [resolution unknown]'
    let new_count = len(filter(copy(thread.comments), {_, m -> has_key(unread, revue#activity#Key(thread.id, m))}))
    call add(view.lines, '## ' . revue#anchor#Label(thread) . (thread.outdated ? ' [outdated]' : '') . state . (new_count ? ' [' . new_count . ' new]' : ''))
    if !empty(get(thread, 'operation_status', '')) | call add(view.lines, thread.operation_status) | endif
    if thread.outdated && !revue#anchor#IsFile(thread)
      if has_key(thread, 'original_context')
        call extend(view.lines, ['Original source:'] + thread.original_context)
      else
        call extend(view.lines, ['Original diff:'] + split(get(thread, 'hunk', ''), "\n", 1))
      endif
    endif
    if !empty(get(thread, 'original_comparison', {}))
      call add(view.lines, 'Original comparison: ' . strpart(thread.original_comparison.head, 0, 12) . ' · :ReviewThreadComparison')
    elseif has_key(thread, 'original_source')
      call add(view.lines, 'Original code: ' . (get(thread.original_source, 'available', 0) ? ':ReviewThreadComparison verifies historical context' : get(thread.original_source, 'reason', 'unavailable')))
    endif
    let index = 0
    for comment in thread.comments
      call revue#discussion#Append(view, comment, thread.id, index, unread, a:0 > 1 ? a:2 : '')
      let index += 1
    endfor
    for row in range(first, len(view.lines)) | let view.threads[string(row)] = thread.id | endfor
  endfor
  if len(view.lines) == 3 | call add(view.lines, 'No comments on this file.') | endif
  return view
endfunction

function! revue#discussion#Selected(session, row) abort
  if index(['threads', 'conversation'], get(b:, 'revue_view', '')) < 0 | return {} | endif
  let target = get(get(a:session, 'messagemap', {}), string(a:row), {})
  if empty(target) | return {} | endif
  let comments = a:session.snapshot.conversation
  if !empty(target.thread)
    let threads = filter(copy(a:session.snapshot.threads), {_, t -> t.id ==# target.thread})
    if empty(threads) | return {} | endif
    let comments = threads[0].comments
  endif
  if !empty(target.comment)
    let found = filter(copy(comments), {_, c -> get(c, 'id', '') ==# target.comment && get(c, 'kind', 'comment') ==# get(target, 'kind', 'comment')})
    if empty(found) | return {} | endif
    let comment = found[0]
  else
    " Version-1 fixtures may omit message IDs; indexing is only a display fallback.
    if target.index >= len(comments) | return {} | endif
    let comment = comments[target.index]
  endif
  return extend(copy(target), {'message': comment})
endfunction
