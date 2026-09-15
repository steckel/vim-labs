set nocompatible nomore laststatus=2
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = tempname()
let g:revue_reading_layout = 'auto'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.threads[0].comments[2].body .= "\n\n" . repeat("Long discussion line for scroll coverage.\n", 80) . 'END OF LONG DISCUSSION'
let g:mutations = 0
function! LayoutHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  elseif a:request.op ==# 'refresh'
    let g:RefreshDone = a:Done
  else
    let g:mutations += 1
    throw 'Layout fixture cannot publish'
  endif
endfunction
function! Sizes() abort
  return map(filter(getwininfo(), {_, w -> w.tabnr == tabpagenr()}), {_, w -> [w.width, w.height]})
endfunction
function! TypingRefresh(timer) abort
  try
    let g:typing_before = [mode(1), win_getid(), bufnr()]
    call g:RefreshDone({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
    let g:typing_after = [mode(1), win_getid(), bufnr()]
  finally
    call feedkeys("\<Esc>", 'n')
  endtry
endfunction
try
  set columns=80 lines=24
  let initial_tab_count = tabpagenr('$')
  let user_window = win_getid()
  call setline(1, 'User workspace stays open')
  let user_buffer = bufnr()
  let id = revue#session#Open(g:fixture.snapshot, function('LayoutHost'), 0)
  RevueRestoreLayout
  let source = revue#session#Inspect(id)
  botright new
  call setline(1, 'User split inside the review')
  let extra_window = win_getid()
  let extra_buffer = bufnr()
  call win_gotoid(source.headwin)
  call cursor(3, 3)
  let source_sizes = Sizes()
  let source_tree = winlayout()
  let source_tab = tabpagenr()
  call setreg('a', 'Register remains native')
  RevueThread
  let reader = win_getid()
  call assert_equal('Discussion', expand('%:t'))
  call assert_equal(1, winnr('$'))
  call assert_true(winheight(0) >= 21, string(winheight(0)))
  call assert_equal(80, winwidth(0))
  call assert_notequal(source_tab, tabpagenr())
  call assert_equal(source_tree, winlayout(source_tab))
  call assert_equal(source.basewin, revue#session#Inspect(id).basewin)
  call assert_equal(source.headwin, revue#session#Inspect(id).headwin)
  RevueFiles
  call assert_equal(reader, win_getid())
  call assert_equal(0, revue#session#Inspect(id).treewin)
  RevueFiles
  call assert_equal(reader, win_getid())
  call assert_equal(1, winnr('$'))
  let source_tree = winlayout(source_tab)
  call search('END OF LONG DISCUSSION', 'W')
  normal! zz
  let selected = revue#discussion#Selected(revue#session#Inspect(id), line('.')).comment
  call assert_equal('local-reply-2', selected)
  RevueReply
  let composer = win_getid()
  call assert_equal('Reply', expand('%:t'))
  call setline(1, ['Draft in the full-area editor', 'Exact Unicode: λ界'])
  let draft_buffer = bufnr()
  call assert_equal(1, winnr('$'))
  call assert_true(winheight(0) >= 21)
  " Refresh while the reader is hidden must not switch tabs or move typing.
  RevueRefresh
  let earlier = deepcopy(g:fixture.snapshot.threads[0].comments[1])
  let earlier.id = 'earlier-reply'
  let earlier.body = 'An earlier inserted reply'
  call insert(g:fixture.snapshot.threads[0].comments, earlier, 1)
  call g:RefreshDone({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  call assert_equal(composer, win_getid())
  call assert_equal(['Draft in the full-area editor', 'Exact Unicode: λ界'], getline(1, '$'))
  call assert_match('An earlier inserted reply', join(getbufline(winbufnr(reader), 1, '$'), "\n"))
  " The hidden-window repaint must preserve actual Insert mode, not only text.
  RevueRefresh
  let g:fixture.snapshot.threads[0].comments[1].body .= ' (updated while typing)'
  call cursor(1, 1)
  call timer_start(30, function('TypingRefresh'))
  call feedkeys('A typed during refresh', 'xt!')
  call assert_match('^i', g:typing_before[0])
  call assert_equal(g:typing_before, g:typing_after)
  call assert_equal(composer, win_getid())
  call assert_equal('Draft in the full-area editor typed during refresh', getline(1))
  RevuePreview
  call assert_equal('Preview', expand('%:t'))
  call assert_equal(1, winnr('$'))
  call assert_true(winheight(0) >= 21)
  call assert_match('Exact Unicode: λ界', join(getline(1, '$'), "\n"))
  RevueClose
  call assert_equal(composer, win_getid())
  RevueClose
  call assert_equal(reader, win_getid())
  call assert_equal(selected, revue#discussion#Selected(revue#session#Inspect(id), line('.')).comment)
  call assert_true(search('An earlier inserted reply', 'bnW') > 0)
  call assert_equal(1, winnr('$'))
  RevueClose
  call assert_equal(source.headwin, win_getid())
  call assert_equal(source_tree, winlayout())
  call assert_equal(source_sizes, Sizes())
  call assert_equal(3, line('.'))
  call assert_equal('Register remains native', getreg('a'))
  " Following source and reopening the reader reuses original windows.
  RevueThread
  let reader = win_getid()
  call revue#session#Next(0)
  call assert_equal(source.headwin, win_getid())
  call assert_equal(source_tree, winlayout())
  RevueThread
  call assert_equal(reader, win_getid())
  call assert_equal(1, winnr('$'))
  " Reopen an existing draft from another tab without creating a duplicate.
  RevueQuote
  let composer = win_getid()
  let draft = bufnr()
  call win_gotoid(reader)
  RevueQuote
  call assert_equal(composer, win_getid())
  call assert_equal(draft, bufnr())
  RevueClose
  " A user split in a reader tab must survive Close and session cleanup.
  belowright new
  call setline(1, 'User notes in the reader tab')
  let reader_notes_window = win_getid()
  let reader_notes_buffer = bufnr()
  call win_gotoid(reader)
  RevueClose
  call assert_equal(source.headwin, win_getid())
  call assert_true(revue#layout#Exists(reader_notes_window))
  call assert_equal(['User notes in the reader tab'], getbufline(reader_notes_buffer, 1, '$'))
  call revue#session#Close()
  call assert_true(revue#layout#Exists(user_window))
  call assert_true(revue#layout#Exists(extra_window))
  call assert_true(revue#layout#Exists(reader_notes_window))
  call assert_equal(['User workspace stays open'], getbufline(user_buffer, 1, '$'))
  call assert_equal(['User split inside the review'], getbufline(extra_buffer, 1, '$'))
  call assert_equal(initial_tab_count + 2, tabpagenr('$'), 'Only user tabs remain')
  " Opting out keeps conventional splits; explicit tab mode still works.
  let g:revue_auto_focus = 0
  set columns=120 lines=40
  let id = revue#session#Open(g:fixture.snapshot, function('LayoutHost'), 0)
  let source_tab = tabpagenr()
  RevueThread
  call assert_equal(source_tab, tabpagenr())
  call assert_true(winnr('$') > 1)
  RevueClose
  let g:revue_reading_layout = 'tab'
  RevueThread
  call assert_equal(1, winnr('$'))
  RevueRestoreLayout
  call assert_equal(source_tab, tabpagenr())
  RevueThread
  execute 'tabclose ' . source_tab
  call assert_equal('threads', b:revue_view)
  RevueClose
  call assert_equal(3, winnr('$'), 'Closed source tab is recreated separately from the reader')
  call assert_equal('head', b:revue_role)
  call assert_equal(g:fixture.content.head.lines, getline(1, '$'))
  call assert_true(revue#layout#Exists(reader_notes_window))
  call revue#session#Close()
  call assert_equal(0, g:mutations)
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call delete(g:revue_draft_dir, 'rf')
if !empty($REVUE_CAP_STORE) | call writefile(v:errors, $REVUE_CAP_STORE . '/errors') | endif
if !empty(v:errors) | call writefile(v:errors, '/dev/stderr') | cquit | endif
qa!
