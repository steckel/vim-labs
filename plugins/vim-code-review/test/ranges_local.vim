set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:data = json_decode(join(readfile($REVUE_RANGE_FIXTURE), "\n"))
let g:revue_local_dir = g:data.store
function! RangeWait(expr) abort
  let started = reltime()
  while !eval(a:expr) && reltimefloat(reltime(started)) < 6
    sleep 10m
  endwhile
  if !eval(a:expr) | throw 'Timeout: ' . a:expr | endif
endfunction
function! RangePick(id) abort
  for [row, id] in items(revue#session#Inspect(g:id).comparisonrows)
    if id ==# a:id | call cursor(str2nr(row), 1) | return | endif
  endfor
  throw 'Missing local comparison'
endfunction
try
  let restarting = filereadable($REVUE_CAP_STORE . '/restart')
  let snapshot = restarting ? g:data.second : g:data.first
  let g:id = revue#backend#Open({'id': 'local', 'connection': g:data.connection, 'review': g:data.review,
        \ 'snapshot': snapshot, 'Request': function('revue#backends#local#Request', [g:data.review])}, 0)
  call RangeWait('!empty(revue#session#Inspect(g:id).loaded)')
  if restarting
    RevueResumeComparison
  else
    call cursor(2, 1)
    RevueComment
    call setline(1, 'Retain this actual local draft')
    RevueClose
    RevueComparisons
    call RangeWait('!get(revue#session#Inspect(g:id), "history_busy", 0)')
    call RangePick(g:data.first.snapshot)
    RevueRangeStart
    call RangePick(g:data.second.snapshot)
    RevueRangeEnd
    RevueOpenRange
  endif
  call RangeWait('has_key(revue#session#Inspect(g:id).snapshot, "range") && !empty(revue#session#Inspect(g:id).loaded)')
  let state = revue#session#Inspect(g:id)
  call assert_equal(['one', 'first', 'three'], getbufline(state.base, 1, '$'))
  call assert_equal(['one', 'second', 'three'], getbufline(state.head, 1, '$'))
  call assert_equal(g:data.first.snapshot, state.drafts[0].snapshot)
  call assert_equal('Retain this actual local draft', state.drafts[0].body)
  call assert_equal(g:data.second.snapshot, state.latest_comparison)
  call assert_equal('local', state.snapshot.backend.id)
  call revue#session#Close()
  call writefile(['restart'], $REVUE_CAP_STORE . '/restart')
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
