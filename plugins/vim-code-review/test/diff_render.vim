set nocompatible nomore
set background=dark
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.key = 'fixture/diff-render'
let g:fixture.snapshot.files = [
      \ {'id': 'mixed', 'path': 'mixed.txt', 'old_path': 'mixed.txt', 'status': 'M', 'patch': "@@ -1,5 +1,5 @@\n start\n-one old payload\n-to remove\n+one new payload\n context\n+added\n tail"},
      \ {'id': 'add', 'path': 'added.txt', 'old_path': 'added.txt', 'status': 'A', 'patch': "@@ -0,0 +1 @@\n+added file"},
      \ {'id': 'delete', 'path': 'deleted.txt', 'old_path': 'deleted.txt', 'status': 'D', 'patch': "@@ -1 +0,0 @@\n-deleted file\n\\ No newline at end of file"},
      \ {'id': 'move', 'path': 'moved.txt', 'old_path': 'moved.txt', 'status': 'M', 'patch': "@@ -1,3 +1,3 @@\n-meaningful_relocated_statement()\n context one\n context two\n+meaningful_relocated_statement()"},
      \ {'id': 'missing', 'path': 'missing.txt', 'old_path': 'missing.txt', 'status': 'M', 'patch': ''},
      \ {'id': 'error', 'path': 'error.txt', 'old_path': 'error.txt', 'status': 'M', 'patch': "@@ -1 +1 @@\n-deleted file\n+added file"}]
let g:content = {
      \ 'mixed': [['start', 'one old payload', 'to remove', 'context', 'tail'], ['start', 'one new payload', 'context', 'added', 'tail']],
      \ 'add': [[], ['added file']], 'delete': [['deleted file'], []],
      \ 'move': [['meaningful_relocated_statement()', 'context one', 'context two'], ['context one', 'context two', 'meaningful_relocated_statement()']],
      \ 'missing': [['before'], ['after']]}
let g:fixture.snapshot.threads = [{'id': 'comment', 'path': 'mixed.txt', 'side': 'head', 'line': 2, 'start': 2, 'outdated': 0, 'comments': [{'author': 'Reviewer', 'body': 'Keep this card visible.', 'created': ''}]}]
function! Host(request, Done) abort
  if a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': g:fixture.snapshot})
  elseif a:request.op ==# 'file'
    if a:request.file.id ==# 'error'
      let g:Done = a:Done
      return
    endif
    let pair = g:content[a:request.file.id]
    call a:Done({'ok': 1, 'data': {'base': {'kind': empty(pair[0]) ? 'absent' : 'text', 'lines': pair[0]}, 'head': {'kind': empty(pair[1]) ? 'absent' : 'text', 'lines': pair[1]}}})
  else
    throw 'Unexpected request: ' . a:request.op
  endif
