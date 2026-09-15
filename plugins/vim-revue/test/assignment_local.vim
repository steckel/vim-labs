set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let config = json_decode(join(readfile($REVUE_ASSIGNMENT_CONFIG), "\n"))
let g:revue_local_dir = config.store
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:revue_participants = [{'id': 'local-agent', 'label': 'Local coding agent'}]
let g:recover = filereadable($REVUE_CAP_STORE . '/operation')
let g:review = config.review
function! LocalAssignmentResult(request, Done, result) abort
  if a:request.op ==# 'mutate' && !g:recover
    call assert_true(a:result.ok, string(a:result))
    call writefile([json_encode(a:request.draft)], $REVUE_CAP_STORE . '/operation')
    call a:Done({'ok': 0, 'unknown': 1, 'error': 'Fixture drops the accepted response'})
  else
    call a:Done(a:result)
  endif
endfunction
function! LocalAssignmentHost(request, Done) abort
  call revue#backends#local#Request(g:review, a:request, function('LocalAssignmentResult', [deepcopy(a:request), a:Done]))
endfunction
function! WaitAssignment() abort
  for _ in range(500)
    let session = revue#session#Inspect(t:revue_session)
    if !empty(session.loaded) && !session.busy && empty(filter(copy(session.drafts), {_, d -> d.state ==# 'submitting'})) | return | endif
    sleep 10m
  endfor
  call assert_report('Assignment read/write did not complete')
endfunction
try
  call revue#backend#Open({'id': 'local', 'review': config.review, 'connection': config.connection,
        \ 'snapshot': config.snapshot, 'Request': function('LocalAssignmentHost')}, 0)
  call WaitAssignment()
  if !g:recover
    RevueThreads
    RevueNextMessage
    RevueAssign
    call cursor(10, 1)
    RevueToggleAssignment
    call feedkeys("1\<CR>", 't')
    RevuePrepareAssignment
    call assert_equal('preview', b:revue_view)
    call assert_match('2 selected messages', join(getline(1, '$'), "\n"))
    RevueClose
    RevueSend
    call WaitAssignment()
    call assert_equal('unknown', revue#session#Inspect(t:revue_session).drafts[-1].state)
  else
    let operation = json_decode(readfile($REVUE_CAP_STORE . '/operation')[0])
    RevueActivity
    for row in keys(revue#session#Inspect(t:revue_session).activityrows)
      if revue#session#Inspect(t:revue_session).activityrows[row].operation ==# operation.id | call cursor(str2nr(row), 1) | break | endif
    endfor
    RevueOpenOperation
    call assert_equal(operation.id, b:revue_draft)
    call assert_false(&modifiable)
    " Recovery must work after configuration loss; no new assignment is sent.
    let g:revue_participants = []
    RevueCheckReceipt
    call WaitAssignment()
    let session = revue#session#Inspect(t:revue_session)
    call assert_equal([], session.drafts)
    call assert_true(session.last_receipt.recovered)
    call assert_equal(2, len(session.last_receipt.targets))
    call writefile([json_encode(session.last_receipt)], $REVUE_CAP_STORE . '/receipt')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
