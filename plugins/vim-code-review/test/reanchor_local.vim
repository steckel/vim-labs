set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_local_dir = $REVUE_LOCAL_STORE
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:config = json_decode(join(readfile($REVUE_REANCHOR_CONFIG), "\n"))
function! WaitAnchor(Check) abort
  let started = reltime()
  while !a:Check() && reltimefloat(reltime(started)) < 10 | sleep 10m | endwhile
  call assert_true(a:Check(), 'Local source/read callback timed out')
endfunction
try
  let restart = filereadable($REVUE_CAP_STORE . '/moved')
  let snapshot = restart ? g:config.latest : g:config.snapshot
  let index = index(map(copy(snapshot.files), {_, f -> f.path}), restart ? 'moved.py' : 'code.py')
  let g:id = revue#backend#Open({'id': 'local', 'connection': g:config.connection, 'review': g:config.review,
        \ 'snapshot': snapshot, 'Request': function('revue#backends#local#Request', [g:config.review])}, index)
  call WaitAnchor({-> !empty(revue#session#Inspect(g:id).loaded)})
  if restart
    RevueRefresh
    call WaitAnchor({-> !empty(revue#session#Inspect(g:id).snapshot.threads)})
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    let thread = revue#session#Inspect(g:id).snapshot.threads[0]
    call assert_equal('moved.py', thread.path)
    call assert_equal([1,2], [thread.start, thread.line])
    call assert_equal('Draft moved deliberately.', thread.comments[0].body)
  else
    call cursor(2,1)
    RevueComment
    call setline(1, 'Draft moved deliberately.')
    RevueRefresh
    call WaitAnchor({-> revue#session#Inspect(g:id).latest_comparison ==# g:config.latest.snapshot})
    RevueReanchorDraft
    call WaitAnchor({-> revue#session#Inspect(g:id).snapshot.snapshot ==# g:config.latest.snapshot})
    for attempt in range(len(g:config.latest.files))
      if get(b:, 'revue_file', '') ==# 'moved.py' | break | endif
      RevueNextFile
    endfor
    call WaitAnchor({-> get(get(revue#session#Inspect(g:id).loaded, 'head', {}), 'kind', '') ==# 'text'})
    1,2RevueReanchorHere
    call assert_equal('reanchor', b:revue_view)
    RevueAcceptReanchor
    let draft = revue#session#Inspect(g:id).drafts[0]
    call assert_equal(g:config.snapshot.snapshot, draft.reanchored_from.snapshot)
    call assert_equal('moved.py', draft.path)
    RevueSend
    call WaitAnchor({-> empty(revue#session#Inspect(g:id).drafts)})
    call writefile(['done'], $REVUE_CAP_STORE . '/moved')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
