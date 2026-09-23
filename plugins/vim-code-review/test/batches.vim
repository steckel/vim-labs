set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'conversation': {'enabled': 1}, 'reply': {'enabled': 1},
      \ 'batch': {'enabled': 1, 'body_required': 0, 'mode': 'atomic', 'kinds': ['comment'], 'max_reviews': 1}}
let g:mode = 'ok'
let g:calls = []
function! BatchHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    call assert_equal('batch', a:request.draft.kind)
    let receipt = {'id': a:request.draft.id, 'items': map(copy(a:request.draft.items), {_, d -> {'draft': d.id, 'id': 'receipt-' . d.id}})}
    if g:mode ==# 'unknown' && !a:request.reconcile
      call writefile([json_encode(a:request.draft)], $REVUE_CAP_STORE . '/frozen')
      call a:Done({'ok': 0, 'unknown': 1, 'error': 'Connection lost after acceptance'})
    elseif g:mode ==# 'failed'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Validation rejected the batch'})
    elseif g:mode ==# 'incomplete'
      let receipt.items = []
      call a:Done({'ok': 1, 'data': receipt})
    else
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
function! AddDraft(text) abort
  call win_gotoid(g:source)
  call cursor(3, 1)
  call revue#session#Comment(0)
  call setline(1, a:text)
  let id = revue#session#Inspect(g:id).drafts[-1].id
  ReviewClose
  return id
endfunction
function! SelectDraft(id) abort
  for [row, id] in items(revue#session#Inspect(g:id).batchrows)
    if id ==# a:id
      call cursor(str2nr(row), 1)
      call revue#session#ToggleBatchDraft()
      return
    endif
  endfor
  call assert_report('Draft not found in batch queue')
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('BatchHost'), 0)
  let g:source = revue#session#Inspect(g:id).headwin
  if filereadable($REVUE_CAP_STORE . '/frozen')
    let outcomes = revue#session#Inspect(g:id).activity
    call assert_equal(2, len(filter(copy(outcomes), {_, e -> e.outcome ==# 'accepted'})))
    call assert_equal(1, len(filter(copy(outcomes), {_, e -> e.outcome ==# 'failed'})))
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/frozen')[0])
    let saved = filter(copy(revue#session#Inspect(g:id).drafts), {_, d -> d.kind ==# 'batch'})[0]
    call assert_equal('unknown', saved.state)
    call assert_equal(frozen.items, saved.items)
    let g:fixture.snapshot.capabilities.batch.enabled = 0
    call revue#session#Refresh()
    call revue#session#Batch(saved.id)
    let g:mode = 'failed'
    for attempt in range(3)
      ReviewSendBatch
      call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
      call assert_equal(1, g:calls[-1].reconcile)
      call assert_equal(saved.id, g:calls[-1].draft.id)
      call assert_equal(saved.items, g:calls[-1].draft.items)
      ReviewUnpackBatch
      call assert_equal('batch', revue#session#Inspect(g:id).drafts[-1].kind)
    endfor
    let g:mode = 'ok'
    ReviewSendBatch
    call assert_equal(4, len(g:calls))
    call assert_equal(1, g:calls[0].reconcile)
    call assert_equal(saved.id, g:calls[0].draft.id)
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    call assert_equal('conversation', revue#session#Inspect(g:id).drafts[0].kind)
    let outcome = revue#session#Inspect(g:id).activity[-1]
    call assert_equal('accepted', outcome.outcome)
    call assert_equal(saved.id, outcome.operation)
    call assert_equal(1, len(outcome.receipt.items))
    call assert_equal(saved.items[0].id, outcome.targets[0].operation)
    call assert_match('completion.vim', outcome.targets[0].target)
  else
    let first = AddDraft('First concern')
    let second = AddDraft('Second concern')
    call revue#session#Conversation()
    call revue#session#NewConversation()
    call setline(1, 'Leave this unselected')
    let excluded = revue#session#Inspect(g:id).drafts[-1].id
    ReviewClose
    ReviewBatch
    call SelectDraft(excluded)
    call assert_equal(0, get(revue#session#Inspect(g:id).batchselected, excluded, 0))
    call SelectDraft(first)
    call SelectDraft(second)
    ReviewEditDraft
    call setline(1, 'Edited second concern')
    ReviewClose
    call assert_match('Edited second concern', join(getline(1, '$'), "\n"))
    " An edit from another window invalidates the displayed batch preview.
    for buf in revue#session#Inspect(g:id).buffers
      if getbufvar(buf, 'revue_draft', '') ==# second
        call setbufline(buf, 1, 'Changed outside the queue')
      endif
    endfor
    ReviewSendBatch
    call assert_equal([], g:calls)
    call assert_match('Changed outside the queue', join(getline(1, '$'), "\n"))
    ReviewSendBatch
    call assert_equal(1, len(g:calls))
    call assert_equal(2, len(g:calls[0].draft.items))
    call assert_equal('Changed outside the queue', g:calls[0].draft.items[1].body)
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    call assert_equal(excluded, revue#session#Inspect(g:id).drafts[0].id)

    let incomplete = AddDraft('Receipt must acknowledge this item')
    ReviewBatch
    call SelectDraft(incomplete)
    let g:mode = 'incomplete'
    ReviewSendBatch
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    call assert_match('Incomplete batch receipt', revue#session#Inspect(g:id).drafts[-1].error)
    let g:mode = 'ok'
    ReviewSendBatch
    call assert_equal(1, g:calls[-1].reconcile)
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))

    let failed = AddDraft('Fix after rejection')
    ReviewBatch
    call SelectDraft(failed)
    let g:mode = 'failed'
    ReviewSendBatch
    call assert_equal('failed', revue#session#Inspect(g:id).drafts[-1].state)
    ReviewUnpackBatch
    call assert_equal(failed, revue#session#Inspect(g:id).drafts[-1].id)
    call assert_equal('Fix after rejection', revue#session#Inspect(g:id).drafts[-1].body)
    let g:mode = 'unknown'
    ReviewSendBatch
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    ReviewUnpackBatch
    call assert_equal('batch', revue#session#Inspect(g:id).drafts[-1].kind)
    call assert_equal(5, len(g:calls))
  endif
  let outbox = revue#session#Inspect(g:id).draftpath
  let first_process = len(g:calls) == 5
  call revue#session#Close()
  if first_process
    " Also cover a crash with a durable submitting state before its callback.
    let saved = json_decode(readfile(outbox)[0])
    for draft in saved.drafts
      if draft.kind ==# 'batch' | let draft.state = 'submitting' | endif
    endfor
    call writefile([json_encode(saved)], outbox)
  endif
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
