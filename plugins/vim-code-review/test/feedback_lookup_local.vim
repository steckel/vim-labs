set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_local_dir = $REVUE_LOCAL_STORE
let g:revue_draft_dir = $REVUE_LOOKUP_DIR . '/drafts'
let g:config = json_decode(join(readfile($REVUE_LOOKUP_DIR . '/config.json'), "\n"))
function! WaitLookup(Check) abort
  let started = reltime()
  while !a:Check() && reltimefloat(reltime(started)) < 10
    sleep 10m
  endwhile
  call assert_true(a:Check(), 'Local lookup callback timed out')
endfunction
try
  let g:id = revue#backend#Open({'id': 'local', 'connection': g:config.connection, 'review': g:config.review,
        \ 'snapshot': g:config.snapshot, 'Request': function('revue#backends#local#Request', [g:config.review])}, 0)
  call WaitLookup({-> !empty(revue#session#Inspect(g:id).loaded)})
  call assert_equal(50, len(revue#session#Inspect(g:id).snapshot.threads))
  let original_cursor = revue#session#Inspect(g:id).snapshot.feedback.cursor
  ReviewTimeline
  call WaitLookup({-> !revue#session#Inspect(g:id).timeline.loading})
  let found = 0
  let target_event = get(filter(copy(revue#session#Inspect(g:id).timeline.items), {_, event -> get(get(event, 'target', {}), 'message', '') ==# 'reply-500'}), 0, {})
  for [row, event] in items(revue#session#Inspect(g:id).timelinerows)
    if event.id ==# get(target_event, 'id', '')
      call cursor(str2nr(row), 1)
      let found = 1
      break
    endif
  endfor
  call assert_true(found, 'History must link the distant exact reply')
  let origin = line('.')
  ReviewLoadEventDiscussion
  call WaitLookup({-> !revue#session#Inspect(g:id).feedback_read.loading})
  let state = revue#session#Inspect(g:id)
  call assert_equal('', state.feedback_read.error)
  call assert_equal(51, len(state.snapshot.threads))
  call assert_equal(original_cursor, state.snapshot.feedback.cursor)
  call assert_equal('partial', state.snapshot.inventory.threads.state)
  call assert_equal('reply-500', revue#discussion#Selected(state, line('.')).comment)
  ReviewClose
  call assert_equal('timeline', b:revue_view)
  call assert_equal(origin, line('.'))
  ReviewLoadMoreFeedback
  call WaitLookup({-> !revue#session#Inspect(g:id).feedback_read.loading})
  call assert_equal('', revue#session#Inspect(g:id).feedback_read.error)
  call assert_equal(101, len(revue#session#Inspect(g:id).snapshot.threads))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_LOOKUP_DIR . '/errors')
if !empty(v:errors) | cquit | endif
qa!
