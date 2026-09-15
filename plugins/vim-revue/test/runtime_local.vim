set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:config = json_decode(join(readfile($REVUE_RUNTIME_CONFIG), "\n"))
let g:revue_local_dir = g:config.store
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_participants = [extend(deepcopy(g:config.participant), {'runtime': g:config.runtime})]
let g:revue_mappings = {'run-participant': 'gr'}
let g:recover = filereadable($REVUE_CAP_STORE . '/run-operation')
let g:requests = []
function! RuntimeResult(request, Done, result) abort
  if a:request.op ==# 'mutate' && !g:recover
    call assert_true(a:result.ok, string(a:result))
    call writefile([json_encode(a:request.draft)], $REVUE_CAP_STORE . '/run-operation')
    " An accepted write with a mismatched receipt must remain frozen.
    let result = deepcopy(a:result)
    let result.data.intent.workspace = '/wrong-receipt-workspace'
    call a:Done(result)
  else
    call a:Done(a:result)
  endif
endfunction
function! RuntimeHost(request, Done) abort
  if a:request.op ==# 'mutate' | call add(g:requests, deepcopy(a:request)) | endif
  call revue#backends#local#Request(g:config.review, a:request, function('RuntimeResult', [deepcopy(a:request), a:Done]))
endfunction
function! WaitRuntime() abort
  for _ in range(500)
    let s = revue#session#Inspect(t:revue_session)
    if !s.busy && !get(get(s,'assignments',{}),'loading',0) && !empty(s.loaded) && empty(filter(copy(s.drafts),{_,d -> d.state ==# 'submitting'})) | return | endif
    sleep 10m
  endfor
  call assert_report('Runtime UI read/write timed out')
endfunction
function! RuntimeItem() abort
  return get(filter(revue#session#ActionGuide(),{_,i -> i.id ==# 'run-participant'}),0,{})
endfunction
function! WaitComplete() abort
  for _ in range(70)
    RevueReloadAssignments
    call WaitRuntime()
    let item=revue#assignment#Find(revue#session#Inspect(t:revue_session),g:config.assignment)
    let latest=get(get(item,'runs',[]),-1,{})
    if get(latest,'state','') ==# 'completed' && !latest.process_held | return latest | endif
    sleep 20m
  endfor
  call assert_report('Participant did not complete: ' . string(item))
  return {}
endfunction
try
  call revue#backend#Open({'id':'local','review':g:config.review,'connection':g:config.connection,
        \ 'snapshot':g:config.snapshot,'Request':function('RuntimeHost')},0)
  call WaitRuntime()
  if g:recover
    let operation=json_decode(readfile($REVUE_CAP_STORE . '/run-operation')[0])
    RevueActivity
    for [row,target] in items(revue#session#Inspect(t:revue_session).activityrows)
      if target.operation ==# operation.id | call cursor(str2nr(row),1) | break | endif
    endfor
    RevueOpenOperation
    call assert_false(&modifiable)
    call assert_equal(operation.id,b:revue_draft)
    RevueCheckReceipt
    call WaitRuntime()
    call assert_true(g:requests[0].reconcile)
    call assert_equal([],filter(copy(revue#session#Inspect(t:revue_session).drafts),{_,d -> d.kind ==# 'participant_run'}))
  endif
  call revue#session#Assignments(g:config.assignment)
  call WaitRuntime()
  call assert_equal('<Plug>(revue-run-participant)',maparg('gr','n'))
  if g:recover
    let prior=WaitComplete()
    call assert_equal('Resume participant',RuntimeItem().label)
    let item=deepcopy(revue#assignment#Find(revue#session#Inspect(t:revue_session),g:config.assignment))
    let snapshot=revue#session#Inspect(t:revue_session).snapshot
    let fields=revue#runtime#Fields(snapshot,item)
    let abandoned=deepcopy(item.runs[-1])
    let abandoned.state='abandoned'
    let abandoned.id='unstarted-resume'
    call add(item.runs,abandoned)
    call assert_equal(fields,revue#runtime#Fields(snapshot,item))
    call remove(item.runs,-1)
    for field in ['workspace','participant','reference','count','thread','expected_version']
      let changed=deepcopy(fields)
      let changed[field]='mismatch'
      call assert_match('changed',revue#runtime#CurrentError(snapshot,item,changed),field)
    endfor
    let item.runs[-1].process_held=v:true
    call assert_match('still owned',revue#runtime#CurrentError(snapshot,item,fields))
    let item.runs[-1].process_held=v:false
    let item.runs[-1].state='prepared'
    let item.runs[-1].expected_version='old-version'
    call assert_match('older assignment',revue#runtime#CurrentError(snapshot,item,fields))
    let item.cancelled=v:true
    call assert_match('cancelled',revue#runtime#CurrentError(snapshot,item,fields))
  else
    call assert_equal('Start participant',RuntimeItem().label)
    let saved=deepcopy(g:revue_participants)
    let g:revue_participants=[]
    call assert_match('Configure',RuntimeItem().reason)
    RevueRunParticipant
    call assert_equal('assignment',b:revue_view)
    let g:revue_participants=saved
  endif
  RevueRunParticipant
  call assert_equal('preview',b:revue_view)
  call assert_match('Workspace: ',join(getline(1,'$'),"\n"))
  call assert_match('workspace-write',join(getline(1,'$'),"\n"))
  if g:recover | call assert_match(prior.thread,join(getline(1,'$'),"\n")) | endif
  RevueClose
  call assert_false(&modifiable)
  call assert_equal('',revue#session#Inspect(t:revue_session).drafts[-1].body)
  if !g:recover
    let g:revue_participants[0].runtime.sandbox='read-only'
    RevueSend
    call assert_equal([],g:requests)
    let g:revue_participants[0].runtime.sandbox='workspace-write'
  endif
  RevueSend
  call WaitRuntime()
  if !g:recover
    call assert_equal('unknown',revue#session#Inspect(t:revue_session).drafts[-1].state)
    call assert_false(&modifiable)
    call assert_equal(1,len(g:requests))
  else
    call revue#session#Assignments(g:config.assignment)
    call WaitRuntime()
    let finished=WaitComplete()
    call assert_equal(prior.thread,finished.thread)
    call assert_notequal(prior.id,finished.id)
    call assert_match('Runtime: completed',join(getline(1,'$'),"\n"))
    call assert_equal(2,len(g:requests))
    call assert_false(g:requests[1].reconcile)
    call assert_equal('resume',g:requests[1].draft.run_mode)
  endif
  call revue#session#Close()
catch
  call add(v:errors,v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors,$REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
