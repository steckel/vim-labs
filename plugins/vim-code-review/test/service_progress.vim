set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {}
let g:fixture.snapshot.capabilities.service_progress = {'enabled': 1}
let g:fixture.snapshot.capabilities.service_viewed = {'enabled': 1, 'body_required': 0}
let g:state = 'unviewed'
let g:mode = ''
let g:writes = []
function! ProgressHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  elseif a:request.op ==# 'service_progress'
    let result = {'ok': 1, 'data': {'path': a:request.path, 'reference': a:request.reference, 'actor': 'fixture:actor', 'actor_label': 'Alex', 'review_id': 'pr1', 'state': g:state}}
    if g:mode ==# 'delay' | let g:ReadDone = a:Done | let g:result = result
    else | call a:Done(result) | endif
  elseif a:request.op ==# 'mutate'
    call add(g:writes, deepcopy(a:request))
    let d = a:request.draft
    let g:LastWriteDone = a:Done
    call assert_equal('service_viewed', d.kind)
    let g:state = d.viewed ? 'viewed' : 'unviewed'
    if g:mode ==# 'reject'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Fixture permission denied'})
    elseif g:mode ==# 'lost'
      call a:Done({'ok': 0, 'unknown': 1, 'error': 'Fixture lost response'})
    else
      let receipt = {'observed': v:true}
      for k in ['id', 'path', 'reference', 'actor', 'review_id', 'viewed'] | let receipt[k] = deepcopy(d[k]) | endfor
      if g:mode ==# 'hold'
        let g:HeldDone = a:Done
        let g:held_receipt = receipt
      else
        call a:Done({'ok': 1, 'data': receipt})
      endif
    endif
  else
    throw 'Unexpected operation: ' . a:request.op
  endif
endfunction
try
  call assert_false(revue#service_progress#Valid({'reference': []}, {}, 'file'))
  let g:id = revue#session#Open(g:fixture.snapshot, function('ProgressHost'), 0)
  call cursor(3, 1)
  let source = [win_getid(), bufnr(), getpos('.')]
  let progress = deepcopy(revue#session#Inspect(g:id).progress)
  RevueServiceProgress
  call assert_equal('service-progress', b:revue_view)
  call assert_match('Service at last read: unviewed', join(getline(1,'$'), "\n"))
  call assert_equal([], g:writes)
  let g:revue_no_default_mappings = 1
  let g:revue_mappings = {'mark-service-viewed': 'gv'}
  call revue#maps#Apply('service-progress')
  call assert_equal('<Plug>(revue-mark-service-viewed)', maparg('gv', 'n'))
  unlet g:revue_no_default_mappings g:revue_mappings
  call revue#maps#Apply('service-progress')
  if filereadable($REVUE_CAP_STORE . '/restart')
    let pending = filter(copy(revue#session#Inspect(g:id).drafts), {_, d -> d.kind ==# 'service_viewed'})[0]
    call assert_equal('unknown', pending.state)
    RevueMarkServiceViewed
    call assert_equal([], g:writes)
    RevueCheckServiceViewed
    call assert_equal(1, g:writes[0].reconcile)
    call assert_equal(pending.id, g:writes[0].draft.id)
    call assert_equal([], filter(copy(revue#session#Inspect(g:id).drafts), {_, d -> d.kind ==# 'service_viewed'}))
  else
    let g:mode = 'reject'
    RevueMarkServiceViewed
    call assert_equal('failed', filter(copy(revue#session#Inspect(g:id).drafts), {_, d -> d.kind ==# 'service_viewed'})[0].state)
    RevueCheckServiceViewed
    call assert_equal(1, len(g:writes), 'Checking a known failure must not retry a write')
    let g:OldDone = g:LastWriteDone
    let g:mode = 'hold'
    RevueMarkServiceViewed
    call g:OldDone({'ok': 0, 'unknown': 0, 'error': 'Duplicate old failure'})
    call assert_equal('submitting', filter(copy(revue#session#Inspect(g:id).drafts), {_, d -> d.kind ==# 'service_viewed'})[0].state)
    RevueMarkServiceViewed
    call assert_equal(2, len(g:writes), 'Repeated activation while submitting is inert')
    call g:HeldDone({'ok': 1, 'data': g:held_receipt})
    let g:mode = ''
    call assert_equal(2, len(g:writes))
    call assert_equal(v:true, g:writes[-1].draft.viewed)
    call assert_equal(progress, revue#session#Inspect(g:id).progress)
    RevueServiceProgress
    call assert_match('Service at last read: viewed', join(getline(1,'$'), "\n"))
    RevueUnmarkServiceViewed
    call assert_equal(v:false, g:writes[-1].draft.viewed)
    RevueServiceProgress
    let g:mode = 'lost'
    RevueMarkServiceViewed
    call assert_equal('unknown', filter(copy(revue#session#Inspect(g:id).drafts), {_, d -> d.kind ==# 'service_viewed'})[0].state)
    call writefile(['yes'], $REVUE_CAP_STORE . '/restart')
  endif
  RevueClose
  call assert_equal(source, [win_getid(), bufnr(), getpos('.')])
  let g:mode = 'delay'
  RevueServiceProgress
  let panel = bufnr()
  RevueClose
  call g:ReadDone(g:result)
  call assert_equal(source, [win_getid(), bufnr(), getpos('.')])
  call assert_equal(progress, revue#session#Inspect(g:id).progress)
  RevueServiceProgress
  let g:result.data.path = 'wrong-file'
  call g:ReadDone(g:result)
  call assert_match('Incomplete service progress', join(getline(1,'$'), "\n"))
  RevueClose
  RevueServiceProgress
  let g:fixture.snapshot.head = 'new-head'
  let g:fixture.snapshot.snapshot = 'new-comparison'
  RevueRefresh
  sleep 300m
  call g:ReadDone(g:result)
  call assert_match('Comparison changed', join(getline(1,'$'), "\n"))
  RevueClose
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
