set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'edit': {'enabled': 1}, 'edit_pending': {'enabled': 1}, 'submit_pending': {'enabled': 1}, 'discard_pending': {'enabled': 1}}
let g:fixture.snapshot.review_actions = [{'id': 'COMMENT', 'enabled': 1}]
let g:summary = {'id': '7', 'kind': 'PENDING', 'body': 'Private summary', 'author': 'alex', 'publication': 'pending', 'pending_review': '7', 'actor': 'fixture:alex', 'version': 'summary-original', 'capabilities': {'edit': {'enabled': 1, 'body_required': 0}}}
let g:review = {'id': '7', 'body': g:summary.body, 'summary': g:summary, 'author': 'alex', 'actor': 'fixture:alex', 'head': g:fixture.snapshot.head, 'version': 'review-original', 'comments': []}
let g:fixture.snapshot.pending_reviews = {'available': v:true, 'actor': 'fixture:alex', 'items': [g:review]}
for message in g:fixture.snapshot.threads[0].comments
  call extend(message, {'version': 'original-' . message.id, 'publication': 'pending', 'pending_review': '7', 'actor': 'fixture:alex', 'capabilities': {'edit': {'enabled': 1}}})
  call add(g:review.comments, {'message': message.id, 'message_kind': 'comment', 'thread': g:fixture.snapshot.threads[0].id,
        \ 'body': message.body, 'author': message.author, 'path': 'completion.vim', 'side': 'head', 'start': 3, 'line': 3})
endfor
let g:calls = []
let g:mode = 'ok'
function! PrivateEditHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    let draft = a:request.draft
    call assert_equal('edit', draft.kind)
    call assert_equal('7', draft.pending_review)
    if g:mode ==# 'reject'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Private review unavailable'})
    elseif g:mode ==# 'bad'
      let receipt = {}
      for key in ['id', 'message', 'message_kind', 'thread'] | let receipt[key] = draft[key] | endfor
      call a:Done({'ok': 1, 'data': receipt})
    else
      let receipt = {}
      for key in ['id', 'message', 'message_kind', 'thread', 'pending_review', 'actor'] | let receipt[key] = draft[key] | endfor
      let message = revue#edit#Message(g:fixture.snapshot, draft)
      let message.body = draft.body
      let message.version = 'saved-' . draft.id
      if draft.message_kind ==# 'PENDING' | let g:review.body = draft.body | endif
      let g:review.version = 'saved-' . draft.id
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
function! SelectPrivate(reply) abort
  ReviewPending
  for row in sort(keys(revue#session#Inspect(g:id).pendingrows), 'n')
    let target = revue#session#Inspect(g:id).pendingrows[row]
    if !a:reply && !has_key(target, 'target') || a:reply && get(get(target, 'target', {}), 'message', '') ==# g:fixture.snapshot.threads[0].comments[1].id
      call cursor(str2nr(row), 1)
      return
    endif
  endfor
  throw 'Missing pending target'
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('PrivateEditHost'), 0)
  if filereadable($REVUE_CAP_STORE . '/private-edit')
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/private-edit')[0])
    call SelectPrivate(0)
    ReviewPublishPending COMMENT
    call assert_equal(frozen.id, b:revue_draft, 'publication resumes unfinished private edit')
    call assert_false(&modifiable)
    let g:fixture.snapshot.capabilities.edit_pending.enabled = 0
    ReviewRefresh
    ReviewEditBase
    ReviewDiscard
    let g:mode = 'reject'
    ReviewCheckReceipt
    call assert_equal(frozen, revue#session#Inspect(g:id).drafts[-1])
    let g:mode = 'ok'
    ReviewCheckReceipt
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    call assert_equal('', g:summary.body)
    call assert_equal(1, g:calls[-1].reconcile)
  else
    call SelectPrivate(0)
    ReviewPublishPending COMMENT
    let publication = deepcopy(revue#session#Inspect(g:id).drafts[-1])
    ReviewClose
    call SelectPrivate(1)
    ReviewEditPending
    call assert_equal(publication.id, b:revue_draft, 'private editing reopens unfinished publication')
    ReviewDiscard
    call SelectPrivate(1)
    ReviewOpenPending
    ReviewEditMessage
    let draft = deepcopy(revue#session#Inspect(g:id).drafts[-1])
    call assert_equal(g:fixture.snapshot.threads[0].comments[1].id, draft.message)
    call assert_equal('7', draft.pending_review)
    call setline(1, 'Revised private reply')
    if line('$') > 1 | 2,$delete _ | endif
    ReviewPreview
    call assert_match('Save privately in pending review #7', join(getline(1, '$'), "\n"))
    call assert_match('Revised private reply', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewClose
    call SelectPrivate(0)
    ReviewDiscardPending
    call assert_equal(draft.id, b:revue_draft, 'discard resumes unfinished private edit')
    let message = revue#edit#Message(g:fixture.snapshot, draft)
    let message.publication = 'published'
    ReviewRefresh
    ReviewSend
    ReviewEditBase
    call assert_equal([], g:calls, 'never reinterpret private edit as public edit')
    let message.publication = 'pending'
    let message.body = 'Browser changed private reply'
    let message.version = 'browser-edit'
    ReviewRefresh
    ReviewSend
    call assert_equal([], g:calls)
    ReviewPreview
    call assert_match('Browser changed private reply', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewEditBase
    call assert_equal('Revised private reply', getline(1))
    ReviewSend
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    call assert_equal('pending', revue#edit#Message(g:fixture.snapshot, draft).publication)
    call SelectPrivate(0)
    ReviewEditPending
    call assert_equal('Private summary', getline(1))
    call assert_equal('PENDING', revue#session#Inspect(g:id).drafts[-1].message_kind)
    call setline(1, '')
    let g:mode = 'bad'
    ReviewSend
    let frozen = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', frozen.state, 'receipt without private target fields stays unknown')
    call assert_equal('', frozen.body, 'clearing a private summary is allowed')
    call writefile([json_encode(frozen)], $REVUE_CAP_STORE . '/private-edit')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
