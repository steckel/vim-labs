set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'discard_pending': {'enabled': 1}, 'submit_pending': {'enabled': 1}}
let g:fixture.snapshot.review_actions = [{'id': 'COMMENT', 'enabled': 1}]
let g:comment = {'message': '101', 'message_kind': 'comment', 'thread': '100', 'path': 'completion.vim', 'side': 'head', 'start': 3, 'line': 3, 'body': 'Private comment to remove', 'author': 'alex'}
let g:fixture.snapshot.pending_reviews = {'available': v:true, 'actor': 'fixture:alex', 'items': [
      \ {'id': '7', 'actor': 'fixture:alex', 'author': 'alex', 'head': g:fixture.snapshot.head, 'body': 'Private browser summary', 'version': 'original', 'comments': [g:comment], 'state': 'pending', 'url': ''}]}
let g:calls = []
let g:mode = 'bad'
function! DiscardHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    call assert_equal('discard_pending', a:request.draft.kind)
    if g:mode ==# 'reject'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Pending review changed'})
    elseif g:mode ==# 'bad'
      call a:Done({'ok': 1, 'data': {'id': a:request.draft.id, 'pending_review': '99'}})
    else
      let receipt = {'discarded': v:true, 'observed': v:true}
      for key in ['id', 'pending_review', 'actor'] | let receipt[key] = a:request.draft[key] | endfor
      let g:fixture.snapshot.pending_reviews.items = []
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
function! SelectPending() abort
  ReviewPending
  call cursor(5, 1)
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('DiscardHost'), 0)
  if filereadable($REVUE_CAP_STORE . '/frozen-discard')
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/frozen-discard')[0])
    call SelectPending()
    ReviewPublishPending COMMENT
    call assert_equal(frozen.id, b:revue_draft, 'publication must reuse uncertain discard')
    call assert_false(&modifiable)
    ReviewDiscard
    ReviewPendingBase
    let g:fixture.snapshot.capabilities.discard_pending.enabled = 0
    ReviewRefresh
    let g:mode = 'reject'
    ReviewCheckReceipt
    call assert_equal(frozen, revue#session#Inspect(g:id).drafts[-1])
    call assert_equal(1, g:calls[-1].reconcile)
    let g:mode = 'ok'
    ReviewCheckReceipt
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    call assert_equal('Keep this local draft', revue#session#Inspect(g:id).drafts[0].body)
    call assert_match('No pending reviews', join(getline(1, '$'), "\n"))
    call assert_match('absent for the verified actor', revue#session#Inspect(g:id).last_outcome)
  else
    call cursor(3, 1)
    ReviewComment
    call setline(1, 'Keep this local draft')
    ReviewClose
    call SelectPending()
    let g:fixture.snapshot.capabilities.discard_pending.enabled = 0
    ReviewRefresh
    ReviewDiscardPending
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    let g:fixture.snapshot.capabilities.discard_pending.enabled = 1
    ReviewRefresh
    call cursor(5, 1)
    ReviewDiscardPending
    call assert_equal('preview', b:revue_view)
    let preview = join(getline(1, '$'), "\n")
    call assert_match('Private browser summary', preview)
    call assert_match('Private comment to remove', preview)
    call assert_notmatch('Keep this local draft', preview)
    ReviewClose
    call assert_false(&modifiable)
    let g:fixture.snapshot.pending_reviews.items[0].version = 'changed'
    let g:fixture.snapshot.pending_reviews.items[0].body = 'Browser edited summary'
    ReviewRefresh
    ReviewSend
    call assert_equal([], g:calls)
    ReviewPreview
    call assert_match('Current pending review changed', join(getline(1, '$'), "\n"))
    call assert_match('Browser edited summary', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewDiscard
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    call SelectPending()
    ReviewDiscardPending
    ReviewClose
    let g:mode = 'reject'
    ReviewSend
    call assert_equal('failed', revue#session#Inspect(g:id).drafts[-1].state)
    call assert_false(&modifiable)
    let g:mode = 'bad'
    ReviewSend
    let frozen = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', frozen.state)
    call assert_equal('Browser edited summary', frozen.pending_body)
    call assert_equal('', frozen.body)
    call writefile([json_encode(frozen)], $REVUE_CAP_STORE . '/frozen-discard')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
