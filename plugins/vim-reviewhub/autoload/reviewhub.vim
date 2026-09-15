let s:trees = {}
let s:serial = 0

function! reviewhub#Open(repo) abort
  let s:serial += 1
  let id = string(s:serial)
  let state = {'id': id, 'repo': a:repo, 'cwd': getcwd(), 'items': [], 'expanded': {}, 'snapshots': {},
        \ 'rows': {}, 'page': 1, 'more': 0, 'query': '', 'message': 'Loading pull requests…', 'generation': 0, 'list_busy': 0}
  tabnew
  let t:reviewhub_id = id
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nomodeline nonumber norelativenumber nowrap cursorline
  execute 'file ' . fnameescape('reviewhub://' . id . '/pulls')
  let state.buf = bufnr()
  let state.win = win_getid()
  let b:reviewhub_id = id
  let s:trees[id] = state
  nnoremap <silent><buffer> <CR> <Cmd>call reviewhub#Activate()<CR>
  nnoremap <silent><buffer> o <Cmd>call reviewhub#Activate()<CR>
  nnoremap <silent><buffer> l <Cmd>call reviewhub#Activate()<CR>
  nnoremap <silent><buffer> h <Cmd>call reviewhub#Collapse()<CR>
  nnoremap <silent><buffer> R <Cmd>call reviewhub#Refresh()<CR>
  nnoremap <silent><buffer> / <Cmd>call reviewhub#Search()<CR>
  nnoremap <silent><buffer> q <Cmd>call reviewhub#Close()<CR>
  nnoremap <silent><buffer> ? <Cmd>call reviewhub#Help()<CR>
  rightbelow vnew
  execute 'file ' . fnameescape('reviewhub://' . id . '/preview')
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nomodeline nonumber norelativenumber wrap linebreak filetype=markdown
  let b:reviewhub_id = id
  let state.preview = bufnr()
  nnoremap <silent><buffer> q <Cmd>call reviewhub#Close()<CR>
  call setline(1, ['GitHub pull requests', '', 'Expand a PR in the tree to preview its conversation.',
        \ 'Open a file or Conversation to review and respond in Revue.', '',
        \ 'j/k navigate · Enter/o expand or open · h collapse', '/ search · R refresh'])
  setlocal nomodifiable
  call win_gotoid(state.win)
  vertical resize 52
  setlocal winfixwidth
  call s:Render(state)
  call s:List(state, 0)
endfunction

function! s:State() abort
  return get(s:trees, get(b:, 'reviewhub_id', get(t:, 'reviewhub_id', '')), {})
endfunction

