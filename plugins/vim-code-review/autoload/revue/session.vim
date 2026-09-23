" Backend-neutral review sessions. All source buffers are snapshots.
let s:sessions = {}
let s:serial = 0

function! s:Id() abort
  let s:serial += 1
  return printf('%d_%d_%d', getpid(), localtime(), s:serial)
endfunction

function! s:Get() abort
  return get(s:sessions, get(b:, 'revue_session', get(t:, 'revue_session', '')), {})
endfunction

function! s:Label(snapshot) abort
  return get(a:snapshot, 'display_id', '#' . get(a:snapshot, 'number', ''))
endfunction

function! s:Notice(text) abort
  echohl WarningMsg
  echom 'revue: ' . a:text
  echohl None
endfunction

function! s:Buffer(session, role) abort
  enew
  let b:revue_buffer_prefix = 'revue://' . a:session.id . '/' . s:Id() . '/'
  call s:BufferName(a:role)
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nomodeline nowrap nowinfixwidth nowinfixheight
  let b:revue_session = a:session.id
  let b:revue_role = a:role
  call add(a:session.buffers, bufnr())
  call revue#maps#Apply(a:role)
  return bufnr()
endfunction

function! s:BufferName(role) abort
  let labels = {'threads': 'Discussion', 'timeline': 'History', 'assignment': 'Outcomes',
        \ 'assignment-selection': 'Assign comments', 'message-history': 'Edit history',
        \ 'pending': 'Pending review', 'file_comment': 'File comment', 'participant_run': 'Participant', 'apply_suggestion': 'Apply suggestion'}
  let label = get(labels, a:role, substitute(a:role, '^.', '\u&', ''))
  let name = get(b:, 'revue_buffer_prefix', '') . label
  if has_key(b:, 'revue_buffer_prefix') && bufname() !=# name
    silent execute 'file ' . fnameescape(name)
  endif
endfunction

function! s:Fill(buf, lines) abort
  if !bufexists(a:buf) | return | endif
  call revue#surface#Clear(a:buf)
  call setbufvar(a:buf, '&modifiable', 1)
  call deletebufline(a:buf, 1, '$')
  call setbufline(a:buf, 1, empty(a:lines) ? [''] : a:lines)
  call setbufvar(a:buf, '&modified', 0)
  call setbufvar(a:buf, '&modifiable', 0)
endfunction

function! s:DraftPath(key) abort
  let dir = get(g:, 'revue_draft_dir', expand('~/.vim/revue-drafts'))
  if !isdirectory(dir) | call mkdir(dir, 'p', 0700) | endif
  return dir . '/' . sha256(a:key) . '.json'
endfunction

function! s:Load(session) abort
  let a:session.draftpath = s:DraftPath(a:session.snapshot.key)
  let a:session.disk = filereadable(a:session.draftpath) ? join(readfile(a:session.draftpath), "\n") : ''
  let a:session.drafts = []
  let a:session.activity = []
  let a:session.refresh_state = {}
  let a:session.saved_navigation = {}
  let a:session.progress = {'marks': {}, 'observed': {}}
  let a:session.filefilters = {}
  let a:session.discussionfilters = {}
  let a:session.revealed_files = {}
  let a:session.read_state = {'known': {}, 'unread': {}, 'initialized': 0}
  if !empty(a:session.disk)
    let saved = json_decode(a:session.disk)
    if get(saved, 'version', 0) != 1 | throw 'Unsupported draft format; file retained at ' . a:session.draftpath | endif
    let a:session.drafts = saved.drafts
    let a:session.activity = get(saved, 'activity', [])
    let a:session.refresh_state = get(saved, 'refresh_state', {})
    if index(['refreshing', 'partial refresh'], get(a:session.refresh_state, 'status', '')) >= 0
      let a:session.refresh_state.status = 'interrupted'
      let a:session.refresh_state.error = ''
    endif
    let a:session.saved_navigation = get(saved, 'navigation', {})
    let a:session.progress = get(saved, 'progress', a:session.progress)
    let a:session.read_state = get(saved, 'read_state', a:session.read_state)
    for draft in a:session.drafts
      if draft.state ==# 'submitting' | let draft.state = 'unknown' | endif
      for step in get(draft, 'steps', [])
        if step.state ==# 'submitting' | let step.state = 'unknown' | endif
      endfor
    endfor
  endif
  for entry in reverse(copy(a:session.activity))
    if index(['accepted', 'observed'], entry.outcome) >= 0
      let a:session.last_outcome = entry.message
      let a:session.last_receipt = entry.receipt
      break
    endif
  endfor
  call revue#activity#Observe(a:session, a:session.snapshot)
endfunction

