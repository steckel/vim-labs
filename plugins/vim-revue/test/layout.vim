set nocompatible nomore laststatus=2
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = tempname()
let g:revue_reading_layout = 'split'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.threads[0].comments[2].body .= "\n\n" . repeat("Long discussion line for scroll coverage.\n", 80) . 'END OF LONG DISCUSSION'
let g:mutations = 0
function! LayoutHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    let g:mutations += 1
    throw 'Layout fixture cannot publish'
  endif
endfunction
function! Sizes() abort
  return map(filter(getwininfo(), {_, w -> w.tabnr == tabpagenr()}), {_, w -> [w.width, w.height]})
endfunction
try
  for width in [80, 120, 200]
    let &columns = width
    set lines=50
    let id = revue#session#Open(g:fixture.snapshot, function('LayoutHost'), 0)
    let s = revue#session#Inspect(id)
    call assert_equal(s.headwin, win_getid())
    if width < 120 | call assert_true(winwidth(0) > width - 10) | endif
    RevueRestoreLayout
    " Selecting a file from base must retain that selected side.
    call win_gotoid(s.basewin)
    call revue#session#Next(0)
    call assert_equal(s.basewin, win_getid())
    " User-adjusted split sizes survive a full reading/composition round trip.
    call win_gotoid(s.treewin)
    vertical resize 20
    call win_gotoid(s.basewin)
    execute 'vertical resize ' . (width - 22) / 3
    call win_gotoid(s.headwin)
    let original = Sizes()
    call cursor(3, 3)
    RevueThread
    if get(revue#session#Inspect(id), 'focus_win', 0) != win_getid() | call revue#session#Focus() | endif
    let panel = win_getid()
    call assert_true(winheight(0) >= 44, string([width, winheight(0)]))
    call assert_true(winwidth(0) >= width - 1)
    call assert_true(search('END OF LONG DISCUSSION', 'W') > 0)
    normal! zz
    call assert_equal('END OF LONG DISCUSSION', getline('.'))
    call assert_true(line('w0') > 1)
    let selected = revue#discussion#Selected(revue#session#Inspect(id), line('.'))
    call assert_equal('local-reply-2', selected.comment)
    RevueReply
    call setline(1, 'A reply from the last message in a long thread.')
    let composer = win_getid()
    call assert_true(winheight(0) >= 42)
    let composing_sizes = Sizes()
    call revue#session#Refresh()
    call assert_equal(composing_sizes, Sizes())
    call assert_equal(composer, win_getid())
    RevuePreview
    call assert_true(winheight(0) >= 40)
    call assert_match('A reply from the last message', join(getline(1, '$'), "\n"))
    RevueClose
    call assert_equal(composer, win_getid())
    RevueClose
    call assert_equal(panel, win_getid())
    call assert_true(winheight(0) >= 44)
    call assert_equal('local-reply-2', revue#discussion#Selected(revue#session#Inspect(id), line('.')).comment)
    RevueClose
    call assert_equal(s.headwin, win_getid())
    call assert_equal(original, Sizes(), 'Restored source split sizes at ' . width)
    call assert_equal(3, line('.'))
    " The file list can be hidden/reopened without rebuilding source buffers.
    let headbuf = bufnr()
    RevueFiles
    call assert_equal(0, revue#session#Inspect(id).treewin)
    call assert_equal(headbuf, bufnr())
    call assert_equal(id, revue#session#Open(g:fixture.snapshot, function('LayoutHost'), 0))
    RevueFiles
    call assert_true(revue#session#Inspect(id).treewin > 0)
    call assert_equal(original, Sizes(), 'Restored file sidebar at ' . width)
    RevueThread
    RevueFiles
    RevueFiles
    RevueClose
    call assert_equal(original, Sizes(), 'Sidebar while reading at ' . width)
    " A source focus keeps coordinates/native diff and has bounded card width.
    RevueFocus
    call assert_true(winwidth(0) > width - 10)
    call revue#session#ResizeCards()
    call assert_true(revue#session#Inspect(id).cardwidths[1] <= 100)
    call assert_equal(1, &diff)
    call assert_equal(g:fixture.content.head.lines, getline(1, '$'))
    let &columns = 80
    call revue#session#ResizeCards()
    let &columns = 200
    call revue#session#ResizeCards()
    RevueRestoreLayout
    call assert_equal(headbuf, bufnr())
    call assert_equal(3, winnr('$'))
    call revue#session#Close()
  endfor
  let g:revue_auto_focus = 0
  set columns=80 lines=24
  let id = revue#session#Open(g:fixture.snapshot, function('LayoutHost'), 0)
  call assert_equal(0, get(revue#session#Inspect(id), 'focus_win', 0))
  RevueThread
  call assert_equal(0, get(revue#session#Inspect(id), 'focus_win', 0))
  call revue#session#Close()
  let rows = revue#comments#Rows(g:fixture.snapshot.threads[0], 40, {'outer_width': 160})
  for row in rows | call assert_equal(160, strdisplaywidth(row.text)) | endfor
  call assert_equal(0, g:mutations)
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call delete(g:revue_draft_dir, 'rf')
if !empty(v:errors) | call writefile(v:errors, '/dev/stderr') | cquit | endif
qa!