function! s:Render(state) abort
  if !bufexists(a:state.buf) | return | endif
  let lines = ['Pull requests · ' . get(get(a:state, 'connection', {}), 'repo', a:state.repo),
        \ empty(a:state.query) ? 'Open · most recently updated' : 'Search: ' . a:state.query,
        \ 'Enter/o/l expand or open · h collapse', '/ search · R refresh · q close · ? help', '']
  let a:state.rows = {}
  for item in a:state.items
    let key = string(item.id)
    call add(lines, (has_key(a:state.expanded, key) ? '▾ ' : '▸ ') . '#' . item.id . ' ' . item.title . '  @' . item.author . (item.draft ? ' [draft]' : ''))
    let a:state.rows[string(len(lines))] = {'kind': 'pr', 'number': item.id}
    if has_key(a:state.expanded, key) && has_key(a:state.snapshots, key)
      let snapshot = a:state.snapshots[key]
      call add(lines, '    Conversation (' . len(snapshot.conversation) . ')')
      let a:state.rows[string(len(lines))] = {'kind': 'conversation', 'number': item.id}
      call add(lines, '    Files (' . len(snapshot.files) . ')')
      let index = 0
      for file in snapshot.files
        let comment_count = len(filter(copy(snapshot.threads), {_, t -> t.path ==# file.path}))
        call add(lines, '      ' . toupper(file.status[0]) . ' ' . file.path . (comment_count ? ' 💬' . comment_count : ''))
        let a:state.rows[string(len(lines))] = {'kind': 'file', 'number': item.id, 'index': index}
        let index += 1
      endfor
    endif
  endfor
  if a:state.more
    call add(lines, '  Load more…')
    let a:state.rows[string(len(lines))] = {'kind': 'more'}
  endif
  call extend(lines, ['', a:state.message])
  call setbufvar(a:state.buf, '&modifiable', 1)
  call deletebufline(a:state.buf, 1, '$')
  call setbufline(a:state.buf, 1, lines)
  call setbufvar(a:state.buf, '&modifiable', 0)
endfunction

function! s:List(state, append) abort
  if a:append && a:state.list_busy | return | endif
  let a:state.list_busy = 1
  let a:state.generation += 1
  let a:state.message = 'Loading pull requests…'
  call s:Render(a:state)
  let req = {'op': 'list', 'repo': a:state.repo, 'cwd': a:state.cwd, 'page': a:append ? a:state.page + 1 : 1, 'query': a:state.query}
  if has_key(a:state, 'connection') | let req.connection = a:state.connection | endif
  call reviewhub#transport#Request(req, function('s:Listed', [a:state.id, a:state.generation, a:append]))
endfunction

function! s:Listed(id, generation, append, result) abort
  let state = get(s:trees, a:id, {})
  if empty(state) || state.generation != a:generation | return | endif
  let state.list_busy = 0
  if a:result.ok
    let state.connection = a:result.data.connection
    if a:append | call extend(state.items, a:result.data.items) | else | let state.items = a:result.data.items | endif
    let state.more = a:result.data.more
    let state.page = a:result.data.page
    let state.message = empty(state.items) ? 'No matching pull requests.' : len(state.items) . ' pull requests loaded.'
    if !a:result.data.authenticated | let state.message .= ' Public access; gh auth login enables posting and higher limits.' | endif
  else
    let state.message = a:result.error
  endif
  call s:Render(state)
endfunction

function! reviewhub#Activate() abort
  let state = s:State()
  if empty(state) | return | endif
  let row = get(state.rows, string(line('.')), {})
  if empty(row) | return | endif
  if row.kind ==# 'more'
    call s:List(state, 1)
  elseif row.kind ==# 'pr'
    let key = string(row.number)
    if has_key(state.expanded, key)
      call remove(state.expanded, key)
      call s:Render(state)
    elseif has_key(state.snapshots, key)
      let state.expanded[key] = 1
      call s:Preview(state, state.snapshots[key])
      call s:Render(state)
    else
      let state.message = 'Loading #' . row.number . ' files and discussions…'
      call s:Render(state)
      call reviewhub#transport#Request({'op': 'open', 'connection': state.connection, 'number': row.number},
            \ function('s:Expanded', [state.id, state.generation, row.number]))
    endif
  else
    call reviewhub#bridge#Open(state.connection, state.snapshots[string(row.number)], get(row, 'index', -1))
  endif
endfunction

function! s:Expanded(id, generation, number, result) abort
  let state = get(s:trees, a:id, {})
  if empty(state) || state.generation != a:generation | return | endif
  if a:result.ok
    let state.snapshots[string(a:number)] = a:result.data
    let state.expanded[string(a:number)] = 1
    let state.message = '#' . a:number . ' loaded. Open Conversation or a file.'
    call s:Preview(state, a:result.data)
  else
    let state.message = a:result.error
  endif
  call s:Render(state)
endfunction

function! s:Preview(state, snapshot) abort
  if !bufexists(a:state.preview) | return | endif
  let snapshot = a:snapshot
  let lines = ['#' . snapshot.number . ' ' . snapshot.title, snapshot.url,
        \ snapshot.author . ' · ' . snapshot.state, 'Review requested: ' . join(snapshot.reviewers, ', '), '']
  call extend(lines, split(snapshot.body, "\n", 1))
  for comment in snapshot.conversation
    call extend(lines, ['', '── ' . comment.author . ' · ' . comment.kind . ' · ' . comment.created . ' ──'])
    call extend(lines, split(comment.body, "\n", 1))
  endfor
  call extend(lines, ['', len(snapshot.threads) . ' code threads. Open a file to see them inline.'])
  call setbufvar(a:state.preview, '&modifiable', 1)
  call deletebufline(a:state.preview, 1, '$')
  call setbufline(a:state.preview, 1, lines)
  call setbufvar(a:state.preview, '&modifiable', 0)
endfunction

function! reviewhub#Collapse() abort
  let state = s:State()
  if empty(state) | return | endif
  let row = get(state.rows, string(line('.')), {})
  let key = string(get(row, 'number', 0))
  if has_key(state.expanded, key)
    call remove(state.expanded, key)
    call s:Render(state)
    for [lnum, value] in items(state.rows)
      if value.kind ==# 'pr' && value.number == get(row, 'number', 0)
        call cursor(str2nr(lnum), 1)
        break
      endif
    endfor
  endif
endfunction

function! reviewhub#Search() abort
  let state = s:State()
  if empty(state) | return | endif
  let state.query = input('GitHub search (e.g. is:open review-requested:@me): ', state.query)
  let state.page = 1
  let state.expanded = {}
  call s:List(state, 0)
endfunction

function! reviewhub#Refresh() abort
  let state = s:State()
  if empty(state) | return | endif
  let state.page = 1
  let state.expanded = {}
  let state.snapshots = {}
  call s:List(state, 0)
endfunction

function! reviewhub#OpenURL(url) abort
  let match = matchlist(a:url, '^https://\([^/]\+\)/\([^/]\+/[^/]\+\)/pull/\(\d\+\)')
  if empty(match)
    echoerr 'Use :ReviewOpen https://github.com/owner/repo/pull/123'
    return
  endif
  let connection = {'host': match[1], 'repo': match[2]}
  echom 'ReviewHub: loading PR…'
  call reviewhub#transport#Request({'op': 'open', 'connection': connection, 'number': str2nr(match[3])},
        \ function('s:OpenedURL', [connection]))
endfunction

function! s:OpenedURL(connection, result) abort
  if a:result.ok
    call reviewhub#bridge#Open(a:connection, a:result.data, -1)
  else
    echohl WarningMsg | echom 'ReviewHub: ' . a:result.error | echohl None
  endif
endfunction

function! reviewhub#Close() abort
  let state = s:State()
  if empty(state) | return | endif
  let state.generation += 1
  if tabpagenr('$') > 1 | tabclose | endif
  execute 'silent! bwipeout! ' . state.buf
  execute 'silent! bwipeout! ' . state.preview
  call remove(s:trees, state.id)
endfunction

function! reviewhub#Help() abort
  echo 'ReviewHub: j/k navigate; Enter/o/l expand PR or open file/conversation; h collapse; / GitHub search; R refresh; q close. In Revue: c comment, t threads, r reply, C conversation.'
endfunction

function! reviewhub#Inspect() abort
  return deepcopy(s:State())
endfunction
