set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:config = json_decode(join(readfile($REVUE_ASSIGNMENT_CONFIG), "\n"))
let g:revue_local_dir = g:config.store
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:recover = filereadable($REVUE_CAP_STORE . '/cancel-operation')
let g:read_mode = 'real'
function! OutcomesResult(request, Done, result) abort
  if a:request.op ==# 'assignments' && a:result.ok | let g:assignment_data = deepcopy(a:result.data) | endif
  if a:request.op ==# 'mutate' && !g:recover
    call assert_equal('cancel_assignment', a:request.draft.kind)
    call assert_true(a:result.ok, string(a:result))
    call writefile([json_encode(a:request.draft)], $REVUE_CAP_STORE . '/cancel-operation')
    call a:Done({'ok': 0, 'unknown': 1, 'error': 'Fixture dropped accepted cancellation response'})
  else
    call a:Done(a:result)
  endif
endfunction
function! OutcomesHost(request, Done) abort
  if a:request.op ==# 'assignments' && g:read_mode ==# 'hold'
    let g:Held = a:Done
  else
    call revue#backends#local#Request(g:config.review, a:request, function('OutcomesResult', [deepcopy(a:request), a:Done]))
  endif
endfunction
function! WaitOutcomes() abort
  for _ in range(500)
    let session = revue#session#Inspect(t:revue_session)
    if !session.busy && !get(get(session, 'assignments', {}), 'loading', 0) && !empty(session.loaded) && empty(filter(copy(session.drafts), {_, d -> d.state ==# 'submitting'})) | return | endif
    sleep 10m
  endfor
  call assert_report('Timed out waiting for assignment state')
endfunction
function! SelectOutcome() abort
  for [row, target] in items(revue#session#Inspect(t:revue_session).assignment_view_rows)
    if target.message ==# g:config.message | call cursor(str2nr(row), 1) | return | endif
  endfor
  call assert_report('No original outcome target')
endfunction
try
  call revue#backend#Open({'id':'local','review':g:config.review,'connection':g:config.connection,
        \ 'snapshot':g:config.snapshot,'Request':function('OutcomesHost')}, 0)
  call WaitOutcomes()
  if g:recover
    let operation = json_decode(readfile($REVUE_CAP_STORE . '/cancel-operation')[0])
    ReviewActivity
    for [row, target] in items(revue#session#Inspect(t:revue_session).activityrows)
      if target.operation ==# operation.id | call cursor(str2nr(row), 1) | break | endif
    endfor
    ReviewOpenOperation
    call assert_equal(operation.id, b:revue_draft)
    call assert_false(&modifiable)
    ReviewCheckReceipt
    call WaitOutcomes()
    let session = revue#session#Inspect(t:revue_session)
    call assert_equal([], filter(copy(session.drafts), {_, d -> d.kind ==# 'cancel_assignment'}))
    call assert_true(session.last_receipt.cancelled)
    call assert_true(session.last_receipt.recovered)
    ReviewAssignments
    call WaitOutcomes()
    call assert_match('Cancelled', join(getline(1,'$'), "\n"))
  else
    ReviewAssignments
    call WaitOutcomes()
    call assert_equal('', revue#session#Inspect(t:revue_session).assignments.error)
    let probe = revue#session#Inspect(t:revue_session)
    for invalid in ['version', 'outcome', 'reference', 'duplicate']
      let candidate = deepcopy(g:assignment_data)
      if invalid ==# 'version' | let candidate.items[0].version = 1
      elseif invalid ==# 'outcome' | let candidate.items[0].outcomes[g:config.message].state = 'approved'
      elseif invalid ==# 'reference' | let candidate.items[0].outcomes[g:config.message].result_reference.head = []
      else | call add(candidate.items, deepcopy(candidate.items[0])) | endif
      call assert_match('rejected',revue#assignment#Apply(probe,candidate))
      call assert_equal(1,len(probe.assignments.items))
    endfor
    call search('^## ', 'w')
    ReviewOpenAssignment
    call assert_equal('assignment', b:revue_view)
    call assert_match('addressed', join(getline(1,'$'), "\n"))
    call search('Inspect the follow-up capture', 'w')
    normal! zt
    redraw!
    let reading = winsaveview()
    let g:read_mode = 'hold'
    ReviewReloadAssignments
    call g:Held({'ok':1,'data':g:assignment_data})
    call assert_equal(reading.lnum,line('.'))
    call assert_equal(reading.topline,winsaveview().topline)
    let g:read_mode = 'real'
    call SelectOutcome()
    " Compact reading text does not change identities used for navigation.
    let original = revue#session#Inspect(t:revue_session)
    let item = original.assignments.items[0]
    call assert_equal(2, exists(':ReviewAssignmentDetails'))
    call assert_false(stridx(join(getline(1, '$'), "\n"), item.id) >= 0)
    call assert_false(stridx(join(getline(1, '$'), "\n"), g:config.message) >= 0)
    let origin_window = win_getid()
    normal! zt
    redraw!
    let outcome_view = winsaveview()
    let @a = 'preserved register'
    let g:read_mode = 'hold'
    ReviewReloadAssignments
    ReviewAssignmentDetails
    let details_window = win_getid()
    let details = getline(1, '$')
    call assert_false(&modifiable)
    call assert_true(index(details, 'Assignment: ' . item.id) >= 0)
    call assert_true(index(details, 'Version: ' . item.version) >= 0)
    call assert_true(index(details, '## Message ' . g:config.message) >= 0)
    call assert_true(index(details, 'Base: ' . item.reference.base) >= 0)
    call assert_true(index(details, 'Head: ' . item.reference.head) >= 0)
    call assert_equal('preserved register', @a)
    " Normal Vim yank copies the exact opaque ID, without a special clipboard API.
    call cursor(index(details, 'Assignment: ' . item.id) + 1, 1)
    normal! "byy
    call assert_equal('Assignment: ' . item.id . "\n", @b)
    call g:Held({'ok': 1, 'data': g:assignment_data})
    call assert_equal(details_window, win_getid())
    call assert_equal(details, getline(1, '$'), 'Details retain the inspected record during refresh')
    let g:read_mode = 'real'
    ReviewClose
    redraw!
    call assert_equal(origin_window, win_getid())
    call assert_equal(outcome_view.lnum, line('.'))
    call assert_equal(outcome_view.topline, winsaveview().topline)
    call assert_equal(g:config.message, revue#session#Inspect(t:revue_session).assignment_view_rows[string(line('.'))].message)
    ReviewAssignmentDiscussion
    call assert_equal(g:config.message, revue#discussion#Selected(revue#session#Inspect(t:revue_session), line('.')).comment)
    ReviewClose
    call assert_equal('assignment', b:revue_view)
    call assert_equal(g:config.message, revue#session#Inspect(t:revue_session).assignment_view_rows[string(line('.'))].message)
    ReviewAssignmentReply
    call assert_equal(g:config.reply, revue#discussion#Selected(revue#session#Inspect(t:revue_session), line('.')).comment)
    ReviewClose
    ReviewAssignmentComparison
    for _ in range(500)
      if !empty(get(revue#session#Inspect(t:revue_session), 'context_return', {})) | break | endif
      sleep 10m
    endfor
    call assert_equal(g:config.original_reference.snapshot, revue#session#Inspect(t:revue_session).snapshot.snapshot)
    ReviewReturnContext
    call assert_equal('assignment', b:revue_view)
    ReviewAssignmentResult
    for _ in range(500)
      if !empty(get(revue#session#Inspect(t:revue_session), 'context_return', {})) | break | endif
      sleep 10m
    endfor
    call assert_equal(g:config.snapshot.snapshot, revue#session#Inspect(t:revue_session).snapshot.snapshot)
    ReviewReturnContext
    call assert_equal('assignment', b:revue_view)
    let g:read_mode = 'hold'
    ReviewReloadAssignments
    let Old = g:Held
    ReviewCancelAssignmentsRead
    call Old({'ok':1,'data':{'items':[]}})
    call assert_equal(1,len(revue#session#Inspect(t:revue_session).assignments.items))
    call assert_match('cancelled',revue#session#Inspect(t:revue_session).assignments.error)
    ReviewReloadAssignments
    let bad = deepcopy(g:assignment_data)
    let bad.review = 'foreign'
    call g:Held({'ok':1,'data':bad})
    call assert_equal(1,len(revue#session#Inspect(t:revue_session).assignments.items))
    call assert_match('another review',revue#session#Inspect(t:revue_session).assignments.error)
    ReviewReloadAssignments
    ReviewHelp
    call g:Held({'ok':1,'data':g:assignment_data})
    call assert_equal('help',b:revue_view)
    ReviewClose
    call assert_equal('assignment',b:revue_view)
    call SelectOutcome()
    ReviewReloadAssignments
    ReviewAssignmentDiscussion
    ReviewReply
    call setline(1,'Human draft survives assignment reload')
    let editor = bufnr()
    call g:Held({'ok':1,'data':g:assignment_data})
    call assert_equal(editor,bufnr())
    call assert_equal('Human draft survives assignment reload',getline(1))
    ReviewClose
    ReviewClose
    call assert_equal('assignment', b:revue_view)
    let g:read_mode = 'real'
    ReviewCancelAssignment
    call assert_equal('preview',b:revue_view)
    call assert_match('does not stop',join(getline(1,'$'),"\n"))
    ReviewClose
    ReviewSend
    call WaitOutcomes()
    call assert_equal('unknown',filter(copy(revue#session#Inspect(t:revue_session).drafts),{_,d -> d.kind ==# 'cancel_assignment'})[0].state)
    ReviewDiscard
    call assert_false(&modifiable)
  endif
  call revue#session#Close()
catch
  call add(v:errors,v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors,$REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
