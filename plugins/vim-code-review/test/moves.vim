set nocompatible nomore hidden
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
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
try
  if empty($REVIEW_MOVES_MODE)
    for case in g:fixture.cases
      let moves = revue#moves#Detect(case.files)
      call assert_equal(case.count, len(moves), string(case.files))
      if case.count == 1 && !empty(moves)
        for side in ['base', 'head']
          call assert_equal(case[side], [moves[0][side][0].path, moves[0][side][0].line])
        endfor
      endif
    endfor
    let g:revue_moved_lines = 0
    call assert_equal([], revue#moves#Detect(g:fixture.files))
    let g:revue_moved_lines = 1
    let snapshot = {'version': 1, 'key': 'fixture/moves', 'display_id': '#1', 'title': 'Moves', 'author': 'author', 'state': 'open', 'body': '', 'url': '', 'reviewers': [], 'base': 'base', 'head': 'head', 'snapshot': 'moves', 'conversation': [], 'review_actions': [], 'files': g:fixture.files, 'threads': [{'id': 't1', 'path': 'source.py', 'side': 'base', 'line': 1, 'start': 1, 'outdated': 0, 'comments': [{'author': 'Reviewer', 'created': '2026-09-22', 'body': 'Keep this discussion here.'}]}]}
    let id = revue#session#Open(snapshot, function('Host'), 0)
    let s = revue#session#Inspect(id)
    call assert_equal([1, 2, 3], sort(Signs(s.base, 'ReviewMovedFrom'), 'n'))
    call assert_equal([], Signs(s.head, 'ReviewMovedTo'))
    call assert_equal(1, len(Labels(s.base)))
    call assert_true(len(filter(prop_list(1, {'bufnr': s.base}), {_, p -> p.type ==# 'RevueCardBorder'})) > 0)
    call assert_equal(g:fixture.files[0].before, getbufline(s.base, 1, '$'))
    call win_gotoid(s.headwin)
    call revue#session#Next(1)
    let s = revue#session#Inspect(id)
    call assert_equal([], Signs(s.base, 'ReviewMovedFrom'))
    call assert_equal([], Labels(s.base))
    call assert_equal([16, 17, 18], sort(Signs(s.head, 'ReviewMovedTo'), 'n'))
    call assert_equal(1, len(Labels(s.head)))
    call assert_equal(g:fixture.files[1].after, getbufline(s.head, 1, '$'))
    call assert_equal(snapshot.threads, s.snapshot.threads)
    call revue#session#Close()
  elseif $REVIEW_MOVES_MODE ==# 'jj_inventory'
    let changes = revue#vcs#DiffNameStatus(revue#vcs#RepoRoot(), 'main')
    call assert_equal([
          \ {'status': 'A', 'file': 'added.py'},
          \ {'status': 'R', 'file': g:fixture.new, 'old_file': g:fixture.old},
          \ {'status': 'D', 'file': 'removed.py'}], changes)
  elseif $REVIEW_MOVES_MODE ==# 'jj_rename'
    let repo = revue#vcs#RepoRoot()
    let changes = revue#vcs#DiffNameStatus(repo, 'main')
    call assert_equal([{'status': 'R', 'file': g:fixture.new, 'old_file': g:fixture.old}], changes)
    let patch = revue#vcs#RawDiff(repo, 'main', g:fixture.new, g:fixture.old)
    call assert_match('rename from ', patch)
    call assert_match('rename to ', patch)
    if g:fixture.edited
      call assert_match('+    return value + changed_constant', patch)
    endif
    Review
    call feedkeys('h', 'xt')
    call assert_equal(repo . '/' . g:fixture.new, expand('%:p'))
    call assert_equal(g:fixture.after, getline(1, '$'))
    let bases = filter(getbufinfo(), {_, b -> b.name =~# 'revue-base-'})
    call assert_equal(1, len(bases))
    call assert_equal(g:fixture.before, getbufline(bases[0].bufnr, 1, '$'))
    let sidebars = filter(getbufinfo(), {_, b -> b.name =~# '__RevueReview_'})
    call assert_equal(1, len(sidebars))
    call assert_true(index(getbufline(sidebars[0].bufnr, 1, '$'), '▸ R ' . g:fixture.old . ' → ' . g:fixture.new) >= 0)
    call revue#review#Close()
  else
    execute 'Review ' . g:fixture.base
    call feedkeys('h', 'xt')
    let head = bufnr()
    let bases = filter(getbufinfo(), {_, b -> b.name =~# 'revue-base-'})
    call assert_equal(1, len(bases))
    let base = bases[0].bufnr
    call assert_equal([1, 2, 3], sort(Signs(base, 'ReviewMovedFrom'), 'n'))
    call assert_equal(1, len(Labels(base)))
    call revue#review#NextFile()
    let head = bufnr()
    call assert_match('target.py$', bufname(head))
    call assert_equal([16, 17, 18], sort(Signs(head, 'ReviewMovedTo'), 'n'))
    call assert_equal(1, len(Labels(head)))
    call assert_equal(g:fixture.files[1].after, getline(1, '$'))
    call setline(16, 'changed_after_review()')
    call feedkeys('h', 'xt')
    doautocmd TextChanged
    call assert_equal([], Signs(head, 'ReviewMovedTo'))
    call assert_equal([], Labels(head))
    call revue#review#RefreshSidebar()
    call assert_equal([], Signs(head, 'ReviewMovedTo'), 'Never label stale unsaved content')
    call setline(16, g:fixture.files[1].after[15])
    setlocal nomodified
    call revue#review#RefreshSidebar()
    call assert_equal(1, len(Labels(head)))
    call revue#review#PrevFile()
    call assert_equal([], Signs(head, 'ReviewMovedTo'))
    call assert_equal([], Labels(head))
    call revue#review#NextFile()
    call revue#review#Close()
    call assert_equal([], Signs(head, 'ReviewMovedTo'))
    call assert_equal([], Labels(head))
  endif
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVIEW_MOVES_ERRORS)
if !empty(v:errors) | cquit | endif
qa!
