set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.review_actions = [{'id': 'ACK', 'label': 'Acknowledge', 'body_required': 0}]
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'conversation': {'enabled': 1}, 'review': {'enabled': 1}}
let g:requests = []
let g:uncertain = 0
let g:receipt_error = ''
function! CapabilityHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  elseif a:request.op ==# 'mutate'
    call add(g:requests, deepcopy(a:request))
    if a:request.reconcile && !empty(g:receipt_error)
      call a:Done({'ok': 0, 'unknown': 0, 'error': g:receipt_error})
    elseif g:uncertain && !a:request.reconcile
      call a:Done({'ok': 0, 'unknown': 1, 'error': 'Receipt not yet visible'})
    else
      call a:Done({'ok': 1, 'data': {'id': 'accepted', 'recovered': a:request.reconcile}})
    endif
  endif
endfunction
try
  let g:fixture.snapshot.capabilities.comment = {'enabled': 0, 'reason': 'Read-only actor'}
  let id = revue#session#Open(g:fixture.snapshot, function('CapabilityHost'), 0)
  let s = revue#session#Inspect(id)
  call cursor(3, 1)
  call revue#session#Comment(0)
  call assert_equal([], revue#session#Inspect(id).drafts)
  let g:fixture.snapshot.capabilities.comment.enabled = 1
  call revue#session#Refresh()
  call revue#session#Comment(0)
  call setline(1, 'Keep this text after access changes.')
  let composer = win_getid()
  let g:fixture.snapshot.capabilities.comment.enabled = 0
  call revue#session#Refresh()
  call revue#session#Send()
  call assert_equal([], g:requests)
  call assert_equal(composer, win_getid())
  call assert_match('Keep this text', revue#session#Inspect(id).drafts[-1].body)
  ReviewClose
  " Object-specific rules may narrow, never widen the review's permission.
  let g:fixture.snapshot.threads[0].capabilities = {'reply': {'enabled': 0, 'reason': 'Thread is locked'}}
  call revue#session#Refresh()
  let before = len(revue#session#Inspect(id).drafts)
  call cursor(3, 1)
  call revue#session#Reply()
  call assert_equal(before, len(revue#session#Inspect(id).drafts))
  " A supported opaque decision may be submitted without invented prose.
  call feedkeys("1\<CR>", 't')
  call revue#session#Review()
  call assert_equal('draft', b:revue_role)
  call revue#session#Send()
  call assert_equal(1, len(g:requests))
  call assert_equal(['ACK', ''], [g:requests[0].draft.event, g:requests[0].draft.body])
  " Blank ordinary comments remain invalid.
  let snapshot = deepcopy(g:fixture.snapshot)
  let snapshot.capabilities.comment.enabled = 1
  call assert_match('Write a message', revue#capabilities#Error(snapshot, {'kind': 'comment', 'body': ''}, 1))
  let snapshot.review_actions[0].enabled = 0
  let snapshot.review_actions[0].reason = 'Actor cannot acknowledge'
  call assert_match('cannot acknowledge', revue#capabilities#Error(snapshot, {'kind': 'review', 'event': 'ACK'}, 0))
  call assert_match('no longer available', revue#capabilities#Error(snapshot, {'kind': 'review', 'event': 'UNKNOWN'}, 0))
  call remove(snapshot, 'capabilities')
  call assert_equal('', revue#capabilities#Error(snapshot, {'kind': 'comment', 'body': 'Legacy adapter'}, 1))
  " Reconciliation of an empty-body decision still works after access loss.
  let g:uncertain = 1
  call feedkeys("1\<CR>", 't')
  call revue#session#Review()
  call revue#session#Send()
  call assert_equal('unknown', revue#session#Inspect(id).drafts[-1].state)
  let g:fixture.snapshot.capabilities.review = {'enabled': 0, 'reason': 'Permission removed'}
  call revue#session#Refresh()
  let frozen = deepcopy(revue#session#Inspect(id).drafts[-1])
  for error in ['Read denied', 'Read timed out', 'Malformed receipt response']
    let g:receipt_error = error
    call revue#session#Send()
    call assert_equal('unknown', revue#session#Inspect(id).drafts[-1].state)
    call assert_equal(0, &modifiable)
    call assert_equal(1, g:requests[-1].reconcile)
    call assert_equal(frozen.id, g:requests[-1].draft.id)
    call assert_equal(frozen.body, g:requests[-1].draft.body)
    call assert_match('delivery still unknown', revue#session#Inspect(id).message)
    ReviewDiscard
    call assert_equal(frozen.id, revue#session#Inspect(id).drafts[-1].id)
  endfor
  let g:receipt_error = ''
  call revue#session#Send()
  call assert_equal(6, len(g:requests))
  call assert_equal(1, g:requests[-1].reconcile)
  call assert_equal(g:requests[-2].draft.id, g:requests[-1].draft.id)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
