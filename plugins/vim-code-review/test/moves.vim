set nocompatible nomore hidden
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_local_dir = $REVIEW_MOVES_TMP . '/store'
let g:revue_auto_focus = 0
let g:revue_draft_dir = $REVIEW_MOVES_TMP . '/drafts'
let g:revue_capability_store = $REVIEW_MOVES_TMP . '/capabilities.json'
runtime plugin/revue.vim
let g:fixture = json_decode(join(readfile($REVIEW_MOVES_FIXTURE), "\n"))
function! Signs(buf, name) abort
  return map(filter(sign_getplaced(a:buf, {'group': '*'})[0].signs, {_, s -> s.name ==# a:name}), {_, s -> s.lnum})
endfunction
function! Labels(buf) abort
  return filter(prop_list(1, {'bufnr': a:buf, 'end_lnum': -1}), {_, p -> p.type ==# 'ReviewMovedLabel'})
endfunction
function! Host(request, Done) abort
  if a:request.op ==# 'file'
    let file = filter(copy(g:fixture.files), {_, f -> f.id ==# a:request.file.id})[0]
    call a:Done({'ok': 1, 'data': {'base': {'kind': 'text', 'lines': file.before}, 'head': {'kind': 'text', 'lines': file.after}}})
  else
    throw 'Unexpected request: ' . a:request.op
  endif
endfunction
function! WaitFor(Fn) abort
  let until = reltime()
  while !a:Fn() && reltimefloat(reltime(until)) < 15 | sleep 10m | endwhile
  call assert_true(a:Fn(), 'Timed out waiting for review')
  if !a:Fn() | throw 'Review did not load: ' . execute('messages') | endif
endfunction
function! OpenReview(base) abort
  execute 'Review ' . a:base
  call WaitFor({-> !empty(get(b:, 'revue_session', ''))})
  let g:id = b:revue_session
  call WaitFor({-> !empty(revue#session#Inspect(g:id).loaded)})
  return revue#session#Inspect(g:id)
endfunction
try
  if empty($REVIEW_MOVES_MODE)
    for case in g:fixture.cases
      let moves = revue#moves#Detect(case.files)
      call assert_equal(case.count, len(moves), string(case.files))
      if case.count == 1 && !empty(moves)
        for side in ['base', 'head']
          call assert_equal(case[side], [moves[0][side][0].path, moves[0][side][0].line])
          if has_key(case, 'length')
            call assert_equal(case.length, len(moves[0][side]))
          endif
        endfor
        call assert_equal(get(case, 'reindented', 0), moves[0].reindented)
      endif
    endfor
    let g:revue_moved_lines = 0
    call assert_equal([], revue#moves#Detect(g:fixture.files))
    let g:revue_moved_lines = 1
    let snapshot = {'version': 1, 'key': 'fixture/moves', 'display_id': '#1', 'title': 'Moves', 'author': 'author', 'state': 'open', 'body': '', 'url': '', 'reviewers': [], 'base': 'base', 'head': 'head', 'snapshot': 'moves', 'conversation': [], 'review_actions': [], 'files': g:fixture.files, 'threads': [{'id': 't1', 'path': 'source.py', 'side': 'base', 'line': 1, 'start': 1, 'outdated': 0, 'comments': [{'author': 'Reviewer', 'created': '2026-09-22', 'body': 'Keep this discussion here.'}]}]}
    let g:id = revue#session#Open(snapshot, function('Host'), 0)
    let s = revue#session#Inspect(g:id)
    call assert_equal([1, 2, 3], sort(Signs(s.base, 'ReviewMovedFrom'), 'n'))
    call assert_equal([], Signs(s.head, 'ReviewMovedTo'))
    call assert_equal(1, len(Labels(s.base)))
    call assert_true(len(filter(prop_list(1, {'bufnr': s.base}), {_, p -> p.type ==# 'RevueCardBorder'})) > 0)
    call assert_equal(g:fixture.files[0].before, getbufline(s.base, 1, '$'))
    call win_gotoid(s.headwin)
    call revue#session#Next(1)
    let s = revue#session#Inspect(g:id)
    call assert_equal([], Signs(s.base, 'ReviewMovedFrom'))
    call assert_equal([], Labels(s.base))
    call assert_equal([16, 17, 18], sort(Signs(s.head, 'ReviewMovedTo'), 'n'))
    call assert_equal(1, len(Labels(s.head)))
    call assert_equal(g:fixture.files[1].after, getbufline(s.head, 1, '$'))
    call assert_equal(snapshot.threads, s.snapshot.threads)
    call revue#session#Close()
  else
    let s = OpenReview(get(g:fixture, 'base', ''))
    let g:id = s.id
    call win_gotoid(s.headwin)
    call assert_false(&modifiable, 'All review source panes are immutable')
    if $REVIEW_MOVES_MODE ==# 'within_file'
      call assert_equal([1, 2, 3], sort(Signs(s.base, 'ReviewMovedFrom'), 'n'))
      call assert_equal([16, 17, 18], sort(Signs(s.head, 'ReviewMovedTo'), 'n'))
      call assert_equal(1, len(Labels(s.base)))
      call assert_equal(1, len(Labels(s.head)))
      call assert_equal(g:fixture.file.before, getbufline(s.base, 1, '$'))
      call assert_equal(g:fixture.file.after, getbufline(s.head, 1, '$'))
    elseif $REVIEW_MOVES_MODE ==# 'jj_inventory'
      call assert_equal([
            \ ['A', 'added.py', 'added.py'],
            \ ['R', g:fixture.new, g:fixture.old],
            \ ['D', 'removed.py', 'removed.py']],
            \ map(copy(s.snapshot.files), {_, f -> [f.status, f.path, f.old_path]}))
    elseif $REVIEW_MOVES_MODE ==# 'jj_rename'
      call assert_equal([['R', g:fixture.new, g:fixture.old]],
            \ map(copy(s.snapshot.files), {_, f -> [f.status, f.path, f.old_path]}))
      call assert_equal(g:fixture.after, getbufline(s.head, 1, '$'))
      call assert_equal(g:fixture.before, getbufline(s.base, 1, '$'))
      call assert_match(escape(g:fixture.old . ' → ' . g:fixture.new, '~.[]*\'), join(getbufline(s.tree, 1, '$'), "\n"))
      if g:fixture.edited | call assert_match('+    return value + changed_constant', s.snapshot.files[0].patch) | endif
    else
      call assert_equal([1, 2, 3], sort(Signs(s.base, 'ReviewMovedFrom'), 'n'))
      call assert_equal(1, len(Labels(s.base)))
      ReviewNextFile
      call WaitFor({-> !empty(revue#session#Inspect(g:id).loaded)})
      let s = revue#session#Inspect(g:id)
      call assert_equal('target.py', getbufvar(s.head, 'revue_file'))
      call assert_equal([16, 17, 18], sort(Signs(s.head, 'ReviewMovedTo'), 'n'))
      call assert_equal(1, len(Labels(s.head)))
      call assert_equal([], Labels(s.base))
      call assert_equal(g:fixture.files[1].after, getbufline(s.head, 1, '$'))
      ReviewPreviousFile
      call WaitFor({-> !empty(revue#session#Inspect(g:id).loaded)})
      call assert_equal([], Signs(s.head, 'ReviewMovedTo'))
      call assert_equal([], Labels(s.head))
    endif
    call revue#session#Close()
    call assert_false(bufexists(s.head))
    call assert_false(bufexists(s.base))
  endif
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVIEW_MOVES_ERRORS)
if !empty(v:errors) | cquit | endif
qa!
