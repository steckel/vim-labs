set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'file_comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'suggestion': {'enabled': 1, 'sides': ['head']}, 'review': {'enabled': 1},
      \ 'stage_batch': {'enabled': 1, 'mode': 'sequential', 'kinds': ['comment', 'file_comment', 'reply']},
      \ 'save_pending': {'enabled': 1, 'kinds': ['comment', 'file_comment', 'reply']}, 'start_pending': {'enabled': 1, 'body_required': 0},
      \ 'batch': {'enabled': 1, 'mode': 'atomic', 'kinds': ['comment', 'review']}, 'submit_pending': {'enabled': 1}, 'discard_pending': {'enabled': 1}}
let g:fixture.snapshot.review_actions = [{'id': 'COMMENT', 'label': 'Comment', 'enabled': 1}]
let g:fixture.snapshot.threads[0].capabilities = {'reply': {'enabled': 1}, 'pending_reply': {'enabled': 1}}
let g:serverfile = $REVUE_CAP_STORE . '/server'
let g:server = filereadable(g:serverfile) ? json_decode(readfile(g:serverfile)[0]) : {'receipts': {}, 'writes': 0, 'native': {}}
let g:phasefile = $REVUE_CAP_STORE . '/phase'
let g:phase = filereadable(g:phasefile) ? str2nr(readfile(g:phasefile)[0]) : 1
let g:mode = g:phase == 1 ? 'unknown-create' : 'fail-reply'
let g:calls = []
function! StageSnapshot() abort
  let snapshot = deepcopy(g:fixture.snapshot)
  let snapshot.pending_reviews = {'available': v:true, 'actor': 'fixture:alex', 'items': empty(g:server.native) ? [] : [deepcopy(g:server.native)]}
  return snapshot
