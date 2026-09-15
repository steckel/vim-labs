" Reading tabs retain the original review windows instead of reconstructing them.
function! revue#layout#Exists(window) abort
  return a:window > 0 && win_id2tabwin(a:window)[0] > 0
endfunction

function! revue#layout#Get(window, name, ...) abort
  let position = win_id2tabwin(a:window)
  return position[0] ? gettabwinvar(position[0], position[1], a:name, a:0 ? a:1 : '') : (a:0 ? a:1 : '')
endfunction

function! revue#layout#Set(window, name, value) abort
  let position = win_id2tabwin(a:window)
  if position[0] | call settabwinvar(position[0], position[1], a:name, a:value) | endif
endfunction

function! revue#layout#BufferWindow(buffer) abort
  let windows = win_findbuf(a:buffer)
  return empty(windows) ? -1 : windows[0]
endfunction

function! revue#layout#New(session, height) abort
  let mode = get(g:, 'revue_reading_layout', 'auto')
  let reader = mode ==# 'tab' || (mode ==# 'auto' && (revue#layout#Narrow() || get(t:, 'revue_reader', '') ==# a:session.id))
  call revue#layout#Unfocus(a:session)
  let layout = revue#layout#Capture()
  if reader
    tabnew
    let t:revue_reader = a:session.id
    let t:revue_session = a:session.id
  else
    execute 'botright ' . a:height . 'new'
  endif
  let w:revue_previous_layout = layout
endfunction

" Window sizing preserves buffers, source coordinates, and window IDs.
function! revue#layout#Capture() abort
  let windows = []
  for info in getwininfo()
    if info.tabnr == tabpagenr()
      call add(windows, {'id': info.winid, 'width': info.width, 'height': info.height})
    endif
  endfor
  return {'tree': winlayout(), 'command': winrestcmd(), 'windows': windows,
        \ 'columns': &columns, 'lines': &lines}
endfunction

function! revue#layout#Restore(layout) abort
  if empty(a:layout) || empty(a:layout.windows) | return 0 | endif
  let anchor = a:layout.windows[0].id
  let tab = win_id2tabwin(anchor)[0]
  if !tab || winlayout(tab) != a:layout.tree | return 0 | endif
  if tab != tabpagenr()
    call win_execute(anchor, 'call revue#layout#Restore(' . string(a:layout) . ')')
    return 1
  endif
  let current = win_getid()
  if &columns == a:layout.columns && &lines == a:layout.lines
    execute a:layout.command
  else
    " Fit saved proportions to the current terminal rather than restoring stale
    " absolute sizes after a phone/desktop resize.
    for window in a:layout.windows
      if win_gotoid(window.id)
        execute 'vertical resize ' . max([1, window.width * &columns / a:layout.columns])
        execute 'resize ' . max([1, window.height * &lines / a:layout.lines])
      endif
    endfor
  endif
  call win_gotoid(current)
  return 1
endfunction

function! revue#layout#Unfocus(session) abort
  if !has_key(a:session, 'focus_layout') | return 1 | endif
  let layout = remove(a:session, 'focus_layout')
  let a:session.focus_win = 0
  call s:FocusBars(a:session, 0)
  return revue#layout#Restore(layout)
endfunction

function! revue#layout#Focus(session) abort
  let target = win_getid()
  if get(a:session, 'focus_win', 0) == target
    call revue#layout#Unfocus(a:session)
    return
  endif
  call revue#layout#Unfocus(a:session)
  let a:session.focus_layout = revue#layout#Capture()
  let a:session.focus_win = target
  call s:FocusBars(a:session, target)
  wincmd _
  wincmd |
endfunction

function! s:FocusBars(session, target) abort
  for info in getwininfo()
    if getbufvar(info.bufnr, 'revue_session', '') ==# a:session.id
      call revue#layout#Set(info.winid, 'revue_focus_target', a:target)
    endif
  endfor
endfunction

function! revue#layout#SetBar(window, text) abort
  highlight default link RevueQuietBar Normal
  " string() quotes paths and labels as data inside the statusline expression.
  call revue#layout#Set(a:window, '&statusline', '%!revue#layout#Bar(' . string(a:text) . ')')
endfunction

function! revue#layout#Bar(text) abort
  let window = get(g:, 'statusline_winid', win_getid())
  let target = revue#layout#Get(window, 'revue_focus_target', 0)
  let info = getwininfo(window)
  if target && target != window && !empty(info) && (info[0].height <= 1 || info[0].width <= 3)
    return '%#RevueQuietBar# '
  endif
  let refresh = revue#session#RefreshLabel(getbufvar(winbufnr(window), 'revue_session', ''))
  if !empty(refresh) && !empty(info) && strdisplaywidth(refresh . a:text) > info[0].width
    return refresh . getbufvar(winbufnr(window), 'revue_view', getbufvar(winbufnr(window), 'revue_role', 'review'))
  endif
  return refresh . a:text
endfunction

function! revue#layout#Narrow() abort
  return get(g:, 'revue_auto_focus', 1) && (&columns < get(g:, 'revue_narrow_columns', 120) || &lines < 32)
endfunction

function! revue#layout#ReplaceWindow(layout, old, new) abort
  if empty(a:layout) | return | endif
  call s:Replace(a:layout.tree, a:old, a:new)
  for window in a:layout.windows
    if window.id == a:old | let window.id = a:new | endif
  endfor
endfunction

function! s:Replace(tree, old, new) abort
  if a:tree[0] ==# 'leaf'
    if a:tree[1] == a:old | let a:tree[1] = a:new | endif
  else
    for child in a:tree[1] | call s:Replace(child, a:old, a:new) | endfor
  endif
endfunction
