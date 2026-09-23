set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile($REVUE_PRIVATE_FIXTURE), "\n"))
function! PrivateRestart(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  elseif filereadable($REVUE_CAP_STORE . '/first') && a:request.op ==# 'verify_pending'
    call a:Done({'ok': 1, 'data': g:fixture.verified})
  endif
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'private-restart', 'review': '42', 'snapshot': g:fixture.first, 'Request': function('PrivateRestart')}, 0)
  ReviewPending
  call cursor(5, 1)
  call assert_false(get(get(revue#session#Inspect(g:id), 'pending_verification', {}), 'loading', 0))
  call assert_false(revue#pending#Find(revue#session#Inspect(g:id).snapshot, '7').complete)
  ReviewVerifyPending
  if filereadable($REVUE_CAP_STORE . '/first')
    call assert_true(revue#pending#Find(revue#session#Inspect(g:id).snapshot, '7').complete)
    call assert_match('4/4 comments loaded', join(getline(1, '$'), "\n"))
  else
    call assert_true(revue#session#Inspect(g:id).pending_verification.loading)
    call writefile(['first'], $REVUE_CAP_STORE . '/first')
  endif
  let outbox = revue#session#Inspect(g:id).draftpath
  call revue#session#Close()
  call assert_notmatch('Body 101', join(readfile(outbox), "\n"), 'read bodies stay backend-owned')
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
