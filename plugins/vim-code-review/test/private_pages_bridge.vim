set nocompatible nomore
let g:root = expand('<sfile>:p:h:h')
execute 'set runtimepath^=' . fnameescape(g:root)
execute 'set runtimepath^=' . fnameescape(fnamemodify(g:root, ':h') . '/vim-code-review-github')
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:reviewhub_command = ['python3', g:root . '/test/private_pages_provider.py']
let g:opened = {}
function! PrivateOpened(result) abort
  let g:opened = a:result
endfunction
function! PrivateAwait(Check) abort
  let start = reltime()
  while !a:Check() && reltimefloat(reltime(start)) < 10 | sleep 10m | endwhile
  if !a:Check() | throw 'Private transport callback timed out' | endif
endfunction
try
  let conn = {'host': 'github.example', 'repo': 'owner/repo'}
  call reviewhub#transport#Request({'op': 'open', 'connection': conn, 'number': 42}, function('PrivateOpened'))
  call PrivateAwait({-> !empty(g:opened)})
  call assert_true(g:opened.ok)
  call reviewhub#bridge#Open(conn, g:opened.data, 0)
  let g:id = t:revue_session
  call PrivateAwait({-> !empty(revue#session#Inspect(g:id).loaded)})
  ReviewPending
  call cursor(5, 1)
  ReviewLoadMoreFeedback
  call PrivateAwait({-> !revue#session#Inspect(g:id).feedback_read.loading})
  call assert_equal('', revue#session#Inspect(g:id).feedback_read.error)
  call assert_equal(4, len(revue#pending#Find(revue#session#Inspect(g:id).snapshot, '7').comments))
  call cursor(5, 1)
  ReviewVerifyPending
  call PrivateAwait({-> !revue#session#Inspect(g:id).pending_verification.loading})
  call assert_equal('', revue#session#Inspect(g:id).pending_verification.error)
  call assert_true(revue#pending#Find(revue#session#Inspect(g:id).snapshot, '7').complete)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
