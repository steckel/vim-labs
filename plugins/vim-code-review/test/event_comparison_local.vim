set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_local_dir = $REVUE_LOCAL_STORE
let g:revue_draft_dir = $REVUE_EVENT_DRAFTS
let g:config = json_decode(join(readfile($REVUE_EVENT_CONFIG), "\n"))
function! WaitForEvent(Check) abort
  let start = reltime()
  while !a:Check() && reltimefloat(reltime(start)) < 10
    sleep 10m
  endwhile
  call assert_true(a:Check(), 'Backend callback timed out')
endfunction
try
  let g:id = revue#backend#Open({'id': 'local', 'connection': g:config.connection, 'review': g:config.review,
        \ 'snapshot': g:config.snapshot, 'Request': function('revue#backends#local#Request', [g:config.review])}, 0)
  call WaitForEvent({-> !empty(revue#session#Inspect(g:id).loaded)})
  RevueTimeline
  call WaitForEvent({-> !revue#session#Inspect(g:id).timeline.loading})
  let state = revue#session#Inspect(g:id)
  let event = filter(copy(state.timeline.items), {_, e -> get(get(e, 'target', {}), 'message', '') ==# g:config.review_message})[0]
  for row in sort(keys(state.timelinerows), 'n')
    if state.timelinerows[row].id ==# event.id | call cursor(str2nr(row) + 1, 1) | break | endif
  endfor
  let original_row = line('.')
  RevueEventComparison
  call WaitForEvent({-> revue#session#Inspect(g:id).snapshot.snapshot ==# g:config.original.snapshot})
  call WaitForEvent({-> !empty(revue#session#Inspect(g:id).loaded)})
  call assert_equal(g:config.original.head, revue#session#Inspect(g:id).snapshot.head)
  call assert_equal(g:config.original.base, revue#session#Inspect(g:id).snapshot.base)
  call assert_equal('head', b:revue_role)
  call assert_notmatch('later source', join(getline(1, '$'), "\n"))
  RevueReturnContext
  call assert_equal('timeline', b:revue_view)
  call assert_equal(original_row, line('.'))
  call assert_equal(event.id, revue#session#Inspect(g:id).timelinerows[string(line('.'))].id)
  call assert_equal(g:config.snapshot.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_EVENT_ERRORS)
if !empty(v:errors) | cquit | endif
qa!
