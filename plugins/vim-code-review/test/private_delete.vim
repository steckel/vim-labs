set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'delete_pending_comment': {'enabled': 1, 'body_required': 0}, 'submit_pending': {'enabled': 1}}
let g:fixture.snapshot.review_actions = [{'id': 'COMMENT', 'enabled': 1}]
let g:thread = g:fixture.snapshot.threads[0]
let g:thread.id = '100'
let g:private = []
for i in range(3)
  let m = g:thread.comments[i]
  call extend(m, {'id': string(100 + i), 'kind': 'comment', 'author': 'alex', 'body': ['Root stays', 'First reply stays', 'Second reply to delete'][i],
        \ 'version': 'v1', 'publication': 'pending', 'pending_review': '7', 'actor': 'fixture:alex',
        \ 'capabilities': {'delete': {'enabled': i > 0, 'scope': 'message', 'reason': 'Root has replies'}}})
  call add(g:private, {'message': m.id, 'message_kind': 'comment', 'thread': '100', 'body': m.body,
        \ 'path': 'completion.vim', 'side': 'head', 'start': 3, 'line': 3, 'author': 'alex'})
endfor
let g:fixture.snapshot.pending_reviews = {'available': v:true, 'actor': 'fixture:alex', 'items': [
      \ {'id': '7', 'actor': 'fixture:alex', 'author': 'alex', 'head': g:fixture.snapshot.head, 'body': 'Review summary stays', 'version': 'review-v1', 'comments': g:private}]}
let g:calls = []
let g:mode = 'bad'
function! DeleteHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    call assert_equal('delete_pending_comment', a:request.draft.kind)
    call assert_equal('102', a:request.draft.message)
    call assert_equal('100', a:request.draft.thread)
    call assert_equal('7', a:request.draft.pending_review)
    call assert_equal('', a:request.draft.body)
    if g:mode ==# 'reject'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Permission changed'})
    elseif g:mode ==# 'bad'
      call a:Done({'ok': 1, 'data': {'id': a:request.draft.id, 'deleted': v:true, 'message': '101'}})
    else
      let receipt = {'deleted': v:true, 'observed': v:true}
      for key in ['id', 'message', 'message_kind', 'thread', 'pending_review', 'actor', 'delete_scope'] | let receipt[key] = a:request.draft[key] | endfor
      call filter(g:fixture.snapshot.threads[0].comments, {_, m -> m.id !=# '102'})
      call filter(g:fixture.snapshot.pending_reviews.items[0].comments, {_, m -> m.message !=# '102'})
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
function! SelectReply() abort
  call revue#session#Threads('100')
  call search('^Second reply', 'w')
  call revue#session#MessageFocus()
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('DeleteHost'), 0)
  if filereadable($REVUE_CAP_STORE . '/private-delete')
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/private-delete')[0])
    ReviewPending
    call cursor(5, 1)
    ReviewPublishPending COMMENT
    call assert_equal(frozen.id, b:revue_draft)
    call assert_false(&modifiable)
    ReviewDiscard
    call assert_equal(2, len(revue#session#Inspect(g:id).drafts))
    let g:fixture.snapshot.capabilities.delete_pending_comment.enabled = 0
    ReviewRefresh
    let g:mode = 'reject'
    ReviewCheckReceipt
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    call assert_equal(1, g:calls[-1].reconcile)
    let g:mode = 'ok'
    ReviewCheckReceipt
    let session = revue#session#Inspect(g:id)
    call assert_equal(1, len(session.drafts))
    call assert_equal('Keep my local draft', session.drafts[0].body)
    call assert_equal(['100', '101'], map(copy(session.snapshot.threads[0].comments), {_, m -> m.id}))
    call assert_equal('Review summary stays', session.snapshot.pending_reviews.items[0].body)
    call assert_match('absent from its review', session.last_outcome)
    call assert_true(session.last_receipt.observed)
  else
    call cursor(3, 1)
    ReviewComment
    call setline(1, 'Keep my local draft')
    ReviewClose
    call SelectReply()
    let g:fixture.snapshot.capabilities.delete_pending_comment.enabled = 0
    ReviewRefresh
    ReviewDeletePendingComment
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    let g:fixture.snapshot.capabilities.delete_pending_comment.enabled = 1
    ReviewRefresh
    call SelectReply()
    let guide = revue#session#ActionGuide()
    call assert_equal('', filter(copy(guide), {_, x -> x.id ==# 'delete-pending-comment'})[0].reason)
    let snap = deepcopy(revue#session#Inspect(g:id).snapshot)
    let fields = revue#delete#Fields(snap, {'message': '102', 'message_kind': 'comment', 'thread': '100'})
    let snap.threads[0].comments[2].capabilities.delete = {'enabled': 0, 'scope': 'message', 'reason': ''}
    call assert_false(empty(revue#delete#Error(snap, fields)), 'empty permission reason must still reject')
    let receipt = extend(deepcopy(fields), {'id': 'operation', 'deleted': v:true})
    let fields.id = 'operation'
    call assert_true(revue#delete#Receipt(fields, receipt))
    let receipt.message = 102
    call assert_false(revue#delete#Receipt(fields, receipt), 'receipt target must be an opaque string')
    ReviewDeletePendingComment
    call assert_equal('preview', b:revue_view)
    let preview = join(getline(1, '$'), "\n")
    call assert_match('Second reply to delete', preview)
    call assert_notmatch('First reply stays', preview)
    call assert_match('comment #102', preview)
    ReviewClose
    call assert_false(&modifiable)
    let g:fixture.snapshot.threads[0].comments[2].body = 'Second reply edited elsewhere'
    let g:fixture.snapshot.threads[0].comments[2].version = 'v2'
    ReviewRefresh
    ReviewSend
    call assert_equal(0, len(g:calls))
    ReviewPreview
    call assert_match('Current message changed', join(getline(1, '$'), "\n"))
    call assert_match('Second reply edited elsewhere', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewDiscard
    call SelectReply()
    call search('^Root stays', 'w')
    ReviewDeletePendingComment
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts), 'root with replies must be unavailable')
    ReviewPending
    call search('^Second reply', 'w')
    ReviewDeletePendingComment
    call assert_equal('preview', b:revue_view)
    ReviewClose
    let g:mode = 'reject'
    ReviewSend
    call assert_equal('failed', revue#session#Inspect(g:id).drafts[-1].state)
    let g:mode = 'bad'
    ReviewSend
    let frozen = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', frozen.state)
    call assert_equal('102', frozen.message)
    call assert_equal('Second reply edited elsewhere', frozen.original_body)
    call writefile([json_encode(frozen)], $REVUE_CAP_STORE . '/private-delete')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
