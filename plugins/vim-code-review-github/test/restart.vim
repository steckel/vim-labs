set nocompatible nomore
execute 'set runtimepath^=' . fnameescape($REVUE_ROOT)
execute 'set runtimepath^=' . fnameescape($REVIEWHUB_ROOT)
runtime plugin/revue.vim
runtime plugin/reviewhub.vim
let g:reviewhub_command = ['python3', $REVIEWHUB_ROOT . '/test/fixture_provider.py']
let g:revue_draft_dir = $REVUE_TEST_STORE . '/drafts'

function! Await(expression) abort
  let start = reltime()
  while !eval(a:expression)
    if reltimefloat(reltime(start)) > 8 | throw 'Timed out: ' . a:expression | endif
    sleep 10m
  endwhile
endfunction

try
  call writefile(['new revision'], $REVUE_TEST_STORE . '/revision-b')
  ReviewOpen https://fixture.test/team/project/pull/42
  call Await('exists("t:revue_session")')
  let g:sid = t:revue_session
  let state = revue#session#Inspect(g:sid)
  call assert_equal('a:d', state.snapshot.snapshot)
  call assert_false(has_key(state.comparisons['a:b'], 'snapshot'))
  call assert_equal('Persist this conversation draft', state.drafts[0].body)
  call assert_equal('unknown', state.drafts[0].state)
  call win_gotoid(state.treewin)
  for [row, target] in items(state.rows)
    if target.kind ==# 'draft'
      call cursor(str2nr(row), 1)
      call revue#session#Activate()
      break
    endif
  endfor
  call assert_equal(0, &modifiable)
  call revue#session#Send()
  call Await('empty(revue#session#Inspect(g:sid).drafts)')
  call Await('!revue#session#Inspect(g:sid).busy')
  call revue#session#ResumeComparison()
  call Await('revue#session#Inspect(g:sid).snapshot.snapshot ==# "a:b"')
  call Await('!empty(revue#session#Inspect(g:sid).loaded)')
  let state = revue#session#Inspect(g:sid)
  call assert_equal('new', getbufline(state.head, 2)[0])
  call revue#session#Comparisons()
  call Await('!revue#session#Inspect(g:sid).history_busy')
  call assert_equal('a:b', revue#session#Inspect(g:sid).snapshot.snapshot)
  call assert_equal('a:d', revue#session#Inspect(g:sid).latest_comparison)
  call writefile(v:errors, $REVUE_TEST_STORE . '/restart-errors')
catch
  call writefile([v:exception, v:throwpoint] + v:errors, $REVUE_TEST_STORE . '/restart-errors')
endtry
qa!