endfunction
function! Signs(buf, name) abort
  return sort(map(filter(sign_getplaced(a:buf, {'group': '*'})[0].signs, {_, s -> s.name ==# a:name}), {_, s -> s.lnum}), 'n')
endfunction
function! Gutter(win, line) abort
  let pos = screenpos(a:win, a:line, 1)
  let info = getwininfo(a:win)[0]
  return join(map(range(info.wincol, pos.col - 1), {_, col -> screenstring(pos.row, col)}), '')
endfunction
function! Attr(win, line, col) abort
  let pos = screenpos(a:win, a:line, a:col)
  return screenattr(pos.row, pos.col)
endfunction
try
  " The review restores the original palette after closing.
  highlight DiffText ctermbg=17 guibg=#111133
  let palette = execute('highlight DiffText')
  let groups = map(['DiffAdd', 'DiffDelete', 'DiffChange', 'DiffText'], {_, name -> hlget(name)[0]})
  let g:id = revue#session#Open(g:fixture.snapshot, function('Host'), 0)
  let s = revue#session#Inspect(g:id)
  call win_gotoid(s.headwin)
  call cursor(1, 1)
  diffupdate
  redraw!
  call assert_equal('yes', &l:signcolumn)
  call assert_true(&l:number)
  call assert_true(&l:diff)
  call assert_equal([2, 3], Signs(s.base, 'ReviewDiffDelete'))
  call assert_equal([2, 4], Signs(s.head, 'ReviewDiffAdd'))
  call assert_match('+.*2', Gutter(s.headwin, 2), 'Addition marker and line number are visible together')
  call assert_match('-.*2', Gutter(s.basewin, 2), 'Deletion marker and line number are visible together')
  call assert_notequal(Attr(s.headwin, 1, 1), Attr(s.headwin, 2, 1), 'Changed lines have a distinct background')
  let left = screenpos(s.basewin, 2, 1)
  let right = screenpos(s.headwin, 2, 1)
  call assert_notequal(screenattr(left.row, getwininfo(s.basewin)[0].wincol + stridx(Gutter(s.basewin, 2), '-')), screenattr(right.row, getwininfo(s.headwin)[0].wincol + stridx(Gutter(s.headwin, 2), '+')), 'Removed and added signs have different colors')
  call assert_notequal(Attr(s.headwin, 2, 1), Attr(s.headwin, 2, 5), 'Changed word retains intraline highlighting')
  call assert_true(len(filter(prop_list(2, {'bufnr': s.head}), {_, p -> p.type ==# 'RevueCardBorder'})) > 0)
  call assert_equal(g:content.mixed[1], getbufline(s.head, 1, '$'))
  call assert_false(getbufvar(s.head, '&modifiable'))
  call assert_equal('#094959', synIDattr(hlID('DiffText'), 'bg#', 'gui'))
  ReviewRefresh
  call assert_equal([2, 4], Signs(s.head, 'ReviewDiffAdd'), 'Refreshing cards does not clear diff signs')
  ReviewNextFile
  call assert_equal([1], Signs(s.head, 'ReviewDiffAdd'))
  call assert_equal([], Signs(s.base, 'ReviewDiffDelete'))
  ReviewNextFile
  call assert_equal([], Signs(s.head, 'ReviewDiffAdd'))
  call assert_equal([1], Signs(s.base, 'ReviewDiffDelete'))
  ReviewNextFile
  diffupdate
  redraw!
  call assert_match('M>', Gutter(s.basewin, 1))
  call assert_match('<M', Gutter(s.headwin, 3), 'Move markers take precedence over +/-')
  ReviewNextFile
  call assert_equal([], Signs(s.head, 'ReviewDiffAdd'))
  call assert_equal([], Signs(s.base, 'ReviewDiffDelete'))
  ReviewPreviousFile
  ReviewNextFile
  ReviewNextFile
  call assert_equal([], Signs(s.head, 'ReviewDiffAdd'), 'Loading clears the previous diff')
  call assert_equal([], Signs(s.base, 'ReviewDiffDelete'))
  call g:Done({'ok': 0, 'error': 'Source unavailable'})
  call assert_equal([], Signs(s.head, 'ReviewDiffAdd'), 'Failed loads never show stale markers')
  call revue#session#Close()
  call assert_equal(palette, execute('highlight DiffText'))
  call assert_equal(groups, map(copy(groups), {_, group -> hlget(group.name)[0]}))
  " Multiple open reviews retain the palette until the last one closes.
  call revue#diff#Enter()
  call revue#diff#Enter()
  call revue#diff#Leave()
  call assert_equal('#094959', synIDattr(hlID('DiffText'), 'bg#', 'gui'))
  highlight DiffText ctermbg=18 guibg=#222244
  call revue#diff#Leave()
  call assert_equal('#222244', synIDattr(hlID('DiffText'), 'bg#', 'gui'), 'Preserve colors changed by the user')
  let g:revue_diff_colors = 0
  let palette = hlget('DiffText')
  call revue#diff#Enter()
  call revue#diff#Leave()
  call assert_equal(palette, hlget('DiffText'), 'Opt-out retains the theme palette')
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
