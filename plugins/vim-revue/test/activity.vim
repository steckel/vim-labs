set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'reply': {'enabled': 1}}
let g:calls = []
let g:mode = 'ok'
let g:refresh_failed = 0
let g:receiptfile = $REVUE_CAP_STORE . '/receipts'
function! ActivityHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  elseif a:request.op ==# 'refresh'
    call a:Done(g:refresh_failed ? {'ok': 0, 'error': 'Fixture network unavailable'} : {'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    let receipts = filereadable(g:receiptfile) ? json_decode(readfile(g:receiptfile)[0]) : {}
    let id = a:request.draft.id
    if a:request.reconcile
      call assert_true(has_key(receipts, id), 'recovery must query an existing receipt')
      let receipt = deepcopy(receipts[id])
      let receipt.recovered = 1
    else
      call assert_false(has_key(receipts, id), 'must not publish an operation twice')
      let receipt = {'id': 'receipt-' . len(receipts), 'url': 'https://example.test/reviews/' . len(receipts)}
      let receipts[id] = receipt
      call writefile([json_encode(receipts)], g:receiptfile)
    endif
    if g:mode ==# 'save-failed'
      call mkdir(revue#session#Inspect(g:id).draftpath . '.lock', '', 0700)
    endif
    call a:Done({'ok': 1, 'data': receipt})
  endif
endfunction
function! SelectMessage(id, kind) abort
  let state = revue#session#Inspect(g:id)
  for target in values(state.messagemap)
    if target.comment ==# a:id && target.kind ==# a:kind
      call cursor(target.start, 1)
      return
    endif
  endfor
  call assert_report('Message not found: ' . a:id)
endfunction
function! SelectOutcome(outcome) abort
  let state = revue#session#Inspect(g:id)
  for row in sort(keys(state.activityrows), 'n')
    if get(state.activityrows[row], 'outcome', '') ==# a:outcome
      call cursor(str2nr(row), 1)
      return
    endif
  endfor
  call assert_report('Outcome not found: ' . a:outcome)
endfunction
try
  let restarting = filereadable($REVUE_CAP_STORE . '/restart')
  if restarting
    let g:fixture.snapshot = json_decode(readfile($REVUE_CAP_STORE . '/snapshot')[0])
  else
    " A legacy v1 outbox has no activity/read fields and must still load.
    call mkdir(g:revue_draft_dir, 'p')
    call writefile([json_encode({'version': 1, 'key': g:fixture.snapshot.key, 'drafts': []})], g:revue_draft_dir . '/' . sha256(g:fixture.snapshot.key) . '.json')
  endif
  let g:id = revue#session#Open(g:fixture.snapshot, function('ActivityHost'), 0)
  if restarting
    let state = revue#session#Inspect(g:id)
    call assert_equal(1, len(state.drafts))
    call assert_equal('unknown', state.drafts[0].state)
    call assert_match('Sent', state.last_outcome)
    call assert_equal(1, len(revue#activity#Unread(state)))
    call assert_equal(1, len(filter(copy(state.activity), {_, e -> e.outcome ==# 'accepted'})))
    RevueActivity
    call search('## Pending', 'w')
    RevueOpenOperation
    call assert_equal(0, &modifiable)
    RevueCheckReceipt
    let state = revue#session#Inspect(g:id)
    call assert_equal([], state.drafts)
    call assert_equal(1, len(g:calls))
    call assert_equal(1, g:calls[0].reconcile)
    call assert_equal(2, len(json_decode(readfile(g:receiptfile)[0])))
    call assert_equal(2, len(filter(copy(state.activity), {_, e -> e.outcome ==# 'accepted'})))
    call assert_equal(1, state.activity[-1].receipt.recovered)
    RevueNextUnread
    call assert_equal('new-reply-2', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    RevueMarkRead
    call assert_equal([], revue#activity#Unread(revue#session#Inspect(g:id)))
    call revue#session#Close()
  else
    call assert_equal([], revue#activity#Unread(revue#session#Inspect(g:id)))
    call cursor(3, 1)
    RevueThread
    call SelectMessage('local-reply-1', 'comment')
    let oldrow = line('.')
    " IDs, not row offsets/body hashes/author names, define arrivals and selection.
    call insert(g:fixture.snapshot.threads[0].comments, {'id': 'inserted', 'author': 'same', 'body': 'Earlier inserted reply'}, 0)
    call add(g:fixture.snapshot.conversation, {'id': 'same-id', 'kind': 'comment', 'author': 'same', 'body': 'Conversation comment'})
    call add(g:fixture.snapshot.conversation, {'id': 'same-id', 'kind': 'review', 'author': 'same', 'body': 'Review summary'})
    call revue#session#Refresh()
    call assert_equal('local-reply-1', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    call assert_true(line('.') > oldrow)
    call assert_equal(3, len(revue#activity#Unread(revue#session#Inspect(g:id))))
    call assert_match('1 new', join(getline(1, '$'), "\n"))
    RevueMarkThreadRead
    call assert_equal(2, len(revue#activity#Unread(revue#session#Inspect(g:id))))
    RevueNextUnread
    call assert_equal('comment', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).kind)
    RevueMarkRead
    RevueNextUnread
    call assert_equal('review', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).kind)
    RevueMarkRead
    call assert_equal([], revue#activity#Unread(revue#session#Inspect(g:id)))
    " A thread outside the current file inventory remains readable; source jump is safe.
    let orphan = deepcopy(g:fixture.snapshot.threads[0])
    let orphan.id = 'orphan'
    let orphan.path = 'removed.vim'
    let orphan.comments = [{'id': 'orphan-message', 'author': 'same', 'body': 'Review on absent file'}]
    call add(g:fixture.snapshot.threads, orphan)
    call revue#session#Refresh()
    RevueNextUnread
    call assert_match('removed.vim', getline(1))
    let panelwin = win_getid()
    RevueJump
    call assert_equal(panelwin, win_getid())
    RevueMarkThreadRead
    call revue#session#Threads('local-thread')
    call SelectMessage('local-root', 'comment')
    RevueReply
    call setline(1, 'My saved reply body')
    let composer = bufnr()
    let editorwin = win_getid()
    call add(g:fixture.snapshot.threads[0].comments, {'id': 'new-reply', 'author': 'reviewer', 'body': 'A new reply while composing'})
    call revue#session#Refresh()
    call assert_equal(editorwin, win_getid())
    call assert_equal(composer, bufnr())
    call assert_equal(['My saved reply body'], getline(1, '$'))
    let g:refresh_failed = 1
    RevueSend
    let state = revue#session#Inspect(g:id)
    call assert_equal([], state.drafts)
    call assert_match('Sent', state.last_outcome)
    call assert_equal(['accepted', 'refresh-failed'], map(copy(state.activity), {_, e -> e.outcome}))
    RevueActivity
    call assert_match('network unavailable', join(getline(1, '$'), "\n"))
    call SelectOutcome('accepted')
    RevueCopyReceipt a
    call assert_equal('receipt-0', json_decode(@a).id)
    let before = bufnr()
    call revue#session#Reply()
    RevueOpenOperation
    call assert_equal(before, bufnr())
    call assert_equal(1, len(g:calls))
    let g:refresh_failed = 0
    call revue#session#Refresh()
    call assert_equal('accepted', revue#session#Inspect(g:id).activityrows[string(line('.'))].outcome)
    call assert_match('Last refresh: succeeded', join(getline(1, '$'), "\n"))
    call assert_match('REFRESH-FAILED', join(getline(1, '$'), "\n"))
    call cursor(1, 1)
    let @a = 'untouched'
    RevueCopyReceipt a
    call assert_equal('untouched', @a)
    RevueNextUnread
    RevueMarkRead
    call add(g:fixture.snapshot.threads[0].comments, {'id': 'new-reply-2', 'author': 'reviewer', 'body': 'Persist this unread message'})
    call revue#session#Refresh()
    " Crash after remote acceptance but before local acknowledgement persists.
    RevueReply
    call setline(1, 'Accepted immediately before storage failure')
    let g:mode = 'save-failed'
    RevueSend
    let state = revue#session#Inspect(g:id)
    call assert_equal([], state.drafts)
    call assert_equal(2, len(filter(copy(state.activity), {_, e -> e.outcome ==# 'accepted'})))
    call assert_match('Cannot lock', state.persistence_error)
    RevueActivity
    call assert_match('NOT SAVED', join(getline(1, '$'), "\n"))
    let disk = json_decode(join(readfile(state.draftpath), "\n"))
    call assert_equal('submitting', disk.drafts[0].state)
    call delete(state.draftpath . '.lock', 'd')
    call writefile(['restart'], $REVUE_CAP_STORE . '/restart')
    call writefile([json_encode(g:fixture.snapshot)], $REVUE_CAP_STORE . '/snapshot')
    " No Close/save: emulate process loss with the durable submitting intent.
  endif
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
