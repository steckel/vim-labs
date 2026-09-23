set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_local_dir = $REVUE_LOCAL_STORE
let g:revue_draft_dir = $REVUE_HISTORY_DRAFTS
let g:config = json_decode(join(readfile($REVUE_HISTORY_CONFIG), "\n"))
function! WaitForHistory(Check) abort
  let start = reltime()
  while !a:Check() && reltimefloat(reltime(start)) < 10 | sleep 10m | endwhile
  call assert_true(a:Check(), 'Backend callback timed out')
endfunction
try
  let g:id = revue#backend#Open({'id': 'local', 'connection': g:config.connection, 'review': g:config.review,
        \ 'snapshot': g:config.snapshot, 'Request': function('revue#backends#local#Request', [g:config.review])}, 0)
  call WaitForHistory({-> !empty(revue#session#Inspect(g:id).loaded)})
  ReviewThreads
  for [row, target] in items(revue#session#Inspect(g:id).messagemap)
    if target.comment ==# g:config.message | call cursor(str2nr(row), 1) | break | endif
  endfor
  ReviewMessageHistory
  call WaitForHistory({-> !revue#session#Inspect(g:id).message_history.loading})
  call assert_equal('', revue#session#Inspect(g:id).message_history.error)
  call assert_match('-Original reply', join(getline(1, '$'), "\n"))
  call assert_match('+Revised reply', join(getline(1, '$'), "\n"))
  call assert_false(&modifiable)
  ReviewClose
  call assert_equal(g:config.message, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_HISTORY_ERRORS)
if !empty(v:errors) | cquit | endif
qa!