function! s:Save(session) abort
  if has_key(a:session, 'comparisons')
    if has_key(a:session, 'treewin') | call s:RememberSource(a:session) | endif
    call revue#comparisons#Remember(a:session)
  endif
  let path = a:session.draftpath
  " A short-lived atomic mkdir lock also covers two independent Vim processes.
  let lock = path . '.lock'
  try
    let acquired = mkdir(lock, '', 0700)
    if acquired != 1
      throw 'Draft is being saved by another Vim'
    endif
  catch
    let a:session.persistence_error = 'Cannot lock local review state: ' . lock
    call s:Notice('Cannot lock draft. Your text remains in this Vim: ' . lock)
    return 0
  endtry
  try
    let current = filereadable(path) ? join(readfile(path), "\n") : ''
    if current !=# a:session.disk
      throw 'Draft changed in another Vim; close the other session and reconcile ' . path
    endif
    let text = json_encode({'version': 1, 'key': a:session.snapshot.key, 'drafts': a:session.drafts,
          \ 'activity': a:session.activity, 'refresh_state': a:session.refresh_state, 'read_state': a:session.read_state,
          \ 'navigation': revue#comparisons#Navigation(a:session), 'progress': a:session.progress})
    let tmp = path . '.' . getpid() . '.tmp'
    if writefile([text], tmp) != 0 | throw 'Cannot write draft' | endif
    call setfperm(tmp, 'rw-------')
    if rename(tmp, path) != 0 | throw 'Cannot replace draft' | endif
    let a:session.disk = text
    let a:session.persistence_error = ''
    return 1
  catch
    let a:session.persistence_error = v:exception
    call s:Notice(v:exception)
    return 0
  finally
    call delete(lock, 'd')
  endtry
endfunction

function! revue#session#Open(snapshot, Host, index) abort
  if get(a:snapshot, 'version', 0) != 1 | throw 'Unsupported review API version' | endif
  for session in values(s:sessions)
    let live = filter([session.treewin, session.headwin, session.basewin, get(session, 'panelwin', 0)], {_, w -> w > 0 && win_id2tabwin(w)[0] > 0})
    if session.snapshot.key ==# a:snapshot.key && !empty(live)
      call win_gotoid(live[0])
      if a:index >= 0 | call s:Select(session, a:index) | else | call revue#session#Conversation() | endif
      return session.id
    endif
  endfor
  let session = {'id': s:Id(), 'snapshot': deepcopy(a:snapshot), 'Host': a:Host,
        \ 'buffers': [], 'index': -1, 'generation': 0, 'loaded': {}, 'cache': {},
        \ 'drafts': [], 'composer': -1, 'busy': 0, 'message': '', 'threadmap': {}}
  call s:Load(session)
  call revue#comparisons#Init(session)
  call s:Save(session)
  let s:sessions[session.id] = session
  tabnew
  let t:revue_session = session.id
  let session.tree = s:Buffer(session, 'files')
  let session.treewin = win_getid()
  setlocal winfixwidth nonumber norelativenumber cursorline
  rightbelow vnew
  let session.head = s:Buffer(session, 'head')
  let session.headwin = win_getid()
  call s:CodeMaps()
  aboveleft vnew
  let session.base = s:Buffer(session, 'base')
  let session.basewin = win_getid()
  call s:CodeMaps()
  call win_execute(session.treewin, 'vertical resize 32')
  call win_execute(session.headwin, 'wincmd =')
  call revue#layout#SetBar(session.treewin, ' Revue ' . substitute(s:Label(session.snapshot), '%', '%%', 'g'))
  call s:RenderTree(session)
  if a:index >= 0 && a:index < len(session.snapshot.files)
    " Size the initial source pane before the provider can deliver its file.
    " Synchronous providers otherwise render every card at two widths.
    if revue#layout#Narrow()
      call win_gotoid(session.headwin)
      call revue#layout#Focus(session)
    endif
    call s:Select(session, a:index)
  else
    call win_gotoid(session.headwin)
    call revue#session#Conversation()
  endif
  call s:CheckViewed(session)
  return session.id
endfunction

function! s:CodeMaps() abort
  setlocal number signcolumn=number
  augroup RevueCards
    autocmd! * <buffer>
    autocmd VimResized,WinEnter <buffer> call revue#session#ResizeCards()
    if exists('##WinResized')
      autocmd WinResized <buffer> call revue#session#ResizeCards()
    endif
  augroup END
endfunction

function! s:RenderTree(session) abort
  let treewin = get(a:session, 'treewin', 0)
  let treepos = revue#layout#Exists(treewin) ? getcurpos(treewin) : []
  let selected = empty(treepos) ? {} : get(get(a:session, 'rows', {}), string(treepos[1]), {})
  let snapshot = a:session.snapshot
  let lines = [s:Label(snapshot) . ' ' . snapshot.title, snapshot.author . ' · ' . snapshot.state,
        \ strpart(snapshot.base, 0, 8) . ' → ' . strpart(snapshot.head, 0, 8), '', 'Conversation', 'Files']
  let a:session.rows = {'5': {'kind': 'conversation'}}
  let visible = revue#discovery#Files(a:session)
  " Aggregate once per redraw; scanning every message for every file makes
  " large reviews quadratic. These are transient counts, never stale caches.
  let thread_counts = {}
  for thread in snapshot.threads + revue#local_feedback#Cards(a:session)
    let thread_counts[thread.path] = get(thread_counts, thread.path, 0) + 1
  endfor
  let unread_entries = revue#activity#Unread(a:session)
  let unread_counts = {}
  for entry in unread_entries
    let unread_counts[entry.path] = get(unread_counts, entry.path, 0) + 1
  endfor
  let viewed = len(filter(copy(snapshot.files), {_, f -> revue#progress#State(a:session, snapshot, f) ==# 'viewed'}))
  let checking = len(filter(copy(snapshot.files), {_, f -> revue#progress#State(a:session, snapshot, f) ==# 'checking'}))
  let lines[5] = printf('Files %d/%d · %d viewed (local)', len(visible), len(snapshot.files), viewed)
  for index in visible
    let file = snapshot.files[index]
    let comment_count = get(thread_counts, file.path, 0)
    let state = revue#progress#State(a:session, snapshot, file)
    let marker = state ==# 'viewed' ? ' [viewed]' : state ==# 'checking' ? ' [checking]' : state ==# 'unavailable' ? ' [unverified]' : ''
    call add(lines, printf('%s %s %s%s%s', index == a:session.index ? '▸' : ' ', toupper(file.status[0]), file.path, comment_count ? ' [' . comment_count . ']' : '', marker))
    let unread = get(unread_counts, file.path, 0)
    if unread | let lines[-1] .= ' [' . unread . ' new]' | endif
    if has_key(a:session.revealed_files, file.id) | let lines[-1] .= ' [revealed]' | endif
    let a:session.rows[string(len(lines))] = {'kind': 'file', 'index': index, 'id': file.id}
  endfor
  if empty(visible) | call add(lines, 'No files match. :ReviewFileFilter clear') | endif
  if a:session.index >= 0 && index(visible, a:session.index) < 0 | call add(lines, 'Current file is hidden by filters.') | endif
  call add(lines, 'File filters: ' . revue#discovery#Summary(a:session.filefilters))
  call extend(lines, revue#inventory#Lines(a:session, ['files']))
  if !empty(get(get(snapshot, 'feedback', {}), 'cursor', ''))
    call add(lines, 'More feedback available · :ReviewLoadMoreFeedback')
    call add(lines, 'Thread counts and filters cover loaded feedback.')
  endif
  if checking | call add(lines, checking . ' files awaiting content verification.') | endif
  call add(lines, 'All discussions · :ReviewDiscussions')
  let a:session.rows[string(len(lines))] = {'kind': 'discussions'}
  if has_key(snapshot, 'pending_reviews')
    call add(lines, 'Backend pending reviews · ' . (get(snapshot.pending_reviews, 'available', 0) ? len(get(snapshot.pending_reviews, 'items', [])) : 'unavailable'))
    let a:session.rows[string(len(lines))] = {'kind': 'pending'}
  endif
  let local = revue#local_feedback#Enabled(a:session)
  call extend(lines, ['', (local ? 'Pending feedback / operations' : 'Drafts') . ' (' . len(a:session.drafts) . ')'])
  if local | call add(lines, 'Collect feedback · :ReviewBatch · Markdown buffer') | endif
  for draft in a:session.drafts
    call add(lines, '  ' . (local && revue#local_feedback#IsFeedback(draft) && draft.state ==# 'draft' ? 'Pending' : draft.state) . ' · ' . revue#suggestion#Label(draft) . ' ' . (draft.kind ==# 'batch' ? '(' . len(draft.items) . ' drafts)' : get(draft, 'path', '')))
    let a:session.rows[string(len(lines))] = {'kind': 'draft', 'id': draft.id}
  endfor
  let buf = a:session.tree
  call add(lines, '')
  call add(lines, 'Activity · ' . len(a:session.activity) . ' outcomes · ' . len(unread_entries) . ' new messages')
  let a:session.rows[string(len(lines))] = {'kind': 'activity'}
  if has_key(get(snapshot, 'capabilities', {}), 'timeline')
    call add(lines, 'Review history · :ReviewTimeline')
    let a:session.rows[string(len(lines))] = {'kind': 'timeline'}
  endif
  call extend(lines, ['', s:Hint(buf, 'open') . ' open · ' . s:Hint(buf, 'next-file') . '/' . s:Hint(buf, 'previous-file') . ' file',
        \ s:Hint(buf, 'conversation') . ' conversation · ' . s:Hint(buf, 'review') . ' review',
        \ s:Hint(buf, 'refresh') . ' refresh · ' . s:Hint(buf, 'close') . ' close', s:Hint(buf, 'help') . ' help', '', a:session.message])
  if !empty(get(a:session, 'last_outcome', '')) | call add(lines, a:session.last_outcome) | endif
  if !empty(get(a:session, 'persistence_error', '')) | call add(lines, 'NOT SAVED: ' . a:session.persistence_error) | endif
  if a:session.snapshot.snapshot !=# a:session.latest_comparison
    call add(lines, 'Historical comparison · :ReviewLatest opens latest')
  endif
  if has_key(snapshot, 'context')
    call extend(lines, ['Original code context', revue#message#OneLine(get(snapshot.context, 'label', '')),
          \ revue#message#OneLine(get(snapshot.context, 'basis', '')),
          \ empty(get(a:session, 'context_return', {})) ? ':ReviewLatest opens latest' : ':ReviewReturnContext returns'])
  endif
  call add(lines, ':ReviewComparisons · ' . len(a:session.comparisons) . ' observed comparisons')
  for side in ['base', 'head']
    if revue#layout#Exists(get(a:session, side . 'win', 0))
      let path = a:session.index < 0 ? '(no changed files)' : snapshot.files[a:session.index].path
      call revue#layout#SetBar(a:session[side . 'win'], ' ' . side . ' ' . strpart(snapshot[side], 0, 12) . ' · ' . substitute(path, '%', '%%', 'g') . (has_key(snapshot, 'context') ? ' [original code context]' : snapshot.snapshot ==# a:session.latest_comparison ? ' [latest]' : ' [historical]'))
    endif
  endfor
  call s:Fill(a:session.tree, lines)
  if !empty(selected)
    " A filter or asynchronous update must not put another action under the cursor.
    let row = 6
    for [candidate, target] in items(a:session.rows)
      if target.kind ==# selected.kind && get(target, 'id', '') ==# get(selected, 'id', '')
        let row = str2nr(candidate)
        break
      endif
    endfor
    call win_execute(treewin, 'call cursor(' . row . ', ' . treepos[2] . ')')
  endif
endfunction

function! s:Hint(buf, action) abort
  for binding in getbufvar(a:buf, 'revue_bindings', [])
    if binding.id ==# a:action | return empty(binding.key) ? ':' . binding.command : binding.key | endif
  endfor
  return ''
endfunction

function! revue#session#Activate() abort
  let session = s:Get()
  if empty(session) | return | endif
  let row = get(session.rows, string(line('.')), {})
  if get(row, 'kind', '') ==# 'file'
    call s:Select(session, row.index)
  elseif get(row, 'kind', '') ==# 'draft'
    call s:Composer(session, row.id)
  elseif get(row, 'kind', '') ==# 'conversation'
    call revue#session#Conversation()
  elseif get(row, 'kind', '') ==# 'discussions'
    call revue#session#Discussions()
  elseif get(row, 'kind', '') ==# 'activity'
    call revue#session#Activity()
  elseif get(row, 'kind', '') ==# 'timeline'
    call revue#session#Timeline()
  elseif get(row, 'kind', '') ==# 'pending'
    call revue#session#Pending()
  endif
endfunction

function! revue#session#Next(delta) abort
  let session = s:Get()
  if empty(session) | return | endif
  if a:delta == 0 | call s:Select(session, session.index) | return | endif
  let visible = revue#discovery#Files(session)
  if a:delta < 0 | call reverse(visible) | endif
  let candidates = filter(visible, {_, i -> a:delta > 0 ? i > session.index : i < session.index})
  let offset = abs(a:delta) - 1
  if offset >= len(candidates) | call s:Notice('No further files match the active filters.') | return | endif
  call s:Select(session, candidates[offset])
endfunction

function! s:RememberSource(session) abort
  if a:session.index < 0 || empty(a:session.loaded) | return | endif
  let views = {}
  for side in ['base', 'head']
    let win = a:session[side . 'win']
    if revue#layout#Exists(win) && winbufnr(win) == a:session[side]
      call win_execute(win, 'let w:revue_source_view = winsaveview()')
      let views[side] = revue#layout#Get(win, 'revue_source_view')
    endif
  endfor
  let a:session.sourceviews[a:session.snapshot.files[a:session.index].id] = views
endfunction

function! s:Select(session, index, ...) abort
  if a:index < 0 || a:index >= len(a:session.snapshot.files) | return | endif
  let options = a:0 ? a:1 : {}
  " A reader may live in another tab. Reuse the source tab before rebuilding
  " a genuinely missing pane; tab-local lookup would duplicate the entire diff.
  let selected_side = a:session.index >= 0 && get(b:, 'revue_role', '') ==# 'base' ? 'base' : 'head'
  let source_found = 0
  for name in ['head', 'base', 'tree']
    let win = a:session[name . 'win']
    if revue#layout#Exists(win) && winbufnr(win) == a:session[name]
      let source_found = 1
      if win_id2tabwin(win)[0] != tabpagenr() | call win_gotoid(win) | endif
      break
    endif
  endfor
  if !source_found
    tabnew
    let t:revue_session = a:session.id
    execute 'buffer ' . a:session.tree
    let a:session.treewin = win_getid()
    setlocal winfixwidth nonumber norelativenumber cursorline nowrap
    call s:Notice('Source windows were closed; reopened the review in a new tab.')
  endif
  if index(revue#discovery#Files(a:session), a:index) < 0
    let a:session.revealed_files[a:session.snapshot.files[a:index].id] = 1
  endif
  call s:RememberSource(a:session)
  for side in ['base', 'head']
    if win_id2win(a:session[side . 'win']) <= 0 || winbufnr(a:session[side . 'win']) != a:session[side]
      rightbelow vnew
      execute 'buffer ' . a:session[side]
      let a:session[side . 'win'] = win_getid()
      call s:CodeMaps()
    endif
  endfor
  let focus_side = get(options, 'side', selected_side)
  let a:session.index = a:index
  let a:session.generation += 1
  let file = a:session.snapshot.files[a:index]
  let a:session.loadviews = extend(deepcopy(get(a:session.sourceviews, file.id, {})), get(options, 'views', {}))
  let a:session.loadjump = get(options, 'jump', {})
  let a:session.loaded = {}
  for side in ['base', 'head']
    call revue#moves#Clear(a:session[side], 'ReviewMoves_' . a:session.id)
    call sign_unplace('RevueThreads_' . a:session.id, {'buffer': a:session[side]})
    call setbufvar(a:session[side], 'revue_file', file.path)
    call setbufvar(a:session[side], 'revue_comparison', a:session.snapshot.snapshot)
  endfor
  let a:session.message = 'Loading ' . file.path
  call s:Fill(a:session.head, ['Loading ' . file.path . '…'])
  call s:Fill(a:session.base, ['Loading base revision…'])
  call s:RenderTree(a:session)
  call win_gotoid(a:session[focus_side . 'win'])
  if get(a:session, 'focus_win', 0) > 0 && a:session.focus_win != win_getid()
    call revue#layout#Focus(a:session)
  endif
  if has_key(a:session.cache, file.id)
    call s:FileLoaded(a:session.id, a:session.generation, {'ok': 1, 'data': a:session.cache[file.id]})
    return
  endif
  call a:session.Host({'op': 'file', 'snapshot': a:session.snapshot, 'file': file},
        \ function('s:FileLoaded', [a:session.id, a:session.generation]))
endfunction

function! s:FileLoaded(id, generation, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || session.generation != a:generation | return | endif
  if !a:result.ok
    call revue#progress#Observe(session, session.snapshot, session.snapshot.files[session.index], {})
    let session.message = a:result.error
    call s:Fill(session.head, [a:result.error])
    call s:Annotations(session)
    call s:RenderTree(session)
    return
  endif
  let session.loaded = a:result.data
  let file = session.snapshot.files[session.index]
  let session.cache[file.id] = a:result.data
  call revue#progress#Observe(session, session.snapshot, file, a:result.data)
  for side in ['base', 'head']
    let content = a:result.data[side]
    let lines = content.kind ==# 'text' || content.kind ==# 'absent' ? content.lines : ['[' . content.kind . '] ' . get(content, 'message', 'Open the file on the provider website.')]
    call s:Fill(session[side], lines)
    call setbufvar(session[side], 'revue_side', side)
    call setbufvar(session[side], 'revue_file', file.path)
    let ext = fnamemodify(file.path, ':e')
    let ft = get({'py': 'python', 'js': 'javascript', 'ts': 'typescript', 'md': 'markdown', 'rb': 'ruby', 'rs': 'rust', 'sh': 'sh'}, ext, ext)
    if ft =~# '^\w\+$' | call setbufvar(session[side], '&filetype', ft) | endif
    call win_execute(session[side . 'win'], 'diffthis')
    call revue#layout#SetBar(session[side . 'win'], ' ' . side . ' ' . strpart(session.snapshot[side], 0, 8) . ' · ' . substitute(file.path, '%', '%%', 'g'))
  endfor
  let moves = revue#moves#Detect(session.snapshot.files)
  for side in ['base', 'head']
    call revue#moves#Paint(session[side], side, file.id, moves, 'ReviewMoves_' . session.id)
  endfor
  let session.message = file.path . ' · ' . s:Hint(session.head, 'reply') . ' reply · ' . s:Hint(session.head, 'threads') . ' threads'
  call s:Annotations(session)
  for [side, view] in items(get(session, 'loadviews', {}))
    if winbufnr(session[side . 'win']) == session[side]
      call win_execute(session[side . 'win'], 'call winrestview(' . string(view) . ')')
    endif
  endfor
  let session.loadviews = {}
  if !empty(get(session, 'loadjump', {}))
    let jump = session.loadjump
    call win_execute(session[jump.side . 'win'], ['call cursor(' . jump.line . ', 1)', 'normal! zv', 'normal! zz'])
    let session.loadjump = {}
  endif
  call s:RenderTree(session)
endfunction

function! s:CardWidth(session, side) abort
  let available = s:PaneWidth(a:session, a:side)
  let limit = get(g:, 'revue_comment_width', 100)
  return limit > 0 ? min([available, max([12, limit])]) : available
endfunction

function! s:PaneWidth(session, side) abort
  let info = getwininfo(a:session[a:side . 'win'])
  return empty(info) ? 40 : max([12, info[0].width - info[0].textoff - 2])
endfunction

function! revue#session#ResizeCards() abort
  let session = s:Get()
  if empty(session) || empty(session.loaded) || get(session, 'defer_card_resize', 0) | return | endif
  " A new reader tab briefly inherits the source buffer during WinEnter.
  " Reflow only when a source pane is visible in this tab; its next WinEnter
  " will catch up after returning. Data refresh still calls Annotations directly.
  if win_id2tabwin(session.basewin)[0] != tabpagenr() && win_id2tabwin(session.headwin)[0] != tabpagenr()
    return
  endif
  let widths = [s:CardWidth(session, 'base'), s:CardWidth(session, 'head')]
  let panes = [s:PaneWidth(session, 'base'), s:PaneWidth(session, 'head')]
  if widths != get(session, 'cardwidths', []) || panes != get(session, 'cardpanewidths', []) | call s:Annotations(session) | endif
endfunction

function! s:Annotations(session) abort
  call revue#comments#Setup()
  let group = 'RevueThreads_' . a:session.id
  let a:session.cardwidths = [s:CardWidth(a:session, 'base'), s:CardWidth(a:session, 'head')]
  let a:session.cardpanewidths = [s:PaneWidth(a:session, 'base'), s:PaneWidth(a:session, 'head')]
  for side in ['base', 'head']
    call sign_unplace(group, {'buffer': a:session[side]})
    for name in ['ReviewThread'] + revue#comments#Types()
      if !empty(prop_type_get(name))
        call prop_remove({'bufnr': a:session[side], 'type': name, 'all': 1}, 1, len(getbufline(a:session[side], 1, '$')))
      endif
    endfor
  endfor
  if a:session.index < 0
    let a:session.card_body_caches = {}
    return
  endif
  let file = a:session.snapshot.files[a:session.index]
  let sources = {'base': getbufline(a:session.base, 1, '$'), 'head': getbufline(a:session.head, 1, '$')}
  let previous_caches = get(a:session, 'card_body_caches', {})
  let a:session.card_body_caches = {}
  for thread in a:session.snapshot.threads + revue#local_feedback#Cards(a:session)
    let file_thread = revue#anchor#IsFile(thread)
    if thread.path !=# file.path || thread.outdated || (!file_thread && thread.line <= 0) | continue | endif
    let side = file_thread ? get(get(a:session.loaded, 'head', {}), 'kind', '') ==# 'absent' ? 'base' : 'head' : thread.side
    if (!file_thread && get(get(a:session.loaded, side, {}), 'kind', '') !=# 'text') || empty(thread.comments) | continue | endif
    let buf = a:session[side]
    let placement = file_thread ? 1 : thread.line
    if placement > len(getbufline(buf, 1, '$')) | continue | endif
    let state_hint = ''
    if !file_thread && has_key(thread, 'resolved') && empty(revue#capabilities#Error(a:session.snapshot, {'kind': 'thread_state', 'thread': thread.id, 'resolved': !thread.resolved}, 0))
      let state_hint = s:Hint(buf, thread.resolved ? 'reopen' : 'resolve') . (thread.resolved ? ' reopen thread' : ' resolve thread')
    endif
    let pending_state = revue#thread_state#Pending(a:session, thread.id)
    if !empty(pending_state) | let state_hint = revue#thread_state#Status(pending_state) | endif
    let context = {'lines': file_thread ? [] : sources[side], 'author': a:session.snapshot.author,
          \ 'reply_hint': file_thread ? ':ReviewFileThreads then :ReviewReply' : s:Hint(buf, 'reply'),
          \ 'thread_hint': s:Hint(buf, file_thread ? 'file-threads' : 'thread'), 'state_hint': state_hint,
          \ 'outer_width': s:PaneWidth(a:session, side), 'unread': a:session.read_state.unread}
    " At most eight displayed threads retain body rows; other threads still
    " render in full. Never persist these presentation-only caches.
    if len(a:session.card_body_caches) < 8
      let cache_key = file.id . ':' . thread.id
      let context.body_cache = get(previous_caches, cache_key, {})
      let a:session.card_body_caches[cache_key] = context.body_cache
    endif
    let rows = revue#comments#Rows(thread, s:CardWidth(a:session, side), context)
    try
      for row in rows
        call prop_add(placement, 0, {'bufnr': buf, 'type': row.type, 'text': row.text, 'text_align': file_thread ? 'above' : 'below', 'text_padding_left': 1})
      endfor
      if get(g:, 'revue_thread_separators', 1)
        call sign_place(0, group, 'RevueThreadBoundary', buf, {'lnum': placement, 'priority': 100})
      endif
    catch
      " Older Vim builds may lack virtual text; the thread panel is still available.
    endtry
  endfor
endfunction

function! s:ComparisonSelection(session) abort
  if get(b:, 'revue_view', '') !=# 'comparisons' | return {} | endif
  let id = get(get(a:session, 'comparisonrows', {}), string(line('.')), '')
  if empty(id) | return {} | endif
  let rows = sort(map(filter(items(a:session.comparisonrows), {_, pair -> pair[1] ==# id}), {_, pair -> str2nr(pair[0])}), 'n')
  return {'id': id, 'first': rows[0], 'offset': line('.') - rows[0]}
endfunction

function! s:ComparisonView(session, view, target) abort
  let view = deepcopy(a:view)
  let rows = sort(map(filter(items(get(a:session, 'comparisonrows', {})), {_, pair -> pair[1] ==# get(a:target, 'id', '')}), {_, pair -> str2nr(pair[0])}), 'n')
  if empty(rows)
    let view.lnum = 1 | let view.topline = 1
  else
    let delta = rows[0] - a:target.first
    let view.lnum = min([rows[-1], rows[0] + a:target.offset])
    let view.topline = max([1, view.topline + delta])
  endif
  return view
endfunction

function! s:Origin() abort
  let session = s:Get()
  return {'win': win_getid(), 'buf': bufnr(), 'view': winsaveview(),
        \ 'parent': deepcopy(get(b:, 'revue_origin', {})),
        \ 'discovery': get(b:, 'revue_view', '') ==# 'discussions' ? deepcopy(get(get(session, 'discoveryrows', {}), string(line('.')), {})) : {},
        \ 'comparison_target': s:ComparisonSelection(session),
        \ 'history': deepcopy(get(get(session, 'message_history', {}), 'target', {})),
        \ 'history_row': get(b:, 'revue_view', '') ==# 'message-history' ? deepcopy(get(get(session, 'historyrows', {}), string(line('.')), {})) : {},
        \ 'timeline_target': get(b:, 'revue_view', '') ==# 'timeline' ? deepcopy(get(get(session, 'timelinerows', {}), string(line('.')), {})) : {},
        \ 'readiness_target': get(b:, 'revue_view', '') ==# 'readiness' ? deepcopy(get(get(session, 'readinessrows', {}), string(line('.')), {})) : {},
        \ 'assignment_detail': get(get(session, 'assignments', {}), 'detail', ''),
        \ 'assignment_row': index(['assignments', 'assignment'], get(b:, 'revue_view', '')) >= 0 ? deepcopy(get(get(session, 'assignment_view_rows', {}), string(line('.')), {})) : {},
        \ 'tick': b:changedtick, 'role': get(b:, 'revue_role', ''),
        \ 'reaction': get(b:, 'revue_view', '') ==# 'reactions' ? deepcopy(get(session, 'reaction_target', {})) : {},
        \ 'focused': get(session, 'focus_win', 0) == win_getid(), 'comparison': get(session.snapshot, 'snapshot', ''),
        \ 'path': get(b:, 'revue_file', ''), 'side': get(b:, 'revue_side', ''),
        \ 'fileindex': session.index, 'message': deepcopy(get(get(session, 'messagemap', {}), string(line('.')), {})),
        \ 'kind': get(b:, 'revue_view', ''), 'thread': get(session, 'panelthread', ''), 'batch': get(session, 'batchid', '')}
endfunction

function! s:Return(session, origin) abort
  let origin = a:origin
  let comparison = get(origin, 'comparison', a:session.snapshot.snapshot)
  if comparison !=# a:session.snapshot.snapshot
    if !has_key(a:session.comparisons, comparison)
      call s:Notice('Original comparison is unavailable; current comparison retained.')
      return
    endif
    call s:SwitchComparison(a:session, comparison)
  endif
  if !empty(get(origin, 'path', '')) && index(['base', 'head'], get(origin, 'side', '')) >= 0
    let index = index(map(copy(a:session.snapshot.files), {_, file -> file.path}), origin.path)
    if index >= 0
      " The source can stay loaded while reading in another tab. Returning to
      " that same comparison/file needs its view restored, not a file reload.
      let window = a:session[origin.side . 'win']
      if index == a:session.index && !empty(a:session.loaded) &&
            \ getbufvar(a:session[origin.side], 'revue_comparison', '') ==# comparison &&
            \ revue#layout#Exists(a:session.basewin) && winbufnr(a:session.basewin) == a:session.base &&
            \ revue#layout#Exists(a:session.headwin) && winbufnr(a:session.headwin) == a:session.head &&
            \ revue#layout#Exists(window) && winbufnr(window) == a:session[origin.side]
        call win_gotoid(window)
        if get(origin, 'focused', 0) && get(a:session, 'focus_win', 0) != window
          call revue#layout#Focus(a:session)
        endif
        call winrestview(origin.view)
        call revue#session#ResizeCards()
        return
      endif
      call s:Select(a:session, index, {'side': origin.side, 'views': {origin.side: origin.view}})
      if get(origin, 'focused', 0) | call revue#layout#Focus(a:session) | endif
      return
    endif
    call s:Notice('Original file is unavailable in this comparison.')
  endif
  if !empty(origin) && win_gotoid(origin.win) && bufnr() == origin.buf
    if empty(origin.path) || get(b:, 'revue_file', '') ==# origin.path
      if get(origin, 'kind', '') ==# 'batch'
        call revue#session#Batch(get(origin, 'batch', ''))
      elseif get(origin, 'kind', '') ==# 'feedback'
        call revue#session#Feedback()
      endif
      if get(origin, 'kind', '') ==# 'threads' || get(origin, 'kind', '') !=# get(b:, 'revue_view', '')
        if get(origin, 'kind', '') ==# 'threads'
          if empty(get(origin, 'thread', '')) && get(origin, 'fileindex', -1) >= 0 && origin.fileindex != a:session.index
            call s:Select(a:session, origin.fileindex)
          endif
          call revue#session#Threads(get(origin, 'thread', ''))
        elseif get(origin, 'kind', '') ==# 'conversation'
          call revue#session#Conversation()
        elseif get(origin, 'kind', '') ==# 'comparisons'
          call revue#session#Comparisons()
        elseif get(origin, 'kind', '') ==# 'activity'
          call revue#session#Activity()
        elseif index(['assignments', 'assignment'], get(origin, 'kind', '')) >= 0
          call revue#session#Assignments(get(origin, 'assignment_detail', ''))
        elseif get(origin, 'kind', '') ==# 'assignment-selection'
          call revue#session#AssignmentSelection()
        elseif get(origin, 'kind', '') ==# 'reanchor'
          call revue#session#ReanchorPreview()
        elseif get(origin, 'kind', '') ==# 'message-history'
          call revue#session#MessageHistory(origin.history)
        elseif get(origin, 'kind', '') ==# 'timeline'
          call revue#session#Timeline()
        elseif get(origin, 'kind', '') ==# 'readiness'
          call revue#session#Readiness()
        elseif get(origin, 'kind', '') ==# 'discussions'
          call revue#session#Discussions()
        elseif get(origin, 'kind', '') ==# 'reactions'
          call revue#session#Reactions(origin.reaction)
        elseif get(origin, 'kind', '') ==# 'pending'
          call revue#session#Pending()
        endif
      endif
      call s:RestoreOriginView(a:session, origin)
      return
    endif
  endif
  let kind = get(origin, 'kind', '')
  if index(['threads', 'conversation', 'activity', 'timeline', 'service-progress', 'readiness', 'comparisons', 'discussions', 'reactions', 'pending', 'message-history', 'reanchor', 'assignment-selection', 'assignments', 'assignment'], kind) >= 0
    if kind ==# 'threads'
      if empty(get(origin, 'thread', '')) && get(origin, 'fileindex', -1) >= 0
        call s:Select(a:session, origin.fileindex)
      endif
      call revue#session#Threads(get(origin, 'thread', ''))
    elseif kind ==# 'conversation'
      call revue#session#Conversation()
    elseif kind ==# 'activity'
      call revue#session#Activity()
    elseif index(['assignments', 'assignment'], kind) >= 0
      call revue#session#Assignments(get(origin, 'assignment_detail', ''))
    elseif kind ==# 'assignment-selection'
      call revue#session#AssignmentSelection()
    elseif kind ==# 'reanchor'
      call revue#session#ReanchorPreview()
    elseif kind ==# 'message-history'
      call revue#session#MessageHistory(origin.history)
    elseif kind ==# 'timeline'
      call revue#session#Timeline()
    elseif kind ==# 'service-progress'
      call revue#session#ServiceProgress(1)
    elseif kind ==# 'readiness'
      call revue#session#Readiness()
    elseif kind ==# 'discussions'
      call revue#session#Discussions()
    elseif kind ==# 'reactions'
      call revue#session#Reactions(origin.reaction)
    elseif kind ==# 'pending'
      call revue#session#Pending()
    else
      call revue#session#Comparisons()
    endif
    call s:RestoreOriginView(a:session, origin)
    return
  endif
  let draft = s:Draft(a:session, getbufvar(get(origin, 'buf', -1), 'revue_draft', ''))
  if !empty(draft)
    call s:Composer(a:session, draft.id)
    call s:RestoreOriginView(a:session, origin)
    return
  endif
  for win in [get(a:session, 'headwin', 0), get(a:session, 'basewin', 0), get(a:session, 'treewin', 0)]
    if win_gotoid(win) | return | endif
  endfor
endfunction

function! s:RestoreOriginView(session, origin) abort
  let view = deepcopy(a:origin.view)
  if index(['assignments', 'assignment'], get(a:origin, 'kind', '')) >= 0
    let view = revue#assignment#Restore(view, get(a:origin, 'assignment_row', {}), get(a:session, 'assignment_view_rows', {}))
  endif
  if get(a:origin, 'kind', '') ==# 'comparisons'
    let view = s:ComparisonView(a:session, view, get(a:origin, 'comparison_target', {}))
  endif
  if get(a:origin, 'kind', '') ==# 'message-history'
    let view = revue#timeline#Restore(view, get(a:origin, 'history_row', {}), get(a:session, 'historyrows', {}))
  endif
  if get(a:origin, 'kind', '') ==# 'timeline'
    let view = revue#timeline#Restore(view, get(a:origin, 'timeline_target', {}), get(a:session, 'timelinerows', {}))
  endif
  if get(a:origin, 'kind', '') ==# 'readiness'
    let view = revue#timeline#Restore(view, get(a:origin, 'readiness_target', {}), get(a:session, 'readinessrows', {}))
  endif
  if has_key(a:origin, 'parent') && get(b:, 'revue_role', '') ==# 'discussion'
    let b:revue_origin = deepcopy(a:origin.parent)
  endif
  let selected = get(a:origin, 'message', {})
  let discovery = get(a:origin, 'discovery', {})
  if !empty(discovery) && get(a:origin, 'kind', '') ==# 'discussions'
    let found = 0
    for row in sort(keys(a:session.discoveryrows), 'n')
      if revue#discovery#Key(a:session.discoveryrows[row]) ==# revue#discovery#Key(discovery)
        let delta = str2nr(row) - discovery.start
        let view.lnum += delta
        let view.topline = max([1, view.topline + delta])
        let found = 1
        break
      endif
    endfor
    if !found | let view.lnum = 1 | let view.topline = 1 | endif
  endif
  if index(['threads', 'conversation'], get(a:origin, 'kind', '')) >= 0 && !empty(selected) && !empty(selected.comment)
    for target in values(a:session.messagemap)
      if target.thread ==# selected.thread && target.comment ==# selected.comment && target.kind ==# selected.kind
        let delta = target.start - selected.start
        let view.lnum = min([target.end, view.lnum + delta])
        let view.topline = max([1, view.topline + delta])
        break
      endif
    endfor
  endif
  call winrestview(view)
  call revue#session#MessageFocus()
  if get(a:origin, 'focused', 0) && get(a:session, 'focus_win', 0) != win_getid()
    call revue#layout#Focus(a:session)
  endif
endfunction

function! revue#session#CloseView() abort
  let session = s:Get()
  if empty(session) | return | endif
  if index(['discussion', 'draft'], get(b:, 'revue_role', '')) < 0
    if get(session, 'focus_win', 0) == win_getid()
      call revue#session#RestoreLayout()
      return
    endif
    call revue#session#Close()
    return
  endif
  if get(b:, 'revue_role', '') ==# 'draft'
    call revue#session#SaveDraft()
    if &modified | call s:Notice('Draft could not be saved; keep this window open.') | return | endif
  endif
  let origin = get(b:, 'revue_origin', {})
  let layout = get(w:, 'revue_previous_layout', {})
  " Closing a reader crosses intermediate source sizes before restoring focus.
  " Keep data refresh active, but reflow source cards only at the final size.
  let previous = get(session, 'defer_card_resize', 0)
  let session.defer_card_resize = 1
  try
    call revue#layout#Unfocus(session)
    close
    call revue#layout#Restore(layout)
    call s:Return(session, origin)
  finally
    let session.defer_card_resize = previous
    call revue#session#ResizeCards()
  endtry
endfunction

function! revue#session#Focus() abort
  let session = s:Get()
  if empty(session) | return | endif
  call revue#layout#Focus(session)
  call revue#session#ResizeCards()
  call s:Notice(get(session, 'focus_win', 0) ? 'Focused reading. :ReviewRestoreLayout restores split sizes; :ReviewClose returns.' : 'Split sizes restored.')
endfunction

function! revue#session#RestoreLayout() abort
  let session = s:Get()
  if empty(session) | return | endif
  if get(t:, 'revue_reader', '') ==# session.id && winnr('$') == 1 && index(['discussion', 'draft'], get(b:, 'revue_role', '')) >= 0
    call revue#session#CloseView()
    return
  endif
  call revue#layout#Unfocus(session)
  call revue#session#ResizeCards()
endfunction

function! revue#session#ToggleFiles() abort
  let session = s:Get()
  if empty(session) | return | endif
  let current = win_getid()
  let focused = get(session, 'focus_win', 0) == current
  call revue#layout#Unfocus(session)
  for name in ['head', 'base', 'tree']
    let win = session[name . 'win']
    if revue#layout#Exists(win) && winbufnr(win) == session[name]
      if win_id2tabwin(win)[0] != tabpagenr() | call win_gotoid(win) | endif
      break
    endif
  endfor
  if session.treewin > 0 && revue#layout#Exists(session.treewin) && winbufnr(session.treewin) == session.tree
    if winnr('$') == 1 | call s:Notice('Keep a code or discussion window open before hiding files.') | return | endif
    let session.files_layout = revue#layout#Capture()
    let session.files_oldwin = session.treewin
    let session.files_width = getwininfo(session.treewin)[0].width
    call win_gotoid(session.treewin)
    hide close
    let session.treewin = 0
  else
    if !win_gotoid(session.basewin) | call win_gotoid(session.headwin) | endif
    execute 'leftabove vertical sbuffer ' . session.tree
    let session.treewin = win_getid()
    setlocal winfixwidth nonumber norelativenumber cursorline nowrap
    call revue#layout#SetBar(win_getid(), ' Revue ' . substitute(s:Label(session.snapshot), '%', '%%', 'g'))
    execute 'vertical resize ' . get(session, 'files_width', 32)
    if has_key(session, 'files_layout')
      call revue#layout#ReplaceWindow(session.files_layout, session.files_oldwin, session.treewin)
      call revue#layout#Restore(session.files_layout)
      for buf in session.buffers
        let origin = getbufvar(buf, 'revue_origin', {})
        if get(origin, 'win', 0) == session.files_oldwin
          let origin.win = session.treewin
          call setbufvar(buf, 'revue_origin', origin)
        endif
      endfor
      for info in getwininfo()
        if info.tabnr == tabpagenr()
          let previous = getwinvar(info.winid, 'revue_previous_layout', {})
          call revue#layout#ReplaceWindow(previous, session.files_oldwin, session.treewin)
          call setwinvar(info.winid, 'revue_previous_layout', previous)
        endif
      endfor
    endif
  endif
  if !win_gotoid(current) | call win_gotoid(session.headwin) | endif
  if focused | call revue#layout#Focus(session) | endif
  call revue#session#ResizeCards()
endfunction

function! s:Panel(session, kind) abort
  let origin = s:Origin()
  if a:kind ==# 'preview'
    if !(get(a:session, 'previewwin', 0) && winbufnr(a:session.previewwin) == get(a:session, 'preview', -1) && win_gotoid(a:session.previewwin))
      call revue#layout#New(a:session, 16)
      let a:session.preview = s:Buffer(a:session, 'discussion')
      let a:session.previewwin = win_getid()
      setlocal wrap linebreak nonumber norelativenumber signcolumn=no filetype=markdown
      if revue#layout#Narrow() || origin.focused | call revue#layout#Focus(a:session) | endif
    endif
    let b:revue_origin = origin
    let b:revue_view = 'preview'
    call s:BufferName('preview')
    if origin.buf != a:session.preview && (revue#layout#Narrow() || origin.focused) && get(a:session, 'focus_win', 0) != win_getid()
      call revue#layout#Focus(a:session)
    endif
    call revue#layout#SetBar(win_getid(), ' Revue preview | :ReviewClose returns to editing ')
    call revue#maps#Apply('preview')
    return a:session.preview
  endif
  if !(get(a:session, 'panelwin', 0) && winbufnr(a:session.panelwin) == get(a:session, 'panel', -1) && win_gotoid(a:session.panelwin))
    call revue#layout#New(a:session, 14)
    let a:session.panel = s:Buffer(a:session, 'discussion')
    let a:session.panelwin = win_getid()
    let b:revue_origin = origin
    setlocal wrap linebreak nonumber norelativenumber signcolumn=no filetype=markdown
    if revue#layout#Narrow() || origin.focused | call revue#layout#Focus(a:session) | endif
  elseif origin.buf != a:session.panel
    let b:revue_origin = origin
    if (revue#layout#Narrow() || origin.focused) && get(a:session, 'focus_win', 0) != win_getid()
      call revue#layout#Focus(a:session)
    endif
  endif
  let a:session.panelkind = a:kind
  let a:session.threadmap = {}
  let a:session.messagemap = {}
  let a:session.activityrows = {}
  let a:session.discoveryrows = {}
  let a:session.reactionrows = {}
  let a:session.pendingrows = {}
  let a:session.timelinerows = {}
  let a:session.readinessrows = {}
  let a:session.historyrows = {}
  if get(b:, 'revue_view', '') !=# a:kind | let b:revue_markdown_cache = {} | endif
  let b:revue_view = a:kind
  call s:BufferName(a:kind)
  call revue#layout#SetBar(win_getid(), ' Revue ' . a:kind . ' | ' . strpart(a:session.snapshot.base, 0, 8) . ' → ' . strpart(a:session.snapshot.head, 0, 8) . (has_key(a:session.snapshot, 'context') ? ' [original code context]' : a:session.snapshot.snapshot ==# a:session.latest_comparison ? ' [latest]' : ' [historical]') . ' | :ReviewClose ')
  call revue#maps#Apply(a:kind)
  augroup RevueMessageFocus
    autocmd! * <buffer>
    autocmd CursorMoved,WinEnter <buffer> call revue#session#MessageFocus()
    autocmd BufLeave <buffer> call revue#session#MessageFocus(0)
  augroup END
  call revue#session#MessageFocus()
  return a:session.panel
endfunction

function! revue#session#MessageFocus(...) abort
  for match in getmatches()
    if match.id == get(w:, 'revue_message_focus', -1) && match.group ==# 'RevueMessageFocus'
      call matchdelete(match.id)
    endif
  endfor
  let w:revue_message_focus = -1
  if (a:0 && !a:1) || index(['threads', 'conversation'], get(b:, 'revue_view', '')) < 0 | return | endif
  let session = s:Get()
  let target = get(get(session, 'messagemap', {}), string(line('.')), {})
  if empty(target) | return | endif
  highlight default RevueMessageFocus cterm=bold ctermfg=255 ctermbg=237 gui=bold guifg=#f0f6fc guibg=#303946
  let w:revue_message_focus = matchaddpos('RevueMessageFocus', [[target.start]], 20)
endfunction

function! revue#session#Conversation() abort
  let session = s:Get()
  if empty(session) | return | endif
  let snapshot = session.snapshot
  let lines = ['# ' . snapshot.title, snapshot.url, snapshot.author . ' · ' . snapshot.state,
        \ 'Review requested: ' . join(snapshot.reviewers, ', '), '', snapshot.body, '', '── Conversation ──']
  " Expand body newlines into real buffer lines.
  let lines = split(join(lines, "\n"), "\n", 1)
  call extend(lines, revue#feedback#Lines(session))
  let view = {'lines': lines, 'messages': {}}
  let index = 0
  for comment in snapshot.conversation
    call revue#discussion#Append(view, comment, '', index, session.read_state.unread, snapshot.author)
    let index += 1
  endfor
  call extend(view.lines, ['', ':ReviewNewConversation · :ReviewReview · :ReviewClose'])
  call s:Fill(s:Panel(session, 'conversation'), view.lines)
  let session.messagemap = view.messages
  call revue#markdown#View(session.panel, view)
  call revue#session#MessageFocus()
endfunction

function! s:ThreadsAtCursor(session) abort
  if index(['base', 'head'], get(b:, 'revue_role', '')) < 0 || a:session.index < 0 | return [] | endif
  let path = a:session.snapshot.files[a:session.index].path
  let side = get(b:, 'revue_side', '')
  let row = line('.')
  return filter(copy(a:session.snapshot.threads), {_, t -> t.path ==# path && !t.outdated && t.side ==# side && row >= t.start && row <= t.line})
endfunction

function! revue#session#FocusThread() abort
  let session = s:Get()
  if empty(session) | return | endif
  let matches = s:ThreadsAtCursor(session)
  if empty(matches) | call revue#session#Threads() | return | endif
  let chosen = 0
  if len(matches) > 1
    let origin = [win_getid(), bufnr(), session.snapshot.snapshot, session.snapshot.files[session.index].id, b:revue_side, line('.')]
    let choices = ['Choose a discussion:']
    for index in range(len(matches))
      let thread = matches[index]
      let first = get(thread.comments, 0, {'author': '', 'body': ''})
      call add(choices, printf('%d. %s · %s:%d-%d · %d replies · %s', index + 1, first.author,
            \ thread.side, thread.start, thread.line, max([0, len(thread.comments) - 1]), strcharpart(substitute(first.body, '\n', ' ', 'g'), 0, 70)))
    endfor
    let chosen = inputlist(choices) - 1
    if chosen < 0 || chosen >= len(matches) | return | endif
    " A timer may refresh or navigate while the native chooser is open. Keep
    " the chosen identity, but only follow it from the same source location.
    let current = s:Get()
    if empty(current) || current.id !=# session.id || current.index < 0 ||
          \ origin !=# [win_getid(), bufnr(), current.snapshot.snapshot, current.snapshot.files[current.index].id, get(b:, 'revue_side', ''), line('.')] ||
          \ empty(filter(s:ThreadsAtCursor(current), {_, t -> t.id ==# matches[chosen].id}))
      call s:Notice('Discussion or source selection changed; choose the discussion again.')
      return
    endif
  endif
  call revue#session#Threads(matches[chosen].id)
endfunction

function! revue#session#Threads(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let target = line('.')
  let side = get(b:, 'revue_side', 'head')
  let selected = a:0 ? a:1 : ''
  if empty(selected)
    if session.index < 0 | return | endif
    let path = session.snapshot.files[session.index].path
    let threads = filter(copy(session.snapshot.threads), {_, t -> t.path ==# path})
  else
    let threads = filter(copy(session.snapshot.threads), {_, t -> t.id ==# selected})
    let path = empty(threads) ? selected . ' (no longer available)' : threads[0].path
  endif
  let threads = deepcopy(threads)
  for thread in threads
    let thread.operation_status = revue#thread_state#Status(revue#thread_state#Pending(session, thread.id))
  endfor
  let view = revue#discussion#Threads(threads, (empty(selected) ? '# Threads: ' : '# Thread: ') . path, session.read_state.unread, session.snapshot.author, get(get(session.snapshot, 'context', {}), 'note', ''), !empty(get(session, 'context_return', {})))
  let focus = 4
  for thread in threads
    if thread.side ==# side && target >= thread.start && target <= thread.line
      let positions = sort(keys(filter(copy(view.threads), {_, id -> id ==# thread.id})), 'n')
      if !empty(positions) | let focus = str2nr(positions[0]) | endif
    endif
  endfor
  let panel = s:Panel(session, 'threads')
  let view.lines[1] = 'Messages ' . s:Hint(panel, 'previous-message') . ' / ' . s:Hint(panel, 'next-message') .
        \ ' · Actions ' . s:Hint(panel, 'actions') . ' · Quote ' . s:Hint(panel, 'quote')
  call s:Fill(panel, view.lines)
  let session.panelthread = selected
  let session.threadmap = view.threads
  let session.messagemap = view.messages
  call revue#markdown#View(session.panel, view)
  call cursor(focus, 1)
  call revue#session#MessageFocus()
endfunction

function! revue#session#NextMessage(delta) abort
  let session = s:Get()
  if empty(session) || index(['threads', 'conversation'], get(b:, 'revue_view', '')) < 0 | return | endif
  let rows = sort(uniq(sort(map(values(session.messagemap), {_, t -> t.start}), 'n')), 'n')
  if a:delta < 0 | call reverse(rows) | endif
  for row in rows
    if (row - line('.')) * a:delta > 0
      call cursor(row, 1)
      call revue#session#MessageFocus()
      return
    endif
  endfor
endfunction

function! revue#session#Activity() abort
  let session = s:Get()
  if empty(session) | return | endif
  let view = revue#activity#View(session)
  call s:Fill(s:Panel(session, 'activity'), view.lines)
  let session.activityrows = view.operations
endfunction

function! revue#session#Discussions(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let origin = get(b:, 'revue_view', '') ==# 'discussions' ? s:Origin() : {}
  if a:0 && !empty(a:1) | let session.discussionfilters.text = a:1 | endif
  let view = revue#discovery#View(session)
  call s:Fill(s:Panel(session, 'discussions'), view.lines)
  let session.discoveryrows = view.rows
  if !empty(origin) | call s:RestoreOriginView(session, origin) | endif
endfunction

function! revue#session#LoadMoreFeedback(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let reason = revue#feedback#Availability(session)
  if !empty(reason) | call s:Notice(reason) | return | endif
  let previous = get(session, 'feedback_read', {})
  let epoch = get(session, 'latest_request', 0)
  let same = get(previous, 'snapshot', '') ==# session.snapshot.snapshot && get(previous, 'epoch', -1) == epoch
  let state = {'serial': get(previous, 'serial', 0) + 1, 'loading': 1, 'error': '',
        \ 'snapshot': session.snapshot.snapshot, 'epoch': epoch, 'seen': same ? get(previous, 'seen', []) : []}
  let session.feedback_read = state
  let cursor = session.snapshot.feedback.cursor
  call s:RepaintPanel(session)
  call session.Host({'op': 'feedback_page', 'cursor': cursor, 'reference': revue#comparisons#Reference(session.snapshot)},
        \ function('s:FeedbackLoaded', [session.id, state.serial, state.snapshot, epoch, cursor, a:0 ? deepcopy(a:1) : {}]))
endfunction

function! revue#session#CancelFeedback() abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'feedback_read') | return | endif
  let session.feedback_read.serial += 1
  let session.feedback_read.loading = 0
  let session.feedback_read.error = 'Read cancelled; loaded discussions retained. Load more to retry.'
  call s:RepaintPanel(session)
endfunction

function! s:FeedbackLoaded(id, serial, comparison, epoch, cursor, navigation, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:serial != get(get(session, 'feedback_read', {}), 'serial', -1) | return | endif
  let state = session.feedback_read
  let state.loading = 0
  if session.snapshot.snapshot !=# a:comparison || get(session, 'latest_request', 0) != a:epoch ||
        \ get(get(session.snapshot, 'feedback', {}), 'cursor', '') !=# a:cursor
    return
  endif
  try
    if !get(a:result, 'ok', 0) | throw get(a:result, 'error', 'Feedback read failed.') | endif
    let data = get(a:result, 'data', {})
    if get(state, 'mode', '') !=# 'lookup' && type(data) == v:t_dict && index(state.seen, get(data, 'next_cursor', '')) >= 0
      throw 'Feedback cursor repeated an earlier page. Refresh the review.'
    endif
    let snapshot = get(state, 'mode', '') ==# 'lookup' ? revue#feedback#LookupMerge(session.snapshot, data, state.target, state.reference) : revue#feedback#Merge(session.snapshot, data, a:cursor)
    " Paging finds older feedback; it is not evidence of a newly arrived message.
    for entry in revue#activity#Messages(snapshot) | let session.read_state.known[entry.key] = 1 | endfor
    call revue#activity#Observe(session, snapshot)
    let session.snapshot = snapshot
    let session.comparisons[snapshot.snapshot].snapshot = deepcopy(snapshot)
    if get(state, 'mode', '') !=# 'lookup' | call add(state.seen, a:cursor) | endif
    let state.error = ''
    call s:Annotations(session)
    call s:Save(session)
  catch
    let state.error = v:exception
  endtry
  call s:RepaintPanel(session)
  call s:RenderTree(session)
  if !empty(a:navigation) && empty(state.error) && win_getid() == a:navigation.win && bufnr() == a:navigation.buf &&
        \ get(b:, 'revue_session', '') ==# session.id && get(b:, 'revue_view', '') ==# 'timeline' &&
        \ session.timeline.serial == a:navigation.serial
    let event = s:TimelineEvent(session)
    if get(event, 'id', '') ==# a:navigation.event.id && get(event, 'target', {}) ==# a:navigation.event.target
      if empty(s:EventDiscussionError(session, event))
        call s:OpenDiscussionTarget(session, event.target, s:Origin())
      else
        call s:Notice(empty(get(get(session.snapshot, 'feedback', {}), 'cursor', '')) ?
              \ 'Feedback loaded; this message is unavailable in this comparison. Use its event link or refresh.' :
              \ 'This message is not on the loaded pages yet. :ReviewLoadEventDiscussion loads the next page.')
      endif
    endif
  endif
endfunction

function! revue#session#ServiceProgress(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let current = get(b:, 'revue_view', '') ==# 'service-progress'
  let state = get(session, 'service_progress', {})
  if a:0 || current
    if empty(state) | return | endif
    let path = state.path
  else
    let index = s:SelectedFile(session)
    if index < 0 | call s:Notice('Select a source file to inspect service progress.') | return | endif
    let path = session.snapshot.files[index].path
  endif
  if !a:0
    let serial = get(state, 'serial', 0) + 1
    let session.service_progress = {'path': path, 'reference': revue#comparisons#Reference(session.snapshot), 'data': {}, 'loading': 0, 'error': revue#service_progress#Reason(session), 'serial': serial}
  endif
  let state = session.service_progress
  let panel = s:Panel(session, 'service-progress')
  if a:0
    call s:Fill(panel, revue#service_progress#View(session))
    return
  endif
  let state.loading = empty(state.error)
  call s:Fill(panel, revue#service_progress#View(session))
  if !state.loading | return | endif
  try
    call session.Host({'op': 'service_progress', 'path': path, 'reference': state.reference}, function('s:ServiceProgressLoaded', [session.id, state.serial, session.generation, panel]))
  catch
    call s:ServiceProgressLoaded(session.id, state.serial, session.generation, panel, {'ok': 0, 'error': v:exception})
  endtry
endfunction

function! s:ServiceProgressLoaded(id, serial, generation, panel, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || get(get(session, 'service_progress', {}), 'serial', -1) != a:serial | return | endif
  let state = session.service_progress
  let state.loading = 0
  if a:generation != session.generation || state.reference !=# revue#comparisons#Reference(session.snapshot) || !empty(revue#service_progress#Reason(session))
    let state.error = 'Comparison changed during service read. Reload.'
  elseif !get(a:result, 'ok', 0) || !revue#service_progress#Valid(get(a:result, 'data', {}), state.reference, state.path)
    let state.error = get(a:result, 'error', 'Incomplete service progress response.')
  else
    let state.data = deepcopy(a:result.data)
  endif
  if bufexists(a:panel) && getbufvar(a:panel, 'revue_view', '') ==# 'service-progress'
    call s:Fill(a:panel, revue#service_progress#View(session))
  endif
endfunction

function! revue#session#ServiceViewed(value) abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'service-progress' | return | endif
  let state = session.service_progress
  let pending = filter(copy(session.drafts), {_, d -> d.kind ==# 'service_viewed' && d.path ==# state.path})
  if !empty(pending)
    let draft = pending[0]
    if a:value < 0 && draft.state !=# 'unknown' | call s:Notice('No uncertain service Viewed operation for this file.') | return | endif
    if draft.state ==# 'submitting' | call s:Notice('Service Viewed update is in progress.') | return | endif
    if draft.state ==# 'unknown' && a:value >= 0 | call s:Notice('Check the existing outcome before changing service progress.') | return | endif
    if a:value >= 0 && draft.viewed != a:value | call s:Composer(session, draft.id) | call s:Notice('Discard this saved intent before choosing the opposite state.') | return | endif
  else
    if a:value < 0 | call s:Notice('No uncertain service Viewed operation for this file.') | return | endif
    if state.loading || !empty(state.error) || empty(state.data) | call s:Notice('Load current service state first.') | return | endif
    let fields = {'kind': 'service_viewed', 'body': '', 'path': state.path, 'reference': deepcopy(state.reference),
          \ 'actor': state.data.actor, 'actor_label': state.data.actor_label, 'review_id': state.data.review_id, 'viewed': a:value ? v:true : v:false}
    let id = s:NewDraft(session, fields, 1)
    if empty(id) | return | endif
    let draft = s:Draft(session, id)
  endif
  let reconcile = draft.state ==# 'unknown'
  if !reconcile
    let error = s:SubmissionError(session, draft)
    if !empty(error) | call s:Notice(error) | return | endif
  endif
  let previous = draft.state
  let draft.state = 'submitting'
  if !s:Save(session) | let draft.state = previous | return | endif
  if !has_key(session, 'service_viewed_attempts') | let session.service_viewed_attempts = {} | endif
  let attempt = get(session.service_viewed_attempts, draft.id, 0) + 1
  let session.service_viewed_attempts[draft.id] = attempt
  call s:Fill(bufnr(), revue#service_progress#View(session))
  try
    call session.Host({'op': 'mutate', 'draft': deepcopy(draft), 'reconcile': reconcile}, function('s:ServiceViewedSent', [session.id, draft.id, attempt, reconcile]))
  catch
    call s:ServiceViewedSent(session.id, draft.id, attempt, reconcile, {'ok': 0, 'unknown': 1, 'error': v:exception})
  endtry
endfunction

function! s:ServiceViewedSent(id, operation, attempt, reconcile, result) abort
  let session = get(s:sessions, a:id, {})
  let draft = empty(session) ? {} : s:Draft(session, a:operation)
  if empty(draft) || draft.state !=# 'submitting' || a:attempt != get(get(session, 'service_viewed_attempts', {}), a:operation, 0) | return | endif
  call s:Sent(a:id, a:operation, a:reconcile, a:result)
endfunction

function! revue#session#Readiness() abort
  let session = s:Get()
  if empty(session) | return | endif
  call revue#readiness#Init(session)
  let view = revue#readiness#View(session)
  let panel = s:Panel(session, 'readiness')
  let view.lines[2] = s:Hint(panel, 'readiness-link') . ' opens details · ' . s:Hint(panel, 'copy-readiness-link') . ' copies link · :ReviewCancelReadiness'
  call s:Fill(panel, view.lines)
  let session.readinessrows = view.rows
  call revue#layout#SetBar(win_getid(), ' Revue readiness | read-only observations | :ReviewClose ')
  if !session.readiness.requested | call revue#session#LoadReadiness(1) | endif
endfunction

function! revue#session#LoadReadiness(reset) abort
  let session = s:Get()
  if empty(session) | return | endif
  call revue#readiness#Init(session)
  let state = session.readiness
  if state.loading | call s:Notice('Readiness is already loading; cancel to restart.') | return | endif
  let state.requested = 1
  let state.error = revue#readiness#Reason(session)
  if empty(state.error) && !a:reset && (empty(state.data) || state.data.complete)
    let state.error = 'No more check pages. Reload readiness for fresh observations.'
  endif
  if !empty(state.error)
    if get(session, 'panelkind', '') ==# 'readiness' | call s:RepaintPanel(session) | endif
    return
  endif
  let state.serial += 1
  let state.loading = 1
  let reference = revue#comparisons#Reference(session.snapshot)
  let cursor = a:reset ? '' : state.data.next_cursor
  let Done = function('s:ReadinessLoaded', [session.id, state.serial, reference, cursor, a:reset])
  if get(session, 'panelkind', '') ==# 'readiness' | call s:RepaintPanel(session) | endif
  try
    call session.Host({'op': 'readiness', 'reference': reference, 'cursor': cursor}, Done)
  catch
    call Done({'ok': 0, 'error': v:exception})
  endtry
endfunction

function! s:ReadinessLoaded(id, serial, reference, cursor, reset, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:serial != get(get(session, 'readiness', {}), 'serial', -1) || !session.readiness.loading | return | endif
  let state = session.readiness
  let state.loading = 0
  if revue#comparisons#Reference(session.snapshot) !=# a:reference || session.latest_comparison !=# a:reference.snapshot
    let state.error = 'Selected comparison changed during the read. Reload readiness.'
  else
    try
      let state.error = get(a:result, 'ok', 0) ? revue#readiness#Apply(state, get(a:result, 'data', {}), a:reference, a:cursor, a:reset) : get(a:result, 'error', 'Readiness read failed.')
    catch
      let state.error = 'Invalid readiness response: ' . v:exception
    endtry
  endif
  if get(session, 'panelkind', '') ==# 'readiness' | call s:RepaintPanel(session) | endif
endfunction

function! revue#session#CancelReadiness() abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'readiness') | return | endif
  let session.readiness.serial += 1
  let session.readiness.loading = 0
  let session.readiness.error = 'Read cancelled; previous observations retained.'
  if get(session, 'panelkind', '') ==# 'readiness' | call s:RepaintPanel(session) | endif
endfunction

function! revue#session#ReadinessLink(copy) abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'readiness' | return | endif
  let url = get(get(session.readinessrows, string(line('.')), {}), 'url', '')
  if !revue#links#IsWeb(url) | call s:Notice('Select a readiness item with a web link.') | return | endif
  if a:copy | call setreg(v:register, url, 'v') | call s:Notice('Readiness link copied.')
  else | call s:Browse(url) | endif
endfunction

function! revue#session#Timeline() abort
  let session = s:Get()
  if empty(session) | return | endif
  call revue#timeline#Init(session)
  let origin = get(b:, 'revue_view', '') ==# 'timeline' ? s:Origin() : {}
  let view = revue#timeline#View(session)
  call s:Fill(s:Panel(session, 'timeline'), view.lines)
  let session.timelinerows = view.rows
  call revue#layout#SetBar(win_getid(), ' Revue history | backend events | :ReviewClose ')
  if !empty(origin) | call s:RestoreOriginView(session, origin) | endif
  if !session.timeline.requested | call revue#session#LoadTimeline(1) | endif
endfunction

function! revue#session#LoadTimeline(reset) abort
  let session = s:Get()
  if empty(session) | return | endif
  call revue#timeline#Init(session)
  let state = session.timeline
  let rule = get(get(session.comparisons[session.latest_comparison].snapshot, 'capabilities', {}), 'timeline', {})
  let state.requested = 1
  if !get(rule, 'enabled', 0)
    let state.error = get(rule, 'reason', 'This backend does not provide review history.')
    if empty(state.error) | let state.error = 'This backend does not provide review history.' | endif
    if get(session, 'panelkind', '') ==# 'timeline' | call s:RepaintPanel(session) | endif
    return
  endif
  if !a:reset && state.loading | call s:Notice('History is already loading.') | return | endif
  if !a:reset && state.complete | call s:Notice('Oldest available event reached; reload for newer activity.') | return | endif
  let state.serial += 1
  let state.loading = 1
  let state.error = ''
  let cursor = a:reset ? '' : state.cursor
  if get(session, 'panelkind', '') ==# 'timeline' | call s:RepaintPanel(session) | endif
  call session.Host({'op': 'timeline', 'cursor': cursor}, function('s:TimelineLoaded', [session.id, state.serial, cursor, a:reset]))
endfunction

function! s:TimelineLoaded(id, serial, cursor, reset, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:serial != get(get(session, 'timeline', {}), 'serial', -1) | return | endif
  let state = session.timeline
  let state.loading = 0
  let state.error = get(a:result, 'ok', 0) ? revue#timeline#Apply(state, get(a:result, 'data', {}), a:cursor, a:reset) : get(a:result, 'error', 'Timeline read failed.')
  if get(session, 'panelkind', '') ==# 'timeline' | call s:RepaintPanel(session) | endif
endfunction

function! revue#session#CancelTimeline() abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'timeline') | return | endif
  let session.timeline.serial += 1
  let session.timeline.loading = 0
  let session.timeline.error = 'Read cancelled; existing events retained. Retry older events or reload.'
  if get(session, 'panelkind', '') ==# 'timeline' | call s:RepaintPanel(session) | endif
endfunction

function! s:TimelineEvent(session) abort
  if get(b:, 'revue_view', '') !=# 'timeline' | return {} | endif
  let selected = get(get(a:session, 'timelinerows', {}), string(line('.')), {})
  return get(filter(copy(get(get(a:session, 'timeline', {}), 'items', [])), {_, event -> event.id ==# get(selected, 'id', '')}), 0, {})
endfunction

function! s:EventDiscussionError(session, event) abort
  let target = get(a:event, 'target', {})
  if empty(target) | return 'This event has no linked discussion here; use its event link.' | endif
  let messages = a:session.snapshot.conversation
  if target.kind ==# 'thread'
    let thread = get(filter(copy(a:session.snapshot.threads), {_, t -> t.id ==# target.thread}), 0, {})
    let messages = get(thread, 'comments', [])
  endif
  return empty(filter(copy(messages), {_, m -> m.id ==# target.message && get(m, 'kind', 'comment') ==# target.message_kind})) ?
        \ (revue#feedback#LookupSupported(a:session.snapshot, target) ? 'This message is not loaded. :ReviewLoadEventDiscussion fetches its complete discussion.' : empty(revue#feedback#Availability(a:session)) ? 'This message is not loaded. :ReviewLoadEventDiscussion loads one feedback page and opens it if found.' :
        \ 'This message is unavailable in the loaded discussion; refresh the review or open its event link.') : ''
endfunction

function! revue#session#LoadEventDiscussion() abort
  let session = s:Get()
  if empty(session) | return | endif
  let event = s:TimelineEvent(session)
  if empty(get(event, 'target', {})) | call s:Notice('Select an event with a linked discussion first.') | return | endif
  if empty(s:EventDiscussionError(session, event)) | call revue#session#EventDiscussion() | return | endif
  if revue#feedback#LookupSupported(session.snapshot, event.target)
    let error = revue#feedback#LookupAvailability(session)
    if !empty(error) | call s:Notice(error) | return | endif
    let previous = get(session, 'feedback_read', {})
    let epoch = get(session, 'latest_request', 0)
    let same = get(previous, 'snapshot', '') ==# session.snapshot.snapshot && get(previous, 'epoch', -1) == epoch
    let reference = revue#comparisons#Reference(session.snapshot)
    let session.feedback_read = {'serial': get(previous, 'serial', 0) + 1, 'loading': 1, 'error': '', 'mode': 'lookup',
          \ 'snapshot': session.snapshot.snapshot, 'epoch': epoch, 'seen': same ? get(previous, 'seen', []) : [], 'target': deepcopy(event.target), 'reference': reference}
    let navigation = {'event': deepcopy(event), 'win': win_getid(), 'buf': bufnr(), 'serial': session.timeline.serial}
    let cursor = get(get(session.snapshot, 'feedback', {}), 'cursor', '')
    let Done = function('s:FeedbackLoaded', [session.id, session.feedback_read.serial, session.snapshot.snapshot, epoch, cursor, navigation])
    call s:RepaintPanel(session)
    try
      call session.Host({'op': 'feedback_lookup', 'reference': reference, 'target': deepcopy(event.target)}, Done)
    catch
      call Done({'ok': 0, 'error': 'Discussion lookup interrupted: ' . v:exception})
    endtry
    return
  endif
  call revue#session#LoadMoreFeedback({'event': event, 'win': win_getid(), 'buf': bufnr(), 'serial': session.timeline.serial})
endfunction

function! revue#session#EventDiscussion() abort
  let session = s:Get()
  if empty(session) | return | endif
  let event = s:TimelineEvent(session)
  let error = s:EventDiscussionError(session, event)
  if !empty(error) | call s:Notice(error) | return | endif
  call s:OpenDiscussionTarget(session, event.target, s:Origin())
endfunction

function! revue#session#EventLink(copy) abort
  let session = s:Get()
  if empty(session) | return | endif
  let event = s:TimelineEvent(session)
  let url = get(event, 'url', '')
  if !revue#links#IsWeb(url) | call s:Notice('This event has no web link.') | return | endif
  if a:copy | call setreg(v:register, url, 'v') | call s:Notice('Event link copied.')
  else | call s:Browse(url) | endif
endfunction

function! s:EventComparisonError(session, event) abort
  if empty(a:event) | return 'Select a history event first.' | endif
  let reference = get(a:event, 'reviewed_comparison', {})
  if empty(reference)
    return 'The backend has not verified this event’s full comparison. A reviewed head alone does not establish its base; use the event link when available.'
  endif
  let existing = get(get(a:session.comparisons, reference.snapshot, {}), 'reference', {})
  for field in ['base', 'head', 'range', 'context']
    if !empty(existing) && get(existing, field, '') !=# get(reference, field, '')
      return 'The event comparison conflicts with a retained source identity; current code is unchanged.'
    endif
  endfor
  return s:ComparisonAvailability(a:session, reference)
endfunction

function! revue#session#EventComparison() abort
  let session = s:Get()
  if empty(session) | return | endif
  let event = s:TimelineEvent(session)
  let error = s:EventComparisonError(session, event)
  if !empty(error) | call s:Notice(error) | return | endif
  let reference = revue#comparisons#Reference(event.reviewed_comparison)
  let origin = s:Origin()
  call revue#comparisons#AddReference(session, reference)
  call revue#session#OpenComparison(reference.snapshot, {'event_origin': origin,
        \ 'event_id': event.id, 'event_reference': deepcopy(event.reviewed_comparison), 'event_serial': session.timeline.serial})
endfunction

function! revue#session#Filter(kind, args) abort
  let session = s:Get()
  if empty(session) | return | endif
  let domains = a:kind ==# 'file' ? {'path': [], 'status': ['all', 'modified', 'added', 'removed', 'renamed', 'copied', 'changed'],
        \ 'threads': ['all', 'any', 'none', 'unresolved', 'resolved', 'unknown', 'outdated'], 'viewed': ['all', 'viewed', 'unviewed', 'checking']} :
        \ {'text': [], 'path': [], 'author': [], 'kind': ['all', 'thread', 'conversation', 'draft'],
        \ 'state': ['all', 'unresolved', 'resolved', 'unknown', 'draft', 'failed', 'submitting'], 'anchor': ['all', 'current', 'outdated', 'none']}
  let field = matchstr(a:args, '^\s*\zs\S\+')
  let value = substitute(a:args, '^\s*\S\+\s*', '', '')
  let key = a:kind ==# 'file' ? 'filefilters' : 'discussionfilters'
  if field ==# 'clear' && empty(value)
    let session[key] = {}
  elseif !has_key(domains, field)
    call s:Notice('Filter fields: ' . join(sort(keys(domains)), ', ') . ', clear. Text matches literal substrings.')
    return
  else
    if !empty(domains[field])
      let value = empty(value) ? 'all' : tolower(value)
      if index(domains[field], value) < 0 | call s:Notice('Use ' . field . ': ' . join(domains[field], ', ')) | return | endif
    endif
    let session[key][field] = value
  endif
  if a:kind ==# 'file'
    let session.revealed_files = {}
    call s:RenderTree(session)
  else
    call revue#session#Discussions()
  endif
endfunction

function! revue#session#OpenDiscussion() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'discussions' | return | endif
  let target = get(session.discoveryrows, string(line('.')), {})
  if empty(target) | call s:Notice('Select a discussion or draft.') | return | endif
  call s:OpenDiscussionTarget(session, target, s:Origin())
endfunction

function! s:OpenDiscussionTarget(session, target, origin) abort
  let session = a:session
  let target = a:target
  let origin = a:origin
  if target.kind ==# 'draft'
    call s:Composer(session, target.draft)
    if get(b:, 'revue_view', '') ==# 'batch'
      for [row, id] in items(session.batchrows)
        if id ==# target.item | call cursor(str2nr(row), 1) | break | endif
      endfor
    endif
  else
    if target.kind ==# 'thread'
      let threads = filter(copy(session.snapshot.threads), {_, t -> t.id ==# target.thread})
      if empty(threads) | call s:Notice('This thread is no longer available.') | return | endif
      let index = index(map(copy(session.snapshot.files), {_, f -> f.path}), threads[0].path)
      if index >= 0
        call s:Select(session, index, {'side': revue#anchor#IsFile(threads[0]) ? 'head' : threads[0].side})
      else
        call s:Notice('Source file is absent from this comparison. The discussion remains available.')
      endif
      call revue#session#Threads(target.thread)
    else
      call revue#session#Conversation()
    endif
    if has_key(target, 'message')
      for message in values(session.messagemap)
        let match = !empty(target.message) ? message.comment ==# target.message && message.kind ==# target.message_kind : message.index == target.index
        if match
          call cursor(message.start, 1)
          normal! zz
          break
        endif
      endfor
    endif
  endif
  let b:revue_origin = origin
endfunction

function! revue#session#Viewed(value) abort
  let session = s:Get()
  if empty(session) || index(['files', 'base', 'head'], get(b:, 'revue_role', '')) < 0 | return | endif
  let index = session.index
  if b:revue_role ==# 'files'
    let target = get(session.rows, string(line('.')), {})
    if get(target, 'kind', '') !=# 'file' | call s:Notice('Select a file to change Viewed state.') | return | endif
    let index = target.index
  endif
  if index < 0 | return | endif
  let file = session.snapshot.files[index]
  let key = json_encode([session.snapshot.snapshot, file.id])
  if has_key(get(session, 'progress_queue', {}), key) | let session.progress_queue[key].action = a:value | endif
  if revue#progress#Set(session, session.snapshot, file, a:value)
    call s:Save(session)
    call s:RenderTree(session)
    return
  endif
  call s:Notice('Verifying compared content for ' . file.path . ' before changing Viewed state…')
  call s:QueueViewed(session, session.snapshot, file, a:value)
endfunction

function! revue#session#VerifyViewed() abort
  let session = s:Get()
  if !empty(session) | call s:CheckViewed(session, 1) | endif
endfunction

function! s:CheckViewed(session, ...) abort
  for file in a:session.snapshot.files
    let state = revue#progress#State(a:session, a:session.snapshot, file)
    if state ==# 'checking' || (a:0 && a:1 && state ==# 'unavailable')
      if a:session.index >= 0 && file.id ==# a:session.snapshot.files[a:session.index].id && empty(a:session.loaded) | continue | endif
      call s:QueueViewed(a:session, a:session.snapshot, file, -1)
    endif
  endfor
endfunction

function! s:QueueViewed(session, snapshot, file, action) abort
  let cache = a:snapshot.snapshot ==# a:session.snapshot.snapshot ? a:session.cache : a:session.comparisons[a:snapshot.snapshot].cache
  if has_key(cache, a:file.id)
    call revue#progress#Observe(a:session, a:snapshot, a:file, cache[a:file.id])
    if !empty(revue#progress#Stamp(a:session, a:snapshot, a:file))
      if a:action >= 0 | call revue#progress#Set(a:session, a:snapshot, a:file, a:action) | endif
      call s:Save(a:session)
      call s:RenderTree(a:session)
      return
    endif
  endif
  if !has_key(a:session, 'progress_queue') | let a:session.progress_queue = {} | let a:session.progress_order = [] | endif
  let key = json_encode([a:snapshot.snapshot, a:file.id])
  if has_key(a:session.progress_queue, key)
    if a:action >= 0 | let a:session.progress_queue[key].action = a:action | endif
  else
    let a:session.progress_queue[key] = {'snapshot': a:snapshot, 'file': a:file, 'action': a:action}
    call add(a:session.progress_order, key)
  endif
  call s:RenderTree(a:session)
  call timer_start(0, function('s:PumpViewed', [a:session.id]))
endfunction

function! s:PumpViewed(id, timer) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || !empty(get(session, 'progress_running', '')) || empty(get(session, 'progress_order', [])) | return | endif
  let key = remove(session.progress_order, 0)
  let session.progress_running = key
  let task = session.progress_queue[key]
  call session.Host({'op': 'file', 'snapshot': task.snapshot, 'file': task.file}, function('s:ViewedLoaded', [a:id, key]))
endfunction

function! s:ViewedLoaded(id, key, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) | return | endif
  let task = remove(session.progress_queue, a:key)
  let session.progress_running = ''
  let content = a:result.ok ? a:result.data : {}
  call revue#progress#Observe(session, task.snapshot, task.file, content)
  if a:result.ok
    let session.comparisons[task.snapshot.snapshot].cache[task.file.id] = content
    if session.snapshot.snapshot ==# task.snapshot.snapshot | let session.cache[task.file.id] = content | endif
  endif
  if task.action >= 0
    let applied = revue#progress#Set(session, task.snapshot, task.file, task.action)
    call s:Notice(applied ? task.file.path . (task.action ? ' marked Viewed.' : ' marked unviewed.') : 'Cannot verify compared content; Viewed state was not changed. ' . get(a:result, 'error', ''))
  endif
  call s:Save(session)
  call s:RenderTree(session)
  call timer_start(0, function('s:PumpViewed', [a:id]))
endfunction

function! revue#session#Comparisons() abort
  let session = s:Get()
  if empty(session) | return | endif
  let view = revue#comparisons#View(session)
  call s:Fill(s:Panel(session, 'comparisons'), view.lines)
  let session.comparisonrows = view.rows
  if !get(session, 'history_requested', 0) && get(get(get(session.snapshot, 'capabilities', {}), 'comparisons', {}), 'enabled', 0)
    call revue#session#LoadHistory()
  endif
endfunction

function! s:RangeError(session) abort
  let rule = get(get(a:session.comparisons[a:session.latest_comparison].snapshot, 'capabilities', {}), 'comparison_range', {})
  if !get(rule, 'enabled', 0) | return empty(get(rule, 'reason', '')) ? 'This backend does not support range selection.' : rule.reason | endif
  for name in ['from', 'to']
    let endpoint = get(get(a:session, 'range_selection', {}), name, {})
    let reference = get(endpoint, 'reference', {})
    if index(get(rule, 'sides', []), get(endpoint, 'side', '')) < 0 || empty(get(reference, get(endpoint, 'side', ''), ''))
      return 'Choose both range endpoints and a supported source side first.'
    endif
    if has_key(reference, 'range') || has_key(reference, 'context') | return 'Choose original comparisons as endpoints, not derived ranges or code contexts.' | endif
  endfor
  return ''
endfunction

function! revue#session#RangeEndpoint(name, side) abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'comparisons' | return | endif
  let id = get(session.comparisonrows, string(line('.')), '')
  if empty(id) | call s:Notice('Select a comparison row first.') | return | endif
  let side = empty(a:side) ? 'head' : a:side
  let rule = get(get(session.comparisons[session.latest_comparison].snapshot, 'capabilities', {}), 'comparison_range', {})
  if !get(rule, 'enabled', 0) || index(get(rule, 'sides', []), side) < 0
    call s:Notice('Range selection is unavailable for this side; use a backend-supported base or head.') | return
  endif
  let reference = revue#comparisons#Reference(session.comparisons[id].reference)
  if has_key(reference, 'range') || has_key(reference, 'context') | call s:Notice('Select an original comparison as an endpoint, not a derived range or code context.') | return | endif
  let session.range_selection[a:name] = {'reference': deepcopy(reference), 'side': side}
  let session.comparison_request = get(session, 'comparison_request', 0) + 1
  let session.range_status = 'Endpoints selected; inspect them above, then :ReviewOpenRange.'
  call s:Save(session)
  call s:RepaintPanel(session)
endfunction

function! revue#session#ClearRange() abort
  let session = s:Get()
  if empty(session) | return | endif
  let session.range_selection = {}
  let session.range_status = ''
  let session.comparison_request = get(session, 'comparison_request', 0) + 1
  call s:Save(session)
  call s:RepaintPanel(session)
endfunction

function! revue#session#OpenRange() abort
  let session = s:Get()
  if empty(session) | return | endif
  let error = s:RangeError(session)
  if !empty(error) | call s:Notice(error) | return | endif
  let selection = deepcopy(session.range_selection)
  let session.comparison_request = get(session, 'comparison_request', 0) + 1
  let session.range_status = 'Loading selected range…'
  call s:RepaintPanel(session)
  call session.Host({'op': 'comparison_range', 'selection': selection},
        \ function('s:RangeLoaded', [session.id, selection, session.comparison_request, s:Origin(), session.generation]))
endfunction

function! s:RangeLoaded(id, selection, token, origin, generation, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:token != get(session, 'comparison_request', 0) | return | endif
  let data = get(a:result, 'data', {})
  let valid = a:result.ok && s:ValidSnapshot(session, data) && get(data, 'range', {}) ==# a:selection
  for [name, side] in [['from', 'base'], ['to', 'head']]
    let endpoint = a:selection[name]
    let valid = valid && get(data, side, '') ==# endpoint.reference[endpoint.side] && get(data, 'snapshot', '') !=# endpoint.reference.snapshot
  endfor
  let existing = get(get(session.comparisons, get(data, 'snapshot', ''), {}), 'reference', {})
  let valid = valid && get(data, 'snapshot', '') !=# session.latest_comparison &&
        \ (empty(existing) || (get(existing, 'base', '') ==# get(data, 'base', '') && get(existing, 'head', '') ==# get(data, 'head', '')))
  if !valid
    let session.range_status = 'Range unavailable: ' . get(a:result, 'error', 'Backend returned different endpoints; current source retained.')
    call s:RepaintPanel(session)
    call s:Notice(session.range_status)
    return
  endif
  let session.range_status = 'Selected range loaded. Existing drafts retain their original code.'
  call revue#comparisons#AddReference(session, extend(revue#comparisons#Reference(data), {'label': 'Selected range'}))
  call s:ComparisonLoaded(a:id, data.snapshot, a:token, a:origin, a:generation, {}, a:result)
endfunction

function! s:SwitchComparison(session, id, ...) abort
  let options = a:0 ? a:1 : {}
  if has_key(options, 'path') && index(map(copy(a:session.comparisons[a:id].snapshot.files), {_, f -> f.path}), options.path) < 0
    call s:Notice('The original file is unavailable in this comparison. Current source and discussion are retained.')
    return
  endif
  if a:id ==# a:session.snapshot.snapshot && empty(options)
    let a:session.snapshot = deepcopy(a:session.comparisons[a:id].snapshot)
    call revue#activity#Observe(a:session, a:session.snapshot)
    call s:Annotations(a:session)
    call s:RepaintPanel(a:session)
    call s:RenderTree(a:session)
    return
  endif
  call s:RememberSource(a:session)
  call revue#comparisons#Remember(a:session)
  let path = get(options, 'path', a:session.index < 0 ? '' : a:session.snapshot.files[a:session.index].path)
  if a:id !=# a:session.snapshot.snapshot | let a:session.previous_comparison = a:session.snapshot.snapshot | endif
  let entry = a:session.comparisons[a:id]
  let a:session.snapshot = deepcopy(entry.snapshot)
  let a:session.cache = entry.cache
  let a:session.sourceviews = entry.views
  let a:session.index = -1
  let a:session.loaded = {}
  let a:session.generation += 1
  let index = has_key(options, 'path') ? -1 : index(map(copy(a:session.snapshot.files), {_, f -> f.id}), get(entry, 'file', ''))
  if index < 0 | let index = index(map(copy(a:session.snapshot.files), {_, f -> f.path}), path) | endif
  if index < 0 && !empty(a:session.snapshot.files) | let index = 0 | endif
  if index >= 0
    call s:Select(a:session, index, extend({'side': get(entry, 'side', 'head')}, options))
  else
    for side in ['base', 'head']
      call s:Fill(a:session[side], ['No changed files in this comparison.'])
      call setbufvar(a:session[side], 'revue_file', '')
      call setbufvar(a:session[side], 'revue_comparison', a:id)
    endfor
    call s:Annotations(a:session)
    call revue#session#Conversation()
  endif
  call s:RepaintPanel(a:session)
  call s:RenderTree(a:session)
  for buf in a:session.buffers
    let draft = s:Draft(a:session, getbufvar(buf, 'revue_draft', ''))
    if !empty(draft) && bufexists(buf) | call s:DraftContext(a:session, draft, buf) | endif
  endfor
  call s:Save(a:session)
  call s:CheckViewed(a:session)
  if has_key(options, 'assignment_origin')
    let a:session.context_return = options.assignment_origin
    call s:Notice('Assignment comparison opened. :ReviewReturnContext returns to the selected outcome.')
  endif
  if has_key(options, 'event_origin')
    let a:session.context_return = options.event_origin
    call s:Notice('Event comparison opened. :ReviewReturnContext returns to the history event.')
  endif
endfunction

function! revue#session#OpenComparison(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let id = a:0 ? a:1 : get(b:, 'revue_view', '') ==# 'comparisons' ? get(get(session, 'comparisonrows', {}), string(line('.')), '') : ''
  if empty(id) || !has_key(session.comparisons, id)
    call s:Notice('Select a comparison first.')
    return
  endif
  let session.comparison_request = get(session, 'comparison_request', 0) + 1
  let options = a:0 > 1 ? a:2 : {}
  if has_key(session.comparisons[id], 'snapshot') && !get(get(get(session.comparisons[session.latest_comparison].snapshot, 'capabilities', {}), 'comparisons', {}), 'refresh_on_open', 0)
    call s:SwitchComparison(session, id, options)
    return
  endif
  if !get(get(get(session.comparisons[session.latest_comparison].snapshot, 'capabilities', {}), 'comparisons', {}), 'enabled', 0)
    call s:Notice('This backend cannot retrieve saved historical comparisons.')
    return
  endif
  let session.history_status = 'Loading comparison ' . id . '…'
  call s:RepaintPanel(session)
  call session.Host({'op': 'comparison', 'reference': deepcopy(session.comparisons[id].reference)},
        \ function('s:ComparisonLoaded', [session.id, id, session.comparison_request, s:Origin(), session.generation, options]))
endfunction

function! s:ValidSnapshot(session, data) abort
  if type(a:data) != v:t_dict || get(a:data, 'version', 0) != 1 || get(a:data, 'key', '') !=# a:session.snapshot.key | return 0 | endif
  for field in ['key', 'snapshot', 'base', 'head', 'title', 'author', 'state', 'body', 'url']
    if type(get(a:data, field, 0)) != v:t_string | return 0 | endif
  endfor
  for field in ['files', 'threads', 'conversation', 'reviewers', 'review_actions']
    if type(get(a:data, field, 0)) != v:t_list | return 0 | endif
  endfor
  return !empty(a:data.snapshot) && !empty(a:data.base) && !empty(a:data.head)
endfunction

function! s:ComparisonLoaded(sessionid, id, token, origin, generation, options, result) abort
  let session = get(s:sessions, a:sessionid, {})
  if empty(session) | return | endif
  let reference = session.comparisons[a:id].reference
  let data = get(a:result, 'data', {})
  let valid = a:result.ok && s:ValidSnapshot(session, data) && get(data, 'snapshot', '') ==# a:id
  for field in ['base', 'head', 'base_tip', 'range', 'context']
    let valid = valid && (!has_key(reference, field) || get(data, field, '') ==# reference[field])
  endfor
  if has_key(a:options, 'event_origin') || has_key(a:options, 'assignment_origin')
    for file in valid ? data.files : []
      let valid = valid && type(file) == v:t_dict
      for field in ['id', 'path', 'old_path', 'status', 'patch']
        let valid = valid && type(get(file, field, 0)) == v:t_string
      endfor
    endfor
  endif
  if !valid
    let session.history_status = 'Comparison unavailable: ' . get(a:result, 'error', 'Backend returned a different comparison; current source retained.')
    call s:RepaintPanel(session)
    call s:Notice(session.history_status)
    return
  endif
  call revue#comparisons#Observe(session, data, 0)
  let session.history_status = 'Loaded comparison ' . a:id
  let focused = a:origin.win == win_getid() && a:origin.buf == bufnr() && a:origin.kind ==# get(b:, 'revue_view', '')
  let focused = focused && line('.') == a:origin.view.lnum && col('.') - 1 == a:origin.view.col &&
        \ (a:origin.role !=# 'draft' || b:changedtick == a:origin.tick)
  if has_key(a:options, 'assignment_origin')
    let item = s:AssignmentItem(session)
    let focused = focused && session.assignments.serial == a:options.assignment_serial && get(item, 'id', '') ==# a:options.assignment_id && get(item, 'version', '') ==# a:options.assignment_version
  endif
  if has_key(a:options, 'event_origin')
    let event = s:TimelineEvent(session)
    let focused = focused && session.timeline.serial == a:options.event_serial &&
          \ get(event, 'id', '') ==# a:options.event_id && get(event, 'reviewed_comparison', {}) ==# a:options.event_reference
  endif
  if a:token == get(session, 'comparison_request', 0) && a:generation == session.generation && focused
    call s:SwitchComparison(session, a:id, a:options)
  else
    let session.history_status .= ' · select it to open; navigation changed while loading.'
    call s:RepaintPanel(session)
  endif
  call s:Save(session)
endfunction

function! revue#session#LoadHistory() abort
  let session = s:Get()
  if empty(session) || get(session, 'history_busy', 0) | return | endif
  if !get(get(get(session.comparisons[session.latest_comparison].snapshot, 'capabilities', {}), 'comparisons', {}), 'enabled', 0)
    call s:Notice('This backend does not offer comparison history.')
    return
  endif
  let session.history_requested = 1
  let session.history_busy = 1
  let session.latest_request = get(session, 'latest_request', 0) + 1
  let session.history_status = 'Loading backend comparison history…'
  call s:RepaintPanel(session)
  call session.Host({'op': 'comparisons'}, function('s:HistoryLoaded', [session.id, session.latest_request]))
endfunction

function! revue#session#CopyComparison(register) abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'comparisons' | return | endif
  let id = get(session.comparisonrows, string(line('.')), '')
  if empty(id) | call s:Notice('Select a comparison to copy its reference.') | return | endif
  call setreg(empty(a:register) ? '"' : a:register, json_encode(session.comparisons[id].reference), 'v')
  call s:Notice('Comparison reference copied.')
endfunction

function! s:HistoryLoaded(id, epoch, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) | return | endif
  let session.history_busy = 0
  let data = get(a:result, 'data', {})
  let valid = a:result.ok && type(get(data, 'items', 0)) == v:t_list
  if valid
    for reference in data.items
      if type(reference) != v:t_dict || !empty(filter(['snapshot', 'base', 'head'], {_, field -> type(get(reference, field, 0)) != v:t_string || empty(reference[field])}))
        let valid = 0
        break
      endif
      let existing = get(session.comparisons, reference.snapshot, {})
      if has_key(existing, 'snapshot') && (existing.snapshot.base !=# reference.base || existing.snapshot.head !=# reference.head)
        let valid = 0
        break
      endif
    endfor
  endif
  if !valid
    let session.history_status = 'History unavailable: ' . get(a:result, 'error', 'Malformed comparison inventory.')
  else
    for reference in data.items
      let clean = revue#comparisons#Reference(reference)
      let clean.label = get(reference, 'label', '')
      call revue#comparisons#AddReference(session, clean)
    endfor
    let latest = get(data, 'latest', {})
    if a:epoch == get(session, 'latest_request', 0) && s:ValidSnapshot(session, latest)
      call revue#comparisons#Observe(session, latest)
      call revue#activity#Observe(session, latest)
      if session.snapshot.snapshot ==# latest.snapshot
        let session.snapshot = latest
        call s:Annotations(session)
      endif
    endif
    let session.history_status = (get(data, 'complete', 0) ? '' : 'Partial history: ') . get(data, 'scope', 'Backend comparison references loaded.')
    call s:Save(session)
  endif
  call s:RepaintPanel(session)
  call s:RenderTree(session)
endfunction

function! revue#session#ResumeComparison() abort
  let session = s:Get()
  if !empty(session) | call revue#session#OpenComparison(get(session, 'resume_comparison', '')) | endif
endfunction

function! revue#session#DraftComparison() abort
  let session = s:Get()
  if empty(session) | return | endif
  let draft = s:Draft(session, get(b:, 'revue_draft', get(session, 'batchid', '')))
  if empty(draft) | call s:Notice('Open a draft to inspect its original comparison.') | return | endif
  if !has_key(session.comparisons, draft.snapshot)
    call revue#comparisons#AddReference(session, revue#comparisons#Reference(draft))
  endif
  call revue#session#OpenComparison(draft.snapshot)
endfunction

function! revue#session#ThreadComparison() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'threads' | return | endif
  let id = get(session.threadmap, string(line('.')), '')
  let threads = filter(copy(session.snapshot.threads), {_, t -> t.id ==# id})
  let reference = empty(threads) ? {} : get(threads[0], 'original_comparison', {})
  if empty(threads) | call s:Notice('Select a discussion first.') | return | endif
  let origin = s:Origin()
  if empty(reference)
    let source = get(threads[0], 'original_source', {})
    let capability = get(get(session.comparisons[session.latest_comparison].snapshot, 'capabilities', {}), 'thread_context', {})
    if !get(capability, 'enabled', 0) || !get(source, 'available', 0) || empty(get(source, 'token', ''))
      call s:Notice(empty(get(source, 'reason', '')) ? 'The backend does not provide this thread’s original comparison.' : source.reason) | return
    endif
    let target = {'thread': id, 'token': source.token}
    if type(get(source, 'lookup', 0)) == v:t_string && !empty(source.lookup)
      let target.lookup = source.lookup
    endif
    let session.comparison_request = get(session, 'comparison_request', 0) + 1
    let session.history_status = 'Verifying original source context…'
    call s:Notice(session.history_status)
    call session.Host({'op': 'thread_context', 'target': target}, function('s:ThreadContextLoaded',
          \ [session.id, target, session.comparison_request, origin, session.generation]))
    return
  endif
  let session.context_return = origin
  call revue#comparisons#AddReference(session, reference)
  let side = revue#anchor#IsFile(threads[0]) ? 'head' : threads[0].side
  call revue#session#OpenComparison(reference.snapshot, {'path': get(threads[0], 'original_path', threads[0].path),
        \ 'side': side, 'jump': {'side': side, 'line': max([1, get(threads[0], 'original_line', threads[0].line)])}})
endfunction

function! s:ThreadContextLoaded(id, target, token, origin, generation, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:token != get(session, 'comparison_request', 0) | return | endif
  let data = type(get(a:result, 'data', 0)) == v:t_dict ? a:result.data : {}
  let snapshot = type(get(data, 'snapshot', 0)) == v:t_dict ? data.snapshot : {}
  let location = type(get(data, 'location', 0)) == v:t_dict ? data.location : {}
  let context = type(get(snapshot, 'context', 0)) == v:t_dict ? snapshot.context : {}
  let valid = a:result.ok && s:ValidSnapshot(session, snapshot) && get(data, 'thread', '') ==# a:target.thread && get(data, 'token', '') ==# a:target.token
  let valid = valid && get(context, 'thread', '') ==# a:target.thread && get(context, 'token', '') ==# a:target.token &&
        \ get(snapshot, 'snapshot', '') !=# session.latest_comparison
  let valid = valid && type(get(context, 'note', 0)) == v:t_string && type(get(context, 'label', 0)) == v:t_string
  for field in ['path', 'side', 'start', 'line']
    let valid = valid && has_key(location, field) && get(context, field, '') ==# get(location, field, '')
  endfor
  " A list alone is not a valid file inventory. Reject malformed entries before
  " extracting paths or letting the comparison renderer consume the snapshot.
  for file in valid ? snapshot.files : []
    let valid = valid && type(file) == v:t_dict
    for field in ['id', 'path', 'old_path', 'status', 'patch']
      let valid = valid && type(get(file, field, 0)) == v:t_string
    endfor
  endfor
  let valid = valid && index(['base', 'head'], get(location, 'side', '')) >= 0 &&
        \ type(get(location, 'path', 0)) == v:t_string && !empty(location.path) &&
        \ type(get(location, 'start', '')) == v:t_number && type(get(location, 'line', '')) == v:t_number &&
        \ get(location, 'start', 0) > 0 && get(location, 'line', 0) >= get(location, 'start', 1) &&
        \ index(map(copy(get(snapshot, 'files', [])), {_, f -> f.path}), get(location, 'path', '')) >= 0
  let threads = filter(copy(session.snapshot.threads), {_, t -> t.id ==# a:target.thread})
  let valid = valid && !empty(threads) && get(get(threads[0], 'original_source', {}), 'token', '') ==# a:target.token
  if !valid
    let session.history_status = 'Original context unavailable: ' . get(a:result, 'error', 'Backend returned a different source target; discussion retained.')
    call s:Notice(session.history_status)
    return
  endif
  let reference = revue#comparisons#Reference(snapshot)
  let existing = get(session.comparisons, snapshot.snapshot, {})
  if !empty(existing) && (existing.reference.base !=# snapshot.base || existing.reference.head !=# snapshot.head || get(existing.reference, 'context', {}) !=# context)
    call s:Notice('Original context identity changed; discussion retained.') | return
  endif
  call revue#comparisons#AddReference(session, extend(reference, {'label': 'Original code context'}))
  let focused = win_getid() == a:origin.win && bufnr() == a:origin.buf && line('.') == a:origin.view.lnum && col('.') - 1 == a:origin.view.col
  let selected = revue#discussion#Selected(session, line('.'))
  let focused = focused && get(selected, 'comment', '') ==# get(a:origin.message, 'comment', '') && get(session.threadmap, string(line('.')), '') ==# a:target.thread
  if focused && a:generation == session.generation
    let session.context_return = a:origin
  endif
  call s:ComparisonLoaded(a:id, snapshot.snapshot, a:token, a:origin, focused ? a:generation : -1,
        \ {'path': location.path, 'side': location.side, 'jump': {'side': location.side, 'line': location.line}}, {'ok': 1, 'data': snapshot})
  if session.snapshot.snapshot ==# snapshot.snapshot | call s:Notice(context.note . ' :ReviewReturnContext returns.') | endif
endfunction

function! revue#session#ReturnContext() abort
  let session = s:Get()
  if empty(session) || empty(get(session, 'context_return', {})) | call s:Notice('No earlier discussion or history position is retained in this Vim session.') | return | endif
  let session.comparison_request = get(session, 'comparison_request', 0) + 1
  let origin = session.context_return
  if !has_key(get(session.comparisons, origin.comparison, {}), 'snapshot') | call s:Notice('The earlier discussion source is unavailable.') | return | endif
  call s:Return(session, origin)
  let session.context_return = {}
endfunction

function! revue#session#Capture(untracked, ...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let choice = a:0 ? a:1 : ''
  if index(['', 'tracked', 'all'], choice) < 0 | call s:Notice('Use :ReviewCapture [tracked|all]; ! also includes untracked files.') | return | endif
  for draft in session.drafts
    if draft.kind ==# 'capture'
      call s:Composer(session, draft.id)
      call s:Notice('A capture is already pending. Its original settings are retained; inspect or discard it before changing them.')
      return
    endif
  endfor
  let context = get(session.snapshot, 'capture_context', {})
  let include = choice ==# 'tracked' ? 0 : choice ==# 'all' || a:untracked || get(context, 'untracked', 0)
  let fields = {'kind': 'capture', 'untracked': include ? v:true : v:false}
  if !empty(s:NewDraft(session, fields)) | call s:Notice('Inspect the capture settings; :ReviewSend captures saved files into this review.') | endif
endfunction

function! revue#session#Latest() abort
  let session = s:Get()
  if !empty(session) | call revue#session#OpenComparison(session.latest_comparison) | endif
endfunction

function! revue#session#PreviousComparison() abort
  let session = s:Get()
  if empty(session) | return | endif
  call revue#session#OpenComparison(get(session, 'previous_comparison', ''))
endfunction

function! s:SubmissionError(session, draft) abort
  let latest = a:session.comparisons[a:session.latest_comparison].snapshot
  if a:draft.kind ==# 'service_viewed' | return revue#service_progress#Error(latest, a:draft) | endif
  if a:draft.kind ==# 'apply_suggestion'
    let error = revue#apply_suggestion#Validate(latest, a:draft, a:draft)
    return empty(error) ? revue#apply_suggestion#Unsaved(a:draft) : error
  endif
  if a:draft.kind ==# 'participant_run'
    return revue#runtime#CurrentError(latest, revue#assignment#Find(a:session, a:draft.assignment), a:draft)
  endif
  if a:draft.kind ==# 'cancel_assignment'
    let item = revue#assignment#Find(a:session, a:draft.assignment)
    if empty(item) || item.version !=# a:draft.expected_version || item.cancelled
      return 'Assignment changed or is not loaded. Reload assignments and prepare a new cancellation.'
    endif
  endif
  if index(['comment', 'file_comment', 'review', 'batch', 'capture', 'submit_pending', 'start_pending'], a:draft.kind) >= 0 &&
        \ (get(a:draft, 'snapshot', latest.snapshot) !=# latest.snapshot || get(a:draft, 'base_tip', get(latest, 'base_tip', latest.base)) !=# get(latest, 'base_tip', latest.base))
    return 'This draft belongs to an older comparison. Inspect :ReviewLatest; the original anchor is retained.'
  endif
  let error = revue#anchor#Error(latest, a:draft)
  if !empty(error) | return error | endif
  return revue#capabilities#Error(latest, a:draft, 1)
endfunction

function! revue#session#OpenOperation() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'activity' | return | endif
  let target = get(session.activityrows, string(line('.')), {})
  if empty(target) | call s:Notice('Select a pending operation or delivery outcome.') | return | endif
  if empty(s:Draft(session, target.operation))
    call s:Notice('Historical outcome. Receipt and target are shown here; there is no pending draft.')
  else
    call s:Composer(session, target.operation)
  endif
endfunction

function! revue#session#CopyReceipt(register) abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'activity' | return | endif
  let receipt = get(get(session.activityrows, string(line('.')), {}), 'receipt', {})
  if empty(receipt) | call s:Notice('This row has no delivery receipt.') | return | endif
  call setreg(empty(a:register) ? '"' : a:register, json_encode(receipt), 'v')
  call s:Notice('Delivery receipt copied.')
endfunction

function! revue#session#NextUnread() abort
  let session = s:Get()
  if empty(session) | return | endif
  let entries = revue#activity#Unread(session)
  if empty(entries) | call s:Notice('No new messages in this comparison.') | return | endif
  let selected = revue#discussion#Selected(session, line('.'))
  let current = empty(selected) ? get(session, 'unread_cursor', '') : revue#activity#Key(selected.thread, selected.message)
  let next = (index(map(copy(entries), {_, e -> e.key}), current) + 1) % len(entries)
  let entry = entries[next]
  let session.unread_cursor = entry.key
  if empty(entry.thread)
    call revue#session#Conversation()
  else
    let fileindex = index(map(copy(session.snapshot.files), {_, f -> f.path}), entry.path)
    if fileindex >= 0 && fileindex != session.index | call s:Select(session, fileindex) | endif
    call revue#session#Threads(entry.thread)
  endif
  for target in values(session.messagemap)
    if target.thread ==# entry.thread && target.comment ==# entry.message.id && target.kind ==# get(entry.message, 'kind', 'comment')
      call cursor(target.start, 1)
      normal! zz
      return
    endif
  endfor
endfunction

function! revue#session#MarkRead() abort
  let session = s:Get()
  if empty(session) | return | endif
  let selected = revue#discussion#Selected(session, line('.'))
  if empty(selected) | call s:Notice('Select a message to mark read.') | return | endif
  let key = revue#activity#Key(selected.thread, selected.message)
  if !has_key(session.read_state.unread, key) | return | endif
  call remove(session.read_state.unread, key)
  call s:Save(session)
  call s:Annotations(session)
  call s:RepaintPanel(session)
  call s:RenderTree(session)
endfunction

function! revue#session#MarkThreadRead() abort
  let session = s:Get()
  if empty(session) | return | endif
  let id = get(b:, 'revue_view', '') ==# 'threads' ? get(session.threadmap, string(line('.')), '') : ''
  if index(['base', 'head'], get(b:, 'revue_role', '')) >= 0
    let matches = s:ThreadsAtCursor(session)
    if len(matches) > 1
      call revue#session#Threads()
      call s:Notice('Choose a thread, then use :ReviewMarkThreadRead.')
      return
    endif
    let id = empty(matches) ? '' : matches[0].id
  endif
  if empty(id) | call s:Notice('Select a code thread to mark read.') | return | endif
  for entry in revue#activity#Unread(session)
    if entry.thread ==# id | call remove(session.read_state.unread, entry.key) | endif
  endfor
  call s:Save(session)
  call s:Annotations(session)
  call s:RepaintPanel(session)
  call s:RenderTree(session)
endfunction

" Re-render only the owned panel mode. Preserve message identity across inserted
" rows and preserve the user's current editor/composer focus and scroll offset.
function! revue#session#RepaintPanel() abort
  let session = s:Get()
  if !empty(session) && !get(session, 'closing', 0) | call s:RepaintPanel(session) | endif
endfunction

function! s:RepaintPanel(session) abort
  if !revue#layout#Exists(get(a:session, 'panelwin', 0)) || winbufnr(a:session.panelwin) != get(a:session, 'panel', -1) | return | endif
  if win_id2tabwin(a:session.panelwin)[0] != tabpagenr()
    " Evaluate in the existing hidden window without WinEnter/TabEnter or a
    " visible tab switch. Keep its text/cache current while the user types.
    call win_execute(a:session.panelwin, 'call revue#session#RepaintPanel()')
    return
  endif
  let previous = win_getid()
  call win_gotoid(a:session.panelwin)
  let view = winsaveview()
  let selected = get(get(a:session, 'messagemap', {}), string(line('.')), {})
  let operation = get(get(a:session, 'activityrows', {}), string(line('.')), {})
  let discovery = get(get(a:session, 'discoveryrows', {}), string(line('.')), {})
  let pending = get(get(a:session, 'pendingrows', {}), string(line('.')), {})
  let comparison_target = s:ComparisonSelection(a:session)
  let timeline_target = get(get(a:session, 'timelinerows', {}), string(line('.')), {})
  let readiness_target = get(get(a:session, 'readinessrows', {}), string(line('.')), {})
  let history_row = get(get(a:session, 'historyrows', {}), string(line('.')), {})
  let assignment_row = get(get(a:session, 'assignment_view_rows', {}), string(line('.')), {})
  let reaction_row = get(get(a:session, 'reactionrows', {}), string(line('.')), {})
  let kind = get(a:session, 'panelkind', '')
  if kind ==# 'threads'
    call revue#session#Threads(get(a:session, 'panelthread', ''))
  elseif kind ==# 'feedback'
    let key = get(a:session.feedbackrows, string(line('.')), '')
    let oldrows = sort(keys(filter(copy(a:session.feedbackrows), {_, value -> value ==# key})), 'n')
    let offset = empty(oldrows) ? 0 : line('.') - str2nr(oldrows[0])
    call revue#session#Feedback()
    let newrows = sort(keys(filter(copy(a:session.feedbackrows), {_, value -> value ==# key})), 'n')
    if !empty(newrows) | let view.lnum = str2nr(newrows[0]) + min([offset, len(newrows) - 1]) | endif
  elseif kind ==# 'conversation'
    call revue#session#Conversation()
  elseif index(['assignments', 'assignment'], kind) >= 0
    call revue#session#AssignmentView()
    let view = revue#assignment#Restore(view, assignment_row, a:session.assignment_view_rows)
  elseif kind ==# 'assignment-selection'
    call revue#session#AssignmentSelection()
  elseif kind ==# 'batch'
    call revue#session#Batch(get(a:session, 'batchid', ''))
  elseif kind ==# 'activity'
    call revue#session#Activity()
  elseif kind ==# 'reanchor'
    call revue#session#ReanchorPreview()
  elseif kind ==# 'message-history'
    call revue#session#MessageHistory()
    let view = revue#timeline#Restore(view, history_row, a:session.historyrows)
  elseif kind ==# 'timeline'
    call revue#session#Timeline()
    let view = revue#timeline#Restore(view, timeline_target, a:session.timelinerows)
  elseif kind ==# 'service-progress'
      call revue#session#ServiceProgress(1)
    elseif kind ==# 'readiness'
    call revue#session#Readiness()
    let view = revue#timeline#Restore(view, readiness_target, a:session.readinessrows)
  elseif kind ==# 'comparisons'
    call revue#session#Comparisons()
    let view = s:ComparisonView(a:session, view, comparison_target)
  elseif kind ==# 'discussions'
    call revue#session#Discussions()
  elseif kind ==# 'reactions'
    call revue#session#Reactions(a:session.reaction_target)
    for [row, item] in items(get(a:session, 'reactionrows', {}))
      if item.id ==# get(reaction_row, 'id', '')
        let view.topline = max([1, view.topline + str2nr(row) - view.lnum])
        let view.lnum = str2nr(row)
        break
      endif
    endfor
  elseif kind ==# 'pending'
    call revue#session#Pending()
    let view.lnum = 1
    for row in sort(keys(a:session.pendingrows), 'n')
      if revue#pending#RowKey(a:session.pendingrows[row]) ==# revue#pending#RowKey(pending) | let view.lnum = str2nr(row) | break | endif
    endfor
  endif
  if !empty(selected) && !empty(selected.comment)
    for target in values(a:session.messagemap)
      if target.comment ==# selected.comment && target.thread ==# selected.thread && target.kind ==# selected.kind
        let delta = target.start - selected.start
        let view.lnum = min([target.end, view.lnum + delta])
        let view.topline = max([1, view.topline + delta])
        break
      endif
    endfor
  elseif !empty(discovery)
    let found = 0
    for row in sort(keys(a:session.discoveryrows), 'n')
      if revue#discovery#Key(a:session.discoveryrows[row]) ==# revue#discovery#Key(discovery)
        let delta = str2nr(row) - discovery.start
        let view.lnum += delta
        let view.topline = max([1, view.topline + delta])
        let found = 1
        break
      endif
    endfor
    if !found
      let view.lnum = 1
      let view.topline = 1
      call s:Notice('The selected discussion no longer matches this view.')
    endif
  elseif !empty(operation)
    for row in sort(keys(a:session.activityrows), 'n')
      let target = a:session.activityrows[row]
      if target.operation ==# operation.operation && get(target, 'sequence', -1) == get(operation, 'sequence', -1)
        let view.topline = max([1, view.topline + str2nr(row) - view.lnum])
        let view.lnum = str2nr(row)
        break
      endif
    endfor
  endif
  call winrestview(view)
  call revue#session#MessageFocus()
  call win_gotoid(previous)
endfunction

function! revue#session#CopyMessage(link, register) abort
  let session = s:Get()
  if empty(session) | return | endif
  let selected = revue#discussion#Selected(session, line('.'))
  if empty(selected) | call s:Notice('Select a message first.') | return | endif
  let text = a:link ? get(selected.message, 'url', '') : selected.message.body
  if a:link && empty(text) | call s:Notice('This message has no permalink.') | return | endif
  call setreg(empty(a:register) ? '"' : a:register, text, 'v')
  call s:Notice(a:link ? 'Message link copied.' : 'Message body copied.')
endfunction

function! revue#session#MessageActions() abort
  let session = s:Get()
  if empty(session) | return | endif
  let selected = deepcopy(revue#discussion#Selected(session, line('.')))
  let window = win_getid()
  if empty(selected) | call s:Notice('Select a message first.') | return | endif
  let actions = ['Quote in reply', 'Copy message body']
  if get(get(get(selected.message, 'capabilities', {}), 'reactions', {}), 'enabled', 0)
    call add(actions, 'Reactions')
  endif
  if get(get(get(selected.message, 'capabilities', {}), 'edit', {}), 'enabled', 0) && get(get(get(session.snapshot, 'capabilities', {}), 'edit', {}), 'enabled', 0)
    call add(actions, 'Edit message')
  endif
  let deleting = revue#delete#Fields(session.snapshot, {'message': selected.comment, 'message_kind': selected.kind, 'thread': selected.thread})
  if empty(revue#capabilities#Error(session.snapshot, deleting, 0)) | call add(actions, 'Delete private comment') | endif
  if !empty(revue#links#Semantic(selected.message.body, get(selected.message, 'resolved_links', {})))
    call add(actions, 'Links in message body')
  endif
  if !empty(selected.thread) && empty(revue#capabilities#Error(session.snapshot, {'kind': 'reply', 'thread': selected.thread}, 0))
    call add(actions, 'Reply to thread')
  endif
  if !empty(selected.thread)
    let private_fields = revue#pending#ReplyFields(session.snapshot, selected.thread)
    if !has_key(private_fields, 'error') && empty(revue#capabilities#Error(session.snapshot, private_fields, 0))
      call add(actions, 'Reply privately')
    endif
  endif
  let threads = filter(copy(session.snapshot.threads), {_, t -> t.id ==# selected.thread})
  let pending_state = revue#thread_state#Pending(session, selected.thread)
  if !empty(pending_state)
    call add(actions, pending_state.state ==# 'unknown' ? 'Check resolution outcome' : pending_state.state ==# 'submitting' ? 'Resolution in progress' : pending_state.resolved ? 'Retry resolving thread' : 'Retry reopening thread')
  elseif !empty(threads) && has_key(threads[0], 'resolved')
    let desired = !threads[0].resolved
    if empty(revue#capabilities#Error(session.snapshot, {'kind': 'thread_state', 'thread': selected.thread, 'resolved': desired}, 0))
      call add(actions, desired ? 'Resolve thread' : 'Reopen thread')
    endif
  endif
  if !empty(get(selected.message, 'url', ''))
    call add(actions, 'Copy permalink')
    if revue#links#IsWeb(selected.message.url) | call add(actions, 'Open permalink') | endif
  endif
  if has_key(session.read_state.unread, revue#activity#Key(selected.thread, selected.message))
    call add(actions, 'Mark message read')
  endif
  let deletion = revue#delete_message#Fields(session.snapshot, {'message': selected.comment, 'message_kind': selected.kind, 'thread': selected.thread})
  if empty(revue#capabilities#Error(session.snapshot, deletion, 0)) | call add(actions, 'Delete message') | endif
  if empty(s:MessageHistoryError(session, selected.message)) | call add(actions, 'Edit history') | endif
  call add(actions, 'Quote with attribution')
  let application = {'thread': selected.thread, 'message': selected.comment, 'message_kind': selected.kind, 'expected_version': get(selected.message, 'version', '')}
  if empty(revue#apply_suggestion#Error(session.snapshot, application)) | call add(actions, 'Apply suggestion to workspace') | endif
  if !empty(revue#links#Body(selected.message.body)) | call add(actions, 'Explicit URLs including code') | endif
  let menu = [revue#message#Header(selected.message, session.snapshot.author),
        \ revue#message#OneLine(selected.kind . ' #' . selected.comment) . ' · message actions']
  for index in range(len(actions)) | call add(menu, printf('%d. %s', index + 1, actions[index])) | endfor
  let choice = inputlist(menu) - 1
  if choice < 0 || choice >= len(actions) | return | endif
  if !s:SameMessage(session, selected, window)
    call s:Notice('Message selection changed; choose the action again.')
    return
  endif
  if actions[choice] ==# 'Quote in reply'
    call revue#session#Quote(0)
  elseif actions[choice] ==# 'Quote with attribution'
    call revue#session#Quote(0, 0, 0, 1)
  elseif actions[choice] ==# 'Apply suggestion to workspace'
    call revue#session#ApplySuggestion()
  elseif actions[choice] ==# 'Explicit URLs including code'
    call revue#session#BodyLinks(1)
  elseif actions[choice] ==# 'Copy message body'
    call revue#session#CopyMessage(0, '"')
  elseif actions[choice] ==# 'Delete message'
    call revue#session#DeleteMessage()
  elseif actions[choice] ==# 'Delete private comment'
    call revue#session#DeletePendingComment()
  elseif actions[choice] ==# 'Reply privately'
    call revue#session#Reply(1)
  elseif actions[choice] ==# 'Edit history'
    call revue#session#MessageHistory()
  elseif actions[choice] ==# 'Edit message'
    call revue#session#EditMessage()
  elseif actions[choice] ==# 'Reactions'
    call revue#session#Reactions()
  elseif actions[choice] ==# 'Reply to thread'
    call revue#session#Reply()
  elseif actions[choice] ==# 'Resolve thread' || actions[choice] ==# 'Reopen thread'
    call revue#session#ChangeThreadState(actions[choice] ==# 'Resolve thread')
  elseif actions[choice] ==# 'Check resolution outcome'
    call revue#session#CheckThreadState()
  elseif actions[choice] ==# 'Resolution in progress'
    call s:Notice('Resolution is in progress; wait for its outcome.')
  elseif actions[choice] ==# 'Retry resolving thread' || actions[choice] ==# 'Retry reopening thread'
    call revue#session#ChangeThreadState(actions[choice] ==# 'Retry resolving thread')
  elseif actions[choice] ==# 'Copy permalink'
    call revue#session#CopyMessage(1, '"')
  elseif actions[choice] ==# 'Open permalink'
    call revue#session#OpenLink()
  elseif actions[choice] ==# 'Links in message body'
    call revue#session#BodyLinks()
  elseif actions[choice] ==# 'Mark message read'
    call revue#session#MarkRead()
  endif
endfunction

function! s:MessageHistoryError(session, message) abort
  if empty(a:message) | return 'The selected message is unavailable.' | endif
  for rule in [get(get(a:session.snapshot, 'capabilities', {}), 'message_history', {}), get(get(a:message, 'capabilities', {}), 'message_history', {})]
    if !get(rule, 'enabled', 0) | return empty(get(rule, 'reason', '')) ? 'Edit history is unavailable here; use the message link when available.' : rule.reason | endif
  endfor
  return empty(get(a:message, 'version', '')) ? 'The backend has not supplied a message version.' : ''
endfunction

function! revue#session#MessageHistory(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let selected = revue#discussion#Selected(session, line('.'))
  let target = a:0 ? a:1 : get(b:, 'revue_view', '') ==# 'message-history' ? session.message_history.target :
        \ empty(selected) ? {} : {'message': selected.comment, 'message_kind': selected.kind, 'thread': selected.thread,
        \ 'expected_version': get(selected.message, 'version', ''), 'body': selected.message.body}
  if empty(target) | call s:Notice('Select a message to inspect its edit history.') | return | endif
  if get(get(session, 'message_history', {}), 'target', {}) !=# target
    let message = revue#edit#Message(session.snapshot, target)
    let session.history_request = get(session, 'history_request', 0) + 1
    let session.message_history = revue#message_history#State(target, empty(message) ? target.message_kind . ' #' . target.message : revue#message#Header(message, session.snapshot.author), get(message, 'url', ''))
  endif
  let state = session.message_history
  let view = revue#message_history#View(state)
  let origin = s:Origin()
  call s:Fill(s:Panel(session, 'message-history'), view.lines)
  call revue#surface#Paint(session.panel, view.decorations, 0)
  if origin.kind !=# 'message-history' | let b:revue_origin = origin | endif
  let session.historyrows = view.rows
  call revue#layout#SetBar(win_getid(), ' Edit history | :ReviewReviewActions · :ReviewClose ')
  if !state.requested | call revue#session#LoadMessageHistory(1) | endif
endfunction

function! revue#session#LoadMessageHistory(reset) abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'message_history') | return | endif
  let state = session.message_history
  if !a:reset && (state.loading || state.complete) | return | endif
  let state.requested = 1
  let session.history_request = get(session, 'history_request', 0) + 1
  let state.loading = 0
  let message = revue#edit#Message(session.snapshot, state.target)
  let state.error = s:MessageHistoryError(session, message)
  if !empty(state.error) | call s:RepaintPanel(session) | return | endif
  if a:reset
    let state.target.expected_version = message.version
    let state.target.body = message.body
  elseif state.target.expected_version !=# message.version || state.target.body !=# message.body
    let state.error = 'Message changed. Reload its edit history.'
    call s:RepaintPanel(session)
    return
  endif
  let state.loading = 1
  let cursor = a:reset ? '' : state.cursor
  let target = deepcopy(state.target)
  call s:RepaintPanel(session)
  call session.Host({'op': 'message_history', 'target': target, 'cursor': cursor},
        \ function('s:MessageHistoryLoaded', [session.id, session.history_request, session.generation, target, cursor, a:reset]))
endfunction

function! s:MessageHistoryLoaded(id, serial, generation, target, cursor, reset, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:serial != get(session, 'history_request', 0) || get(get(session, 'message_history', {}), 'target', {}) !=# a:target | return | endif
  let state = session.message_history
  let state.loading = 0
  let message = revue#edit#Message(session.snapshot, a:target)
  if a:generation != session.generation || empty(message) || get(message, 'version', '') !=# a:target.expected_version || message.body !=# a:target.body
    let state.error = 'Message or comparison changed. Reload edit history.'
  elseif !empty(s:MessageHistoryError(session, message))
    let state.error = s:MessageHistoryError(session, message)
  else
    let state.error = get(a:result, 'ok', 0) ? revue#message_history#Apply(state, get(a:result, 'data', {}), a:cursor, a:reset) : get(a:result, 'error', 'Edit history could not be read.')
  endif
  if get(session, 'panelkind', '') ==# 'message-history' | call s:RepaintPanel(session) | endif
endfunction

function! revue#session#CancelMessageHistory() abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'message_history') | return | endif
  let session.history_request = get(session, 'history_request', 0) + 1
  let session.message_history.loading = 0
  let session.message_history.error = 'Read cancelled; loaded edits retained. Reload or load older edits to retry.'
  call s:RepaintPanel(session)
endfunction

function! revue#session#HistoryMessageLink() abort
  let session = s:Get()
  let url = get(get(session, 'message_history', {}), 'url', '')
  if !revue#links#IsWeb(url) | call s:Notice('This message has no web link.') | return | endif
  call s:Browse(url)
endfunction

function! revue#session#Reactions(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let selected = revue#discussion#Selected(session, line('.'))
  let target = a:0 ? deepcopy(a:1) : get(b:, 'revue_view', '') ==# 'reactions' ? deepcopy(get(session, 'reaction_target', {})) : empty(selected) ? {} : {'message': selected.comment, 'message_kind': selected.kind, 'thread': selected.thread}
  if empty(target) | call s:Notice('Select a message to inspect its reactions.') | return | endif
  let message = revue#edit#Message(session.snapshot, target)
  let available = !empty(message) && get(get(get(session.snapshot, 'capabilities', {}), 'reactions', {}), 'enabled', 0) && get(get(get(message, 'capabilities', {}), 'reactions', {}), 'enabled', 0)
  let origin = s:Origin()
  let session.reaction_selection = origin.kind ==# 'reactions' ? get(get(get(session, 'reactionrows', {}), string(line('.')), {}), 'id', '') : ''
  let panel = s:Panel(session, 'reactions')
  if origin.kind !=# 'reactions' | let b:revue_origin = origin | endif
  let session.reaction_target = target
  let session.reaction_data = {}
  let session.reactionrows = {}
  let session.reaction_request = get(session, 'reaction_request', 0) + 1
  call s:PaintReactions(session, panel, available ? 'Loading reaction counts and your state…' : 'The message or its reaction details are no longer available.')
  if origin.kind !=# 'reactions' | call cursor(1, 1) | endif
  if !available | return | endif
  call session.Host({'op': 'reactions', 'target': target}, function('s:ReactionsLoaded', [session.id, session.reaction_request, session.generation, panel]))
endfunction

function! s:ReactionsLoaded(id, token, generation, panel, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:token != get(session, 'reaction_request', 0) || a:generation != session.generation || !bufexists(a:panel) || getbufvar(a:panel, 'revue_view', '') !=# 'reactions' || revue#layout#BufferWindow(a:panel) < 0 | return | endif
  let message = revue#edit#Message(session.snapshot, session.reaction_target)
  let session.reactionrows = {}
  if empty(message) | call s:PaintReactions(session, a:panel, 'The selected message is no longer available.') | return | endif
  if !a:result.ok || !revue#reaction#Valid(get(a:result, 'data', {}))
    call s:PaintReactions(session, a:panel, get(a:result, 'error', 'Backend returned incomplete reaction data.'))
    return
  endif
  let session.reaction_data = deepcopy(a:result.data)
  let message.reactions = deepcopy(a:result.data)
  call s:PaintReactions(session, a:panel, '')
  call s:Annotations(session)
endfunction

function! s:PaintReactions(session, panel, error) abort
  let view = revue#reaction#View(a:session, a:error)
  let a:session.reactionrows = view.rows
  call s:Fill(a:panel, view.lines)
  call revue#surface#Paint(a:panel, map(copy(view.lines), {_, text -> {'text': text, 'type': text =~# '^#' ? 'RevueCardHeader' : 'RevueCardBody'}}), 0)
  for [row, item] in items(view.rows)
    if item.id ==# get(a:session, 'reaction_selection', '')
      let win = revue#layout#BufferWindow(a:panel)
      if win > 0 | call win_execute(win, 'call cursor(' . row . ', 1)') | endif
      break
    endif
  endfor
endfunction

function! revue#session#React() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'reactions' | return | endif
  let item = get(get(session, 'reactionrows', {}), string(line('.')), {})
  if empty(item) | call s:Notice('Select a reaction with known actor state.') | return | endif
  if !empty(get(item, 'reason', '')) | call s:Notice(item.reason) | return | endif
  let target = session.reaction_target
  let draft = revue#reaction#Pending(session, target, item.id)
  if empty(draft)
    let fields = extend(deepcopy(target), {'kind': 'reaction', 'reaction': item.id, 'reaction_label': item.label,
          \ 'actor': session.reaction_data.actor, 'actor_label': get(session.reaction_data, 'actor_label', session.reaction_data.actor), 'present': item.mine ? v:false : v:true})
    let id = s:NewDraft(session, fields, 1)
    if empty(id) | return | endif
    let draft = s:Draft(session, id)
  endif
  if draft.state ==# 'submitting' | call s:Notice('This reaction operation is already in progress.') | return | endif
  let reconcile = draft.state ==# 'unknown'
  if !reconcile
    let error = s:SubmissionError(session, draft)
    if draft.actor !=# get(session.reaction_data, 'actor', '') | let error = 'Reaction actor changed; reload the chooser.' | endif
    if !empty(error) | call s:Notice(error) | return | endif
  endif
  let oldstate = draft.state
  let draft.state = 'submitting'
  if !s:Save(session) | let draft.state = oldstate | return | endif
  if !has_key(session, 'reaction_attempts') | let session.reaction_attempts = {} | endif
  let attempt = get(session.reaction_attempts, draft.id, 0) + 1
  let session.reaction_attempts[draft.id] = attempt
  let session.reaction_selection = item.id
  call s:PaintReactions(session, bufnr(), '')
  call s:RenderTree(session)
  try
    call session.Host({'op': 'mutate', 'draft': deepcopy(draft), 'reconcile': reconcile}, function('s:ReactionSent', [session.id, draft.id, attempt, reconcile]))
  catch
    call s:ReactionSent(session.id, draft.id, attempt, reconcile, {'ok': 0, 'unknown': 1, 'error': 'Reaction request interrupted: ' . v:exception})
  endtry
endfunction

function! s:ReactionSent(id, draftid, attempt, reconcile, result) abort
  let session = get(s:sessions, a:id, {})
  let draft = empty(session) ? {} : s:Draft(session, a:draftid)
  if empty(draft) || draft.state !=# 'submitting' || get(get(session, 'reaction_attempts', {}), a:draftid, 0) != a:attempt | return | endif
  call s:Sent(a:id, a:draftid, a:reconcile, a:result)
endfunction

function! revue#session#EditMessage() abort
  let session = s:Get()
  if empty(session) | return | endif
  let selected = revue#discussion#Selected(session, line('.'))
  if empty(selected) || empty(selected.comment) | call s:Notice('Select an identified message to edit.') | return | endif
  call s:EditTarget(session, {'message': selected.comment, 'message_kind': selected.kind, 'thread': selected.thread}, selected.message)
endfunction

function! s:EditTarget(session, target, message) abort
  let pending = get(a:message, 'pending_review', '')
  if !empty(pending) && s:PendingBusy(a:session, '', pending) | return | endif
  for draft in a:session.drafts
    if draft.kind ==# 'edit' && draft.message ==# a:target.message && draft.message_kind ==# a:target.message_kind && draft.thread ==# a:target.thread
      call s:Composer(a:session, draft.id)
      return
    endif
    if !empty(pending) && get(draft, 'pending_review', '') ==# pending && index(['submit_pending', 'discard_pending', 'delete_pending_comment'], draft.kind) >= 0
      call s:Composer(a:session, draft.id)
      call s:Notice('Inspect the existing publication/discard operation before editing this private review.')
      return
    endif
  endfor
  let fields = extend(deepcopy(a:target), {'kind': 'edit', 'expected_version': get(a:message, 'version', ''),
        \ 'original_body': a:message.body, 'body': a:message.body})
  if !empty(pending) | call extend(fields, {'pending_review': pending, 'actor': get(a:message, 'actor', '')}) | endif
  call s:NewDraft(a:session, fields)
endfunction

function! revue#session#EditBase() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_role', '') !=# 'draft' | return | endif
  let draft = s:Draft(session, get(b:, 'revue_draft', ''))
  if empty(draft) || draft.kind !=# 'edit' | call s:Notice('Open a message edit draft first.') | return | endif
  if index(['draft', 'failed'], draft.state) < 0 | call s:Notice('Check the receipt before changing an uncertain edit.') | return | endif
  call revue#session#SaveDraft()
  if get(b:, 'revue_save_error', 0) | return | endif
  let editor = bufnr()
  let latest = session.comparisons[session.latest_comparison].snapshot
  let message = deepcopy(revue#edit#Message(latest, draft))
  if empty(message) || empty(get(message, 'version', '')) | call s:Notice('Refresh to load the current message before accepting its version.') | return | endif
  let proposed = extend(deepcopy(draft), {'expected_version': message.version, 'original_body': message.body})
  let error = revue#capabilities#Error(latest, proposed, 0)
  if !empty(error) | call s:Notice(error) | return | endif
  if proposed.expected_version ==# draft.expected_version | call s:Notice('This edit already uses the current message version.') | return | endif
  if confirm('Accept the current message version as the edit base? Inspect :ReviewPreview first. Your replacement text is retained.', "&Accept\n&Keep original base", 2) != 1 | return | endif
  if bufnr() != editor || get(b:, 'revue_draft', '') !=# draft.id || index(['draft', 'failed'], draft.state) < 0
    call s:Notice('Edit selection or delivery state changed; inspect the draft again.')
    return
  endif
  let latest = session.comparisons[session.latest_comparison].snapshot
  if !empty(revue#capabilities#Error(latest, proposed, 0)) | call s:Notice('The message changed again; refresh and inspect the preview.') | return | endif
  let previous = deepcopy(draft)
  let draft.expected_version = proposed.expected_version
  let draft.original_body = proposed.original_body
  let draft.state = 'draft'
  if !s:Save(session) | call extend(draft, previous) | return | endif
  call s:DraftContext(session, draft, bufnr())
  call s:Notice('Current version accepted as edit base. Your replacement text is retained; preview before sending.')
endfunction

function! s:SameMessage(session, selected, window) abort
  if win_getid() != a:window || get(b:, 'revue_session', '') !=# a:session.id | return 0 | endif
  let current = revue#discussion#Selected(a:session, line('.'))
  return !empty(current) && current.comment ==# a:selected.comment
        \ && current.thread ==# a:selected.thread && current.kind ==# a:selected.kind
        \ && (!empty(current.comment) || current.index == a:selected.index)
        \ && current.message.body ==# a:selected.message.body
        \ && get(current.message, 'version', '') ==# get(a:selected.message, 'version', '')
endfunction

function! revue#session#BodyLinks(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let selected = deepcopy(revue#discussion#Selected(session, line('.')))
  if empty(selected) | call s:Notice('Select a message first.') | return | endif
  let explicit = a:0 && a:1
  let session.link_request = get(session, 'link_request', 0) + 1
  if !explicit && get(get(get(session.snapshot, 'capabilities', {}), 'rendered_links', {}), 'enabled', 0)
    let target = {'message': selected.comment, 'message_kind': selected.kind, 'thread': selected.thread,
          \ 'body': selected.message.body, 'expected_version': get(selected.message, 'version', ''),
          \ 'pending_review': get(selected.message, 'pending_review', '')}
    call s:Notice('Loading backend-rendered links…')
    call session.Host({'op': 'rendered_links', 'target': target}, function('s:LinksLoaded', [session.id, session.link_request, win_getid(), selected]))
    return
  endif
  let links = explicit ? revue#links#Body(selected.message.body) : revue#links#Semantic(selected.message.body, get(selected.message, 'resolved_links', {}))
  call s:ChooseLinks(session, selected, win_getid(), links, explicit)
endfunction

function! s:LinksLoaded(id, token, window, selected, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:token != get(session, 'link_request', 0) || !s:SameMessage(session, a:selected, a:window) | return | endif
  let data = get(a:result, 'data', {})
  if !a:result.ok
    call s:Notice(get(a:result, 'error', 'Backend links unavailable.') . ' :ReviewBodyURLs reads explicit addresses locally.')
    return
  endif
  if type(data) != v:t_dict || get(data, 'message', '') !=# a:selected.comment || get(data, 'message_kind', '') !=# a:selected.kind || get(data, 'thread', '') !=# a:selected.thread || get(data, 'version', '') !=# get(a:selected.message, 'version', '') || type(get(data, 'links', 0)) != v:t_list
    call s:Notice('Backend links did not match the selected message/version. Refresh and try again.')
    return
  endif
  let links = []
  for link in data.links
    if type(link) != v:t_dict || type(get(link, 'label', 0)) != v:t_string || !revue#links#IsWeb(get(link, 'url', ''))
      call s:Notice('Backend returned an unsupported link destination.')
      return
    endif
    call add(links, extend(deepcopy(link), {'reason': '', 'line': 0}))
  endfor
  call s:ChooseLinks(session, a:selected, a:window, links, 0)
endfunction

function! s:ChooseLinks(session, selected, window, links, explicit) abort
  if empty(a:links) | call s:Notice(a:explicit ? 'No explicit HTTP(S) URLs in this message body.' : 'No supported prose links in this message. :ReviewBodyURLs includes addresses in code examples.') | return | endif
  let menu = [revue#message#Header(a:selected.message, a:session.snapshot.author),
        \ a:explicit ? 'Body URLs (includes code examples) · 0 cancels' : 'Message links · 0 cancels']
  for index in range(len(a:links))
    let item = a:links[index]
    call add(menu, printf('%d. %s%s', index + 1, get(item, 'line', 0) > 0 ? 'Line ' . item.line . ': ' : '', revue#message#OneLine(get(item, 'label', item.url))))
    if !a:explicit | call add(menu, '   ' . (empty(item.reason) ? item.url : item.destination . ' · ' . item.reason)) | endif
  endfor
  let choice = inputlist(menu) - 1
  if choice < 0 || choice >= len(a:links) | return | endif
  if !empty(get(a:links[choice], 'reason', '')) | call s:Notice(a:links[choice].reason) | return | endif
  let url = a:links[choice].url
  let action = inputlist([url, '1. Open in browser', '2. Copy URL to unnamed register', '0. Cancel'])
  if index([1, 2], action) < 0 | return | endif
  if !s:SameMessage(a:session, a:selected, a:window)
    call s:Notice('Message selection or body changed; choose the link again.')
    return
  endif
  if action == 2
    call setreg('"', url, 'v')
    call s:Notice('Body URL copied.')
  else
    call s:Browse(url)
  endif
endfunction

function! s:Browse(url) abort
  if !revue#links#IsWeb(a:url)
    call s:Notice('This address is not an explicit HTTP(S) URL.')
    return
  endif
  if exists('*netrw#BrowseX') || !empty(globpath(&runtimepath, 'autoload/netrw.vim'))
    call netrw#BrowseX(a:url, 0)
  else
    call s:Notice('Browser opener unavailable. Copy the URL instead.')
  endif
endfunction

function! revue#session#OpenLink() abort
  let session = s:Get()
  if empty(session) | return | endif
  let selected = revue#discussion#Selected(session, line('.'))
  let url = empty(selected) ? '' : get(selected.message, 'url', '')
  if !revue#links#IsWeb(url)
    call s:Notice('This message has no web permalink.')
    return
  endif
  call s:Browse(url)
endfunction

function! revue#session#Quote(visual, ...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let start = a:visual == 2 ? a:1 : a:visual ? min([line("'<"), line("'>")]) : line('.')
  let end = a:visual == 2 ? a:2 : a:visual ? max([line("'<"), line("'>")]) : line('.')
  let selected = revue#discussion#Selected(session, start)
  if empty(selected) | call s:Notice('Select a message to quote.') | return | endif
  let body = selected.message.body
  if a:visual
    if start < selected.body_start || end > selected.body_end
      call s:Notice('Select body text within one message to quote.')
      return
    endif
    if a:visual == 2
      let body = join(getline(start, end), "\n")
    elseif exists('*getregion')
      let body = join(getregion(getpos("'<"), getpos("'>"), {'type': visualmode()}), "\n")
    else
      let lines = getline(start, end)
      if visualmode() !=# 'V'
        call s:Notice('Use a linewise selection to quote on this Vim build.')
        return
      endif
      let body = join(lines, "\n")
    endif
  endif
  let quote = join(map(split(body, "\n", 1), {_, text -> '> ' . text}), "\n") . "\n\n"
  if a:0 >= 3 ? a:3 : get(g:, 'revue_quote_attribution', 0)
    let quote = revue#message#Attribution(selected.message) . "\n\n" . quote
  endif
  let fields = empty(selected.thread) ? {'kind': 'conversation'} : {'kind': 'reply', 'thread': selected.thread}
  let private = !empty(selected.thread) && (revue#pending#PrivateThread(session.snapshot, selected.thread) || get(selected.message, 'publication', '') ==# 'pending')
  for draft in session.drafts
    if draft.kind ==# 'reply' && get(draft, 'thread', '') ==# selected.thread && !empty(get(draft, 'pending_mode', '')) && index(['draft', 'failed'], draft.state) < 0
      call s:Composer(session, draft.id)
      call s:Notice('Recover the existing private reply before quoting again. Quoted text was not appended.')
      return
    endif
  endfor
  if private
    let fields = revue#pending#ReplyFields(session.snapshot, selected.thread)
    if has_key(fields, 'error') | call s:Notice(fields.error) | return | endif
    if s:PendingBusy(session, '', fields.pending_review) | return | endif
    for draft in session.drafts
      if draft.kind ==# 'reply' && draft.thread ==# selected.thread && (get(draft, 'pending_mode', '') !=# 'add' || get(draft, 'pending_review', '') !=# fields.pending_review || get(draft, 'actor', '') !=# fields.actor || index(['draft', 'failed'], draft.state) < 0)
        call s:Composer(session, draft.id)
        call s:Notice('Inspect or recover the existing reply before adding a private quote. Quoted text was not appended.')
        return
      endif
    endfor
    let error = revue#capabilities#Error(session.snapshot, fields, 0)
    if !empty(error) | call s:Notice(error) | return | endif
  endif
  " Reuse an editable reply rather than silently replacing or duplicating it.
  for draft in session.drafts
    if draft.kind ==# fields.kind && get(draft, 'thread', '') ==# get(fields, 'thread', '') && index(['draft', 'failed'], draft.state) >= 0
      call s:Composer(session, draft.id)
      let existing = join(getline(1, '$'), "\n")
      let combined = (empty(existing) ? '' : existing . "\n\n") . quote
      call setline(1, split(combined, "\n", 1))
      call revue#session#SaveDraft()
      call cursor(line('$'), 1)
      return
    endif
  endfor
  let fields.body = quote
  if !empty(s:NewDraft(session, fields)) | call cursor(line('$'), 1) | endif
endfunction

function! revue#session#JumpThread() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'threads' | return | endif
  let id = get(session.threadmap, string(line('.')), '')
  for thread in session.snapshot.threads
    if thread.id ==# id && !thread.outdated && session.index >= 0 && thread.path ==# session.snapshot.files[session.index].path
      if revue#anchor#IsFile(thread)
        call win_gotoid(session[get(get(session.loaded, 'head', {}), 'kind', '') ==# 'absent' ? 'basewin' : 'headwin'])
        normal! ggzt
        return
      endif
      if get(get(session.loaded, thread.side, {}), 'kind', '') !=# 'text'
        call s:Notice('Source text is not loaded for this thread yet.')
        return
      endif
      call win_gotoid(session[thread.side . 'win'])
      call cursor(thread.line, 1)
      normal! zv
      return
    endif
  endfor
endfunction

function! revue#session#NextThread(delta) abort
  let session = s:Get()
  if empty(session) || session.index < 0 | return | endif
  let side = get(b:, 'revue_side', 'head')
  let positions = sort(map(filter(copy(session.snapshot.threads), {_, t -> t.path ==# session.snapshot.files[session.index].path && t.side ==# side && !t.outdated}), {_, t -> t.line}), 'n')
  if a:delta < 0 | call reverse(positions) | endif
  for lnum in positions
    if (lnum - line('.')) * a:delta > 0
      call cursor(lnum, 1)
      normal! zv
      return
    endif
  endfor
endfunction

function! revue#session#ReanchorDraft() abort
  let session = s:Get()
  if empty(session) || !s:SyncDraftBuffers(session) | return | endif
  let draft = s:Draft(session, get(b:, 'revue_draft', ''))
  let error = revue#reanchor#Error(session.comparisons[session.latest_comparison].snapshot, draft)
  if !empty(error) | call s:Notice(error) | return | endif
  let session.reanchor = {'original': deepcopy(draft), 'origin': s:Origin(),
        \ 'old_source': draft.kind ==# 'comment' ? deepcopy(s:DraftSource(session, draft)) : {}}
  call win_gotoid(session.headwin)
  call revue#session#Latest()
  call s:Notice('Choose a new file or source range, then :ReviewReanchorHere. :ReviewCancelReanchor returns to the original draft.')
endfunction

function! s:ReanchorError(session, ...) abort
  let state = get(a:session, 'reanchor', {})
  if empty(state) | return 'Open a local draft and use :ReviewReanchorDraft first.' | endif
  let original = s:Draft(a:session, state.original.id)
  let error = revue#reanchor#Error(a:session.comparisons[a:session.latest_comparison].snapshot, original)
  if !empty(error) | return error | endif
  if original !=# state.original | return 'The original draft changed. Cancel and start its move again; the edited text is retained.' | endif
  if a:session.busy | return 'Wait for the current review refresh before choosing or accepting a target.' | endif
  if !a:0 && !has_key(state, 'proposal') | return 'Choose a new file or source range first.' | endif
  if has_key(state, 'proposal') && !a:0
    if state.latest_request != get(a:session, 'latest_request', 0) || state.generation != a:session.generation || state.proposal.snapshot !=# a:session.latest_comparison || state.proposal.snapshot !=# a:session.snapshot.snapshot
      return 'The comparison or review changed. Close this preview and choose the target again.'
    endif
    let error = revue#capabilities#Error(a:session.snapshot, state.proposal, 0)
    if !empty(error) | return error | endif
    return revue#anchor#Error(a:session.snapshot, state.proposal, state.new_source)
  endif
  return ''
endfunction

function! revue#session#ReanchorHere(visual, ...) abort
  let session = s:Get()
  if empty(session) || !s:SyncDraftBuffers(session) | return | endif
  let state = get(session, 'reanchor', {})
  if empty(state) | call s:Notice('Open a local draft and use :ReviewReanchorDraft first.') | return | endif
  " A newly chosen location replaces only the ephemeral candidate.
  let error = s:ReanchorError(session, 1)
  if !empty(error) | call s:Notice(error) | return | endif
  if session.snapshot.snapshot !=# session.latest_comparison || s:SelectedFile(session) < 0
    call s:Notice('Select a file in the latest comparison before choosing the new anchor.')
    return
  endif
  let file = session.snapshot.files[s:SelectedFile(session)]
  let location = {'path': file.path, 'old_path': file.old_path}
  let source = {}
  if state.original.kind ==# 'comment'
    let side = get(b:, 'revue_side', '')
    if index(['base', 'head'], side) < 0 | call s:Notice('Choose a source line or Visual range for this draft.') | return | endif
    let location.side = side
    let location.start = a:0 ? a:1 : a:visual ? min([line("'<"), line("'>")]) : line('.')
    let location.end = a:0 ? a:2 : a:visual ? max([line("'<"), line("'>")]) : line('.')
    let source = deepcopy(get(session.loaded, side, {}))
  endif
  let proposal = revue#reanchor#Propose(state.original, session.snapshot, location, s:Id())
  let error = revue#capabilities#Error(session.snapshot, proposal, 0)
  if empty(error) | let error = revue#anchor#Error(session.snapshot, proposal, source) | endif
  if !empty(error) | call s:Notice(error) | return | endif
  if proposal.snapshot ==# state.original.snapshot && empty(filter(copy(location), {key, value -> get(state.original, key, 0) !=# value}))
    call s:Notice('Choose a different source location or comparison.')
    return
  endif
  let state.proposal = proposal
  let state.new_source = source
  let state.target_origin = s:Origin()
  let state.generation = session.generation
  let state.latest_request = get(session, 'latest_request', 0)
  call revue#session#ReanchorPreview()
endfunction

function! revue#session#ReanchorPreview() abort
  let session = s:Get()
  if empty(session) || !has_key(get(session, 'reanchor', {}), 'proposal') | return | endif
  let rows = revue#reanchor#View(session.reanchor, s:ReanchorError(session))
  call s:Fill(s:Panel(session, 'reanchor'), map(copy(rows), {_, row -> row.text}))
  call revue#surface#Paint(session.panel, rows, 0)
  call revue#layout#SetBar(win_getid(), ' Move draft | :ReviewAcceptReanchor · :ReviewCancelReanchor ')
endfunction

function! revue#session#CancelReanchor() abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'reanchor') | return | endif
  let origin = deepcopy(session.reanchor.origin)
  if get(b:, 'revue_view', '') ==# 'help' && get(get(b:, 'revue_origin', {}), 'kind', '') ==# 'reanchor' | call revue#session#CloseView() | endif
  if get(b:, 'revue_view', '') ==# 'reanchor' | call revue#session#CloseView() | endif
  call remove(session, 'reanchor')
  call s:Return(session, origin)
  call s:Notice('Move cancelled. The original draft is retained.')
endfunction

function! revue#session#AcceptReanchor() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'reanchor' || !s:SyncDraftBuffers(session) | return | endif
  if !has_key(get(session, 'reanchor', {}), 'proposal') | call s:Notice('Choose a new source location first.') | return | endif
  let error = s:ReanchorError(session)
  if !empty(error) | call s:Notice(error) | call revue#session#ReanchorPreview() | return | endif
  let state = session.reanchor
  let original = s:Draft(session, state.original.id)
  let index = index(session.drafts, original)
  let before = deepcopy(session.drafts)
  let selected = deepcopy(get(session, 'batchselected', {}))
  let session.drafts[index] = deepcopy(state.proposal)
  if has_key(get(session, 'batchselected', {}), original.id) | call remove(session.batchselected, original.id) | endif
  if !s:Save(session)
    let session.drafts = before
    let session.batchselected = selected
    call s:Notice('Move was not saved. The original draft and preview are retained.')
    return
  endif
  let new_id = state.proposal.id
  let target_origin = deepcopy(state.target_origin)
  call revue#session#CloseView()
  call remove(session, 'reanchor')
  for buf in session.buffers
    if getbufvar(buf, 'revue_draft', '') ==# original.id | execute 'silent! bwipeout! ' . buf | endif
  endfor
  call s:Return(session, target_origin)
  call s:RenderTree(session)
  call s:Composer(session, new_id)
  call s:Notice('Draft moved locally. Its text is unchanged; inspect Preview before sending.')
endfunction

function! revue#session#Comment(visual, ...) abort
  let session = s:Get()
  if empty(session) || session.index < 0 | return | endif
  let side = get(b:, 'revue_side', '')
  if empty(side) | call s:Notice('Select a source pane first.') | return | endif
  if get(get(session.loaded, side, {}), 'kind', '') !=# 'text'
    call s:Notice('Source text is unavailable on this side. Use :ReviewFileComment for whole-file feedback.')
    return
  endif
  let start = a:0 ? a:1 : a:visual ? min([line("'<"), line("'>")]) : line('.')
  let end = a:0 ? a:2 : a:visual ? max([line("'<"), line("'>")]) : line('.')
  let suggestion = a:0 > 2 && a:3
  if start < 1 || end < start || end > len(session.loaded[side].lines)
    call s:Notice('Select a valid source line range.')
    return
  endif
  let file = session.snapshot.files[session.index]
  let fields = {'kind': 'comment', 'path': file.path, 'old_path': file.old_path, 'side': side, 'start': start, 'end': end}
  if suggestion
    for draft in session.drafts
      if get(draft, 'suggestion', 0) && draft.snapshot ==# session.snapshot.snapshot &&
            \ get(draft, 'path', '') ==# file.path && get(draft, 'side', '') ==# side && draft.start == start && draft.end == end
        call s:Composer(session, draft.id)
        return
      endif
    endfor
    if session.snapshot.snapshot !=# session.latest_comparison
      call s:Notice('Open the latest comparison before proposing a new suggestion.')
      return
    endif
    let fields.suggestion = v:true
    let fields.body = revue#suggestion#Seed(session.loaded[side].lines[start - 1 : end - 1])
  endif
  let error = revue#anchor#Error(session.snapshot, fields, session.loaded[side])
  if !empty(error) | call s:Notice(error) | return | endif
  let id = s:NewDraft(session, fields)
  if suggestion && !empty(id) | call cursor(2, 1) | endif
endfunction

function! s:SelectedFile(session) abort
  if index(['files', 'base', 'head'], get(b:, 'revue_role', '')) < 0 | return -1 | endif
  if b:revue_role !=# 'files' | return a:session.index | endif
  let target = get(a:session.rows, string(line('.')), {})
  return get(target, 'kind', '') ==# 'file' ? target.index : -1
endfunction

function! revue#session#FileComment() abort
  let session = s:Get()
  if empty(session) | return | endif
  let index = s:SelectedFile(session)
  if index < 0 | call s:Notice('Select a file to comment on.') | return | endif
  let file = session.snapshot.files[index]
  for draft in session.drafts
    if draft.kind ==# 'file_comment' && draft.snapshot ==# session.snapshot.snapshot && draft.path ==# file.path
      call s:Composer(session, draft.id)
      return
    endif
  endfor
  if session.snapshot.snapshot !=# session.latest_comparison
    call s:Notice('Open the latest comparison before creating a file comment.')
    return
  endif
  call s:NewDraft(session, {'kind': 'file_comment', 'path': file.path, 'old_path': file.old_path})
endfunction

function! revue#session#FileThreads() abort
  let session = s:Get()
  if empty(session) | return | endif
  let index = s:SelectedFile(session)
  if index < 0 | call s:Notice('Select a file to read its discussions.') | return | endif
  let origin = s:Origin()
  if session.index != index | call s:Select(session, index) | endif
  call revue#session#Threads()
  let b:revue_origin = origin
  call cursor(4, 1)
  call revue#session#MessageFocus()
endfunction

function! revue#session#Suggest(visual, ...) abort
  let start = a:0 ? a:1 : a:visual ? min([line("'<"), line("'>")]) : line('.')
  let end = a:0 ? a:2 : a:visual ? max([line("'<"), line("'>")]) : line('.')
  call revue#session#Comment(a:visual, start, end, 1)
endfunction

function! revue#session#ApplySuggestion() abort
  let session = s:Get()
  if empty(session) | return | endif
  let selected = deepcopy(revue#discussion#Selected(session, line('.')))
  if empty(selected) | call s:Notice('Select the message containing the suggestion.') | return | endif
  for draft in session.drafts
    if draft.kind ==# 'apply_suggestion' && draft.message ==# selected.comment && draft.thread ==# selected.thread
      call s:Composer(session, draft.id)
      return
    endif
  endfor
  let target = {'thread': selected.thread, 'message': selected.comment, 'message_kind': selected.kind, 'expected_version': get(selected.message, 'version', '')}
  let error = revue#apply_suggestion#Error(session.snapshot, target)
  if !empty(error) | call s:Notice(error) | return | endif
  if session.snapshot.snapshot !=# session.latest_comparison | call s:Notice('Open the latest comparison before applying a suggestion.') | return | endif
  let session.application_read = get(session, 'application_read', 0) + 1
  let serial = session.application_read
  let origin = {'window': win_getid(), 'selected': selected, 'reference': revue#comparisons#Reference(session.snapshot), 'target': target}
  call s:Notice('Checking the suggestion against the saved workspace file…')
  try
    call session.Host({'op': 'suggestion_plan', 'reference': origin.reference, 'target': target}, function('s:SuggestionPlanned', [session.id, serial, origin]))
  catch
    call s:Notice('Suggestion preview failed: ' . v:exception)
  endtry
endfunction

function! s:SuggestionPlanned(id, serial, origin, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || get(session, 'application_read', 0) != a:serial | return | endif
  if !s:SameMessage(session, a:origin.selected, a:origin.window) || revue#comparisons#Reference(session.snapshot) !=# a:origin.reference
    call s:Notice('Suggestion selection changed; request its preview again.')
    return
  endif
  if !get(a:result, 'ok', 0) | call s:Notice(get(a:result, 'error', 'Suggestion preview unavailable.')) | return | endif
  let plan = get(a:result, 'data', {})
  if type(plan) != v:t_dict || has_key(plan, 'id') || has_key(plan, 'state') | call s:Notice('Invalid application preview envelope.') | return | endif
  let error = revue#apply_suggestion#Validate(session.snapshot, a:origin.target, plan)
  if empty(error) | let error = revue#apply_suggestion#Unsaved(plan) | endif
  if !empty(error) | call s:Notice(error) | return | endif
  call s:NewDraft(session, plan)
endfunction

function! revue#session#Commentable(patch, side) abort
  let result = {}
  let old = 0
  let new = 0
  let active = 0
  for text in split(a:patch, "\n", 1)
    let hunk = matchlist(text, '^@@ -\(\d\+\)\%(,\d\+\)\? +\(\d\+\)\%(,\d\+\)\? @@')
    if !empty(hunk)
      let old = str2nr(hunk[1])
      let new = str2nr(hunk[2])
      let active = 1
    elseif active
      let prefix = strpart(text, 0, 1)
      if prefix ==# ' ' || prefix ==# '-'
        if a:side ==# 'base' | let result[string(old)] = 1 | endif
        let old += 1
      endif
      if prefix ==# ' ' || prefix ==# '+'
        if a:side ==# 'head' | let result[string(new)] = 1 | endif
        let new += 1
      endif
    endif
  endfor
  return result
endfunction

function! revue#session#NewConversation() abort
  let session = s:Get()
  if !empty(session) && get(b:, 'revue_view', '') ==# 'conversation'
    call s:NewDraft(session, {'kind': 'conversation'})
  endif
endfunction

function! revue#session#Review() abort
  let session = s:Get()
  if empty(session) | return | endif
  let actions = get(session.snapshot, 'review_actions', [])
  if empty(actions) | call s:Notice('This provider does not offer review decisions. Use the conversation or inline comments.') | return | endif
  let choices = ['Review decision:']
  for index in range(len(actions))
    let rule = revue#capabilities#Rule(session.snapshot, {'kind': 'review', 'event': actions[index].id})
    call add(choices, (index + 1) . '. ' . actions[index].label . (rule.enabled ? '' : ' [unavailable: ' . rule.reason . ']'))
  endfor
  let choice = inputlist(choices)
  if choice < 1 || choice > len(actions) | return | endif
  call s:NewDraft(session, {'kind': 'review', 'event': actions[choice - 1].id})
endfunction

function! s:PendingBusy(session, except, review) abort
  for draft in a:session.drafts
    if draft.id ==# a:except | continue | endif
    if get(draft, 'delivery', '') ==# 'private' || get(draft, 'pending_mode', '') ==# 'create' || (!empty(a:review) && get(draft, 'pending_review', '') ==# a:review && index(['submit_pending', 'discard_pending', 'delete_pending_comment'], draft.kind) >= 0)
      call s:Composer(a:session, draft.id)
      call s:Notice('Inspect the existing pending-review operation before preparing another private save.')
      return 1
    endif
  endfor
  return 0
endfunction

function! revue#session#StartPending() abort
  let session = s:Get()
  if empty(session) | return | endif
  if s:PendingBusy(session, '', '') | return | endif
  let inventory = get(session.snapshot, 'pending_reviews', {})
  if !empty(get(inventory, 'items', []))
    call revue#session#Pending()
    call s:Notice('A pending review already exists. Select it to continue.')
    return
  endif
  call s:NewDraft(session, {'kind': 'start_pending', 'pending_mode': 'create', 'pending_review': '', 'actor': get(inventory, 'actor', '')})
endfunction

function! revue#session#SavePending() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_role', '') !=# 'draft' | return | endif
  let draft = s:Draft(session, get(b:, 'revue_draft', ''))
  if empty(draft) || index(['comment', 'file_comment', 'reply'], draft.kind) < 0 | call s:Notice('Open an inline, suggestion, whole-file or reply draft to save privately.') | return | endif
  if index(['draft', 'failed'], draft.state) < 0 | call s:Notice('Check the receipt before changing an uncertain private save.') | return | endif
  call revue#session#SaveDraft()
  if get(b:, 'revue_save_error', 0) | return | endif
  let inventory = get(session.comparisons[session.latest_comparison].snapshot, 'pending_reviews', {})
  let items = get(inventory, 'items', [])
  if len(items) > 1 | call s:Notice('More than one native pending review is available. Inspect :ReviewPending before saving.') | return | endif
  let review = empty(items) ? {} : items[0]
  if s:PendingBusy(session, draft.id, get(review, 'id', '')) | return | endif
  let proposed = extend(deepcopy(draft), {'pending_mode': empty(review) ? 'create' : 'add',
        \ 'pending_review': get(review, 'id', ''), 'pending_head': get(review, 'head', ''), 'actor': get(inventory, 'actor', '')})
  let error = s:SubmissionError(session, proposed)
  if !empty(error) | call s:Notice(error) | return | endif
  let before = deepcopy(draft)
  call extend(draft, proposed)
  let draft.state = 'draft'
  if !s:Save(session) | call filter(draft, {key, _ -> has_key(before, key)}) | call extend(draft, before) | return | endif
  call s:DraftContext(session, draft, bufnr())
  call revue#session#Preview()
endfunction

function! revue#session#Pending() abort
  let session = s:Get()
  if empty(session) | return | endif
  let origin = s:Origin()
  let view = revue#pending#View(session.snapshot)
  let verification = get(session, 'pending_verification', {})
  if get(verification, 'loading', 0) | call add(view.lines, 'Verifying complete review… :ReviewCancelVerifyPending') | endif
  if !empty(get(verification, 'error', '')) | call add(view.lines, 'Verification unavailable: ' . revue#message#OneLine(verification.error)) | endif
  call s:Fill(s:Panel(session, 'pending'), view.lines)
  let rows = map(copy(view.lines), {index, text -> {'text': text, 'type': get(view.styles, string(index + 1), empty(text) ? 'RevueCardBorder' : 'RevueCardBody')}})
  call revue#surface#Paint(session.panel, rows, 0)
  if origin.kind !=# 'pending' | let b:revue_origin = origin | endif
  let session.pendingrows = view.rows
endfunction

function! revue#session#VerifyPending() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'pending' | return | endif
  let state = get(session, 'pending_verification', {})
  if get(state, 'loading', 0) | return | endif
  let row = get(session.pendingrows, string(line('.')), {})
  let review = revue#pending#Find(session.snapshot, get(row, 'review', ''))
  if empty(review) | call s:Notice('Select a private review first.') | return | endif
  if get(review, 'complete', 1) | call s:Notice('The complete private review is already loaded.') | return | endif
  if !get(get(get(session.snapshot, 'capabilities', {}), 'verify_pending', {}), 'enabled', 0)
    call s:Notice('This backend cannot verify the complete private review.') | return
  endif
  let target = {'review': review.id, 'actor': review.actor, 'read_version': review.read_version}
  let serial = get(state, 'serial', 0) + 1
  let session.pending_verification = {'serial': serial, 'loading': 1, 'error': '', 'target': target}
  call s:RepaintPanel(session)
  call session.Host({'op': 'verify_pending', 'target': target, 'reference': revue#comparisons#Reference(session.snapshot)},
        \ function('s:PendingVerified', [session.id, serial, session.generation, get(session, 'latest_request', 0), session.snapshot.snapshot]))
endfunction

function! revue#session#CancelVerifyPending() abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'pending_verification') | return | endif
  let session.pending_verification.serial += 1
  let session.pending_verification.loading = 0
  let session.pending_verification.error = 'Read cancelled. Loaded private feedback is retained.'
  call s:RepaintPanel(session)
endfunction

function! s:PendingVerified(id, serial, generation, epoch, comparison, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || get(get(session, 'pending_verification', {}), 'serial', -1) != a:serial | return | endif
  let state = session.pending_verification
  let state.loading = 0
  try
    if session.generation != a:generation || get(session, 'latest_request', 0) != a:epoch || session.snapshot.snapshot !=# a:comparison
      throw 'The comparison or refresh changed. Verify the current private review again.'
    endif
    if !get(a:result, 'ok', 0) | throw get(a:result, 'error', 'Private review verification failed.') | endif
    let data = get(a:result, 'data', {})
    let review = get(data, 'review', {})
    let old = revue#pending#Find(session.snapshot, state.target.review)
    if get(data, 'target', {}) !=# state.target || get(data, 'snapshot', '') !=# a:comparison || empty(old) || get(old, 'read_version', '') !=# state.target.read_version
      throw 'Private review verification no longer matches this selection.'
    endif
    for [key, expected] in items({'id': old.id, 'actor': old.actor, 'head': old.head, 'body': old.body, 'read_version': old.read_version, 'total': old.total})
      if get(review, key, v:null) !=# expected | throw 'Verified private review identity or coverage changed.' | endif
    endfor
    if get(review, 'complete', 0) isnot v:true || type(get(review, 'version', 0)) != v:t_string || empty(review.version) || type(get(review, 'comments', 0)) != v:t_list || len(review.comments) != old.total
      throw 'The complete private review was not verified.'
    endif
    if !get(get(get(session.snapshot, 'capabilities', {}), 'verify_pending', {}), 'enabled', 0) | throw 'Private verification capability changed.' | endif
    call revue#pending#ValidateComplete(review)
    let seen = {}
    for comment in review.comments
      if type(comment) != v:t_dict || type(get(comment, 'message', 0)) != v:t_string || empty(comment.message) || has_key(seen, comment.message) || type(get(comment, 'body', 0)) != v:t_string
        throw 'Invalid complete private comment inventory.'
      endif
      let seen[comment.message] = comment
    endfor
    for comment in old.comments
      if !has_key(seen, comment.message) || seen[comment.message].body !=# comment.body | throw 'Previously loaded private comments changed during verification.' | endif
    endfor
    call extend(old, deepcopy(review))
    let session.comparisons[session.snapshot.snapshot].snapshot = deepcopy(session.snapshot)
    let state.error = ''
    let session.message = 'Complete private review verified. Publication and discard remain separate actions.'
  catch
    let state.error = v:exception
  endtry
  call s:RepaintPanel(session)
  call s:RenderTree(session)
endfunction

function! revue#session#OpenPending() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'pending' | return | endif
  let row = get(session.pendingrows, string(line('.')), {})
  let target = get(row, 'target', {})
  if empty(target) | call s:Notice('Select a pending comment to open it; :ReviewPublishPending prepares the review.') | return | endif
  if empty(revue#edit#Message(session.snapshot, target)) | call s:Notice('This comment is not available in the current discussion view. Its pending-review text is retained here.') | return | endif
  let origin = s:Origin()
  call revue#session#Threads(target.thread)
  let b:revue_origin = origin
  for entry in values(session.messagemap)
    if entry.comment ==# target.message && entry.thread ==# target.thread && entry.kind ==# target.message_kind
      call cursor(entry.start, 1)
      call revue#session#MessageFocus()
      return
    endif
  endfor
endfunction

function! revue#session#EditPending() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'pending' | return | endif
  let row = get(session.pendingrows, string(line('.')), {})
  if empty(row) | call s:Notice('Select a pending review summary or comment to edit.') | return | endif
  let review = revue#pending#Find(session.snapshot, row.review)
  if empty(review) | call s:Notice('Refresh to load the pending review.') | return | endif
  let target = has_key(row, 'target') ? deepcopy(row.target) : {'message': review.id, 'message_kind': 'PENDING', 'thread': ''}
  let target.pending_review = review.id
  let message = revue#edit#Message(session.snapshot, target)
  if empty(message) | call s:Notice('The selected private message is unavailable; refresh first.') | return | endif
  call s:EditTarget(session, {'message': target.message, 'message_kind': target.message_kind, 'thread': target.thread}, message)
endfunction

function! s:DeleteTarget(session) abort
  if get(b:, 'revue_view', '') ==# 'pending'
    return deepcopy(get(get(a:session.pendingrows, string(line('.')), {}), 'target', {}))
  endif
  let selected = revue#discussion#Selected(a:session, line('.'))
  return empty(selected) ? {} : {'message': selected.comment, 'message_kind': selected.kind, 'thread': selected.thread}
endfunction

function! revue#session#Assignments(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  if !get(get(get(session.snapshot, 'capabilities', {}), 'assignments', {}), 'enabled', 0)
    call s:Notice('This backend does not provide assignment outcomes.') | return
  endif
  call revue#assignment#Init(session)
  let origin = s:Origin()
  let session.assignments.detail = a:0 ? a:1 : ''
  call revue#session#AssignmentView()
  if origin.kind !=# get(b:, 'revue_view', '') | let b:revue_origin = origin | endif
  if !session.assignments.requested | call revue#session#ReloadAssignments() | endif
endfunction

function! revue#session#AssignmentView() abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'assignments') | return | endif
  let view = revue#assignment#View(session, session.assignments.detail)
  let panel = s:Panel(session, empty(session.assignments.detail) ? 'assignments' : 'assignment')
  call s:Fill(panel, view.lines)
  let session.assignment_view_rows = view.rows
  call revue#surface#Paint(panel, view.decorations, 0)
  call revue#layout#SetBar(win_getid(), ' Assignment outcomes | :ReviewReviewActions · :ReviewClose ')
endfunction

function! revue#session#ReloadAssignments() abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'assignments') | return | endif
  let state = session.assignments
  let state.serial += 1
  let state.requested = 1
  let state.loading = 0
  if !get(get(get(session.snapshot, 'capabilities', {}), 'assignments', {}), 'enabled', 0)
    let state.error = 'Assignment reads are unavailable.'
    call s:RepaintPanel(session) | return
  endif
  let state.error = ''
  let state.loading = 1
  if index(['assignments', 'assignment'], get(session, 'panelkind', '')) >= 0 | call s:RepaintPanel(session) | endif
  call session.Host({'op': 'assignments'}, function('s:AssignmentsLoaded', [session.id, state.serial, session.generation]))
endfunction

function! s:AssignmentsLoaded(id, serial, generation, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:serial != get(get(session, 'assignments', {}), 'serial', -1) | return | endif
  let state = session.assignments
  let state.loading = 0
  if a:generation != session.generation
    let state.error = 'Review context changed; reload assignments. Loaded results retained.'
  elseif !get(get(get(session.snapshot, 'capabilities', {}), 'assignments', {}), 'enabled', 0)
    let state.error = 'Assignment reads are no longer available.'
  else
    let state.error = get(a:result, 'ok', 0) ? revue#assignment#Apply(session, get(a:result, 'data', {})) : get(a:result, 'error', 'Assignment read failed; loaded results retained.')
  endif
  if index(['assignments', 'assignment'], get(session, 'panelkind', '')) >= 0 | call s:RepaintPanel(session) | endif
endfunction

function! revue#session#CancelAssignmentsRead() abort
  let session = s:Get()
  if empty(session) || !has_key(session, 'assignments') | return | endif
  let session.assignments.serial += 1
  let session.assignments.loading = 0
  let session.assignments.error = 'Read cancelled; loaded assignments retained. Reload to retry.'
  if index(['assignments', 'assignment'], get(session, 'panelkind', '')) >= 0 | call s:RepaintPanel(session) | endif
endfunction

function! s:AssignmentItem(session) abort
  if index(['assignments', 'assignment'], get(b:, 'revue_view', '')) < 0 | return {} | endif
  let id = get(b:, 'revue_view', '') ==# 'assignment' ? a:session.assignments.detail : get(get(a:session.assignment_view_rows, string(line('.')), {}), 'assignment', '')
  return revue#assignment#Find(a:session, id)
endfunction

function! revue#session#OpenAssignment() abort
  let session = s:Get()
  if empty(session) | return | endif
  let item = s:AssignmentItem(session)
  if empty(item) | call s:Notice('Select an assignment.') | return | endif
  call revue#session#Assignments(item.id)
  call cursor(1, 1)
endfunction

function! revue#session#AssignmentDetails() abort
  let session = s:Get()
  if empty(session) | return | endif
  let item = s:AssignmentItem(session)
  if empty(item) | call s:Notice('Select an assignment first.') | return | endif
  let lines = revue#assignment#Details(deepcopy(item), deepcopy(s:AssignmentTarget(session)))
  let panel = s:Panel(session, 'preview')
  call s:Fill(panel, lines)
  call revue#surface#Paint(panel, map(copy(lines), {_, text -> {'text': text, 'type': text =~# '^#' ? 'RevueCardHeader' : 'RevueCardBody'}}), 0)
  call revue#layout#SetBar(win_getid(), ' Assignment details | :ReviewClose returns to outcomes ')
  call cursor(1, 1)
endfunction

function! s:AssignmentTarget(session) abort
  if get(b:, 'revue_view', '') !=# 'assignment' | return {} | endif
  let item = s:AssignmentItem(a:session)
  let row = get(get(a:session, 'assignment_view_rows', {}), string(line('.')), {})
  return get(filter(copy(get(item, 'targets', [])), {_, t -> t.message ==# get(row, 'message', '')}), 0, {})
endfunction

function! revue#session#AssignmentDiscussion(reply) abort
  let session = s:Get()
  if empty(session) | return | endif
  let item = s:AssignmentItem(session)
  let selected = s:AssignmentTarget(session)
  if empty(selected) | call s:Notice('Select a comment outcome first.') | return | endif
  let target = {'kind': 'thread', 'thread': selected.thread, 'message': selected.message, 'message_kind': selected.message_kind}
  if a:reply
    let thread = get(filter(copy(session.snapshot.threads), {_, t -> t.id ==# selected.thread}), 0, {})
    let replies = filter(reverse(copy(get(thread, 'comments', []))), {_, m -> get(m, 'assignment', '') ==# item.id && get(m, 'in_reply_to', '') ==# selected.message})
    if empty(replies) | call s:Notice('No matching participant reply is loaded. Refresh review feedback to check for replies.') | return | endif
    let target.message = replies[0].id
    let target.message_kind = get(replies[0], 'kind', 'comment')
  endif
  let error = s:EventDiscussionError(session, {'target': target})
  if !empty(error) | call s:Notice('Assigned message is not in loaded feedback. Refresh or load more feedback; the retained original text remains here.') | return | endif
  call s:OpenDiscussionTarget(session, target, s:Origin())
endfunction

function! revue#session#AssignmentComparison(result) abort
  let session = s:Get()
  if empty(session) | return | endif
  let item = s:AssignmentItem(session)
  if empty(item) | call s:Notice('Select an assignment first.') | return | endif
  let target = s:AssignmentTarget(session)
  let reference = a:result ? get(get(item.outcomes, get(target, 'message', ''), {}), 'result_reference', {}) : item.reference
  let error = s:EventComparisonError(session, {'reviewed_comparison': reference})
  if !empty(error) | call s:Notice(empty(reference) ? 'This outcome has no verified result comparison.' : error) | return | endif
  let origin = s:Origin()
  call revue#comparisons#AddReference(session, reference)
  call revue#session#OpenComparison(reference.snapshot, {'assignment_origin': origin,
        \ 'assignment_id': item.id, 'assignment_version': item.version, 'assignment_serial': session.assignments.serial})
endfunction

function! revue#session#RunParticipant(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let item = s:AssignmentItem(session)
  if empty(item) | call s:Notice('Select an assignment first.') | return | endif
  for draft in session.drafts
    if draft.kind ==# 'participant_run' && draft.assignment ==# item.id
      call s:Composer(session, draft.id) | return
    endif
  endfor
  let latest = session.comparisons[session.latest_comparison].snapshot
  let fields = revue#runtime#Fields(latest, item, a:0 && a:1)
  let error = revue#runtime#CurrentError(latest, item, fields)
  if !empty(error) | call s:Notice(error) | return | endif
  if !empty(s:NewDraft(session, fields)) | call revue#session#Preview() | endif
endfunction

function! revue#session#CancelAssignment() abort
  let session = s:Get()
  if empty(session) | return | endif
  let item = s:AssignmentItem(session)
  if empty(item) | call s:Notice('Select an assignment first.') | return | endif
  for draft in session.drafts
    if draft.kind ==# 'cancel_assignment' && draft.assignment ==# item.id
      call s:Composer(session, draft.id) | return
    endif
  endfor
  if item.cancelled | call s:Notice('This assignment is already cancelled; existing discussion is retained.') | return | endif
  if !empty(s:NewDraft(session, {'kind': 'cancel_assignment', 'assignment': item.id,
        \ 'expected_version': item.version, 'participant': deepcopy(item.participant), 'count': len(item.targets), 'body': ''}))
    call revue#session#Preview()
  endif
endfunction

function! revue#session#Assign() abort
  let session = s:Get()
  if empty(session) | return | endif
  if !get(get(get(session.snapshot, 'capabilities', {}), 'assignment', {}), 'enabled', 0)
    call s:Notice('This backend does not support comment assignments.') | return
  endif
  if session.snapshot.snapshot !=# session.latest_comparison
    call s:Notice('Open the latest comparison before assigning feedback.') | return
  endif
  let candidates = revue#assignment#Candidates(session.snapshot)
  if empty(candidates) | call s:Notice('No saved line/file messages are loaded. General conversation and local drafts cannot be assigned.') | return | endif
  let selected = revue#discussion#Selected(session, line('.'))
  let selection = {}
  if get(b:, 'revue_view', '') ==# 'threads' && !empty(selected)
    for item in candidates
      if item.target.message ==# selected.comment && item.target.thread ==# selected.thread && item.target.message_kind ==# selected.kind
        let selection[revue#assignment#Key(item.target)] = 1
      endif
    endfor
  endif
  let origin = s:Origin()
  let session.assignment_selection = {'items': candidates, 'selected': selection,
        \ 'reference': revue#assignment#Reference(session.snapshot)}
  call revue#session#AssignmentSelection()
  let b:revue_origin = origin
  call cursor(7, 1)
endfunction

function! revue#session#AssignmentSelection() abort
  let session = s:Get()
  if empty(session) || empty(get(session, 'assignment_selection', {})) | return | endif
  let selection = session.assignment_selection
  let panel = s:Panel(session, 'assignment-selection')
  let session.assignmentrows = {}
  let lines = ['# Assign feedback', printf('%d selected / %d loaded messages · maximum 50', len(selection.selected), len(selection.items)),
        \ 'Saved line/file discussions only. Selection is local until saved.',
        \ 'Uses feedback loaded when opened; re-open to choose newer messages.',
        \ 'Choose messages, then :ReviewPrepareAssignment to choose a participant.', '']
  for item in selection.items
    let first = len(lines) + 1
    call extend(lines, [(has_key(selection.selected, revue#assignment#Key(item.target)) ? '[x] ' : '[ ] ') . item.path . ' · ' . item.anchor,
          \ '    ' . item.author . ' · ' . strcharpart(revue#message#OneLine(item.body), 0, 140), ''])
    for row in range(first, len(lines) - 1) | let session.assignmentrows[string(row)] = item | endfor
  endfor
  call s:Fill(panel, lines)
  let surfaces = []
  for index in range(len(lines))
    call add(surfaces, {'text': lines[index], 'type': lines[index] =~# '^\%(#\|\[[ x]\]\)' ? 'RevueCardHeader' : 'RevueCardBody'})
  endfor
  call revue#surface#Paint(panel, surfaces, 0)
  call revue#layout#SetBar(win_getid(), ' Assign feedback | :ReviewReviewActions · :ReviewClose ')
endfunction

function! revue#session#ToggleAssignment() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'assignment-selection' | return | endif
  let item = get(session.assignmentrows, string(line('.')), {})
  if empty(item) | call s:Notice('Select a message row.') | return | endif
  let selected = session.assignment_selection.selected
  let key = revue#assignment#Key(item.target)
  if has_key(selected, key)
    call remove(selected, key)
  elseif len(selected) < min([50, get(get(session.snapshot.capabilities, 'assignment', {}), 'max_targets', 50)])
    let selected[key] = 1
  else
    call s:Notice('Assignment selection is full; remove a message first.') | return
  endif
  let view = winsaveview()
  call revue#session#AssignmentSelection()
  call winrestview(view)
endfunction

function! revue#session#PrepareAssignment() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'assignment-selection' | return | endif
  let state = deepcopy(session.assignment_selection)
  let items = filter(copy(state.items), {_, item -> has_key(state.selected, revue#assignment#Key(item.target))})
  if empty(items) | call s:Notice('Select at least one message.') | return | endif
  let participants = revue#assignment#Participants()
  if empty(participants) | call s:Notice('Configure g:revue_participants with stable id and label entries. Assignment does not start an agent.') | return | endif
  let window = win_getid()
  let buffer = bufnr()
  let menu = ['Choose a participant (0 cancels; no process starts):']
  for index in range(len(participants)) | call add(menu, printf('%d. %s · %s', index + 1, participants[index].label, participants[index].id)) | endfor
  let choice = inputlist(menu)
  if choice <= 0 || choice > len(participants) | return | endif
  if win_getid() != window || bufnr() != buffer || get(b:, 'revue_view', '') !=# 'assignment-selection' || state !=# session.assignment_selection
    call s:Notice('Selection changed while choosing a participant; inspect it again.') | return
  endif
  let fields = {'kind': 'assignment', 'body': '', 'reference': state.reference,
        \ 'participant': participants[choice - 1], 'targets': map(copy(items), {_, item -> item.target}), 'selection': items}
  let error = revue#assignment#Error(session.comparisons[session.latest_comparison].snapshot, fields)
  if !empty(error) | call s:Notice(error) | return | endif
  if !empty(s:NewDraft(session, fields)) | call revue#session#Preview() | endif
endfunction

function! revue#session#DeleteMessage() abort
  let session = s:Get()
  if empty(session) | return | endif
  let target = s:DeleteTarget(session)
  if empty(target) | call s:Notice('Select a published message first.') | return | endif
  for draft in session.drafts
    if get(draft, 'message', '') ==# target.message && get(draft, 'message_kind', '') ==# target.message_kind && get(draft, 'thread', '') ==# target.thread
      call s:Composer(session, draft.id)
      call s:Notice('Finish or cancel the existing operation for this message first.')
      return
    endif
  endfor
  if !empty(s:NewDraft(session, revue#delete_message#Fields(session.snapshot, target))) | call revue#session#Preview() | endif
endfunction

function! revue#session#DeletePendingComment() abort
  let session = s:Get()
  if empty(session) | return | endif
  let target = s:DeleteTarget(session)
  if empty(target) | call s:Notice('Select an individual private comment first.') | return | endif
  let fields = revue#delete#Fields(session.snapshot, target)
  if s:PendingBusy(session, '', fields.pending_review) | return | endif
  for draft in session.drafts
    if get(draft, 'pending_review', '') ==# fields.pending_review && !empty(fields.pending_review)
      call s:Composer(session, draft.id)
      call s:Notice('Finish or cancel the existing private operation before deleting a comment.')
      return
    endif
  endfor
  if !empty(s:NewDraft(session, fields)) | call revue#session#Preview() | endif
endfunction

function! revue#session#DiscardPending() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'pending' | return | endif
  let row = get(session.pendingrows, string(line('.')), {})
  if empty(row) | call s:Notice('Select a pending review to prepare discard.') | return | endif
  if s:PendingBusy(session, '', row.review) | return | endif
  for draft in session.drafts
    if get(draft, 'pending_review', '') ==# row.review
      call s:Composer(session, draft.id)
      call s:Notice('The existing pending-review operation is retained. Inspect it before preparing another action.')
      return
    endif
  endfor
  let review = revue#pending#Find(session.snapshot, row.review)
  if empty(review) | call s:Notice('Refresh to load the pending review.') | return | endif
  if !empty(s:NewDraft(session, {'kind': 'discard_pending', 'pending_review': review.id, 'actor': review.actor,
        \ 'expected_version': review.version, 'pending_head': review.head, 'pending_comments': deepcopy(review.comments),
        \ 'pending_body': review.body, 'body': ''}))
    call revue#session#Preview()
  endif
endfunction

function! revue#session#PublishPending(event) abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'pending' | return | endif
  let row = get(session.pendingrows, string(line('.')), {})
  if empty(row) | call s:Notice('Select a pending review to prepare publication.') | return | endif
  if s:PendingBusy(session, '', row.review) | return | endif
  for draft in session.drafts
    if get(draft, 'pending_review', '') ==# row.review
      call s:Composer(session, draft.id)
      call s:Notice('The existing pending-review operation is retained. Inspect it before preparing another action.')
      return
    endif
  endfor
  let review = deepcopy(revue#pending#Find(session.snapshot, row.review))
  if empty(review) | call s:Notice('Refresh to load the pending review.') | return | endif
  let error = revue#pending#CompleteError(review)
  if !empty(error) | call s:Notice(error) | return | endif
  let window = win_getid()
  let event = a:event
  if empty(event)
    let actions = get(session.snapshot, 'review_actions', [])
    let menu = ['Publish pending review #' . review.id . ':']
    for index in range(len(actions)) | call add(menu, (index + 1) . '. ' . actions[index].label) | endfor
    let choice = inputlist(menu) - 1
    if choice < 0 || choice >= len(actions) | return | endif
    let event = actions[choice].id
  endif
  if win_getid() != window || get(b:, 'revue_view', '') !=# 'pending' || get(get(session.pendingrows, string(line('.')), {}), 'review', '') !=# review.id
    call s:Notice('Pending review selection changed; choose the decision again.')
    return
  endif
  call s:NewDraft(session, {'kind': 'submit_pending', 'pending_review': review.id, 'actor': review.actor,
        \ 'expected_version': review.version, 'pending_head': review.head, 'pending_comments': deepcopy(review.comments),
        \ 'event': event, 'body': review.body})
endfunction

function! revue#session#PendingBase() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_role', '') !=# 'draft' | return | endif
  let draft = s:Draft(session, get(b:, 'revue_draft', ''))
  if empty(draft) || draft.kind !=# 'submit_pending' | call s:Notice('Open a pending-review publication draft first.') | return | endif
  if index(['draft', 'failed'], draft.state) < 0 | call s:Notice('An uncertain publication can only check its receipt.') | return | endif
  call revue#session#SaveDraft()
  if get(b:, 'revue_save_error', 0) | return | endif
  let latest = session.comparisons[session.latest_comparison].snapshot
  let review = revue#pending#Find(latest, draft.pending_review)
  if empty(review) | call s:Notice('Refresh to load the pending review.') | return | endif
  let proposed = extend(deepcopy(draft), {'expected_version': review.version, 'pending_comments': deepcopy(review.comments),
        \ 'pending_head': review.head, 'head': latest.head, 'base_tip': get(latest, 'base_tip', latest.base), 'snapshot': latest.snapshot})
  let error = revue#capabilities#Error(latest, proposed, 0)
  if !empty(error) | call s:Notice(error) | return | endif
  let editor = bufnr()
  if confirm('Accept refreshed pending-review contents and comparison? Inspect :ReviewPreview first. Your summary is retained.', "&Accept\n&Keep original base", 2) != 1 | return | endif
  if bufnr() != editor || get(b:, 'revue_draft', '') !=# draft.id || index(['draft', 'failed'], draft.state) < 0 | return | endif
  let latest = session.comparisons[session.latest_comparison].snapshot
  if !empty(revue#capabilities#Error(latest, proposed, 0)) | call s:Notice('The pending review changed again; inspect the preview.') | return | endif
  let before = deepcopy(draft)
  for key in ['expected_version', 'pending_comments', 'pending_head', 'head', 'base_tip', 'snapshot'] | let draft[key] = proposed[key] | endfor
  let draft.state = 'draft'
  if !s:Save(session) | call extend(draft, before) | return | endif
  call s:DraftContext(session, draft, bufnr())
  call s:Notice('Refreshed pending contents accepted. Your summary is retained; preview before publishing.')
endfunction

function! revue#session#Reply(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  let id = get(b:, 'revue_view', '') ==# 'threads' ? get(session.threadmap, string(line('.')), '') : ''
  if index(['base', 'head'], get(b:, 'revue_role', '')) >= 0
    if session.index < 0 | return | endif
    let matches = s:ThreadsAtCursor(session)
    if len(matches) == 1
      let id = matches[0].id
    elseif len(matches) > 1
      call revue#session#Threads()
      call s:Notice('Choose a thread, then press r to reply.')
      return
    else
      let id = ''
    endif
  endif
  if empty(id) | call s:Notice('Place the cursor on a code thread to reply.') | return | endif
  let selected = get(b:, 'revue_view', '') ==# 'threads' ? revue#discussion#Selected(session, line('.')) : {}
  let private = (a:0 && a:1) || revue#pending#PrivateThread(session.snapshot, id) || get(get(selected, 'message', {}), 'publication', '') ==# 'pending'
  for draft in session.drafts
    if draft.kind ==# 'reply' && draft.thread ==# id && (private || !empty(get(draft, 'pending_mode', '')))
      call s:Composer(session, draft.id)
      call s:Notice('Your existing reply is retained. Inspect its delivery mode before saving.')
      return
    endif
  endfor
  let fields = private ? revue#pending#ReplyFields(session.snapshot, id) : {'kind': 'reply', 'thread': id}
  if has_key(fields, 'error') | call s:Notice(fields.error) | return | endif
  if private && s:PendingBusy(session, '', fields.pending_review) | return | endif
  call s:NewDraft(session, fields)
endfunction

function! s:StateThread(session) abort
  let id = get(b:, 'revue_view', '') ==# 'threads' ? get(a:session.threadmap, string(line('.')), '') : ''
  if index(['base', 'head'], get(b:, 'revue_role', '')) >= 0
    let matches = s:ThreadsAtCursor(a:session)
    if len(matches) > 1
      call revue#session#Threads()
      call s:Notice('Choose a thread, then use :ReviewResolve or :ReviewReopen.')
      return ''
    endif
    let id = empty(matches) ? '' : matches[0].id
  endif
  return id
endfunction

function! revue#session#CheckThreadState() abort
  let session = s:Get()
  if empty(session) | return | endif
  let draft = revue#thread_state#Pending(session, s:StateThread(session))
  if empty(draft) || draft.state !=# 'unknown' | call s:Notice('No uncertain resolution here; :ReviewActivity retains other operations.') | return | endif
  call s:SendThreadState(session, draft)
endfunction

function! revue#session#ChangeThreadState(resolved) abort
  let session = s:Get()
  if empty(session) | return | endif
  let id = s:StateThread(session)
  if empty(id) | call s:Notice('Select a code thread to change its resolution.') | return | endif
  let threads = filter(copy(session.snapshot.threads), {_, t -> t.id ==# id})
  if empty(threads) | call s:Notice('This thread is no longer available.') | return | endif
  let desired = a:resolved ? v:true : v:false
  " Reuse durable intent instead of creating another uncertain operation.
  for draft in session.drafts
    if draft.kind ==# 'thread_state' && draft.thread ==# id
      if draft.state ==# 'unknown'
        call s:Notice('Outcome unknown; :ReviewCheckThreadState checks the original operation before another change.')
        return
      endif
      if draft.resolved != desired
        call s:Notice('A different state change is pending for this thread. Inspect it before acting.')
      else
        call s:SendThreadState(session, draft)
      endif
      return
    endif
  endfor
  let fields = {'kind': 'thread_state', 'thread': id, 'resolved': desired}
  if has_key(threads[0], 'resolved') && threads[0].resolved == desired | call s:Notice('Thread already has the requested state.') | return | endif
  let error = revue#capabilities#Error(session.snapshot, fields, 0)
  if !empty(error) | call s:Notice(error) | return | endif
  let fields.expected_resolved = threads[0].resolved ? v:true : v:false
  let operation = s:NewDraft(session, fields, 1)
  if !empty(operation) | call s:SendThreadState(session, s:Draft(session, operation)) | endif
endfunction

function! s:SendThreadState(session, draft) abort
  if a:draft.state ==# 'submitting' | call s:Notice('Resolution is in progress; wait for its outcome.') | return | endif
  let reconcile = a:draft.state ==# 'unknown'
  if !reconcile
    let error = s:SubmissionError(a:session, a:draft)
    if !empty(error) | call s:Notice(error) | return | endif
  endif
  let previous = a:draft.state
  let a:draft.state = 'submitting'
  if !s:Save(a:session) | let a:draft.state = previous | return | endif
  if !has_key(a:session, 'state_attempts') | let a:session.state_attempts = {} | endif
  let attempt = get(a:session.state_attempts, a:draft.id, 0) + 1
  let a:session.state_attempts[a:draft.id] = attempt
  call s:Annotations(a:session)
  call s:RenderTree(a:session)
  call s:RepaintPanel(a:session)
  try
    call a:session.Host({'op': 'mutate', 'draft': deepcopy(a:draft), 'reconcile': reconcile}, function('s:ThreadStateSent', [a:session.id, a:draft.id, attempt, reconcile]))
  catch
    call s:ThreadStateSent(a:session.id, a:draft.id, attempt, reconcile, {'ok': 0, 'unknown': 1, 'error': 'Resolution request interrupted: ' . v:exception})
  endtry
endfunction

function! s:ThreadStateSent(id, operation, attempt, reconcile, result) abort
  let session = get(s:sessions, a:id, {})
  let draft = empty(session) ? {} : s:Draft(session, a:operation)
  if empty(draft) || draft.state !=# 'submitting' || get(get(session, 'state_attempts', {}), a:operation, 0) != a:attempt | return | endif
  call s:Sent(a:id, a:operation, a:reconcile, a:result)
  call s:Annotations(session)
endfunction

function! revue#session#CheckReceipt() abort
  let session = s:Get()
  if empty(session) | return | endif
  let draft = s:Draft(session, get(b:, 'revue_draft', get(session, 'batchid', '')))
  if empty(draft) || draft.state !=# 'unknown'
    call s:Notice('There is no uncertain submission here to check.')
    return
  endif
  if draft.kind ==# 'batch' | call revue#session#SendBatch()
  else | call revue#session#Send() | endif
endfunction

function! s:NewDraft(session, fields, ...) abort
  let error = revue#capabilities#Error(a:session.snapshot, a:fields, 0)
  if !empty(error) | call s:Notice(error) | return '' | endif
  let draft = extend({'id': s:Id(), 'head': a:session.snapshot.head, 'base_tip': get(a:session.snapshot, 'base_tip', a:session.snapshot.base),
        \ 'snapshot': a:session.snapshot.snapshot, 'body': '', 'state': 'draft'}, a:fields)
  if has_key(a:session.snapshot, 'range') && draft.snapshot ==# a:session.snapshot.snapshot
    let draft.range = deepcopy(a:session.snapshot.range)
  endif
  if has_key(a:session.snapshot, 'context') && draft.snapshot ==# a:session.snapshot.snapshot
    let draft.context = deepcopy(a:session.snapshot.context)
  endif
  call add(a:session.drafts, draft)
  if !s:Save(a:session) && (a:0 || index(['assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) >= 0)
    call remove(a:session.drafts, -1)
    return ''
  endif
  call s:RenderTree(a:session)
  if a:0 | return draft.id | endif
  call s:Composer(a:session, draft.id)
  return draft.id
endfunction

function! s:Draft(session, id) abort
  for draft in a:session.drafts
    if draft.id ==# a:id | return draft | endif
  endfor
  return {}
endfunction

function! s:Composer(session, id) abort
  let draft = s:Draft(a:session, a:id)
  if empty(draft) | return | endif
  if draft.kind ==# 'batch' | call revue#session#Batch(draft.id) | return | endif
  let origin = s:Origin()
  for buf in a:session.buffers
    if getbufvar(buf, 'revue_draft', '') ==# a:id
      if origin.buf != buf | call setbufvar(buf, 'revue_origin', origin) | endif
      if revue#layout#BufferWindow(buf) >= 0
        call win_gotoid(revue#layout#BufferWindow(buf))
        if (revue#layout#Narrow() || origin.focused) && get(a:session, 'focus_win', 0) != win_getid() | call revue#layout#Focus(a:session) | endif
        return
      endif
      call revue#layout#New(a:session, 10)
      execute 'buffer ' . buf
      if revue#layout#Narrow() || origin.focused | call revue#layout#Focus(a:session) | endif
      return
    endif
  endfor
  call revue#layout#New(a:session, 10)
  let buf = s:Buffer(a:session, 'draft')
  setlocal buftype=acwrite modifiable wrap linebreak filetype=markdown
  let b:revue_draft = a:id
  let b:revue_origin = origin
  call s:BufferName(draft.kind)
  if revue#layout#Narrow() || origin.focused | call revue#layout#Focus(a:session) | endif
  let a:session.composer = buf
  call setline(1, split(draft.body, "\n", 1))
  setlocal nomodified
  if index(['thread_state', 'capture', 'reaction', 'discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) >= 0 || index(['submitting', 'unknown'], draft.state) >= 0 | setlocal nomodifiable | endif
  call s:DraftBar(a:session, draft)
  call s:DraftContext(a:session, draft, buf)
  augroup RevueComposer
    autocmd! * <buffer>
    autocmd TextChanged,TextChangedI,BufLeave,BufWriteCmd <buffer> call revue#session#SaveDraft()
    autocmd BufWinEnter,WinEnter,VimResized <buffer> call revue#session#ResizeDraftContext()
  augroup END
  if draft.kind ==# 'apply_suggestion' | call s:Notice('Read-only application preview · :ReviewSend confirms saving the replacement to disk') | return | endif
  if draft.kind ==# 'participant_run' | call s:Notice('Participant operation saved · inspect :ReviewPreview · :ReviewSend confirms execution') | return | endif
  if revue#local_feedback#Enabled(a:session) && revue#local_feedback#IsFeedback(draft)
    call s:Notice('Pending feedback · autosaved as you edit · :ReviewClose returns to the card · :ReviewBatch collects feedback')
    return
  endif
  call s:Notice(draft.kind ==# 'assignment' ? 'Assignment ready · inspect :ReviewPreview · :ReviewSend saves locally' : 'Draft ready · :w saves locally · :ReviewReviewActions')
endfunction

function! revue#session#ResizeDraftContext() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_role', '') !=# 'draft' | return | endif
  let draft = s:Draft(session, get(b:, 'revue_draft', ''))
  if !empty(draft) | call s:DraftContext(session, draft, bufnr()) | endif
endfunction

function! s:DraftSource(session, draft) abort
  let comparison = get(a:session.comparisons, a:draft.snapshot, {})
  let files = filter(copy(get(get(comparison, 'snapshot', {}), 'files', [])), {_, f -> f.path ==# a:draft.path})
  let cache = a:draft.snapshot ==# a:session.snapshot.snapshot ? a:session.cache : get(comparison, 'cache', {})
  return empty(files) ? {} : get(get(cache, files[0].id, {}), a:draft.side, {})
endfunction

function! s:ContextLines(session, draft) abort
  let draft = a:draft
  let original = get(get(a:session.comparisons, draft.snapshot, {}), 'snapshot', a:session.snapshot)
  if draft.kind ==# 'apply_suggestion' | return revue#apply_suggestion#Preview(draft) | endif
  if draft.kind ==# 'participant_run' | return revue#runtime#Preview(draft) | endif
  if draft.kind ==# 'cancel_assignment' | return revue#assignment#CancelPreview(draft) | endif
  if draft.kind ==# 'assignment'
    let error = revue#assignment#Error(a:session.comparisons[a:session.latest_comparison].snapshot, draft)
    return revue#assignment#Preview(draft) + (empty(error) ? [] : ['', 'Unavailable: ' . error])
  endif
  let lines = [s:Label(a:session.snapshot) . ' · ' . get(a:session.snapshot, 'submit_target', a:session.snapshot.key)]
  if has_key(draft, 'reanchored_from')
    let previous = draft.reanchored_from
    call add(lines, 'Moved locally from ' . previous.path . ' · source ' . previous.head . (has_key(previous, 'side') ? ' · ' . previous.side . ':' . previous.start . '-' . previous.end : ' · whole file'))
  endif
  if !empty(get(draft, 'pending_mode', ''))
    call extend(lines, [draft.pending_mode ==# 'create' ? 'Create a private pending review' : 'Add private feedback to pending review #' . draft.pending_review,
          \ 'Actor: ' . draft.actor . ' · will save privately on the backend.',
          \ 'Only this draft is included. :w still saves locally; :ReviewSend saves privately.'])
  endif
  if draft.kind ==# 'delete_message'
    call extend(lines, ['Delete ' . (get(draft, 'message_publication', '') ==# 'local' ? 'local review ' : 'published ') . draft.message_kind . ' #' . draft.message . ' · by ' . draft.message_author,
          \ 'Actor: ' . draft.actor . ' · ' . (empty(draft.thread) ? 'General conversation' : 'Thread ' . draft.thread),
          \ 'Deletes exactly this message. Other messages remain; an empty thread may disappear.',
          \ ':ReviewDiscard cancels this local operation. :ReviewPreview shows the original text.'])
  elseif draft.kind ==# 'delete_pending_comment'
    call extend(lines, ['Delete private comment #' . draft.message . ' · thread ' . draft.thread,
          \ get(draft, 'path', '') . ' · ' . get(draft, 'anchor_label', '') . ' · by ' . get(draft, 'message_author', ''),
          \ 'Pending review #' . draft.pending_review . ' · actor ' . draft.actor,
          \ 'Deletes exactly this message. An empty thread may disappear.',
          \ 'Other comments and the review summary remain. :ReviewDiscard cancels this local operation.'])
  elseif draft.kind ==# 'discard_pending'
    call extend(lines, ['Discard pending review #' . draft.pending_review,
          \ 'Permanently deletes its private summary and all ' . len(draft.pending_comments) . ' comments from the backend.',
          \ 'Local outbox drafts are retained. :ReviewDiscard cancels only this local operation.',
          \ ':ReviewPreview shows every private comment to be removed.'])
  elseif draft.kind ==# 'submit_pending'
    call extend(lines, ['Publish pending review #' . draft.pending_review . ' · ' . draft.event,
          \ len(draft.pending_comments) . ' comments saved privately on the backend will become published.',
          \ 'Reviewed source ' . strpart(draft.pending_head, 0, 12) . ' · current source ' . strpart(a:session.snapshot.head, 0, 12),
          \ 'Local outbox drafts are excluded. :ReviewPreview shows the full publication contents.'])
    if draft.pending_head !=# a:session.snapshot.head | call add(lines, 'This pending review concerns an older source revision.') | endif
  elseif draft.kind ==# 'service_viewed'
    call extend(lines, [(draft.viewed ? 'Mark viewed on service: ' : 'Mark unviewed on service: ') . revue#message#OneLine(draft.path), 'Actor: ' . revue#message#OneLine(draft.actor_label), 'Personal service progress only; local marks and comments remain independent.'])
  elseif draft.kind ==# 'reaction'
    call extend(lines, [(draft.present ? 'Add your ' : 'Remove your ') . revue#message#OneLine(draft.reaction_label) . ' reaction',
          \ draft.message_kind . ' message #' . draft.message, 'Actor: ' . revue#message#OneLine(get(draft, 'actor_label', draft.actor)),
          \ 'Only your reaction changes. Message text, thread resolution and review decisions are unchanged.'])
  elseif draft.kind ==# 'edit'
    if !empty(get(draft, 'pending_review', '')) | call add(lines, 'Save privately in pending review #' . draft.pending_review . ' · actor ' . draft.actor . '. Publication is a separate action.') | endif
    call extend(lines, ['Edit message · ' . draft.message_kind . ' #' . draft.message,
          \ empty(draft.thread) ? (empty(get(draft, 'pending_review', '')) ? 'Review conversation' : 'Private review summary') : 'Thread ' . draft.thread,
          \ 'Replaces this message body only. :ReviewPreview shows original, current and proposed text.'])
  elseif draft.kind ==# 'capture'
    let context = get(original, 'capture_context', {})
    call extend(lines, ['Capture saved workspace files', get(context, 'workspace', 'Backend-managed workspace'),
          \ 'Against fixed base ' . get(context, 'base', original.base),
          \ draft.untracked ? 'Include untracked files.' : 'Exclude untracked files.',
          \ 'Unsaved buffers are excluded. Discussion and old captures are retained.',
          \ 'The new comparison is offered with :ReviewLatest. Capturing does not resolve threads or commit.'])
    if !get(context, 'options_known', 1) | call add(lines, 'Legacy review: untracked files default to excluded; :ReviewCapture! opts in for a new capture.') | endif
  elseif draft.kind ==# 'reply' || draft.kind ==# 'thread_state'
    let threads = filter(copy(original.threads), {_, t -> t.id ==# draft.thread})
    if !empty(threads)
      let thread = threads[0]
      let action = draft.kind ==# 'reply' ? 'Reply' : draft.resolved ? 'Resolve thread' : 'Reopen thread'
      call add(lines, action . ' · ' . thread.path . ' · ' . revue#anchor#Label(thread) . (thread.outdated ? ' [outdated]' : ''))
      if draft.kind ==# 'thread_state'
        call add(lines, 'Thread ' . thread.id . ' · ' . (has_key(thread, 'resolved') ? thread.resolved ? 'Resolved' : 'Unresolved' : 'Resolution unknown'))
        call add(lines, 'Discussion remains expanded. This action changes resolution only.')
      endif
      if !empty(thread.comments)
        let summary = get(split(thread.comments[0].body, '\n\s*\n'), 0, '')
        call add(lines, thread.comments[0].author . ': ' . strcharpart(substitute(summary, '\n', ' ', 'g'), 0, 160))
      endif
    else
      call add(lines, (draft.kind ==# 'reply' ? 'Reply' : 'Thread state') . ' · thread ' . draft.thread)
      call add(lines, 'Thread context is unavailable. The original target is retained.')
    endif
  elseif draft.kind ==# 'file_comment'
    call add(lines, 'File comment · ' . draft.path)
    if get(draft, 'old_path', draft.path) !=# draft.path | call add(lines, 'Renamed from ' . draft.old_path) | endif
    call add(lines, 'Applies to the whole file in this comparison.')
  elseif draft.kind ==# 'comment'
    call add(lines, (get(draft, 'suggestion', 0) ? 'Suggestion' : 'Comment') . ' · ' . draft.path . ' · ' . draft.side . ':' . draft.start . '-' . draft.end)
    let files = filter(copy(original.files), {_, f -> f.path ==# draft.path})
    if !empty(files) && !revue#anchor#InDiff(files[0], draft)
      call add(lines, 'Outside the diff hunks; anchored to this comparison’s original source.')
    endif
    if get(draft, 'suggestion', 0) | call add(lines, 'Edit the fenced replacement; keep explanation outside. This proposes a change only.') | endif
    let content = s:DraftSource(a:session, draft)
    if empty(content) | call add(lines, 'Original source is not loaded; this draft retains its original anchor. :ReviewDraftComparison') | endif
    if get(content, 'kind', '') ==# 'text'
      for row in range(draft.start, min([draft.end, draft.start + 2]))
        if row <= len(content.lines) | call add(lines, printf('%d │ %s', row, content.lines[row - 1])) | endif
      endfor
      if draft.end > draft.start + 2 | call add(lines, '… selected range continues') | endif
    endif
  else
    call add(lines, revue#suggestion#Label(draft) . (has_key(draft, 'event') ? ' · ' . draft.event : ''))
  endif
  call add(lines, 'Comparison ' . strpart(draft.head, 0, 12) . ' · :ReviewPreview · :ReviewClose')
  if draft.snapshot !=# a:session.latest_comparison
    call add(lines, 'Older comparison. Draft and thread identity are retained; :ReviewLatest inspects current code.')
  endif
  let permissions = index(['edit', 'submit_pending', 'discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) >= 0 ? a:session.comparisons[a:session.latest_comparison].snapshot : a:session.snapshot
  let rule = revue#capabilities#Rule(permissions, draft)
  let action_error = revue#capabilities#Error(permissions, draft, 0)
  if empty(action_error)
    let action_error = revue#anchor#Error({'files': original.files, 'capabilities': get(a:session.snapshot, 'capabilities', {})}, draft)
  endif
  if !empty(action_error)
    call add(lines, 'Unavailable: ' . action_error . ' Draft text is retained.')
  elseif !rule.body_required && index(['thread_state', 'capture', 'reaction', 'discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) < 0
    call add(lines, 'Message optional for this action.')
  endif
  return lines
endfunction

function! s:CompactContext(session, draft, ...) abort
  let draft = a:draft
  if draft.kind ==# 'delete_message'
    let lines = [s:Label(a:session.snapshot),
          \ 'Delete ' . (get(draft, 'message_publication', '') ==# 'local' ? 'local review ' : 'published ') . draft.message_kind . ' #' . draft.message . ' · by ' . draft.message_author,
          \ empty(draft.thread) ? 'General conversation' : get(draft, 'path', '') . ' · ' . get(draft, 'anchor_label', '') . ' · thread ' . draft.thread,
          \ 'Only this message. Other messages remain; an empty thread may disappear.']
    if get(draft, 'message_publication', '') ==# 'local' | call add(lines, 'Local audit events and receipts are retained.') | endif
    let error = revue#capabilities#Error(a:session.comparisons[a:session.latest_comparison].snapshot, draft, 0)
    if !empty(error) | call add(lines, 'Unavailable: ' . error) | endif
    return lines
  endif
  if index(['comment', 'reply', 'file_comment', 'review', 'start_pending'], draft.kind) < 0
    return s:ContextLines(a:session, draft)
  endif
  let original = get(get(a:session.comparisons, draft.snapshot, {}), 'snapshot', a:session.snapshot)
  let lines = [s:Label(a:session.snapshot) . ' · Source ' . strpart(draft.head, 0, 12) . (draft.snapshot ==# a:session.latest_comparison ? '' : ' · older comparison')]
  if draft.kind ==# 'comment'
    call add(lines, (get(draft, 'suggestion', 0) ? 'Suggestion' : 'Comment') . ' · ' . draft.path . ' · ' . draft.side . ':' . draft.start . '-' . draft.end)
    let source = s:DraftSource(a:session, draft)
    if !(a:0 && a:1) && get(source, 'kind', '') ==# 'text' && draft.start <= len(source.lines)
      let excerpt = source.lines[draft.start - 1]
      call add(lines, printf('%d │ %s', draft.start, strcharpart(excerpt, 0, 96) . (strchars(excerpt) > 96 ? '…' : '')))
    endif
  elseif draft.kind ==# 'file_comment'
    call add(lines, 'File comment · ' . draft.path)
  elseif draft.kind ==# 'reply'
    let threads = filter(copy(original.threads), {_, t -> t.id ==# draft.thread})
    if empty(threads)
      call add(lines, 'Reply · thread ' . draft.thread . ' · context unavailable')
    else
      let thread = threads[0]
      call add(lines, 'Reply · ' . thread.path . ' · ' . revue#anchor#Label(thread) . (thread.outdated ? ' [outdated]' : ''))
      if !(a:0 && a:1) && !empty(thread.comments)
        let excerpt = revue#message#OneLine(get(split(thread.comments[0].body, '\n\s*\n'), 0, ''))
        call add(lines, thread.comments[0].author . ': ' . strcharpart(excerpt, 0, 72) . (strchars(excerpt) > 72 ? '…' : ''))
      endif
    endif
  elseif draft.kind ==# 'review'
    call add(lines, 'Review decision · ' . draft.event)
  endif
  if !empty(get(draft, 'pending_mode', ''))
    call add(lines, 'Save privately · ' . (draft.pending_mode ==# 'create' ? 'new review' : 'review #' . draft.pending_review) . ' · only this draft')
  else
    call add(lines, substitute(revue#actions#Delivery(draft, a:session.snapshot), ' (confirmation)$', '', ''))
  endif
  " These disclosures remain beside the body; complete context follows preview.
  for text in s:ContextLines(a:session, draft)
    if text =~# '^\%(Unavailable:\|Original source\|Thread context\|Outside the diff\|Renamed from\|Message optional\)'
      call add(lines, text)
    endif
  endfor
  return lines
endfunction

function! s:DraftBar(session, draft) abort
  let state = get(b:, 'revue_save_error', 0) ? 'SAVE FAILED · text retained' : a:draft.state ==# 'unknown' ? 'UNKNOWN · check receipt' : a:draft.state ==# 'failed' ? 'SUBMISSION FAILED · draft saved' : 'Draft saved locally'
  if revue#local_feedback#Enabled(a:session) && revue#local_feedback#IsFeedback(a:draft) && !get(b:, 'revue_save_error', 0) && a:draft.state ==# 'draft'
    let state = 'Pending · saved locally'
  endif
  let action = substitute(revue#actions#Delivery(a:draft, a:session.snapshot), ' (confirmation)$', '', '')
  call revue#layout#SetBar(win_getid(), ' Revue · ' . state . ' | ' . substitute(action, '%', '%%', 'g') . ' %<| :ReviewReviewActions ')
endfunction

function! s:DraftContext(session, draft, buf) abort
  if a:draft.kind ==# 'apply_suggestion'
    let lines = revue#apply_suggestion#Preview(a:draft) + ['', 'Operation: ' . a:draft.state,
          \ a:draft.state ==# 'unknown' ? ':ReviewCheckReceipt checks the original application.' : ':ReviewSend confirms applying this exact replacement.', ':ReviewClose returns to the message.']
    let rows = map(copy(lines), {_, text -> {'text': text, 'type': text =~# '^#' ? 'RevueCardHeader' : text =~# '^- ' ? 'RevueCardDelete' : text =~# '^+ ' ? 'RevueCardAdd' : 'RevueCardBody'}})
    call s:Fill(a:buf, lines)
    call revue#surface#Paint(a:buf, rows, 0)
    return
  endif
  if index(['thread_state', 'capture', 'reaction', 'discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], a:draft.kind) >= 0
    call s:Fill(a:buf, s:ContextLines(a:session, a:draft) + ['', 'Operation: ' . a:draft.state,
          \ a:draft.state ==# 'unknown' ? ':ReviewCheckReceipt · delivery still unknown' : a:draft.kind ==# 'thread_state' ? ':ReviewSend · retry explicit state change' : ':ReviewSend · confirm ' . (a:draft.kind ==# 'capture' ? 'capture settings' : a:draft.kind ==# 'participant_run' ? 'participant execution' : 'state change'), ':ReviewClose · return to discussion'])
    return
  endif
  highlight default link RevueDraftContext Comment
  if empty(prop_type_get('RevueDraftContext'))
    call prop_type_add('RevueDraftContext', {'highlight': 'RevueDraftContext'})
  endif
  try
    call prop_remove({'bufnr': a:buf, 'type': 'RevueDraftContext', 'all': 1}, 1, len(getbufline(a:buf, 1, '$')))
    let windows = filter(getwininfo(), {_, w -> w.bufnr == a:buf})
    let width = empty(windows) ? 80 : max([12, min(map(copy(windows), {_, w -> w.width - w.textoff - 1}))])
    for text in s:CompactContext(a:session, a:draft)
      for wrapped in revue#comments#Wrap(text, width)
        call prop_add(1, 0, {'bufnr': a:buf, 'type': 'RevueDraftContext', 'text': wrapped, 'text_align': 'above'})
      endfor
    endfor
  catch
    " The complete context remains available through the real-text preview.
  endtry
endfunction

function! revue#session#Preview() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_role', '') !=# 'draft' | return | endif
  let draft = s:Draft(session, get(b:, 'revue_draft', ''))
  if empty(draft) | return | endif
  call revue#session#SaveDraft()
  if index(['assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) >= 0
    let panel = s:Panel(session, 'preview')
    let rows = map(s:ContextLines(session, draft), {_, text -> {'text': text, 'type': text =~# '^#' ? 'RevueCardHeader' : 'RevueCardBody'}})
    call s:Fill(panel, map(copy(rows), {_, row -> row.text}))
    call revue#surface#Paint(panel, rows, 0)
    call revue#layout#SetBar(win_getid(), (draft.kind ==# 'service_viewed' ? ' Service Viewed state' : draft.kind ==# 'apply_suggestion' ? ' Suggestion application' : draft.kind ==# 'participant_run' ? ' Participant' : ' Assignment') . ' preview | :ReviewClose returns to the saved operation ')
    call cursor(1, 1)
    return
  endif
  if index(['capture', 'reaction'], draft.kind) >= 0
    call s:Fill(s:Panel(session, 'preview'), ['# ' . (draft.kind ==# 'capture' ? 'Capture' : 'Reaction') . ' preview'] + s:ContextLines(session, draft))
    call cursor(1, 1)
    return
  endif
  let body = index(['thread_state', 'capture', 'reaction', 'discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) >= 0 ? '' : join(getline(1, '$'), "\n")
  let comment = {'author': 'Draft preview', 'body': body, 'created': ''}
  let thread = {'comments': [comment], 'start': 0, 'line': 0, 'outdated': draft.snapshot !=# session.snapshot.snapshot}
  let context = {}
  if draft.kind ==# 'comment'
    let thread.start = draft.start
    let thread.line = draft.end
    let source = s:DraftSource(session, draft)
    let context.lines = get(source, 'kind', '') ==# 'text' ? source.lines : []
    " A cached historical source belongs to this draft, never the current file.
    let thread.outdated = empty(context.lines)
  endif
  let panel = s:Panel(session, 'preview')
  if draft.kind ==# 'delete_message'
    call revue#layout#SetBar(win_getid(), ' Deletion preview | :ReviewClose returns to the operation ')
    let lines = ['# Message deletion preview'] + s:CompactContext(session, draft, 1) + ['']
    let offset = len(lines)
    let rows = map(revue#delete_message#Preview(session.comparisons[session.latest_comparison].snapshot, draft),
          \ {_, line -> {'text': line, 'type': line =~# '^## ' ? 'RevueCardHeader' : 'RevueCardBody'}})
    call s:Fill(panel, lines + map(copy(rows), {_, row -> row.text}) + ['', '## Full deletion context'] + s:ContextLines(session, draft))
    call revue#surface#Paint(panel, rows, offset)
    call cursor(1, 1)
    return
  endif
  if draft.kind ==# 'delete_pending_comment' | call revue#layout#SetBar(win_getid(), ' Revue preview | :ReviewClose returns to deletion operation ') | endif
  if draft.kind ==# 'discard_pending' | call revue#layout#SetBar(win_getid(), ' Revue preview | :ReviewClose returns to discard operation ') | endif
  let outer = max([12, winwidth(0) - 2])
  let limit = get(g:, 'revue_comment_width', 100)
  let context.outer_width = outer
  let context.inline_styles = 1
  let rows = revue#comments#Rows(thread, limit > 0 ? min([outer, max([12, limit])]) : outer, context)
  let label = revue#suggestion#Label(draft)
  if !empty(get(draft, 'pending_mode', '')) | let label = substitute(label, '^private ', '', '') | endif
  let lines = ['# ' . toupper(strcharpart(label, 0, 1)) . strcharpart(label, 1) . ' preview'] + s:CompactContext(session, draft, 1) + ['']
  if draft.kind ==# 'edit'
    call extend(lines, revue#edit#Before(session.comparisons[session.latest_comparison].snapshot, draft))
  endif
  if draft.kind ==# 'delete_pending_comment'
    call extend(lines, revue#delete#Preview(session.comparisons[session.latest_comparison].snapshot, draft))
  endif
  if draft.kind ==# 'discard_pending'
    call extend(lines, revue#pending#DiscardPreview(session.comparisons[session.latest_comparison].snapshot, draft))
  endif
  if draft.kind ==# 'submit_pending'
    call extend(lines, revue#pending#Publication(session.comparisons[session.latest_comparison].snapshot, draft))
  endif
  if get(draft, 'suggestion', 0) && !empty(revue#suggestion#Parse(body).error)
    call add(lines, 'Cannot submit: ' . revue#suggestion#Parse(body).error)
  endif
  " Preview uses the body renderer but has no active reply footer.
  let rows = index(['discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) >= 0 ? [] : filter(rows, {_, r -> index(['RevueCardAction', 'RevueCardMeta'], r.type) < 0})
  let offset = len(lines)
  let details = index(['comment', 'reply', 'file_comment', 'review', 'start_pending'], draft.kind) >= 0 ? ['', '## Full review context'] + s:ContextLines(session, draft) : []
  call s:Fill(panel, lines + map(copy(rows), {_, r -> r.text}) + details)
  call revue#surface#Paint(panel, rows, offset)
  call cursor(1, 1)
endfunction

function! revue#session#SaveDraft() abort
  let session = s:Get()
  if empty(session) || !exists('b:revue_draft') | return | endif
  let draft = s:Draft(session, b:revue_draft)
  if empty(draft) || draft.state ==# 'submitting' | return | endif
  let body = index(['thread_state', 'capture', 'reaction', 'discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) >= 0 ? '' : join(getline(1, '$'), "\n")
  if draft.state ==# 'unknown' && body !=# draft.body
    call s:Notice('Unknown submission outcome: original draft is retained for reconciliation.')
    return
  endif
  let draft.body = body
  if s:Save(session)
    setlocal nomodified
    let b:revue_save_error = 0
  else
    let b:revue_save_error = 1
  endif
  call s:DraftContext(session, draft, bufnr())
  call s:DraftBar(session, draft)
  if revue#local_feedback#Enabled(session) && revue#local_feedback#IsFeedback(draft)
    call s:Annotations(session)
    call s:RenderTree(session)
  endif
endfunction

function! revue#session#SaveFeedback() abort
  let session = s:Get()
  if empty(session) | return | endif
  let draft = s:Draft(session, get(b:, 'revue_draft', ''))
  if revue#local_feedback#Enabled(session) && revue#local_feedback#IsFeedback(draft) && index(['draft', 'failed'], get(draft, 'state', '')) >= 0
    call revue#session#CloseView()
    return
  endif
  call revue#session#Send()
endfunction

function! revue#session#Send() abort
  let session = s:Get()
  if empty(session) || !exists('b:revue_draft') | return | endif
  call revue#session#SaveDraft()
  let draft = s:Draft(session, b:revue_draft)
  if empty(draft) || draft.state ==# 'submitting' | return | endif
  if draft.kind ==# 'thread_state' | call s:SendThreadState(session, draft) | return | endif
  let reconcile = draft.state ==# 'unknown'
  if !reconcile
    let error = s:SubmissionError(session, draft)
    if !empty(error) | call s:Notice(error) | return | endif
  endif
  let action = get(session.snapshot, 'submit_label', 'Send')
  let target = get(session.snapshot, 'submit_target', session.snapshot.key)
  if !empty(get(draft, 'pending_mode', ''))
    let action = 'Save privately'
    let question = (draft.pending_mode ==# 'create' ? 'Create a private pending review with this ' : 'Add this ') . revue#suggestion#Label(draft) . (draft.pending_mode ==# 'add' ? ' to pending review #' . draft.pending_review : '') . ' in ' . target . '? Nothing is published.'
  elseif draft.kind ==# 'apply_suggestion'
    let action = 'Apply suggestion'
    let question = 'Save the previewed replacement to ' . draft.workspace . '/' . draft.path . ' and capture saved files? No commit, push or resolution.'
  elseif draft.kind ==# 'participant_run'
    let action = revue#runtime#Label(draft)
    let question = draft.run_mode ==# 'abandon' ? 'Abandon only prepared run ' . draft.run . '? Assignment access and comments remain; no process is started or stopped.' : action . ' for ' . draft.participant.label . ' in ' . draft.workspace . ' with ' . get(draft.runtime, 'sandbox', 'workspace-write') . ' access?' . (draft.run_mode ==# 'resume' ? ' Resume exact session ' . draft.thread . '.' : '')
  elseif draft.kind ==# 'cancel_assignment'
    let action = 'Cancel assignment'
    let question = 'Revoke MCP access for assignment ' . draft.assignment . '? Replies and outcomes remain; this does not stop a process.'
  elseif draft.kind ==# 'assignment'
    let action = 'Save assignment'
    let question = printf('Assign %d selected messages to %s locally? Full threads are readable; no agent is started.', len(draft.targets), draft.participant.label)
  elseif draft.kind ==# 'edit'
    if !empty(get(draft, 'pending_review', '')) | let action = 'Save privately' | endif
    let question = action . ' replacement for ' . draft.message_kind . ' message #' . draft.message . ' in ' . target . '?'
  elseif draft.kind ==# 'service_viewed'
    let question = (draft.viewed ? 'Mark viewed' : 'Mark unviewed') . ' on the service for ' . draft.path . ' as ' . draft.actor_label . '?'
  elseif draft.kind ==# 'reaction'
    let question = action . ' ' . (draft.present ? 'add' : 'remove') . ' your ' . draft.reaction_label . ' reaction on message #' . draft.message . ' in ' . target . '?'
  elseif draft.kind ==# 'delete_message'
    let action = 'Delete'
    let question = 'Delete only ' . (get(draft, 'message_publication', '') ==# 'local' ? 'local review ' : 'published ') . draft.message_kind . ' #' . draft.message . ' in ' . target . '? Other messages remain.'
  elseif draft.kind ==# 'delete_pending_comment'
    let action = 'Delete'
    let question = 'Permanently delete only private comment #' . draft.message . ' from review #' . draft.pending_review . ' in ' . target . '?'
  elseif draft.kind ==# 'discard_pending'
    let action = 'Delete'
    let question = 'Permanently delete pending review #' . draft.pending_review . ', its summary and all ' . len(draft.pending_comments) . ' private comments from ' . target . '?'
  elseif draft.kind ==# 'submit_pending'
    let question = action . ' publication of pending review #' . draft.pending_review . ' with ' . len(draft.pending_comments) . ' comments and decision ' . draft.event . ' in ' . target . '?'
  else
    let question = action . ' ' . revue#suggestion#Label(draft) . ' to ' . target . '?'
  endif
  let confirming = {'window': win_getid(), 'buffer': bufnr(), 'draft': deepcopy(draft)}
  if !reconcile && confirm(question, '&' . action . "\n&Keep draft", 2) != 1 | return | endif
  if (!empty(get(draft, 'pending_mode', '')) || index(['discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) >= 0 || (draft.kind ==# 'edit' && !empty(get(draft, 'pending_review', '')))) && !reconcile
    if win_getid() != confirming.window || bufnr() != confirming.buffer || get(b:, 'revue_draft', '') !=# draft.id || draft !=# confirming.draft
      call s:Notice('The operation changed during confirmation. Inspect it again.')
      return
    endif
    let error = s:SubmissionError(session, draft)
    if !empty(error) | call s:Notice(error) | return | endif
  endif
  let oldstate = draft.state
  let draft.state = 'submitting'
  if !s:Save(session) | let draft.state = oldstate | return | endif
  call setbufvar(bufnr(), '&modifiable', 0)
  call s:DraftContext(session, draft, bufnr())
  let session.message = reconcile ? 'Checking submission receipt…' : 'Sending…'
  call s:RenderTree(session)
  try
  call session.Host({'op': 'mutate', 'draft': deepcopy(draft), 'reconcile': reconcile}, function('s:Sent', [session.id, draft.id, reconcile]))
  catch
    call s:Sent(session.id, draft.id, reconcile, {'ok': 0, 'unknown': 1, 'error': 'Submission transport interrupted: ' . v:exception})
  endtry
endfunction

function! s:Sent(id, draftid, reconcile, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) | return | endif
  let draft = s:Draft(session, a:draftid)
  if empty(draft) | return | endif
  if a:result.ok && !empty(get(draft, 'pending_mode', ''))
    let receipt = get(a:result, 'data', {})
    if get(receipt, 'id', '') !=# draft.id || get(receipt, 'actor', '') !=# draft.actor || get(receipt, 'pending_mode', '') !=# draft.pending_mode || type(get(receipt, 'pending_review', 0)) != v:t_string || empty(receipt.pending_review) || (draft.pending_mode ==# 'add' && receipt.pending_review !=# draft.pending_review) || (draft.kind ==# 'reply' && get(receipt, 'thread', '') !=# draft.thread)
      call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching private-save receipt. Check server state before acting again.'})
      return
    endif
  endif
  if a:result.ok && draft.kind ==# 'service_viewed' && !revue#service_progress#Receipt(draft, get(a:result, 'data', {}))
    call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching service Viewed receipt. Check the original outcome.'})
    return
  endif
  if a:result.ok && draft.kind ==# 'thread_state'
    let receipt = get(a:result, 'data', {})
    if get(receipt, 'id', '') !=# draft.id || get(receipt, 'thread', '') !=# draft.thread || type(get(receipt, 'resolved', -1)) != v:t_bool || receipt.resolved != draft.resolved
      call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching thread-state receipt. Check the outcome before acting again.'})
      return
    endif
  endif
  if a:result.ok && draft.kind ==# 'capture'
    let receipt = get(a:result, 'data', {})
    if get(receipt, 'id', '') !=# draft.id || get(receipt, 'previous_snapshot', '') !=# draft.snapshot || empty(get(receipt, 'snapshot', '')) || type(get(receipt, 'changed', '')) != v:t_bool
      call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching capture receipt. Check the outcome before capturing again.'})
      return
    endif
  endif
  if a:result.ok && draft.kind ==# 'edit'
    let receipt = get(a:result, 'data', {})
    if get(receipt, 'id', '') !=# draft.id || get(receipt, 'message', '') !=# draft.message || get(receipt, 'message_kind', '') !=# draft.message_kind || get(receipt, 'thread', '') !=# draft.thread || (!empty(get(draft, 'pending_review', '')) && (get(receipt, 'pending_review', '') !=# draft.pending_review || get(receipt, 'actor', '') !=# draft.actor))
      call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching edit receipt. Check the outcome before editing again.'})
      return
    endif
  endif
  if a:result.ok && draft.kind ==# 'reaction'
    let receipt = get(a:result, 'data', {})
    let valid = 1
    for key in ['id', 'message', 'message_kind', 'thread', 'actor', 'reaction', 'present']
      let valid = valid && has_key(receipt, key) && type(receipt[key]) == type(draft[key]) && receipt[key] ==# draft[key]
    endfor
    if !valid
      call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching reaction receipt; check the outcome before acting again.'})
      return
    endif
  endif
  if a:result.ok && draft.kind ==# 'apply_suggestion' && !revue#apply_suggestion#Receipt(draft, get(a:result, 'data', {}))
    call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching application receipt; check the original operation before applying again.'})
    return
  endif
  if a:result.ok && draft.kind ==# 'participant_run' && !revue#runtime#Receipt(draft, get(a:result, 'data', {}))
    call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching run receipt. Check the outcome before starting again.'})
    return
  endif
  if a:result.ok && draft.kind ==# 'cancel_assignment' && !revue#assignment#CancelReceipt(draft, get(a:result, 'data', {}))
    call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching cancellation receipt. Check the assignment outcome.'})
    return
  endif
  if a:result.ok && draft.kind ==# 'assignment' && !revue#assignment#Receipt(draft, get(a:result, 'data', {}))
    call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching assignment receipt. Check the outcome before assigning again.'})
    return
  endif
  if a:result.ok && draft.kind ==# 'delete_message' && !revue#delete_message#Receipt(draft, get(a:result, 'data', {}))
    call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching published-deletion receipt. Check the outcome before acting again.'})
    return
  endif
  if a:result.ok && draft.kind ==# 'delete_pending_comment' && !revue#delete#Receipt(draft, get(a:result, 'data', {}))
    call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching private-comment deletion receipt. Check the outcome before acting again.'})
    return
  endif
  if a:result.ok && draft.kind ==# 'discard_pending'
    let receipt = get(a:result, 'data', {})
    if get(receipt, 'id', '') !=# draft.id || get(receipt, 'pending_review', '') !=# draft.pending_review || get(receipt, 'actor', '') !=# draft.actor || get(receipt, 'discarded', 0) isnot v:true
      call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching pending-review discard receipt; check server state before acting again.'})
      return
    endif
  endif
  if a:result.ok && draft.kind ==# 'submit_pending'
    let valid = 1
    let receipt = get(a:result, 'data', {})
    for key in ['id', 'pending_review', 'actor', 'event']
      let valid = valid && get(receipt, key, '') ==# draft[key]
    endfor
    if !valid
      call s:Sent(a:id, a:draftid, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'No matching pending-review publication receipt; check the outcome before acting again.'})
      return
    endif
  endif
  if a:result.ok
    call filter(session.drafts, {_, d -> d.id !=# a:draftid})
    let session.message = (get(session.snapshot, 'submit_label', 'Send') ==# 'Save' ? 'Saved. ' : 'Sent. ') . get(a:result.data, 'url', '')
    let session.last_outcome = draft.kind ==# 'thread_state' ? (get(a:result.data, 'observed', 0) ? 'Requested thread state observed.' : draft.resolved ? 'Thread resolved.' : 'Thread reopened.') : session.message
    if draft.kind ==# 'apply_suggestion'
      let session.last_outcome = !a:result.data.applied ? 'Suggestion was not applied. No write was repeated; select the message for a fresh preview.' : (a:result.data.observed ? 'Suggested result observed; no write repeated.' : 'Suggestion saved to workspace.') . (empty(a:result.data.result_snapshot) ? ' Capture unavailable: ' . a:result.data.capture_error : ' :ReviewLatest opens the resulting capture.')
      let session.message = session.last_outcome
    endif
    if draft.kind ==# 'capture' | let session.last_outcome = a:result.data.changed ? 'New capture saved. :ReviewLatest opens it; original drafts are retained.' : 'Saved files match the current capture. No new comparison was needed.' | endif
    if draft.kind ==# 'assignment' | let session.last_outcome = 'Assignment ' . a:result.data.assignment . ' saved locally. No agent was started; :ReviewActivity retains its receipt.' | endif
    if draft.kind ==# 'cancel_assignment'
      let session.last_outcome = 'Assignment cancelled; MCP access revoked. Replies retained; process status is unknown.'
      let item = revue#assignment#Find(session, draft.assignment)
      if !empty(item) | let item.cancelled = v:true | let item.version = a:result.data.version | endif
    endif
    if draft.kind ==# 'participant_run'
      let session.last_outcome = draft.run_mode ==# 'abandon' ? 'Prepared run abandoned. Assignment access and comments retained; reload to prepare a new start or resume.' : 'Run ' . a:result.data.run . ' accepted; reload assignments for current process state.' . (empty(get(a:result.data, 'dispatch_error', '')) ? '' : ' Dispatch: ' . a:result.data.dispatch_error)
    endif
    if index(['assignment', 'participant_run'], draft.kind) >= 0 && has_key(session, 'assignments') | let session.assignments.requested = 0 | endif
    let session.last_receipt = deepcopy(a:result.data)
    if !empty(get(draft, 'pending_mode', '')) | let session.last_outcome = 'Saved to review #' . a:result.data.pending_review . '. :ReviewPending shows current private state; browser publication may have changed it.' | endif
    if draft.kind ==# 'edit' | let session.last_outcome = 'Message ' . draft.message . (empty(get(draft, 'pending_review', '')) ? ' updated.' : ' saved to pending review #' . draft.pending_review . '. Refresh shows its current publication state.') | endif
    if draft.kind ==# 'service_viewed'
      let session.last_outcome = 'Requested service Viewed state observed; local marks unchanged.'
      if has_key(session, 'service_progress') && session.service_progress.path ==# draft.path && session.service_progress.reference ==# draft.reference | let session.service_progress.data = {} | let session.service_progress.error = 'Service state updated; :ReviewServiceProgress reloads.' | endif
    endif
    if draft.kind ==# 'reaction' | let session.last_outcome = get(a:result.data, 'observed', 0) ? 'Requested reaction state observed.' : 'Reaction update accepted. Refresh shows current state.' | endif
    if draft.kind ==# 'delete_message' | let session.last_outcome = 'Message #' . draft.message . (get(a:result.data, 'observed', 0) ? ' is absent from the verified review; the deleting request is not known.' : ' deleted.') | endif
    if draft.kind ==# 'delete_pending_comment' | let session.last_outcome = 'Private comment #' . draft.message . (get(a:result.data, 'observed', 0) ? ' is absent from its review for the verified actor.' : ' deleted.') | endif
    if draft.kind ==# 'discard_pending' | let session.last_outcome = get(a:result.data, 'observed', 0) ? 'Pending review #' . draft.pending_review . ' is absent for the verified actor.' : 'Pending review #' . draft.pending_review . ' discarded.' | endif
    if draft.kind ==# 'submit_pending' | let session.last_outcome = 'Pending review #' . draft.pending_review . ' published. Refresh shows its current state.' | endif
    call revue#activity#Record(session, draft, get(a:result.data, 'observed', 0) ? 'observed' : 'accepted', session.last_outcome, a:result.data)
    call s:Save(session)
    let origin = get(b:, 'revue_draft', '') ==# a:draftid ? get(b:, 'revue_origin', {}) : {}
    if draft.kind ==# 'delete_message' && index(['threads', 'conversation'], get(origin, 'kind', '')) >= 0
      " Return beside the removed message, using stable identity before refresh.
      let candidates = filter(values(session.messagemap), {_, t -> t.thread ==# draft.thread && !(t.comment ==# draft.message && t.kind ==# draft.message_kind)})
      let at = get(get(origin, 'message', {}), 'start', 1)
      call sort(candidates, {a, b -> abs(a.start - at) - abs(b.start - at)})
      let origin.message = empty(candidates) ? {} : deepcopy(candidates[0])
      let origin.view.lnum = get(origin.message, 'start', 1)
      let origin.view.topline = origin.view.lnum
    endif
    let layout = {}
    for buf in copy(session.buffers)
      if getbufvar(buf, 'revue_draft', '') ==# a:draftid
        let win = revue#layout#BufferWindow(buf)
        if win > 0
          let layout = revue#layout#Get(win, 'revue_previous_layout', {})
          if get(session, 'focus_win', 0) == win | call revue#layout#Unfocus(session) | endif
        endif
        execute 'silent! bwipeout! ' . buf
      endif
    endfor
    if !empty(layout) | call revue#layout#Restore(layout) | endif
    if !empty(origin) | call s:Return(session, origin) | endif
    call s:Refresh(session)
  else
    let draft.state = a:reconcile || get(a:result, 'unknown', 0) ? 'unknown' : 'failed'
    let session.message = (a:reconcile ? 'Receipt check failed; delivery still unknown. ' : '') . a:result.error . (draft.state ==# 'unknown' ? ' Send again checks receipts without reposting.' : ' Draft retained.')
    if draft.kind ==# 'service_viewed' && has_key(session, 'service_progress') && session.service_progress.path ==# draft.path && session.service_progress.reference ==# draft.reference
      let session.service_progress.error = a:result.error
    endif
    if draft.kind ==# 'reaction'
      let session.message = a:result.error . (draft.state ==# 'unknown' ? ' Outcome unknown; check the receipt in Reactions or Activity.' : ' Reaction not accepted; retry from Reactions or inspect Activity.')
    endif
    if draft.kind ==# 'thread_state'
      let session.message = a:result.error . (draft.state ==# 'unknown' ? ' Outcome unknown; :ReviewCheckThreadState checks the original operation. Activity retains details.' : ' Resolution not accepted; retry its explicit command or inspect Activity.')
    endif
    if draft.kind ==# 'apply_suggestion'
      let session.message = a:result.error . (draft.state ==# 'unknown' ? ' Application outcome unknown; :ReviewCheckReceipt checks the original intent without writing again.' : ' Application not accepted; the preview is retained.')
    endif
    call revue#activity#Record(session, draft, a:reconcile ? 'receipt-check-failed' : draft.state, session.message, {})
    call s:Save(session)
    for buf in session.buffers
      if getbufvar(buf, 'revue_draft', '') ==# a:draftid
        call setbufvar(buf, '&modifiable', index(['thread_state', 'capture', 'reaction', 'discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) < 0 && draft.state !=# 'unknown')
        call s:DraftContext(session, draft, buf)
      endif
    endfor
  endif
  call s:RenderTree(session)
  call s:RepaintPanel(session)
  call s:Notice(session.message)
endfunction

function! revue#session#Discard() abort
  let session = s:Get()
  if empty(session) || !exists('b:revue_draft') | return | endif
  let id = b:revue_draft
  let draft = s:Draft(session, id)
  if index(['submitting', 'unknown'], get(draft, 'state', '')) >= 0
    call s:Notice('Delivery is still unknown or in progress. Keep the operation for receipt recovery.')
    return
  endif
  if confirm('Discard this local draft?', "&Discard\n&Keep", 2) != 1 | return | endif
  let before = copy(session.drafts)
  call filter(session.drafts, {_, d -> d.id !=# id})
  if s:Save(session)
    let origin = get(b:, 'revue_origin', {})
    let layout = get(w:, 'revue_previous_layout', {})
    call revue#layout#Unfocus(session)
    bwipeout!
    call revue#layout#Restore(layout)
    call s:Return(session, origin)
    call s:RenderTree(session)
    if revue#local_feedback#Enabled(session) | call s:Annotations(session) | endif
  else
    let session.drafts = before
  endif
endfunction

function! revue#session#Refresh() abort
  let session = s:Get()
  if !empty(session) | call s:Refresh(session) | endif
endfunction

function! revue#session#Feedback() abort
  let session = s:Get()
  if empty(session) | return | endif
  if !revue#local_feedback#Enabled(session) | call s:Notice('This feedback collection is for local reviews.') | return | endif
  if !s:SyncDraftBuffers(session) | return | endif
  let items = revue#local_feedback#Items(session)
  if !has_key(session, 'feedbackselected') | let session.feedbackselected = {} | endif
  let lines = ['# Collect review feedback',
        \ 'Pending cards are saved locally. Export keeps their status and text intact.',
        \ 'Space select · a select all loaded · u clear · Enter edit / read',
        \ 'm / :ReviewExportMarkdown → Markdown buffer · :ReviewClose → return',
        \ printf('Selected %d of %d loaded items', len(filter(copy(items), {_, i -> get(session.feedbackselected, i.key, 0)})), len(items))]
  if !empty(get(get(session.snapshot, 'feedback', {}), 'cursor', ''))
    call add(lines, 'More saved feedback available · :ReviewLoadMoreFeedback, then select the new items.')
  endif
  call add(lines, '')
  let rows = {}
  for item in items
    let first = len(lines) + 1
    call add(lines, (get(session.feedbackselected, item.key, 0) ? '[x] ' : '[ ] ') . item.status . ' · ' . revue#local_feedback#Location(item))
    call extend(lines, split(item.body, "\n", 1) + [''])
    for row in range(first, len(lines)) | let rows[string(row)] = item.key | endfor
  endfor
  if empty(items) | call add(lines, 'No feedback yet. Use c on a code line, write your comment, then :ReviewClose.') | endif
  let panel = s:Panel(session, 'feedback')
  let session.feedbackrows = rows
  let session.feedback_preview = deepcopy(items)
  call s:Fill(panel, lines)
endfunction

function! revue#session#ToggleFeedback() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'feedback' | return | endif
  let key = get(session.feedbackrows, string(line('.')), '')
  if empty(key) | return | endif
  let view = winsaveview()
  let session.feedbackselected[key] = !get(session.feedbackselected, key, 0)
  call revue#session#Feedback()
  call winrestview(view)
endfunction

function! revue#session#SelectFeedback(selected) abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'feedback' | return | endif
  let session.feedbackselected = {}
  if a:selected
    for item in session.feedback_preview | let session.feedbackselected[item.key] = 1 | endfor
  endif
  call revue#session#Feedback()
endfunction

function! revue#session#EditFeedback() abort
  let session = s:Get()
  if empty(session) || !revue#local_feedback#Enabled(session) | return | endif
  let items = revue#local_feedback#Items(session)
  if get(b:, 'revue_view', '') ==# 'feedback'
    let key = get(session.feedbackrows, string(line('.')), '')
    let matches = filter(items, {_, i -> i.key ==# key})
  elseif index(['base', 'head'], get(b:, 'revue_role', '')) >= 0 && session.index >= 0
    let path = session.snapshot.files[session.index].path
    let side = get(b:, 'revue_side', '')
    let row = line('.')
    let matches = filter(items, {_, i -> i.pending && i.snapshot ==# session.snapshot.snapshot && get(i, 'path', '') ==# path &&
          \ (i.kind ==# 'file_comment' || (get(i, 'side', '') ==# side && row >= get(i, 'start', 0) && row <= get(i, 'end', 0)))})
  else
    call revue#session#Feedback()
    return
  endif
  if empty(matches) | call s:Notice('No pending feedback here. :ReviewBatch lists all feedback.') | return | endif
  let choice = 0
  if len(matches) > 1
    let origin = [win_getid(), bufnr(), line('.'), session.snapshot.snapshot]
    let choices = ['Choose pending feedback to edit:']
    for item in matches | call add(choices, len(choices) . '. ' . revue#message#OneLine(item.body)) | endfor
    let choice = inputlist(choices) - 1
    if choice < 0 || choice >= len(matches) | return | endif
    if origin !=# [win_getid(), bufnr(), line('.'), session.snapshot.snapshot] | call s:Notice('Source changed; choose again.') | return | endif
  endif
  let item = matches[choice]
  if item.pending
    call s:Composer(session, item.id)
  elseif has_key(item, 'thread')
    call revue#session#Threads(item.thread)
  else
    call revue#session#Conversation()
  endif
endfunction

function! revue#session#ExportMarkdown() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'feedback' | return | endif
  if !s:SyncDraftBuffers(session) | return | endif
  let selected = filter(revue#local_feedback#Items(session), {_, i -> get(session.feedbackselected, i.key, 0)})
  let shown = filter(deepcopy(session.feedback_preview), {_, i -> get(session.feedbackselected, i.key, 0)})
  if selected !=# shown
    call revue#session#Feedback()
    call s:Notice('Feedback changed; check the updated selection before exporting.')
    return
  endif
  if empty(selected) | call s:Notice('Select feedback with Space, or a for all loaded items.') | return | endif
  let lines = revue#local_feedback#Markdown(session, selected)
  " An independent buffer survives review closure and is never refreshed over.
  tabnew
  setlocal buftype=nofile bufhidden=hide noswapfile nobuflisted nomodeline
  execute 'file ' . fnameescape('review-export://' . s:Id() . '/feedback.md')
  setlocal filetype=markdown wrap modifiable
  call setline(1, lines)
  setlocal nomodified
  call s:Notice('Markdown buffer ready · ggVG"+y copies all · :w /path/feedback.md saves a file. Feedback remains unchanged.')
endfunction

function! revue#session#Batch(...) abort
  let session = s:Get()
  if empty(session) | return | endif
  if !a:0 && revue#local_feedback#Enabled(session)
    call revue#session#Feedback()
    return
  endif
  let id = a:0 ? a:1 : ''
  let frozen = empty(id) ? {} : s:Draft(session, id)
  if !empty(id) && (empty(frozen) || frozen.kind !=# 'batch') | return | endif
  let delivery = empty(frozen) ? (a:0 > 1 ? a:2 : get(session, 'batch_delivery', 'public')) : get(frozen, 'delivery', 'public')
  if delivery ==# 'private' && empty(frozen)
    for draft in session.drafts
      if get(draft, 'delivery', '') ==# 'private' | call revue#session#Batch(draft.id) | return | endif
    endfor
  endif
  let capability = get(get(session.snapshot, 'capabilities', {}), delivery ==# 'private' ? 'stage_batch' : 'batch', {})
  if empty(frozen) && empty(capability) | call s:Notice('This backend does not support review batches.') | return | endif
  if empty(frozen) && !s:SyncDraftBuffers(session) | return | endif
  let items = empty(frozen) ? filter(deepcopy(session.drafts), {_, d -> d.kind !=# 'batch'}) : frozen.items
  if !has_key(session, 'batchselected') | let session.batchselected = {} | endif
  let selected = empty(frozen) ? filter(deepcopy(items), {_, d -> get(session.batchselected, d.id, 0)}) : items
  let decisions = filter(copy(selected), {_, d -> d.kind ==# 'review'})
  let decision = empty(decisions) ? get(capability, 'default_label', 'Backend default') : join(map(decisions, {_, d -> d.event}), ', ')
  let supported = map(copy(get(capability, 'kinds', [])), {_, kind -> get({'comment': 'inline comments', 'file_comment': 'file comments', 'reply': 'replies', 'conversation': 'conversation', 'review': 'review decision'}, kind, kind)})
  let header = ['# Review batch · ' . get(session.snapshot, 'submit_target', session.snapshot.key),
        \ 'Submit together · supports: ' . join(supported, ', '),
        \ printf('Selected %d of %d · %s', len(selected), len(items), decision),
        \ 'Comparison ' . strpart(empty(frozen) ? session.snapshot.head : frozen.head, 0, 12),
        \ ':ReviewToggleDraft · :ReviewEditDraft · :ReviewSendBatch · :ReviewClose',
        \ empty(frozen) ? 'Only checked drafts will be submitted. Other drafts remain in the outbox.' : 'Frozen batch: ' . frozen.state . ' · ' . get(frozen, 'error', ''), '']
  if !empty(frozen) | call add(header, 'Failed batch: :ReviewUnpackBatch restores editable drafts. Unknown: Send checks receipts only.') | endif
  if delivery ==# 'private'
    let binding = empty(frozen) ? revue#stage#Binding(session.snapshot) : frozen
    let target = empty(frozen) && has_key(binding, 'error') ? binding.error : empty(binding.pending_review) ? 'create a new private review' : 'private review #' . binding.pending_review
    let header = ['# Save selected feedback privately', target . ' · actor ' . get(binding, 'actor', 'unavailable'),
          \ printf('Selected %d of %d · source %s', len(selected), len(items), strpart(empty(frozen) ? session.snapshot.head : frozen.head, 0, 12)),
          \ 'Saved one at a time; partial results are retained. Publication is separate.',
          \ empty(frozen) ? ':ReviewToggleDraft · :ReviewEditDraft · :ReviewSendBatch · :ReviewClose' : 'Selected feedback is read-only while this queue is retained. :ReviewClose returns.',
          \ 'Only checked comments, file feedback and replies are included. Review decisions remain in the outbox.', '']
    if !empty(frozen)
      call extend(header, [frozen.state ==# 'unknown' ? 'Outcome unknown · :ReviewCheckReceipt reads only' : frozen.state ==# 'submitting' ? 'Saving privately…' : 'Paused · :ReviewSendBatch confirms remaining saves',
            \ ':ReviewUnpackBatch returns only unsaved items when outcomes are known.'] + revue#stage#View(frozen) + [''])
      if !empty(get(frozen, 'error', '')) && empty(filter(copy(frozen.steps), {_, step -> get(step, 'error', '') ==# frozen.error}))
        call add(header, frozen.error)
      endif
    endif
    let session.stage_preview_binding = deepcopy(binding)
  endif
  let view = revue#batch#View(items, session.batchselected, !empty(frozen))
  let panel = s:Panel(session, 'batch')
  let session.batchid = id
  let session.batch_delivery = delivery
  let session.batch_preview_items = deepcopy(items)
  let session.batchrows = {}
  for [row, item] in items(view.rows) | let session.batchrows[string(str2nr(row) + len(header))] = item | endfor
  call s:Fill(panel, header + view.lines)
endfunction

function! s:SyncDraftBuffers(session) abort
  let changed = []
  for buf in a:session.buffers
    let draft = s:Draft(a:session, getbufvar(buf, 'revue_draft', ''))
    if !empty(draft) && index(['batch', 'thread_state', 'capture', 'reaction', 'discard_pending', 'delete_pending_comment', 'delete_message', 'assignment', 'cancel_assignment', 'participant_run', 'apply_suggestion', 'service_viewed'], draft.kind) < 0 && index(['draft', 'failed'], draft.state) >= 0 && getbufvar(buf, '&modified')
      let draft.body = join(getbufline(buf, 1, '$'), "\n")
      call add(changed, buf)
    endif
  endfor
  if !empty(changed)
    if !s:Save(a:session) | return 0 | endif
    for buf in changed | call setbufvar(buf, '&modified', 0) | endfor
  endif
  return 1
endfunction

function! revue#session#ToggleBatchDraft() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'batch' || !empty(get(session, 'batchid', '')) | return | endif
  let id = get(session.batchrows, string(line('.')), '')
  if empty(id) | return | endif
  let draft = s:Draft(session, id)
  let capability = get(get(session.snapshot, 'capabilities', {}), get(session, 'batch_delivery', '') ==# 'private' ? 'stage_batch' : 'batch', {})
  if !get(session.batchselected, id, 0) && (index(get(capability, 'kinds', []), draft.kind) < 0 || index(['draft', 'failed'], draft.state) < 0)
    call s:Notice('This draft must be sent or recovered separately.')
    return
  endif
  let view = winsaveview()
  let session.batchselected[id] = !get(session.batchselected, id, 0)
  call revue#session#Batch()
  call winrestview(view)
endfunction

function! revue#session#EditBatchDraft() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'batch' || !empty(get(session, 'batchid', '')) | return | endif
  let id = get(session.batchrows, string(line('.')), '')
  if !empty(id) | call s:Composer(session, id) | endif
endfunction

function! revue#session#SendBatch() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'batch' | return | endif
  let batch = s:Draft(session, get(session, 'batchid', ''))
  if get(session, 'batch_delivery', '') ==# 'private' || get(batch, 'delivery', '') ==# 'private'
    call s:SendPrivateBatch(session, batch)
    return
  endif
  if !empty(batch) && batch.state ==# 'submitting' | return | endif
  let reconcile = !empty(batch) && batch.state ==# 'unknown'
  if empty(batch)
    if !s:SyncDraftBuffers(session) | return | endif
    let items = filter(deepcopy(session.drafts), {_, d -> d.kind !=# 'batch' && get(session.batchselected, d.id, 0)})
    let displayed = filter(deepcopy(get(session, 'batch_preview_items', [])), {_, d -> get(session.batchselected, d.id, 0)})
    if items !=# displayed
      call revue#session#Batch()
      call s:Notice('Drafts changed; review the updated preview before sending.')
      return
    endif
  else
    let items = deepcopy(batch.items)
  endif
  if !reconcile
    let latest = session.comparisons[session.latest_comparison].snapshot
    let error = revue#batch#Error(latest, items)
    if !empty(error) | call s:Notice(error) | return | endif
    if session.snapshot.snapshot !=# latest.snapshot
      call s:Notice('Open :ReviewLatest before submitting a review batch. Draft anchors are retained.')
      return
    endif
    let action = get(session.snapshot, 'submit_label', 'Send')
    let guard = s:ActionGuard(session)
    if confirm(action . ' these ' . len(items) . ' drafts as one review to ' . get(session.snapshot, 'submit_target', session.snapshot.key) . '?', '&' . action . "\n&Keep draft", 2) != 1 | return | endif
    if empty(s:Get()) || guard !=# s:ActionGuard(s:Get()) | call s:Notice('The review changed during confirmation. Inspect the batch again.') | return | endif
  endif
  let before = deepcopy(session.drafts)
  if empty(batch)
    let batch = {'id': s:Id(), 'kind': 'batch', 'body': '', 'items': items, 'state': 'draft',
          \ 'head': session.snapshot.head, 'base_tip': get(session.snapshot, 'base_tip', session.snapshot.base), 'snapshot': session.snapshot.snapshot}
    let ids = map(copy(items), {_, d -> d.id})
    call filter(session.drafts, {_, d -> index(ids, d.id) < 0})
    call add(session.drafts, batch)
  endif
  let batch.state = 'submitting'
  if !s:Save(session) | let session.drafts = before | return | endif
  for buf in session.buffers
    if index(map(copy(items), {_, d -> d.id}), getbufvar(buf, 'revue_draft', '')) >= 0
      call setbufvar(buf, '&modifiable', 0)
    endif
  endfor
  call revue#session#Batch(batch.id)
  call s:RenderTree(session)
  call session.Host({'op': 'mutate', 'draft': deepcopy(batch), 'reconcile': reconcile}, function('s:BatchSent', [session.id, batch.id, reconcile]))
endfunction

function! s:StagePermission(session, batch) abort
  let latest = a:session.comparisons[a:session.latest_comparison].snapshot
  let error = revue#stage#Availability(latest)
  if !empty(error) | return error | endif
  if a:batch.snapshot !=# latest.snapshot || a:batch.head !=# latest.head || a:batch.base_tip !=# get(latest, 'base_tip', latest.base)
    return 'The comparison changed. Keep saved results and return unsaved drafts for review.'
  endif
  let inventory = get(latest, 'pending_reviews', {})
  if !get(inventory, 'available', 0) || get(inventory, 'actor', '') !=# a:batch.actor | return 'Refresh to verify the private review actor before continuing.' | endif
  return ''
endfunction

function! s:SendPrivateBatch(session, frozen) abort
  let session = a:session
  let batch = a:frozen
  if !empty(batch) && batch.state ==# 'submitting' | return | endif
  if !empty(batch) && batch.state ==# 'unknown'
    call s:StageRun(session.id, batch.id, 1)
    return
  endif
  let latest = session.comparisons[session.latest_comparison].snapshot
  if empty(batch)
    if !s:SyncDraftBuffers(session) | return | endif
    let items = filter(deepcopy(session.drafts), {_, d -> d.kind !=# 'batch' && get(session.batchselected, d.id, 0)})
    let displayed = filter(deepcopy(get(session, 'batch_preview_items', [])), {_, d -> get(session.batchselected, d.id, 0)})
    let binding = revue#stage#Binding(latest)
    if items !=# displayed || binding !=# get(session, 'stage_preview_binding', {})
      call revue#session#Batch()
      call s:Notice('Feedback or private review target changed. Inspect the updated preview.')
      return
    endif
    let error = revue#stage#Error(latest, items, binding)
    if !empty(error) | call s:Notice(error) | return | endif
    if s:PendingBusy(session, '', binding.pending_review) | return | endif
    let batch = extend({'id': s:Id(), 'kind': 'batch', 'delivery': 'private', 'body': '', 'items': items,
          \ 'state': 'draft', 'head': latest.head, 'base_tip': get(latest, 'base_tip', latest.base), 'snapshot': latest.snapshot, 'steps': []}, binding)
    if binding.private_mode ==# 'create'
      let child = {'id': s:Id(), 'kind': 'start_pending', 'body': '', 'state': 'draft', 'pending_mode': 'create', 'pending_review': '', 'actor': binding.actor,
            \ 'head': batch.head, 'base_tip': batch.base_tip, 'snapshot': batch.snapshot}
      call add(batch.steps, {'item': '', 'draft': child, 'state': 'waiting'})
    endif
    for item in items
      let child = extend(deepcopy(item), {'id': s:Id(), 'pending_mode': 'add', 'pending_review': binding.pending_review, 'pending_head': binding.pending_head, 'actor': binding.actor})
      call add(batch.steps, {'item': item.id, 'draft': child, 'state': 'waiting'})
    endfor
  else
    let error = s:StagePermission(session, batch)
    if !empty(error) | call s:Notice(error) | return | endif
  endif
  let remaining = len(filter(copy(batch.steps), {_, step -> !empty(step.item) && step.state !=# 'accepted'}))
  let target = empty(batch.pending_review) ? 'a new private review' : 'private review #' . batch.pending_review
  let guard = s:ActionGuard(session)
  if confirm('Save ' . remaining . ' drafts to ' . target . ' as ' . batch.actor . '? Saves run one at a time and stop on failure. Nothing is published.', "&Save privately\n&Keep draft", 2) != 1 | return | endif
  if empty(s:Get()) || guard !=# s:ActionGuard(s:Get()) | call s:Notice('The review changed during confirmation. Inspect the queue again.') | return | endif
  let before = deepcopy(session.drafts)
  if empty(a:frozen)
    let ids = map(copy(batch.items), {_, item -> item.id})
    call filter(session.drafts, {_, d -> index(ids, d.id) < 0})
    call add(session.drafts, batch)
  endif
  let batch.state = 'submitting'
  if !s:Save(session) | let session.drafts = before | return | endif
  for buf in session.buffers
    if index(map(copy(batch.items), {_, d -> d.id}), getbufvar(buf, 'revue_draft', '')) >= 0 | call setbufvar(buf, '&modifiable', 0) | endif
  endfor
  call revue#session#Batch(batch.id)
  call s:StageRun(session.id, batch.id, 0)
endfunction

function! s:StagePaint(session, batch) abort
  let previous = win_getid()
  if get(a:session, 'panelkind', '') ==# 'batch' && get(a:session, 'batchid', '') ==# a:batch.id && win_gotoid(get(a:session, 'panelwin', 0))
    call revue#session#Batch(a:batch.id)
  endif
  call win_gotoid(previous)
  call s:RenderTree(a:session)
endfunction

function! s:StageRun(id, batchid, reconcile, ...) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) | return | endif
  let batch = s:Draft(session, a:batchid)
  if empty(batch) || get(batch, 'delivery', '') !=# 'private' | return | endif
  " Timer continuation is valid only while the confirmed run is still active.
  if a:0 && batch.state !=# 'submitting' | return | endif
  let candidates = filter(range(len(batch.steps)), {_, i -> a:reconcile ? index(['unknown', 'submitting'], batch.steps[i].state) >= 0 : batch.steps[i].state !=# 'accepted'})
  if empty(candidates)
    if !empty(filter(copy(batch.steps), {_, step -> step.state !=# 'accepted'}))
      let batch.state = 'failed'
      let batch.error = 'No uncertain save remains. Confirm the remaining saves explicitly.'
      call s:Save(session)
      call s:StagePaint(session, batch)
      call s:Refresh(session)
      return
    endif
    let receipt = {'id': batch.id, 'actor': batch.actor, 'pending_review': batch.pending_review, 'items': []}
    for step in batch.steps
      if !empty(step.item) | call add(receipt.items, extend(deepcopy(step.receipt), {'draft': step.item})) | endif
    endfor
    call s:BatchSent(session.id, batch.id, a:reconcile, {'ok': 1, 'data': receipt})
    return
  endif
  let index = candidates[0]
  let step = batch.steps[index]
  if !a:reconcile
    if index(['unknown', 'submitting'], step.state) >= 0 | let batch.state = 'unknown' | call s:StagePaint(session, batch) | return | endif
    let error = s:StagePermission(session, batch)
    let shadow = deepcopy(session.comparisons[session.latest_comparison].snapshot)
    " A creation receipt proves the new ID before it appears in a refresh.
    " The backend still verifies ownership, state and source before every add.
    if empty(error) && step.draft.pending_mode ==# 'add' && empty(revue#pending#Find(shadow, batch.pending_review))
      let shadow.pending_reviews.items = [{'id': batch.pending_review, 'head': step.draft.pending_head, 'actor': batch.actor}]
    endif
    if empty(error) | let error = revue#capabilities#Error(shadow, step.draft, 1) | endif
    if empty(error) | let error = revue#anchor#Error(shadow, step.draft) | endif
    if !empty(error)
      let step.state = 'failed'
      let step.error = error
      let batch.state = 'failed'
      let batch.error = error
      call s:Save(session)
      call s:StagePaint(session, batch)
      return
    endif
  endif
  let prior = step.state
  let step.state = 'submitting'
  let step.attempt = get(step, 'attempt', 0) + 1
  let batch.state = 'submitting'
  if !s:Save(session)
    let step.state = prior
    let batch.state = a:reconcile ? 'unknown' : 'failed'
    call s:StagePaint(session, batch)
    return
  endif
  call s:StagePaint(session, batch)
  try
    call session.Host({'op': 'mutate', 'draft': deepcopy(step.draft), 'reconcile': a:reconcile}, function('s:StageSent', [a:id, a:batchid, index, step.attempt, a:reconcile]))
  catch
    call s:StageSent(a:id, a:batchid, index, step.attempt, a:reconcile, {'ok': 0, 'unknown': 1, 'error': 'Private save interrupted: ' . v:exception})
  endtry
endfunction

function! s:StageSent(id, batchid, index, attempt, reconcile, response) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) | return | endif
  let batch = s:Draft(session, a:batchid)
  if empty(batch) | return | endif
  let step = batch.steps[a:index]
  if step.state !=# 'submitting' || step.attempt != a:attempt | return | endif
  let result = deepcopy(a:response)
  if get(result, 'ok', 0)
    let error = revue#stage#Receipt(step.draft, get(result, 'data', {}))
    if !empty(error) | let result = {'ok': 0, 'unknown': 1, 'error': error} | endif
  endif
  if !get(result, 'ok', 0)
    let step.state = a:reconcile || get(result, 'unknown', 0) ? 'unknown' : 'failed'
    let step.error = get(result, 'error', 'Private save failed.')
    let batch.state = step.state
    let batch.error = step.error
    call revue#activity#Record(session, batch, a:reconcile ? 'receipt-check-failed' : 'private-step-failed', step.error, {})
    call s:Save(session)
    call s:StagePaint(session, batch)
    call s:Refresh(session)
    return
  endif
  let step.state = 'accepted'
  let step.error = ''
  let step.receipt = deepcopy(result.data)
  if empty(step.item)
    let batch.pending_review = result.data.pending_review
    let batch.private_mode = 'add'
    for pending in batch.steps
      if !empty(pending.item) | let pending.draft.pending_review = batch.pending_review | endif
    endfor
  endif
  let batch.error = ''
  let batch.state = a:reconcile ? 'failed' : 'submitting'
  call revue#activity#Record(session, batch, 'private-step-saved', 'Private save receipt confirmed · ' . (empty(step.item) ? 'review created' : step.item), result.data)
  if !s:Save(session)
    let step.state = 'unknown'
    let batch.state = 'unknown'
    let batch.error = 'Private save accepted but local receipt persistence failed. Check the receipt before continuing.'
    call s:StagePaint(session, batch)
    return
  endif
  call s:StagePaint(session, batch)
  if a:reconcile
    " Checking a receipt never starts the next write.
    call s:StageRun(a:id, a:batchid, 1)
  else
    let delay = get(get(get(session.snapshot, 'capabilities', {}), 'stage_batch', {}), 'min_interval_ms', 0)
    if type(delay) != v:t_number || delay < 0 | let delay = 1000 | endif
    call timer_start(max([1, delay]), function('s:StageRun', [a:id, a:batchid, 0]))
  endif
endfunction

function! s:BatchSent(id, batchid, reconcile, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) | return | endif
  let batch = s:Draft(session, a:batchid)
  if empty(batch) | return | endif
  let result = deepcopy(a:result)
  let ids = map(copy(batch.items), {_, d -> d.id})
  if result.ok && sort(map(copy(get(result.data, 'items', [])), {_, r -> get(r, 'draft', '')})) !=# sort(copy(ids))
    let result = {'ok': 0, 'unknown': 1, 'error': 'Incomplete batch receipt. Keep the batch for reconciliation.'}
  endif
  if result.ok
    call filter(session.drafts, {_, d -> d.id !=# a:batchid})
    let session.last_batch_receipt = result.data
    let session.message = get(batch, 'delivery', '') ==# 'private' ? 'Saved privately · ' . len(ids) . ' drafts · review #' . batch.pending_review : 'Batch accepted · ' . len(ids) . ' drafts.'
    let session.last_outcome = session.message
    let session.last_receipt = deepcopy(result.data)
    call revue#activity#Record(session, batch, 'accepted', session.message, result.data)
    for buf in session.buffers
      if index(ids, getbufvar(buf, 'revue_draft', '')) >= 0 | execute 'silent! bwipeout! ' . buf | endif
    endfor
    if get(session, 'batchid', '') ==# batch.id
      let session.batchselected = {}
    else
      call filter(session.batchselected, {key, _ -> index(ids, key) < 0})
    endif
    if !s:Save(session) | call s:Notice('Batch accepted; receipt retained in this session. Disk outbox requires reconciliation.') | endif
  else
    let batch.state = a:reconcile || get(result, 'unknown', 0) ? 'unknown' : 'failed'
    let batch.error = (a:reconcile ? 'Receipt check failed; delivery still unknown. ' : '') . result.error
    call revue#activity#Record(session, batch, a:reconcile ? 'receipt-check-failed' : batch.state, batch.error, {})
    call s:Save(session)
    let session.message = batch.error
  endif
  let previous = win_getid()
  if get(session, 'panelwin', 0) && winbufnr(session.panelwin) == get(session, 'panel', -1) && get(session, 'panelkind', '') ==# 'batch' && get(session, 'batchid', '') ==# batch.id
    call win_gotoid(session.panelwin)
    call revue#session#Batch(result.ok ? '' : batch.id)
  endif
  call win_gotoid(previous)
  call s:RenderTree(session)
  call s:RepaintPanel(session)
  if result.ok | call s:Refresh(session) | endif
endfunction

function! revue#session#UnpackBatch() abort
  let session = s:Get()
  if empty(session) || get(b:, 'revue_view', '') !=# 'batch' | return | endif
  let batch = s:Draft(session, get(session, 'batchid', ''))
  if empty(batch) || index(['draft', 'failed'], batch.state) < 0
    call s:Notice('A submitting or unknown batch must be reconciled before editing.')
    return
  endif
  let before = deepcopy(session.drafts)
  let restore = deepcopy(batch.items)
  if get(batch, 'delivery', '') ==# 'private'
    let accepted = map(filter(copy(batch.steps), {_, step -> step.state ==# 'accepted'}), {_, step -> step.item})
    let restore = filter(restore, {_, item -> index(accepted, item.id) < 0})
  endif
  call filter(session.drafts, {_, d -> d.id !=# batch.id})
  call extend(session.drafts, restore)
  if !s:Save(session) | let session.drafts = before | return | endif
  for buf in session.buffers
    if index(map(copy(restore), {_, d -> d.id}), getbufvar(buf, 'revue_draft', '')) >= 0
      call setbufvar(buf, '&modifiable', 1)
    elseif index(map(copy(batch.items), {_, d -> d.id}), getbufvar(buf, 'revue_draft', '')) >= 0
      execute 'silent! bwipeout! ' . buf
    endif
  endfor
  call revue#session#Batch()
  call s:RenderTree(session)
endfunction

" Status-only transitions do not rebuild unchanged rich message buffers.
function! s:RefreshChrome(session) abort
  if index(['discussions', 'activity', 'reanchor'], get(a:session, 'panelkind', '')) >= 0
    call s:RepaintPanel(a:session)
  endif
  redrawstatus
endfunction

function! s:Refresh(session) abort
  if a:session.busy | return | endif
  if get(get(a:session, 'feedback_read', {}), 'loading', 0)
    let a:session.feedback_read.serial += 1
    let a:session.feedback_read.loading = 0
    let a:session.feedback_read.error = ''
  endif
  let a:session.busy = 1
  let a:session.latest_request = get(a:session, 'latest_request', 0) + 1
  let a:session.refresh_read = {'comparison': a:session.snapshot.snapshot, 'generation': a:session.generation,
        \ 'required': revue#refresh#Keys(a:session.snapshot), 'seen': [], 'started': reltime()}
  let a:session.message = 'Refreshing discussions… :ReviewCancelRefresh keeps the current view.'
  let a:session.refresh_state.status = 'refreshing'
  let a:session.refresh_state.error = ''
  call s:RefreshChrome(a:session)
  call s:RenderTree(a:session)
  let incremental = get(get(get(a:session.snapshot, 'capabilities', {}), 'feedback_refresh', {}), 'enabled', 0)
  let a:session.refresh_read.bounded = incremental
  call a:session.Host({'op': 'refresh', 'incremental': incremental ? v:true : v:false},
        \ function('s:RefreshReceived', [a:session.id, a:session.latest_request, '']))
endfunction

function! revue#session#RefreshLabel(id) abort
  let session = get(s:sessions, a:id, {})
  if get(get(session, 'pending_verification', {}), 'loading', 0) | return 'Verifying private review · :ReviewCancelVerifyPending | ' | endif
  let status = get(get(session, 'refresh_state', {}), 'status', '')
  if status ==# 'refreshing' | return 'Refreshing · :ReviewCancelRefresh | ' | endif
  if status ==# 'partial refresh' | return 'Refresh paused · :ReviewContinueRefresh | ' | endif
  if status ==# 'failed' | return 'Refresh failed · :ReviewReviewActions | ' | endif
  if status ==# 'interrupted' | return 'Refresh interrupted · :ReviewRefresh | ' | endif
  return ''
endfunction

function! revue#session#ContinueRefresh() abort
  let session = s:Get()
  if empty(session) || session.busy | return | endif
  let state = get(session, 'refresh_read', {})
  if !has_key(state, 'candidate') | call s:Notice('No refresh is waiting for another page.') | return | endif
  if state.generation != session.generation || state.comparison !=# session.snapshot.snapshot
    call revue#session#CancelRefresh()
    call s:Notice('The comparison changed. Refresh the displayed review again.')
    return
  endif
  let cursor = get(get(state.candidate, 'feedback', {}), 'cursor', '')
  if empty(cursor) | return | endif
  let session.latest_request += 1
  let session.busy = 1
  let state.started = reltime()
  let session.refresh_state.status = 'refreshing'
  let session.refresh_state.error = ''
  let session.message = 'Refreshing next feedback page… :ReviewCancelRefresh keeps the current view.'
  call s:RefreshChrome(session)
  call s:RenderTree(session)
  call session.Host({'op': 'feedback_page', 'cursor': cursor, 'reference': revue#comparisons#Reference(state.candidate)},
        \ function('s:RefreshReceived', [session.id, session.latest_request, cursor]))
endfunction

function! revue#session#CancelRefresh() abort
  let session = s:Get()
  if empty(session) || empty(get(session, 'refresh_read', {})) | return | endif
  let session.latest_request += 1
  let session.busy = 0
  let session.refresh_read = {}
  let session.refresh_state.status = 'cancelled'
  let session.refresh_state.error = ''
  let session.message = 'Refresh cancelled; previously loaded feedback retained. :ReviewRefresh starts again.'
  call s:RefreshChrome(session)
  call s:RenderTree(session)
endfunction

function! s:RefreshReceived(id, epoch, cursor, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) || a:epoch != get(session, 'latest_request', 0) | return | endif
  let state = session.refresh_read
  let session.busy = 0
  let session.refresh_state.read_seconds = reltimefloat(reltime(state.started))
  try
    if state.generation != session.generation || state.comparison !=# session.snapshot.snapshot
      throw 'Comparison changed during refresh. Refresh the displayed review again.'
    endif
    if !get(a:result, 'ok', 0) | throw get(a:result, 'error', 'Review unavailable.') | endif
    if empty(a:cursor)
      if state.bounded
        call revue#refresh#Validate(a:result.data)
        if a:result.data.snapshot ==# state.comparison && (a:result.data.base !=# session.snapshot.base || a:result.data.head !=# session.snapshot.head)
          throw 'Refreshed source identity conflicts with the displayed comparison.'
        endif
      endif
      let state.candidate = deepcopy(a:result.data)
    else
      if index(state.seen, get(get(a:result, 'data', {}), 'next_cursor', '')) >= 0
        throw 'Refresh cursor repeated a previous page. Start a new refresh.'
      endif
      let candidate = revue#feedback#Merge(state.candidate, a:result.data, a:cursor)
      let state.candidate = candidate
      call add(state.seen, a:cursor)
    endif
    if !state.bounded || revue#refresh#Ready(state)
      let result = {'ok': 1, 'data': state.candidate}
      let missing = state.candidate.snapshot ==# state.comparison ? revue#refresh#Missing(state) : 0
      let session.refresh_read = {}
      let started = reltime()
      call s:Refreshed(a:id, a:epoch, result)
      let session.refresh_state.apply_seconds = reltimefloat(reltime(started))
      if missing
        let session.message = printf('Discussions refreshed; %d previously loaded message(s) are no longer reported. Selection uses the nearest available position.', missing)
        call s:RenderTree(session)
      endif
      return
    endif
    let session.refresh_state.status = 'partial refresh'
    let session.refresh_state.error = ''
    let session.message = printf('Fresh page retained separately; %d previously loaded message(s) not reached. :ReviewContinueRefresh reads one more page; :ReviewCancelRefresh keeps the current view.', revue#refresh#Missing(state))
  catch
    let session.refresh_state.status = 'failed'
    let session.refresh_state.error = v:exception
    let session.message = 'Refresh failed; current feedback retained. ' . v:exception
    call revue#activity#Record(session, {'kind': 'refresh'}, 'refresh-failed', v:exception, {})
    call s:Save(session)
  endtry
  call s:RefreshChrome(session)
  call s:RenderTree(session)
endfunction

function! s:Refreshed(id, epoch, result) abort
  let session = get(s:sessions, a:id, {})
  if empty(session) | return | endif
  if a:epoch != get(session, 'latest_request', 0) | return | endif
  let session.busy = 0
  let unchanged = a:result.ok && session.snapshot ==# a:result.data
  let session.refresh_state.at = strftime('%Y-%m-%d %H:%M:%S')
  if !a:result.ok
    let session.message = a:result.error
    let session.refresh_state.status = 'failed'
    let session.refresh_state.error = a:result.error
    call revue#activity#Record(session, {'kind': 'refresh'}, 'refresh-failed', a:result.error, {})
  elseif session.snapshot.snapshot !=# a:result.data.snapshot
    call revue#comparisons#Observe(session, a:result.data)
    call revue#activity#Observe(session, a:result.data)
    let session.message = 'Latest comparison available. :ReviewLatest opens it; :ReviewComparisons shows observed history. Draft anchors are retained.'
    let session.refresh_state.status = 'new revision available'
    let session.refresh_state.latest_comparison = a:result.data.snapshot
    let session.refresh_state.success_at = session.refresh_state.at
    let session.refresh_state.error = ''
  else
    call revue#comparisons#Observe(session, a:result.data)
    call revue#activity#Observe(session, a:result.data)
    let session.snapshot = a:result.data
    let session.message = 'Discussions refreshed.'
    let session.refresh_state.status = 'succeeded'
    let session.refresh_state.success_at = session.refresh_state.at
    let session.refresh_state.error = ''
    if !unchanged
      for buf in session.buffers
        let draft = s:Draft(session, getbufvar(buf, 'revue_draft', ''))
        if !empty(draft) && bufexists(buf) | call s:DraftContext(session, draft, buf) | endif
      endfor
      call s:Annotations(session)
    endif
  endif
  call s:Save(session)
  if unchanged | call s:RefreshChrome(session) | else | call s:RepaintPanel(session) | endif
  call s:RenderTree(session)
  if a:result.ok | call s:CheckViewed(session) | endif
endfunction

function! revue#session#Close() abort
  let session = s:Get()
  if empty(session) | return | endif
  for draft in session.drafts
    if draft.state ==# 'submitting' | call s:Notice('A submission is in progress; wait for its result before closing.') | return | endif
  endfor
  if !s:Save(session) | return | endif
  let session.generation += 1
  let session.closing = 1
  " Close owned windows across reader tabs, retaining user-created splits/tabs.
  for window in reverse(getwininfo())
    if getbufvar(window.bufnr, 'revue_session', '') ==# session.id && win_gotoid(window.winid)
      if winnr('$') > 1 || tabpagenr('$') > 1 | close | else | enew | endif
    endif
  endfor
  for buf in session.buffers
    if bufexists(buf) | execute 'silent! bwipeout! ' . buf | endif
  endfor
  for tab in gettabinfo()
    if gettabvar(tab.tabnr, 'revue_session', '') ==# session.id | call settabvar(tab.tabnr, 'revue_session', '') | endif
    if gettabvar(tab.tabnr, 'revue_reader', '') ==# session.id | call settabvar(tab.tabnr, 'revue_reader', '') | endif
  endfor
  call remove(s:sessions, session.id)
endfunction

function! s:ComparisonAvailability(session, reference) abort
  let latest = a:session.comparisons[a:session.latest_comparison].snapshot
  let rule = get(get(latest, 'capabilities', {}), 'comparisons', {})
  let cached = get(a:session.comparisons, get(a:reference, 'snapshot', ''), {})
  if has_key(cached, 'snapshot') && !get(rule, 'refresh_on_open', 0) | return '' | endif
  return get(rule, 'enabled', 0) ? '' : empty(get(rule, 'reason', '')) ?
        \ 'This backend cannot retrieve this comparison; cached source and drafts are retained.' : rule.reason
endfunction

function! revue#session#ActionGuide() abort
  let session = s:Get()
  if empty(session) | return [] | endif
  let role = get(b:, 'revue_view', get(b:, 'revue_role', ''))
  let snapshot = session.snapshot
  let latest = session.comparisons[session.latest_comparison].snapshot
  let draft = deepcopy(s:Draft(session, get(b:, 'revue_draft', role ==# 'batch' ? get(session, 'batchid', '') : '')))
  if role ==# 'draft' && !empty(draft) && &modifiable | let draft.body = join(getline(1, '$'), "\n") | endif
  let reasons = {}
  let reasons['reanchor-draft'] = revue#reanchor#Error(latest, draft)
  let reasons['reanchor-here'] = s:ReanchorError(session, 1)
  if empty(reasons['reanchor-here'])
    if snapshot.snapshot !=# session.latest_comparison
      let reasons['reanchor-here'] = 'Open the latest comparison first.'
    elseif s:SelectedFile(session) < 0
      let reasons['reanchor-here'] = 'Select a file or source location first.'
    elseif session.reanchor.original.kind ==# 'comment' && (index(['base', 'head'], role) < 0 || get(get(session.loaded, role, {}), 'kind', '') !=# 'text')
      let reasons['reanchor-here'] = 'Select readable source for this line draft.'
    endif
  endif
  let reasons['accept-reanchor'] = s:ReanchorError(session)
  let reasons['cancel-reanchor'] = empty(get(session, 'reanchor', {})) ? 'No draft move is active.' : ''
  let hidden = []
  if role ==# 'reactions'
    let reaction_row = get(get(session, 'reactionrows', {}), string(line('.')), {})
    let reasons.react = empty(reaction_row) ? 'Select a reaction action.' : get(reaction_row, 'reason', '')
  endif
  if !get(get(get(snapshot, 'capabilities', {}), 'assignments', {}), 'enabled', 0) || role ==# 'assignments' | call add(hidden, 'assignments') | endif
  if !get(get(session, 'assignments', {}), 'loading', 0) | call add(hidden, 'cancel-assignments-read') | endif
  if index(['assignments', 'assignment'], role) >= 0
    let assignment = s:AssignmentItem(session)
    let assignment_target = s:AssignmentTarget(session)
    let reasons['open-assignment'] = empty(assignment) ? 'Select an assignment.' : ''
    let reasons['assignment-details'] = reasons['open-assignment']
    let reasons['run-participant'] = empty(assignment) ? 'Select an assignment.' : revue#runtime#CurrentError(latest, assignment, revue#runtime#Fields(latest, assignment))
    let reasons['abandon-run'] = empty(assignment) ? 'Select an assignment.' : revue#runtime#CurrentError(latest, assignment, revue#runtime#Fields(latest, assignment, 1))
    let reasons['cancel-assignment'] = empty(assignment) ? 'Select an assignment.' : assignment.cancelled ? 'This assignment is already cancelled.' :
          \ !get(get(get(snapshot, 'capabilities', {}), 'cancel_assignment', {}), 'enabled', 0) ? 'Cancellation is unavailable.' : ''
    let reasons['assignment-discussion'] = empty(assignment_target) ? 'Select a comment outcome.' : ''
    let reasons['assignment-reply'] = reasons['assignment-discussion']
    let reasons['assignment-comparison'] = empty(assignment) ? 'Select an assignment.' : s:EventComparisonError(session, {'reviewed_comparison': assignment.reference})
    let result_reference = get(get(get(assignment, 'outcomes', {}), get(assignment_target, 'message', ''), {}), 'result_reference', {})
    let reasons['assignment-result'] = empty(result_reference) ? 'Select an outcome with a verified result comparison.' : s:EventComparisonError(session, {'reviewed_comparison': result_reference})
  endif
  let reasons['verify-pending'] = ''
  if role ==# 'pending'
    let selected_review = revue#pending#Find(snapshot, get(get(session.pendingrows, string(line('.')), {}), 'review', ''))
    let reasons['verify-pending'] = empty(selected_review) ? 'Select a private review first.' : get(selected_review, 'complete', 1) ? 'The complete private review is already loaded.' : ''
    if !get(get(get(snapshot, 'capabilities', {}), 'verify_pending', {}), 'enabled', 0) | call add(hidden, 'verify-pending') | endif
    if get(get(session, 'pending_verification', {}), 'loading', 0) | let reasons['verify-pending'] = 'Verification is already running.' | endif
  endif
  if !get(get(session, 'pending_verification', {}), 'loading', 0) | call add(hidden, 'cancel-verify-pending') | endif
  let reasons['continue-refresh'] = session.busy ? 'A refresh read is already running.' : ''
  if !has_key(get(session, 'refresh_read', {}), 'candidate') | call add(hidden, 'continue-refresh') | endif
  if empty(get(session, 'refresh_read', {})) | call add(hidden, 'cancel-refresh') | endif
  if empty(get(session, 'reanchor', {})) | call extend(hidden, ['cancel-reanchor', 'reanchor-here']) | endif
  if role ==# 'conversation' | call add(hidden, 'conversation') | endif
  if !get(get(get(snapshot, 'capabilities', {}), 'assignment', {}), 'enabled', 0) || role ==# 'assignment-selection' | call add(hidden, 'assign') | endif
  let reasons.assign = snapshot.snapshot !=# session.latest_comparison ? 'Open the latest comparison first.' : ''
  let reasons['assignment-prepare'] = empty(revue#assignment#Participants()) ? 'Configure g:revue_participants with stable id and label entries.' : empty(get(get(session, 'assignment_selection', {}), 'selected', {})) ? 'Select at least one message.' : ''
  let reasons['load-more-feedback'] = revue#feedback#Availability(session)
  if !get(get(session, 'feedback_read', {}), 'loading', 0) | call add(hidden, 'cancel-feedback') | endif
  if !get(get(get(session.snapshot, 'capabilities', {}), 'feedback_page', {}), 'enabled', 0)
    call add(hidden, 'load-more-feedback')
  endif
  let reasons['service-progress'] = revue#service_progress#Reason(session)
  if role ==# 'service-progress'
    let progress = session.service_progress
    for id in ['mark-service-viewed', 'unmark-service-viewed']
      let reasons[id] = !empty(reasons['service-progress']) ? reasons['service-progress'] : progress.loading || !empty(progress.error) || empty(progress.data) ? 'Load current personal service progress first.' : ''
    endfor
    let uncertain = filter(copy(session.drafts), {_, d -> d.kind ==# 'service_viewed' && d.path ==# progress.path && d.state ==# 'unknown'})
    let reasons['check-service-viewed'] = empty(uncertain) ? 'No uncertain service Viewed operation for this file.' : ''
  endif
  let reasons.readiness = revue#readiness#Reason(session)
  if role ==# 'readiness'
    call add(hidden, 'readiness')
    let ready = session.readiness
    let reasons['reload-readiness'] = ready.loading ? 'Readiness is already loading.' : reasons.readiness
    let reasons['more-checks'] = ready.loading ? 'Readiness is already loading.' : !empty(reasons.readiness) ? reasons.readiness : empty(ready.data) || ready.data.complete ? 'No more check pages; reload for fresh observations.' : ''
    if !ready.loading | call add(hidden, 'cancel-readiness') | endif
    let url = get(get(session.readinessrows, string(line('.')), {}), 'url', '')
    let reasons['readiness-link'] = revue#links#IsWeb(url) ? '' : 'Select an item with a web link.'
    let reasons['copy-readiness-link'] = reasons['readiness-link']
  endif
  let reasons.timeline = get(get(get(latest, 'capabilities', {}), 'timeline', {}), 'enabled', 0) ? '' :
        \ get(get(get(latest, 'capabilities', {}), 'timeline', {}), 'reason', 'This backend does not provide review history.')
  if !get(get(get(latest, 'capabilities', {}), 'timeline', {}), 'enabled', 0) && empty(reasons.timeline)
    let reasons.timeline = 'This backend does not provide review history.'
  endif
  if role ==# 'timeline'
    call add(hidden, 'timeline')
    let event = s:TimelineEvent(session)
    let reasons['event-discussion'] = s:EventDiscussionError(session, event)
    let reasons['event-comparison'] = s:EventComparisonError(session, event)
    if empty(get(event, 'target', {})) || empty(reasons['event-discussion'])
      call add(hidden, 'load-event-discussion')
    else
      let reasons['load-event-discussion'] = revue#feedback#LookupSupported(snapshot, event.target) ? revue#feedback#LookupAvailability(session) : revue#feedback#Availability(session)
    endif
    let reasons['event-link'] = revue#links#IsWeb(get(event, 'url', '')) ? '' : 'Select an event with a web link.'
    let reasons['copy-event-link'] = reasons['event-link']
    let reasons['older-events'] = session.timeline.loading ? 'History is already loading.' : session.timeline.complete ? 'Oldest available event reached.' : reasons.timeline
    let reasons['reload-timeline'] = reasons.timeline
    if !session.timeline.loading | call add(hidden, 'cancel-timeline') | endif
  endif
  if empty(get(session, 'context_return', {})) | call add(hidden, 'return-context') | endif
  let pending_viewed = 0
  if role ==# 'comparisons' | call add(hidden, 'comparisons') | endif
  if snapshot.snapshot ==# session.latest_comparison | call add(hidden, 'latest') | endif
  let reasons.latest = s:ComparisonAvailability(session, session.comparisons[session.latest_comparison].reference)
  if empty(get(session, 'previous_comparison', '')) || session.previous_comparison ==# snapshot.snapshot
    call add(hidden, 'previous-comparison')
  else
    let reasons['previous-comparison'] = s:ComparisonAvailability(session, session.comparisons[session.previous_comparison].reference)
  endif
  if empty(draft) | call add(hidden, 'draft-comparison') | endif
  if role ==# 'comparisons'
    let comparison = get(session.comparisonrows, string(line('.')), '')
    let range_rule = get(get(latest, 'capabilities', {}), 'comparison_range', {})
    if empty(range_rule) && empty(session.range_selection)
      call extend(hidden, ['range-start', 'range-end', 'open-range', 'clear-range'])
    else
      let range_reason = !get(range_rule, 'enabled', 0) ? (empty(get(range_rule, 'reason', '')) ? 'This backend does not support range selection.' : range_rule.reason) :
            \ empty(comparison) ? 'Select a comparison first.' : (has_key(session.comparisons[comparison].reference, 'range') || has_key(session.comparisons[comparison].reference, 'context')) ? 'Choose an original comparison, not a derived range or code context.' :
            \ index(get(range_rule, 'sides', []), 'head') < 0 ? 'Use the endpoint command with a supported side.' : ''
      let reasons['range-start'] = range_reason
      let reasons['range-end'] = range_reason
      let reasons['open-range'] = s:RangeError(session)
      if empty(session.range_selection) | call add(hidden, 'clear-range') | endif
    endif
    if empty(comparison)
      let reasons['open-comparison'] = 'Select a comparison first.'
    else
      let reasons['open-comparison'] = s:ComparisonAvailability(session, session.comparisons[comparison].reference)
    endif
    let history = get(get(latest, 'capabilities', {}), 'comparisons', {})
    let reasons['load-history'] = get(session, 'history_busy', 0) ? 'Comparison history is already loading.' :
          \ get(history, 'enabled', 0) ? '' : get(history, 'reason', 'This backend does not provide comparison history.')
    if !get(history, 'enabled', 0) && empty(reasons['load-history'])
      let reasons['load-history'] = 'This backend does not provide comparison history.'
    endif
  endif
  if !empty(draft) | let reasons['draft-comparison'] = s:ComparisonAvailability(session, revue#comparisons#Reference(draft)) | endif
  if index(['files', 'base', 'head'], role) >= 0
    let file_index = s:SelectedFile(session)
    if file_index < 0
      let reasons.viewed = 'Select a file first.'
      call add(hidden, 'unviewed')
    else
      let progress = revue#progress#State(session, snapshot, snapshot.files[file_index])
      let progress_key = json_encode([snapshot.snapshot, snapshot.files[file_index].id])
      let pending_viewed = get(get(get(session, 'progress_queue', {}), progress_key, {}), 'action', -1) == 1
      call add(hidden, progress ==# 'viewed' || pending_viewed ? 'viewed' : 'unviewed')
    endif
    let unverified = filter(copy(snapshot.files), {_, f -> index(['checking', 'unavailable'], revue#progress#State(session, snapshot, f)) >= 0})
    if empty(unverified) | call add(hidden, 'verify-viewed') | endif
  endif
  let selected = revue#discussion#Selected(session, line('.'))
  let thread = get(selected, 'thread', '')
  if role ==# 'threads'
    let original = filter(copy(snapshot.threads), {_, t -> t.id ==# get(session.threadmap, string(line('.')), '')})
    let reasons['thread-comparison'] = empty(original) ? 'Select a discussion first.' :
          \ empty(get(original[0], 'original_comparison', {})) ? 'This backend does not provide the original comparison; the discussion retains available context.' : s:ComparisonAvailability(session, original[0].original_comparison)
    if !empty(original) && empty(get(original[0], 'original_comparison', {})) && get(get(get(latest, 'capabilities', {}), 'thread_context', {}), 'enabled', 0)
      let source = get(original[0], 'original_source', {})
      let reasons['thread-comparison'] = get(source, 'available', 0) && !empty(get(source, 'token', '')) ? '' : empty(get(source, 'reason', '')) ? 'Original source is unavailable.' : source.reason
    endif
  endif
  let private_reply = get(get(selected, 'message', {}), 'publication', '') ==# 'pending'
  if index(['base', 'head'], role) >= 0
    let matches = s:ThreadsAtCursor(session)
    let thread = len(matches) == 1 ? matches[0].id : ''
    if empty(matches)
      let reasons.thread = empty(get(get(snapshot, 'feedback', {}), 'cursor', '')) ? 'No discussion at this line.' :
            \ 'No loaded discussion at this line. Load more review feedback first.'
    endif
  endif
  let state_thread = role ==# 'threads' ? get(session.threadmap, string(line('.')), '') : thread
  let state_operation = revue#thread_state#Pending(session, state_thread)
  for [state_action, state_value] in [['resolve', v:true], ['reopen', v:false]]
    let reasons[state_action] = empty(state_thread) ? 'Select one thread first.' : !empty(state_operation) && (state_operation.state ==# 'unknown' || state_operation.state ==# 'submitting' || state_operation.resolved != state_value) ? revue#thread_state#Status(state_operation) :
          \ revue#capabilities#Error(snapshot, {'kind': 'thread_state', 'thread': state_thread, 'resolved': state_value}, 0)
  endfor
  if empty(state_operation) || state_operation.state !=# 'unknown' | call add(hidden, 'check-thread-state') | endif
  let apply_target = {'thread': get(selected, 'thread', ''), 'message': get(selected, 'comment', ''), 'message_kind': get(selected, 'kind', ''), 'expected_version': get(get(selected, 'message', {}), 'version', '')}
  let reasons['apply-suggestion'] = empty(selected) ? 'Select a suggestion message.' : revue#apply_suggestion#Error(snapshot, apply_target)
  let reasons['message-history'] = empty(selected) ? 'Select a message first.' : s:MessageHistoryError(session, selected.message)
  if role ==# 'message-history'
    let history = session.message_history
    let reasons['older-message-edits'] = history.loading ? 'Edit history is already loading.' : history.complete ? 'All reported entries are loaded.' : ''
    let reasons['history-message-link'] = revue#links#IsWeb(history.url) ? '' : 'This message has no web link.'
    if !history.loading | call add(hidden, 'cancel-message-history') | endif
  endif
  if empty(selected) | let reasons.actions = 'Select a message first.' | endif
  if empty(thread)
    let reasons.reply = 'Select a discussion first; overlapping threads use the discussion list.'
    let reasons['reply-pending'] = reasons.reply
  else
    let private_reply = private_reply || revue#pending#PrivateThread(snapshot, thread)
    let reasons.reply = revue#capabilities#Error(snapshot, {'kind': 'reply', 'thread': thread}, 0)
    let fields = revue#pending#ReplyFields(snapshot, thread)
    let reasons['reply-pending'] = has_key(fields, 'error') ? fields.error : revue#capabilities#Error(snapshot, fields, 0)
    if private_reply | let reasons.reply = reasons['reply-pending'] | endif
  endif
  for [action, kind] in [['comment', 'comment'], ['file-comment', 'file_comment'], ['new-conversation', 'conversation']]
    let reasons[action] = revue#capabilities#Error(snapshot, {'kind': kind}, 0)
  endfor
  let reasons.suggest = get(get(get(snapshot, 'capabilities', {}), 'suggestion', {}), 'enabled', 0) ? reasons.comment : 'This backend does not support creating suggestions.'
  if role ==# 'base' | let reasons.suggest = 'Select source on the head side to suggest a replacement.' | endif
  if s:SelectedFile(session) < 0 | let reasons['file-comment'] = 'Select a file first.' | endif
  let rules = get(snapshot, 'capabilities', {})
  let reasons.batch = get(get(rules, 'batch', {}), 'enabled', 0) ? '' : get(get(rules, 'batch', {}), 'reason', 'This backend does not support review batches.')
  let delete_target = s:DeleteTarget(session)
  let reasons['delete-message'] = empty(delete_target) ? 'Select a published message first.' : revue#capabilities#Error(latest, revue#delete_message#Fields(snapshot, delete_target), 0)
  let reasons['delete-pending-comment'] = empty(delete_target) ? 'Select an individual private comment first.' : revue#capabilities#Error(latest, revue#delete#Fields(snapshot, delete_target), 0)
  let reasons['stage-batch'] = revue#stage#Availability(snapshot)
  let decisions = filter(copy(get(snapshot, 'review_actions', [])), {_, r -> revue#capabilities#Rule(snapshot, {'kind': 'review', 'event': r.id}).enabled})
  let reasons.review = empty(decisions) ? 'No review decision is currently available.' : ''
  let inventory = get(snapshot, 'pending_reviews', {})
  let reasons['start-pending'] = revue#capabilities#Error(snapshot, {'kind': 'start_pending', 'pending_mode': 'create', 'actor': get(inventory, 'actor', '')}, 0)
  if !get(inventory, 'available', 0) | let reasons.pending = get(inventory, 'error', 'Private review state is unavailable; refresh to check it.') | endif
  if role ==# 'pending'
    let row = get(session.pendingrows, string(line('.')), {})
    if empty(get(row, 'target', {})) | let reasons['open-pending'] = 'Select a private comment first.' | endif
    for [action, capability] in [['edit-pending', 'edit_pending'], ['publish-pending', 'submit_pending'], ['discard-pending', 'discard_pending']]
      let rule = get(rules, capability, {})
      let reasons[action] = empty(row) ? 'Select a private review or comment first.' : get(rule, 'enabled', 0) ? '' : get(rule, 'reason', 'This action is unavailable.')
    endfor
    let pending_review = revue#pending#Find(snapshot, get(row, 'review', ''))
    if !empty(pending_review) && !get(pending_review, 'complete', 1)
      for action in ['publish-pending', 'discard-pending'] | let reasons[action] = revue#pending#CompleteError(pending_review) | endfor
      if empty(get(row, 'target', {})) | let reasons['edit-pending'] = 'Verify the complete review before editing its summary.' | endif
    endif
  endif
  if !empty(draft)
    let reasons.send = draft.state ==# 'unknown' ? '' : draft.state ==# 'submitting' ? 'This operation is already submitting.' : s:SubmissionError(session, draft)
    if index(['comment', 'file_comment', 'reply'], draft.kind) >= 0
      let inventory = get(latest, 'pending_reviews', {})
      let reviews = get(inventory, 'items', [])
      let review = get(reviews, 0, {})
      let proposed = extend(deepcopy(draft), {'pending_mode': empty(review) ? 'create' : 'add', 'pending_review': get(review, 'id', ''), 'pending_head': get(review, 'head', ''), 'actor': get(inventory, 'actor', '')})
      let reasons['save-pending'] = index(['draft', 'failed'], draft.state) < 0 ? 'This operation is frozen; check its receipt.' : len(reviews) > 1 ? 'Inspect the available private reviews before saving.' : s:SubmissionError(session, proposed)
    endif
  endif
  if role ==# 'batch'
    let items = filter(deepcopy(session.drafts), {_, d -> d.kind !=# 'batch' && get(session.batchselected, d.id, 0)})
    let reasons['batch-send'] = !empty(draft) && draft.state ==# 'unknown' ? '' : revue#batch#Error(snapshot, empty(draft) ? items : draft.items)
    if get(session, 'batch_delivery', '') ==# 'private'
      let reasons['batch-send'] = empty(draft) ? revue#stage#Error(snapshot, items, revue#stage#Binding(snapshot)) : draft.state ==# 'unknown' ? '' : draft.state ==# 'submitting' ? 'Private saves are already running.' : s:StagePermission(session, draft)
    endif
  endif
  if revue#local_feedback#Enabled(session)
    let reasons.batch = ''
    if revue#local_feedback#IsFeedback(draft) && index(['draft', 'failed'], get(draft, 'state', '')) >= 0 | let reasons.send = '' | endif
  else
    call extend(hidden, ['export', 'edit-feedback', 'toggle-feedback', 'select-feedback', 'clear-feedback', 'export-markdown'])
  endif
  let context = {'role': role, 'snapshot': snapshot, 'draft': draft, 'bindings': get(b:, 'revue_bindings', []), 'reasons': reasons, 'hidden': hidden}
  let items = revue#actions#Items(context)
  for item in items
    if index(['run-participant', 'abandon-run'], item.id) >= 0 && !empty(assignment)
      let item.label = revue#runtime#Label(revue#runtime#Fields(latest, assignment, item.id ==# 'abandon-run'))
      for existing in session.drafts
        if existing.kind ==# 'participant_run' && existing.assignment ==# assignment.id
          let item.label = existing.state ==# 'unknown' ? 'Check participant launch outcome' : 'Continue saved participant operation'
          let item.reason = ''
          break
        endif
      endfor
    endif
    if item.id ==# 'batch' && revue#local_feedback#Enabled(session) | let item.label = 'Collect feedback for export' | endif
    if item.id ==# 'load-event-discussion' && role ==# 'timeline' && revue#feedback#LookupSupported(snapshot, get(event, 'target', {})) | let item.label = 'Fetch this event’s complete discussion and open it' | endif
    if item.id ==# 'react' && role ==# 'reactions' && !empty(reaction_row) | let item.label = reaction_row.action_label | endif
    if item.id ==# 'unviewed' && pending_viewed | let item.label = 'Cancel this file’s pending Viewed mark' | endif
    if item.id ==# 'reply' && private_reply | let item.label = 'Compose a private reply' | endif
    if index(['reply', 'reply-pending'], item.id) >= 0 && !empty(thread)
      for existing in session.drafts
        if existing.kind ==# 'reply' && existing.thread ==# thread && (item.id ==# 'reply-pending' || private_reply || !empty(get(existing, 'pending_mode', '')))
          let item.label = 'Continue existing reply; inspect delivery mode'
          let item.reason = ''
          break
        endif
      endfor
    endif
    if item.id ==# 'batch-send' && get(draft, 'state', '') ==# 'unknown' | let item.label = 'Check batch receipt; do not resend' | endif
    if item.id ==# 'batch-send' && get(session, 'batch_delivery', '') ==# 'private' && get(draft, 'state', '') !=# 'unknown' | let item.label = 'Save remaining items privately (confirmation)' | endif
  endfor
  return items
endfunction

function! s:ActionGuard(session) abort
  " An input prompt can run timers. Freeze identity and state, not a row number.
  return deepcopy({'window': win_getid(), 'buffer': bufnr(), 'position': getcurpos(),
        \ 'tick': b:changedtick, 'role': get(b:, 'revue_view', get(b:, 'revue_role', '')),
        \ 'session': a:session.id, 'snapshot': a:session.snapshot,
        \ 'latest': a:session.comparisons[a:session.latest_comparison].snapshot,
        \ 'reanchor': get(a:session, 'reanchor', {}), 'drafts': a:session.drafts, 'batch': get(a:session, 'batchselected', {}),
        \ 'comparison_references': map(copy(a:session.comparisons), {_, entry -> get(entry, 'reference', {})}),
        \ 'previous_comparison': get(a:session, 'previous_comparison', ''),
        \ 'comparison_target': get(get(a:session, 'comparisonrows', {}), string(line('.')), ''),
        \ 'file_index': a:session.index, 'file_target': get(a:session.rows, string(line('.')), {}),
        \ 'progress': a:session.progress,
        \ 'progress_intent': map(copy(get(a:session, 'progress_queue', {})), {_, task -> task.action}),
        \ 'range_selection': get(a:session, 'range_selection', {}),
        \ 'message_history': get(a:session, 'message_history', {}),
        \ 'readiness': get(a:session, 'readiness', {}),
        \ 'pending_verification': get(a:session, 'pending_verification', {}), 'refresh_read': get(a:session, 'refresh_read', {}), 'timeline': get(a:session, 'timeline', {}), 'feedback_read': get(a:session, 'feedback_read', {}),
        \ 'bindings': get(b:, 'revue_bindings', [])})
endfunction

function! revue#session#ReviewActions() abort
  let session = s:Get()
  if empty(session) | return | endif
  let items = revue#session#ActionGuide()
  let guard = s:ActionGuard(session)
  let selected = revue#discussion#Selected(session, line('.'))
  let target = empty(selected) ? '' : 'Selected message: ' . revue#message#Header(selected.message, session.snapshot.author)
  if empty(target) && index(['files', 'base', 'head'], get(b:, 'revue_role', '')) >= 0
    let file_index = s:SelectedFile(session)
    if file_index >= 0 | let target = 'File: ' . session.snapshot.files[file_index].path | endif
  elseif get(b:, 'revue_view', '') ==# 'comparisons'
    let id = get(session.comparisonrows, string(line('.')), '')
    if has_key(session.comparisons, id)
      let reference = session.comparisons[id].reference
      let target = 'Comparison: ' . get(reference, 'base', '?') . ' → ' . get(reference, 'head', '?')
    endif
  endif
  let draft = s:Draft(session, get(b:, 'revue_draft', ''))
  if !empty(draft)
    let target = 'Draft: ' . revue#suggestion#Label(draft) . ' · ' . get(draft, 'path', get(draft, 'thread', 'review'))
    if !empty(get(draft, 'pending_review', '')) | let target .= ' · private review #' . draft.pending_review | endif
  endif
  let menu = [s:Label(session.snapshot) . ' · ' . revue#message#OneLine(session.snapshot.title),
        \ revue#message#OneLine(target), 'Review actions · 0 cancels'] + revue#actions#Lines(items, 1)
  let choice = inputlist(menu) - 1
  if choice < 0 || choice >= len(items) | return | endif
  if empty(s:Get()) || guard !=# s:ActionGuard(s:Get())
    call s:Notice('The review or selection changed; choose the action again.')
    return
  endif
  let current = revue#session#ActionGuide()
  if current !=# items | call s:Notice('Available actions changed; choose again.') | return | endif
  if !empty(items[choice].reason) | call s:Notice(items[choice].reason) | return | endif
  " Commands come only from the registered bindings (or the built-in :write).
  execute items[choice].command
endfunction

function! revue#session#Help() abort
  let session = s:Get()
  if empty(session) | return | endif
  let origin = get(b:, 'revue_view', '') ==# 'help' ? get(b:, 'revue_origin', {}) : s:Origin()
  let bindings = revue#maps#Help()
  let guide = revue#actions#Lines(revue#session#ActionGuide(), 0)
  let role = get(b:, 'revue_view', get(b:, 'revue_role', 'review'))
  call s:Fill(s:Panel(session, 'help'), ['# Revue help: ' . role, ':ReviewReviewActions opens the action chooser from your working view.'] + guide + ['', 'All commands and configured bindings:'] + bindings + [
        \ '', 'Inline discussions remain expanded. ]c / [c retain native diff navigation.',
        \ 'Use / and ? to search. :w saves locally; :ReviewSend saves pending local feedback or confirms provider delivery.',
        \ ':ReviewClose returns to the originating view. Drafts survive reopening.',
        \ 'Set g:revue_no_default_mappings = 1 to use only commands and Plug mappings.',
        \ 'Customize action keys with g:revue_mappings (see :help revue).',
        \ 'An unknown write outcome is retained; sending again checks receipts.'])
  let b:revue_origin = origin
endfunction

function! revue#session#Inspect(id) abort
  " Read-only diagnostic snapshot, also used by integration tests.
  let session = get(s:sessions, a:id, {})
  if empty(session) | return {} | endif
  let result = copy(session)
  call remove(result, 'Host')
  return deepcopy(result)
endfunction
