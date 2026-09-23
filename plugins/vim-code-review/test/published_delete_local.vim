set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_local_dir = $REVUE_LOCAL_STORE
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:config = json_decode(join(readfile($REVUE_DELETE_CONFIG), "\n"))
function! WaitForDelete(Check) abort
  let start = reltime()
  while !a:Check() && reltimefloat(reltime(start)) < 10 | sleep 10m | endwhile
  call assert_true(a:Check(), 'Backend callback timed out')
endfunction
function! DeletedHere() abort
  return empty(revue#edit#Message(revue#session#Inspect(g:id).snapshot, {'message': g:config.message, 'message_kind': 'reply', 'thread': g:config.thread}))
endfunction
try
  let g:id = revue#backend#Open({'id': 'local', 'connection': g:config.connection, 'review': g:config.review,
        \ 'snapshot': g:config.snapshot, 'Request': function('revue#backends#local#Request', [g:config.review])}, 0)
  call WaitForDelete({-> !empty(revue#session#Inspect(g:id).loaded)})
  if filereadable($REVUE_CAP_STORE . '/deleted')
    ReviewRefresh
    call WaitForDelete(function('DeletedHere'))
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    ReviewActivity
    call assert_match('deleted', join(getline(1, '$'), "\n"))
  else
    ReviewThreads
    for [row, target] in items(revue#session#Inspect(g:id).messagemap)
      if target.comment ==# g:config.message | call cursor(str2nr(row), 1) | break | endif
    endfor
    ReviewDeleteMessage
    call assert_equal('preview', b:revue_view)
    call assert_match('local review', join(getline(1, '$'), "\n"))
    call assert_match('Remove this reply', join(getline(1, '$'), "\n"))
    call assert_false(&modifiable)
    ReviewClose
    ReviewSend
    call WaitForDelete({-> empty(revue#session#Inspect(g:id).drafts)})
    call WaitForDelete(function('DeletedHere'))
    call assert_equal(g:config.root, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    call writefile(['done'], $REVUE_CAP_STORE . '/deleted')
  endif
  call assert_equal([g:config.root], map(copy(revue#session#Inspect(g:id).snapshot.threads[0].comments), {_, m -> m.id}))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
