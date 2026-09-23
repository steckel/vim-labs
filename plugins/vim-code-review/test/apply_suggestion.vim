set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:config = json_decode(join(readfile($REVUE_APPLY_CONFIG), "\n"))
let g:revue_local_dir = g:config.store
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:recover = filereadable($REVUE_CAP_STORE . '/operation')
let g:plans = 0
let g:mutations = 0
function! ApplicationResult(request, Done, result) abort
  if a:request.op ==# 'suggestion_plan' | let g:plans += 1 | endif
  if a:request.op ==# 'mutate'
    let g:mutations += 1
    if !g:recover
      call assert_true(a:result.ok, string(a:result))
      call writefile([json_encode(a:request.draft)], $REVUE_CAP_STORE . '/operation')
      call a:Done({'ok': 0, 'unknown': 1, 'error': 'Fixture drops accepted application response'})
      return
    endif
    call assert_true(a:request.reconcile)
  endif
  call a:Done(a:result)
endfunction
function! ApplicationHost(request, Done) abort
  call revue#backends#local#Request(g:config.review, a:request, function('ApplicationResult', [deepcopy(a:request), a:Done]))
endfunction
function! WaitApplication() abort
  for _ in range(500)
    let session = revue#session#Inspect(t:revue_session)
    if !empty(session.loaded) && !session.busy && empty(filter(copy(session.drafts), {_, d -> d.state ==# 'submitting'})) | return | endif
    sleep 10m
  endfor
  call assert_report('Application did not complete')
endfunction
try
  if g:recover | let g:config.snapshot.capabilities.apply_suggestion.enabled = 0 | endif
  call revue#backend#Open({'id': 'local', 'review': g:config.review, 'connection': g:config.connection,
        \ 'snapshot': g:config.snapshot, 'Request': function('ApplicationHost')}, 0)
  call WaitApplication()
  let id = t:revue_session
  if !g:recover
    call revue#session#Threads(g:config.thread)
    call cursor(1, 1)
    ReviewNextMessage
    let reader = win_getid()
    let selected = revue#discussion#Selected(revue#session#Inspect(id), line('.')).comment
    let @z = 'native register retained'
    let g:revue_mappings = {'apply-suggestion': 'gS'}
    call revue#maps#Apply('threads')
    call assert_equal('<Plug>(revue-apply-suggestion)', maparg('gS', 'n'))
    ReviewApplySuggestion
    for _ in range(500)
      if g:plans | break | endif
      sleep 10m
    endfor
    call assert_equal('draft', b:revue_role, revue#session#Inspect(id).message)
    call assert_false(&modifiable)
    call assert_match('Apply suggestion to workspace', getline(1))
    call assert_match('- new', join(getline(1, '$'), "\n"))
    call assert_match('+ better λ', join(getline(1, '$'), "\n"))
    call assert_equal(['one', 'new', 'three'], readfile(g:config.workspace . '/code.py'))
    call assert_equal(0, g:mutations)
    let operation = deepcopy(revue#session#Inspect(id).drafts[-1])
    let intent = deepcopy(operation)
    call remove(intent, 'state')
    let receipt = {'id': operation.id, 'intent': intent, 'applied': v:true, 'observed': v:false, 'result_snapshot': '', 'capture_error': ''}
    call assert_true(revue#apply_suggestion#Receipt(operation, receipt))
    let receipt.intent.untracked = 0
    call assert_false(revue#apply_suggestion#Receipt(operation, receipt), 'Receipt must preserve Boolean intent types')
    let malformed = deepcopy(operation)
    let malformed.message = 'another-message'
    call assert_false(revue#apply_suggestion#Receipt(operation, {'id': operation.id, 'intent': malformed, 'applied': v:true, 'observed': v:false, 'result_snapshot': '', 'capture_error': ''}))
    let draftwin = win_getid()
    ReviewPreview
    call assert_match('No commit', join(getline(1, '$'), "\n"))
    ReviewClose
    call assert_equal(draftwin, win_getid())
    ReviewClose
    call assert_equal(reader, win_getid())
    call assert_equal(selected, revue#discussion#Selected(revue#session#Inspect(id), line('.')).comment)
    ReviewApplySuggestion
    call assert_equal(1, g:plans, 'Existing application is reused')
    let draftwin = win_getid()
    tabnew
    execute 'edit ' . fnameescape(g:config.workspace . '/code.py')
    call setline(1, 'unsaved Vim changes')
    let editing = bufnr()
    call win_gotoid(draftwin)
    ReviewSend
    call assert_equal(0, g:mutations)
    call assert_equal(['one', 'new', 'three'], readfile(g:config.workspace . '/code.py'))
    call assert_equal('unsaved Vim changes', getbufline(editing, 1)[0])
    execute 'bwipeout! ' . editing
    call win_gotoid(draftwin)
    ReviewSend
    call WaitApplication()
    call assert_equal('unknown', revue#session#Inspect(id).drafts[-1].state)
    call assert_false(&modifiable)
    call assert_equal(['one', 'better λ', 'three'], readfile(g:config.workspace . '/code.py'))
    call assert_equal('native register retained', @z)
    ReviewDiscard
    call assert_equal(1, len(revue#session#Inspect(id).drafts))
  else
    let operation = json_decode(readfile($REVUE_CAP_STORE . '/operation')[0])
    ReviewActivity
    call search('## Pending', 'W')
    ReviewOpenOperation
    call assert_equal(operation.id, b:revue_draft)
    call assert_false(&modifiable)
    ReviewCheckReceipt
    call WaitApplication()
    let session = revue#session#Inspect(id)
    call assert_equal([], session.drafts, session.message)
    call assert_true(session.last_receipt.applied)
    call assert_true(session.last_receipt.recovered)
    call assert_false(empty(session.last_receipt.result_snapshot))
    ReviewLatest
    for _ in range(500)
      if revue#session#Inspect(id).snapshot.snapshot ==# session.last_receipt.result_snapshot | break | endif
      sleep 10m
    endfor
    call WaitApplication()
    let session = revue#session#Inspect(id)
    call assert_equal(session.last_receipt.result_snapshot, session.snapshot.snapshot)
    call assert_true(session.snapshot.threads[0].outdated)
    call assert_false(session.snapshot.threads[0].resolved)
    call assert_match('Applied to workspace', revue#message#Metadata(session.snapshot.threads[0].comments[0]))
    let edited = deepcopy(session.snapshot.threads[0].comments[0])
    let edited.version = 'changed-message-version'
    call assert_notmatch('Applied to workspace', revue#message#Metadata(edited))
    call assert_equal(1, g:mutations)
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
