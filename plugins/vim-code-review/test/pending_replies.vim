set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'save_pending': {'enabled': 1, 'kinds': ['reply']}, 'submit_pending': {'enabled': 1}}
let g:fixture.snapshot.review_actions = [{'id': 'COMMENT', 'enabled': 1}]
let g:native = {'id': '7', 'actor': 'fixture:alex', 'author': 'alex', 'head': 'older-source', 'version': 'native', 'body': 'Pending summary', 'comments': []}
let g:fixture.snapshot.pending_reviews = {'available': v:true, 'actor': 'fixture:alex', 'items': [g:native]}
let g:thread = g:fixture.snapshot.threads[0]
let g:thread.capabilities = {'reply': {'enabled': 1}, 'pending_reply': {'enabled': 1}}
let g:calls = []
let g:mode = 'bad'
function! PrivateReplyHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    let draft = a:request.draft
    call assert_equal('reply', draft.kind)
    call assert_equal('add', draft.pending_mode)
    if g:mode ==# 'reject'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Reply state unavailable'})
    else
      let receipt = {}
      for key in ['id', 'pending_mode', 'pending_review', 'actor'] | let receipt[key] = draft[key] | endfor
      let receipt.thread = g:mode ==# 'bad' ? 'another-thread' : draft.thread
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
function! FocusReply() abort
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
  ReviewThread
  call cursor(1, 1)
  ReviewNextMessage
  ReviewNextMessage
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('PrivateReplyHost'), 0)
  if filereadable($REVUE_CAP_STORE . '/private-reply')
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/private-reply')[0])
    let g:fixture.snapshot.pending_reviews.items = []
    ReviewRefresh
    call FocusReply()
    ReviewReplyPending
    call assert_equal(frozen.id, b:revue_draft, 'existing private reply reopens after browser publication')
    call assert_false(&modifiable)
    ReviewClose
    ReviewQuote
    call assert_equal(frozen.id, b:revue_draft, 'quote must not bypass an unknown private save')
    call assert_equal(frozen.body, join(getline(1, '$'), "\n"))
    ReviewDiscard
    ReviewSavePending
    let g:mode = 'reject'
    ReviewCheckReceipt
    call assert_equal(frozen, revue#session#Inspect(g:id).drafts[-1])
    let g:mode = 'ok'
    ReviewCheckReceipt
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    call assert_equal('Unrelated local feedback', revue#session#Inspect(g:id).drafts[0].body)
    call assert_equal(1, g:calls[-1].reconcile)
    let g:fixture.snapshot.pending_reviews.items = [g:native]
    ReviewRefresh
    call FocusReply()
    ReviewReplyPending
    let private = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('add', private.pending_mode, 'explicit private reply on a published thread')
    call assert_equal('older-source', private.pending_head)
    ReviewDiscard
    call FocusReply()
    ReviewReply
    call assert_false(has_key(revue#session#Inspect(g:id).drafts[-1], 'pending_mode'), 'ordinary reply on a published thread remains ordinary')
    ReviewDiscard
    let g:thread.comments[0].publication = 'pending'
    let g:thread.capabilities.reply.enabled = 0
    ReviewRefresh
    call FocusReply()
    ReviewReply
    call assert_equal('add', revue#session#Inspect(g:id).drafts[-1].pending_mode, 'ordinary reply to a private thread stays private')
    ReviewDiscard
    call FocusReply()
    ReviewQuote
    call assert_equal('add', revue#session#Inspect(g:id).drafts[-1].pending_mode, 'a new quote in a private thread stays private')
    call assert_match('^>', getline(1))
    ReviewDiscard
  else
    call cursor(3, 1)
    ReviewComment
    call setline(1, 'Unrelated local feedback')
    ReviewClose
    call FocusReply()
    ReviewReply
    call setline(1, 'Retain my existing reply text.')
    let public_id = b:revue_draft
    ReviewClose
    let g:thread.comments[0].publication = 'pending'
    let g:thread.capabilities.reply.enabled = 0
    let g:fixture.snapshot.capabilities.reply.enabled = 0
    ReviewRefresh
    call FocusReply()
    ReviewReply
    call assert_equal(public_id, b:revue_draft, 'private intent does not silently replace a public draft')
    call assert_false(has_key(revue#session#Inspect(g:id).drafts[-1], 'pending_mode'))
    ReviewSavePending
    call assert_match('Add private feedback to pending review #7', join(getline(1, '$'), "\n"))
    call assert_match('Retain my existing reply text.', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewClose
    call FocusReply()
    let selected = deepcopy(revue#discussion#Selected(revue#session#Inspect(g:id), line('.')))
    ReviewQuote
    call assert_equal(public_id, b:revue_draft)
    call assert_match('^Retain my existing reply text.', getline(1))
    call assert_true(stridx(join(getline(1, '$'), "\n"), '> ' . split(selected.message.body, "\n", 1)[0]) >= 0)
    let draft = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('add', draft.pending_mode)
    call assert_equal('older-source', draft.pending_head)
    let rows = revue#comments#Rows(g:thread, 90)
    call assert_match('Reply privately', join(map(copy(rows), {_, r -> r.text}), "\n"))
    let g:thread.capabilities.pending_reply.enabled = 0
    ReviewRefresh
    ReviewSend
    call assert_equal([], g:calls)
    let g:thread.capabilities.pending_reply.enabled = 1
    ReviewRefresh
    let g:mode = 'reject'
    ReviewSend
    call assert_equal('failed', revue#session#Inspect(g:id).drafts[-1].state)
    call assert_true(&modifiable)
    let g:mode = 'bad'
    ReviewSend
    let frozen = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', frozen.state, 'wrong reply thread receipt cannot clear the draft')
    call writefile([json_encode(frozen)], $REVUE_CAP_STORE . '/private-reply')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
