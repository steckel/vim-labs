set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'feedback_page': {'enabled': 1}, 'feedback_refresh': {'enabled': 1}}
function! RestartRefreshHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  else
    let g:RefreshDone = a:Done
  endif
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'refresh-restart', 'review': 'review', 'snapshot': g:fixture.snapshot, 'Request': function('RestartRefreshHost')}, 0)
  if filereadable($REVUE_CAP_STORE . '/first')
    call assert_equal('interrupted', revue#session#Inspect(g:id).refresh_state.status)
    call assert_false(revue#session#Inspect(g:id).busy)
    call assert_equal([], filter(revue#session#ActionGuide(), {_, a -> index(['continue-refresh', 'cancel-refresh'], a.id) >= 0}))
    RevueRefresh
    call g:RefreshDone({'ok': 1, 'data': g:fixture.snapshot})
    call assert_equal('succeeded', revue#session#Inspect(g:id).refresh_state.status)
  else
    RevueRefresh
    let first = deepcopy(g:fixture.snapshot)
    let first.threads[0].id = 'new-first-thread'
    let first.feedback = {'cursor': 'another-page'}
    call g:RefreshDone({'ok': 1, 'data': first})
    call assert_equal('partial refresh', revue#session#Inspect(g:id).refresh_state.status)
    call writefile(['first'], $REVUE_CAP_STORE . '/first')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
