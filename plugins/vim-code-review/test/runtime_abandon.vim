set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:config=json_decode(join(readfile($REVUE_RUNTIME_CONFIG),"\n"))
let g:revue_local_dir=g:config.store
let g:revue_draft_dir=$REVUE_CAP_STORE . '/drafts'
let g:revue_participants=[]
let g:revue_mappings={'abandon-run':'gX'}
let g:recover=filereadable($REVUE_CAP_STORE . '/abandon-operation')
let g:requests=[]
function! AbandonResult(request, Done, result) abort
  if a:request.op ==# 'mutate' && !g:recover
    call assert_true(a:result.ok,string(a:result))
    call writefile([json_encode(a:request.draft)],$REVUE_CAP_STORE . '/abandon-operation')
    let result=deepcopy(a:result)
    let result.data.run='foreign-run'
    call a:Done(result)
  else
    call a:Done(a:result)
  endif
endfunction
function! AbandonHost(request, Done) abort
  if a:request.op ==# 'mutate' | call add(g:requests,deepcopy(a:request)) | endif
  call revue#backends#local#Request(g:config.review,a:request,function('AbandonResult',[deepcopy(a:request),a:Done]))
endfunction
function! AwaitAbandon() abort
  for _ in range(500)
    let s=revue#session#Inspect(t:revue_session)
    if !s.busy && !get(get(s,'assignments',{}),'loading',0) && !empty(s.loaded) && empty(filter(copy(s.drafts),{_,d -> d.state ==# 'submitting'})) | return | endif
    sleep 10m
  endfor
  call assert_report('Abandonment UI timed out')
endfunction
function! AbandonAction(id) abort
  return get(filter(revue#session#ActionGuide(),{_,i -> i.id ==# a:id}),0,{})
endfunction
try
  call revue#backend#Open({'id':'local','review':g:config.review,'connection':g:config.connection,
        \ 'snapshot':g:config.snapshot,'Request':function('AbandonHost')},0)
  call AwaitAbandon()
  if g:recover
    let operation=json_decode(readfile($REVUE_CAP_STORE . '/abandon-operation')[0])
    RevueActivity
    for [row,target] in items(revue#session#Inspect(t:revue_session).activityrows)
      if target.operation ==# operation.id | call cursor(str2nr(row),1) | break | endif
    endfor
    RevueOpenOperation
    call assert_false(&modifiable)
    RevueCheckReceipt
    call AwaitAbandon()
    call assert_true(g:requests[0].reconcile)
    call assert_true(revue#session#Inspect(t:revue_session).last_receipt.abandoned)
    call assert_equal([],filter(copy(revue#session#Inspect(t:revue_session).drafts),{_,d -> d.kind ==# 'participant_run'}))
  endif
  call revue#session#Assignments(g:config.assignment)
  call AwaitAbandon()
  call assert_equal('<Plug>(revue-abandon-run)',maparg('gX','n'))
  if g:recover
    call assert_match('unstarted prepared',AbandonAction('abandon-run').reason)
    call assert_match('Runtime: abandoned',join(getline(1,'$'),"\n"))
    let g:revue_participants=[extend(deepcopy(g:config.participant),{'runtime':g:config.runtime})]
    call assert_equal('Start participant',AbandonAction('run-participant').label)
    call assert_equal('',AbandonAction('run-participant').reason)
    call assert_equal(1,len(g:requests))
  else
    call assert_match('older assignment',AbandonAction('run-participant').reason)
    call assert_equal('',AbandonAction('abandon-run').reason)
    RevueAbandonRun
    call assert_equal('preview',b:revue_view)
    call assert_match('# Abandon prepared run',getline(1))
    call assert_match('Assignment access, comments',join(getline(1,'$'),"\n"))
    RevueClose
    call assert_false(&modifiable)
    call assert_equal('',revue#session#Inspect(t:revue_session).drafts[-1].body)
    call assert_equal([],g:requests)
    RevueSend
    call AwaitAbandon()
    call assert_equal('abandon',g:requests[0].draft.run_mode)
    call assert_equal('unknown',revue#session#Inspect(t:revue_session).drafts[-1].state)
    call assert_false(&modifiable)
    call assert_equal(1,len(g:requests))
  endif
  call revue#session#Close()
catch
  call add(v:errors,v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors,$REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
