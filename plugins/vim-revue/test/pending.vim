set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'pending_reviews': {'enabled': 1}, 'submit_pending': {'enabled': 1}}
let g:fixture.snapshot.review_actions = [{'id': 'COMMENT', 'label': 'Comment', 'enabled': 1, 'body_required': 1}, {'id': 'APPROVE', 'label': 'Approve', 'enabled': 0, 'reason': 'Author cannot approve own review'}]
let g:comment = {'message': g:fixture.snapshot.threads[0].comments[1].id, 'message_kind': 'comment', 'thread': 'local-thread',
      \ 'path': 'completion.vim', 'side': 'head', 'start': 3, 'line': 3, 'body': 'Private browser-started feedback', 'author': 'alex'}
let g:fixture.snapshot.threads[0].comments[1].body = g:comment.body
let g:fixture.snapshot.threads[0].comments[1].publication = 'pending'
let g:fixture.snapshot.pending_reviews = {'available': v:true, 'actor': 'fixture:alex', 'items': [
      \ {'id': '7', 'actor': 'fixture:alex', 'author': 'alex', 'head': g:fixture.snapshot.head, 'body': 'Browser summary', 'version': 'original', 'comments': [g:comment], 'state': 'pending', 'url': ''}]}
let g:calls = []
let g:mode = 'ok'
function! PendingHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    call assert_equal('submit_pending', a:request.draft.kind)
    if g:mode ==# 'reject'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Publication permission unavailable'})
    elseif g:mode ==# 'bad'
      call a:Done({'ok': 1, 'data': {'id': 'wrong-review'}})
    else
      let d = a:request.draft
      let g:fixture.snapshot.pending_reviews.items = []
      let receipt = {}
      for key in ['id', 'pending_review', 'actor', 'event'] | let receipt[key] = d[key] | endfor
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
function! SelectPending(comment) abort
  for row in sort(keys(revue#session#Inspect(g:id).pendingrows), 'n')
    let item = revue#session#Inspect(g:id).pendingrows[row]
    if has_key(item, 'target') == a:comment | call cursor(str2nr(row), 1) | return | endif
  endfor
  throw 'Missing pending review row'
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('PendingHost'), 0)
  if filereadable($REVUE_CAP_STORE . '/pending-publication')
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/pending-publication')[0])
    RevuePending
    call SelectPending(0)
    RevuePublishPending COMMENT
    call assert_equal(frozen.id, b:revue_draft)
    call assert_false(&modifiable)
    let g:fixture.snapshot.capabilities.submit_pending.enabled = 0
    RevueRefresh
    RevuePendingBase
    RevueDiscard
    let g:mode = 'reject'
    RevueCheckReceipt
    call assert_equal(frozen, revue#session#Inspect(g:id).drafts[-1])
    call assert_equal(1, g:calls[-1].reconcile)
    let g:mode = 'ok'
    RevueCheckReceipt
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts), 'local outbox draft was not published')
    call assert_equal('Still only local', revue#session#Inspect(g:id).drafts[0].body)
    call assert_match('No pending reviews', join(getline(1, '$'), "\n"))
  else
    call cursor(3, 1)
    RevueComment
    call setline(1, 'Still only local')
    RevueClose
    RevuePending
    call assert_match('Private reviews · saved on backend', join(getline(1, '$'), "\n"))
    call assert_match('Not published', join(getline(1, '$'), "\n"))
    call assert_match('Browser summary', join(getline(1, '$'), "\n"))
    call SelectPending(1)
    RevueOpenPending
    call assert_equal(g:comment.message, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    call assert_match('Pending review', getline('.'))
    RevueClose
    call assert_equal('pending', b:revue_view)
    call SelectPending(0)
    RevuePublishPending APPROVE
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    RevuePublishPending COMMENT
    call assert_equal('Browser summary', getline(1))
    call setline(1, 'My revised summary')
    RevuePreview
    let preview = join(getline(1, '$'), "\n")
    call assert_match('Private browser-started feedback', preview)
    call assert_match('My revised summary', preview)
    call assert_notmatch('Still only local', preview)
    RevueClose
    let g:fixture.snapshot.pending_reviews.items[0].version = 'changed'
    let g:fixture.snapshot.pending_reviews.items[0].body = 'Concurrent browser summary'
    let g:fixture.snapshot.pending_reviews.items[0].comments[0].body = 'Concurrent private feedback'
    RevueRefresh
    RevueSend
    call assert_equal([], g:calls)
    RevuePreview
    call assert_match('Current pending review changed', join(getline(1, '$'), "\n"))
    call assert_match('Concurrent private feedback', join(getline(1, '$'), "\n"))
    call assert_match('Concurrent browser summary', join(getline(1, '$'), "\n"))
    RevueClose
    RevuePendingBase
    call assert_equal('My revised summary', getline(1))
    call assert_equal('changed', revue#session#Inspect(g:id).drafts[-1].expected_version)
    let g:mode = 'reject'
    RevueSend
    call assert_true(&modifiable)
    call assert_equal('failed', revue#session#Inspect(g:id).drafts[-1].state)
    let g:mode = 'bad'
    RevueSend
    call assert_false(&modifiable)
    let frozen = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', frozen.state)
    call writefile([json_encode(frozen)], $REVUE_CAP_STORE . '/pending-publication')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
