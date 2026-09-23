" Read-only discovery models; actions resolve stable targets in session.vim.
function! revue#discovery#Contains(text, query) abort
  return empty(a:query) || stridx(tolower(a:text), tolower(a:query)) >= 0
endfunction

function! revue#discovery#State(thread) abort
  return has_key(a:thread, 'resolved') ? a:thread.resolved ? 'resolved' : 'unresolved' : 'unknown'
endfunction

function! revue#discovery#Summary(filter) abort
  let parts = []
  for key in sort(keys(a:filter))
    if !empty(a:filter[key]) && a:filter[key] !=# 'all' | call add(parts, key . '=' . a:filter[key]) | endif
  endfor
  return empty(parts) ? 'all' : join(parts, ' · ')
endfunction

function! revue#discovery#Files(session) abort
  let result = []
  let filters = get(a:session, 'filefilters', {})
  let index = 0
  for file in a:session.snapshot.files
    let visible = revue#discovery#Contains(file.path . "\n" . file.old_path, get(filters, 'path', ''))
    let status = get(filters, 'status', 'all')
    let visible = visible && (status ==# 'all' || file.status ==# status)
    let wanted = get(filters, 'threads', 'all')
    if wanted !=# 'all'
      let threads = filter(copy(a:session.snapshot.threads), {_, t -> t.path ==# file.path})
      let visible = visible && (wanted ==# 'none' ? empty(threads) : wanted ==# 'any' ? !empty(threads) :
            \ !empty(filter(threads, {_, t -> wanted ==# 'outdated' ? t.outdated : revue#discovery#State(t) ==# wanted})))
    endif
    let viewed = get(filters, 'viewed', 'all')
    if viewed !=# 'all'
      let state = revue#progress#State(a:session, a:session.snapshot, file)
      let visible = visible && (viewed ==# 'viewed' ? state ==# 'viewed' : viewed ==# 'unviewed' ? state !=# 'viewed' : state ==# 'checking')
    endif
    if visible || has_key(get(a:session, 'revealed_files', {}), file.id) | call add(result, index) | endif
    let index += 1
  endfor
  return result
endfunction

function! s:Excerpt(text, query) abort
  let text = substitute(a:text, '\_s\+', ' ', 'g')
  let index = empty(a:query) ? 0 : stridx(tolower(text), tolower(a:query))
  let start = max([0, strchars(strpart(text, 0, max([0, index]))) - 40])
  return (start ? '… ' : '') . strcharpart(text, start, 180) . (strchars(text) > start + 180 ? ' …' : '')
endfunction

function! s:Allowed(filters, entry) abort
  for field in ['kind', 'state', 'anchor']
    let value = get(a:filters, field, 'all')
    if value !=# 'all' && get(a:entry, field, '') !=# value | return 0 | endif
  endfor
  return revue#discovery#Contains(get(a:entry, 'path', ''), get(a:filters, 'path', ''))
endfunction

function! s:MessageMatches(filters, message, path) abort
  return revue#discovery#Contains(get(a:message, 'author', ''), get(a:filters, 'author', '')) &&
        \ revue#discovery#Contains(a:path . "\n" . get(a:message, 'author', '') . "\n" . a:message.body, get(a:filters, 'text', ''))
endfunction

function! s:Rows(view, lines, target) abort
  let start = len(a:view.lines) + 1
  call extend(a:view.lines, a:lines)
  for row in range(start, len(a:view.lines)) | let a:view.rows[string(row)] = extend(deepcopy(a:target), {'start': start}) | endfor
endfunction

function! revue#discovery#Key(target) abort
  return json_encode([get(a:target, 'kind', ''), get(a:target, 'thread', ''), get(a:target, 'message', ''),
        \ get(a:target, 'message_kind', ''), get(a:target, 'draft', ''), get(a:target, 'item', ''),
        \ empty(get(a:target, 'message', '')) ? get(a:target, 'index', -1) : -1])
endfunction

function! revue#discovery#View(session) abort
  let filters = get(a:session, 'discussionfilters', {})
  let view = {'lines': ['# Review discussions', ':ReviewOpenDiscussion · :ReviewDiscussionFilter · :ReviewDiscussions [text] · :ReviewClose',
        \ 'Filters: ' . revue#discovery#Summary(filters), '', ''], 'rows': {}}
  call extend(view.lines, revue#inventory#RefreshLines(a:session))
  call extend(view.lines, revue#feedback#Lines(a:session))
  call add(view.lines, 'Search scope: loaded feedback and local drafts; excludes unloaded pages and other comparisons.')
  call extend(view.lines, revue#inventory#Lines(a:session, ['threads', 'conversation', 'private', 'thread_state']))
  call add(view.lines, '')
  let counts = {'threads': 0, 'messages': 0, 'conversation': 0, 'drafts': 0}
  for thread in revue#anchor#FileFirst(a:session.snapshot.threads)
    let target = {'kind': 'thread', 'thread': thread.id, 'path': thread.path, 'state': revue#discovery#State(thread), 'anchor': thread.outdated ? 'outdated' : 'current'}
    if !s:Allowed(filters, target) | continue | endif
    let matching = filter(copy(thread.comments), {_, m -> s:MessageMatches(filters, m, thread.path)})
    if empty(matching) | continue | endif
    let counts.threads += 1
    let counts.messages += len(matching)
    let source = revue#anchor#IsFile(thread) ? 'File discussion' : thread.outdated ? 'original diff' : revue#anchor#Label(thread)
    call s:Rows(view, ['## ' . thread.path . ' · ' . source . ' · ' . target.state . (thread.outdated ? ' · outdated' : ''),
          \ printf('%d messages · %d replies · %d matching messages', len(thread.comments), max([0, len(thread.comments) - 1]), len(matching))], target)
    let index = 0
    for message in thread.comments
      if s:MessageMatches(filters, message, thread.path)
        let message_target = extend(copy(target), {'message': get(message, 'id', ''), 'message_kind': get(message, 'kind', 'comment'), 'index': index})
        let unread = has_key(a:session.read_state.unread, revue#activity#Key(thread.id, message)) ? ' [new]' : ''
        call s:Rows(view, ['  ' . message.author . unread . ' · ' . s:Excerpt(message.body, get(filters, 'text', ''))], message_target)
      endif
      let index += 1
    endfor
    call add(view.lines, '')
  endfor
  let index = 0
  for message in a:session.snapshot.conversation
    let target = {'kind': 'conversation', 'path': '', 'state': '', 'anchor': 'none', 'message': get(message, 'id', ''), 'message_kind': get(message, 'kind', 'comment'), 'index': index}
    if s:Allowed(filters, target) && s:MessageMatches(filters, message, '')
      let counts.conversation += 1
      call s:Rows(view, ['## Conversation · ' . target.message_kind . ' · ' . message.author,
            \ '  ' . s:Excerpt(message.body, get(filters, 'text', '')), ''], target)
    endif
    let index += 1
  endfor
  for operation in a:session.drafts
    for draft in operation.kind ==# 'batch' ? operation.items : [operation]
      let path = get(draft, 'path', '')
      let outdated = draft.snapshot !=# a:session.snapshot.snapshot
      if has_key(draft, 'thread')
        let threads = filter(copy(a:session.snapshot.threads), {_, t -> t.id ==# draft.thread})
        if !empty(threads) | let path = threads[0].path | endif
        let outdated = outdated || empty(threads) || threads[0].outdated
      endif
      let target = {'kind': 'draft', 'draft': operation.id, 'item': draft.id, 'path': path, 'state': operation.state,
            \ 'anchor': empty(path) && !has_key(draft, 'thread') ? 'none' : outdated ? 'outdated' : 'current'}
      let message = {'body': draft.body, 'author': 'local draft'}
      if !s:Allowed(filters, target) || !s:MessageMatches(filters, message, path) | continue | endif
      let counts.drafts += 1
      call s:Rows(view, ['## Local draft · ' . revue#suggestion#Label(draft) . ' · ' . operation.state . (operation.kind ==# 'batch' ? ' · in batch' : ''),
            \ (empty(path) ? has_key(draft, 'thread') ? '  Thread ' . draft.thread : '  Review conversation' : '  ' . path) . ' · comparison ' . draft.snapshot,
            \ '  ' . s:Excerpt(draft.body, get(filters, 'text', '')), ''], target)
    endfor
  endfor
  let view.lines[3] = printf('%d matching threads (%d matching messages) · %d conversation messages · %d local drafts', counts.threads, counts.messages, counts.conversation, counts.drafts)
  if empty(view.rows) | call add(view.lines, 'No discussions match in loaded feedback. :ReviewDiscussionFilter clear resets filters.') | endif
  return view
endfunction

function! s:Complete(lead, line, domains) abort
  let args = split(a:line, '\s\+', 1)
  let values = len(args) <= 2 ? sort(keys(a:domains)) + ['clear'] : get(a:domains, get(args, 1, ''), [])
  return filter(copy(values), {_, value -> stridx(value, a:lead) == 0})
endfunction

function! revue#discovery#CompleteFile(lead, line, pos) abort
  return s:Complete(a:lead, strpart(a:line, 0, a:pos), {'path': [],
        \ 'status': ['all', 'modified', 'added', 'removed', 'renamed', 'copied', 'changed'],
        \ 'threads': ['all', 'any', 'none', 'unresolved', 'resolved', 'unknown', 'outdated'],
        \ 'viewed': ['all', 'viewed', 'unviewed', 'checking']})
endfunction

function! revue#discovery#CompleteDiscussion(lead, line, pos) abort
  return s:Complete(a:lead, strpart(a:line, 0, a:pos), {'text': [], 'path': [], 'author': [],
        \ 'kind': ['all', 'thread', 'conversation', 'draft'],
        \ 'state': ['all', 'unresolved', 'resolved', 'unknown', 'draft', 'failed', 'submitting'],
        \ 'anchor': ['all', 'current', 'outdated', 'none']})
endfunction