endfunction
function! StageHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': StageSnapshot()})
  else
    call add(g:calls, deepcopy(a:request))
    let draft = a:request.draft
    call assert_notequal('batch', draft.kind, 'private queue never uses publishing batch endpoint')
    call assert_false(has_key(draft, 'event'), 'staging carries no review decision')
    if a:request.reconcile
      call assert_true(has_key(g:server.receipts, draft.id), 'only the uncertain step is recovered')
      call a:Done({'ok': 1, 'data': g:server.receipts[draft.id]})
      return
    endif
    call assert_false(has_key(g:server.receipts, draft.id), 'accepted steps are never resent')
    if g:mode ==# 'fail-reply' && draft.kind ==# 'reply'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Reply temporarily rejected'})
      return
    endif
    if draft.kind ==# 'start_pending'
      call assert_equal({}, g:server.native)
      call assert_equal('create', draft.pending_mode)
      let g:server.native = {'id': '7', 'actor': 'fixture:alex', 'author': 'alex', 'head': draft.head, 'version': 'v1', 'body': '', 'comments': []}
    else
      call assert_equal('add', draft.pending_mode)
      call assert_equal('7', draft.pending_review)
      call assert_equal(g:server.native.head, draft.pending_head)
      if draft.kind ==# 'file_comment'
        call assert_false(has_key(draft, 'side'))
      elseif draft.kind ==# 'comment'
        call assert_true(draft.suggestion)
        call assert_equal(3, draft.start)
      endif
    endif
    let receipt = {'id': draft.id, 'actor': draft.actor, 'pending_mode': draft.pending_mode, 'pending_review': '7'}
    if draft.kind ==# 'reply' | let receipt.thread = draft.thread | endif
    let g:server.receipts[draft.id] = deepcopy(receipt)
    let g:server.writes += 1
    call writefile([json_encode(g:server)], g:serverfile)
    if g:mode ==# 'disk-fail'
      call mkdir(revue#session#Inspect(g:id).draftpath . '.lock')
    endif
    if g:mode ==# 'unknown-create'
      call a:Done({'ok': 0, 'unknown': 1, 'error': 'Connection lost after creating review'})
    else
      if g:mode ==# 'bad-last' && draft.kind ==# 'comment' | let receipt.pending_review = 'wrong-review' | endif
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
function! PrivateBatch() abort
  return get(filter(revue#session#Inspect(g:id).drafts, {_, d -> get(d, 'delivery', '') ==# 'private'}), 0, {})
endfunction
function! AwaitStage() abort
  for attempt in range(200)
    let batch = PrivateBatch()
    if empty(batch) || batch.state !=# 'submitting' | return | endif
    sleep 10m
  endfor
  call assert_report('Private queue did not stop')
endfunction
function! SelectStage(id) abort
  let state = revue#session#Inspect(g:id)
  if get(state.batchselected, a:id, 0) | return | endif
  for [row, id] in items(state.batchrows)
    if id ==# a:id
      call cursor(str2nr(row), 1)
      RevueToggleDraft
      return
    endif
  endfor
  call assert_report('Missing stage item')
endfunction
function! Source() abort
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
endfunction
try
  let g:id = revue#session#Open(StageSnapshot(), function('StageHost'), 0)
  let denied = StageSnapshot()
  let denied.capabilities.stage_batch = {'enabled': 0, 'mode': 'sequential', 'reason': ''}
  call assert_false(empty(revue#stage#Availability(denied)), 'empty backend reason must still deny private staging')
  if g:phase == 1
    call Source()
    RevueFileComment
    call setline(1, 'Review the whole completion file.')
    RevueClose
    call Source()
    RevueReply
    call setline(1, 'Please preserve prefix matching.')
    RevueClose
    call Source()
    RevueSuggest
    RevueClose
    call feedkeys("1\<CR>", 't')
    RevueReview
    call setline(1, 'Keep this decision for later publication.')
    RevueClose
    let drafts = revue#session#Inspect(g:id).drafts
    call assert_match('review decisions', revue#stage#Error(StageSnapshot(), [drafts[-1]], revue#stage#Binding(StageSnapshot())))
    RevueStageBatch
    for item in drafts[:2] | call SelectStage(item.id) | endfor
    call assert_match('Saved one at a time', join(getline(1, '$'), "\n"))
    RevueSendBatch
    call AwaitStage()
    let batch = PrivateBatch()
    call assert_equal('unknown', batch.state)
    call assert_equal(['unknown', 'waiting', 'waiting', 'waiting'], map(copy(batch.steps), {_, s -> s.state}))
    call assert_equal(1, g:server.writes)
    RevueUnpackBatch
    call assert_equal(batch.id, PrivateBatch().id)
    RevueRefresh
    RevuePending
    call cursor(5, 1)
    RevuePublishPending
    call assert_equal('batch', b:revue_view, 'publication surfaces uncertain creation')
    call assert_equal(batch.id, revue#session#Inspect(g:id).batchid)
  elseif g:phase == 2
    let batch = PrivateBatch()
    call assert_equal('unknown', batch.state)
    let g:fixture.snapshot.capabilities.stage_batch.enabled = 0
    RevueRefresh
    call revue#session#Batch(batch.id)
    RevueCheckReceipt
    call AwaitStage()
    call assert_equal(1, len(g:calls))
    call assert_equal(1, g:calls[0].reconcile)
    call assert_equal('failed', PrivateBatch().state, 'receipt recovery pauses before unattempted writes')
    call assert_equal('7', PrivateBatch().pending_review)
    call assert_equal(1, g:server.writes)
    let g:fixture.snapshot.capabilities.stage_batch.enabled = 1
    RevueRefresh
    RevueSendBatch
    call AwaitStage()
    call assert_equal(['accepted', 'accepted', 'failed', 'waiting'], map(copy(PrivateBatch().steps), {_, s -> s.state}))
    call assert_equal(2, g:server.writes)
    let saved = PrivateBatch().items[0].id
    RevueUnpackBatch
    call assert_equal({}, PrivateBatch())
    let remaining = revue#session#Inspect(g:id).drafts
    call assert_equal(-1, index(map(copy(remaining), {_, d -> d.id}), saved))
    call assert_equal(['review', 'reply', 'comment'], map(copy(remaining), {_, d -> d.kind}))
    call assert_match('Keep this decision', remaining[0].body)
    let g:mode = 'bad-last'
    RevueStageBatch
    for item in remaining[1:] | call SelectStage(item.id) | endfor
    RevueSendBatch
    call AwaitStage()
    call assert_equal(['accepted', 'unknown'], map(copy(PrivateBatch().steps), {_, s -> s.state}))
    call assert_equal(4, g:server.writes)
    call assert_match('another private review', PrivateBatch().error)
    RevueUnpackBatch
    call assert_equal('unknown', PrivateBatch().state)
  elseif g:phase == 3
    call assert_equal('unknown', PrivateBatch().state)
    let g:fixture.snapshot.capabilities.stage_batch.enabled = 0
    RevueRefresh
    RevueStageBatch
    RevueCheckReceipt
    call AwaitStage()
    call assert_equal({}, PrivateBatch())
    call assert_equal(1, len(g:calls))
    call assert_equal(1, g:calls[0].reconcile)
    call assert_equal(4, g:server.writes)
    let remaining = revue#session#Inspect(g:id).drafts
    call assert_equal(1, len(remaining))
    call assert_equal('review', remaining[0].kind)
    call assert_match('Keep this decision', remaining[0].body)
    let receipt = revue#session#Inspect(g:id).last_receipt
    call assert_equal('7', receipt.pending_review)
    call assert_equal(2, len(receipt.items))
  else
    let baseline = g:server.writes
    call Source()
    RevueFileComment
    call setline(1, 'A second whole-file observation.')
    RevueClose
    call Source()
    RevueReply
    call setline(1, 'A second reply for this discussion.')
    RevueClose
    let drafts = revue#session#Inspect(g:id).drafts
    RevueStageBatch
    for item in drafts[1:] | call SelectStage(item.id) | endfor
    let g:mode = 'disk-fail'
    RevueSendBatch
    call AwaitStage()
    call assert_equal(baseline + 1, g:server.writes, 'receipt persistence failure stops before the next item')
    call assert_equal(['unknown', 'waiting'], map(copy(PrivateBatch().steps), {_, s -> s.state}))
    call assert_match('local receipt persistence failed', PrivateBatch().error)
    call delete(revue#session#Inspect(g:id).draftpath . '.lock', 'd')
    let g:mode = 'fail-reply'
    RevueCheckReceipt
    call AwaitStage()
    call assert_equal(['accepted', 'waiting'], map(copy(PrivateBatch().steps), {_, s -> s.state}))
    call assert_equal(baseline + 1, g:server.writes, 'receipt check does not save a waiting item')
    RevueSendBatch
    call AwaitStage()
    call assert_equal(['accepted', 'failed'], map(copy(PrivateBatch().steps), {_, s -> s.state}))
    let child = PrivateBatch().steps[1].draft.id
    let g:mode = 'ok'
    RevueSendBatch
    call AwaitStage()
    call assert_equal({}, PrivateBatch())
    call assert_equal(child, g:calls[-1].draft.id, 'known failure resumes the same unsaved operation')
    call assert_equal(baseline + 2, g:server.writes, 'accepted file feedback was not resent')
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
  endif
  call writefile([string(g:phase + 1)], g:phasefile)
  let draftfile = revue#session#Inspect(g:id).draftpath
  call revue#session#Close()
  if g:phase == 1
    " Simulate a process stopping with the first request still in flight.
    let disk = json_decode(join(readfile(draftfile), "\n"))
    for operation in disk.drafts
      if get(operation, 'delivery', '') ==# 'private'
        let operation.state = 'submitting'
        let operation.steps[0].state = 'submitting'
      endif
    endfor
    call writefile([json_encode(disk)], draftfile)
  endif
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
