set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile($REVUE_PRIVATE_FIXTURE), "\n"))
let g:requests = []
function! PrivatePageHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  else
    call add(g:requests, {'request': deepcopy(a:request), 'Done': a:Done})
  endif
endfunction
function! PickPrivate(message) abort
  let state = revue#session#Inspect(g:id)
  for row in sort(keys(state.pendingrows), 'n')
    if get(get(state.pendingrows[row], 'target', {}), 'message', '') ==# a:message | call cursor(str2nr(row), 1) | return | endif
  endfor
  throw 'Private message absent'
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'private-pages', 'review': '42', 'snapshot': g:fixture.first, 'Request': function('PrivatePageHost')}, 0)
  ReviewPending
  call assert_match('2/4 comments loaded', join(getline(1, '$'), "\n"))
  call PickPrivate('102')
  let selected = deepcopy(revue#session#Inspect(g:id).pendingrows[string(line('.'))])
  call assert_match('VerifyPending', filter(revue#session#ActionGuide(), {_, a -> a.id ==# 'publish-pending'})[0].reason)
  ReviewPublishPending
  call assert_equal([], revue#session#Inspect(g:id).drafts, 'partial publication cannot create a draft')
  ReviewDiscardPending
  call assert_equal([], revue#session#Inspect(g:id).drafts, 'partial discard cannot create a draft')
  ReviewLoadMoreFeedback
  call g:requests[-1].Done({'ok': 1, 'data': g:fixture.page})
  call assert_equal('', revue#session#Inspect(g:id).feedback_read.error)
  call assert_equal(selected, revue#session#Inspect(g:id).pendingrows[string(line('.'))])
  call assert_match('4/4 comments loaded', join(getline(1, '$'), "\n"))
  call assert_false(revue#pending#Find(revue#session#Inspect(g:id).snapshot, '7').complete)
  call PickPrivate('202')
  ReviewOpenPending
  call assert_equal('202', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  ReviewClose
  call PickPrivate('202')
  ReviewVerifyPending
  let cancelled = g:requests[-1]
  ReviewCancelVerifyPending
  call cancelled.Done({'ok': 1, 'data': g:fixture.verified})
  call assert_false(revue#pending#Find(revue#session#Inspect(g:id).snapshot, '7').complete)
  ReviewVerifyPending
  call g:requests[-1].Done({'ok': 0, 'error': 'No connection'})
  call assert_match('No connection', join(getline(1, '$'), "\n"))
  ReviewVerifyPending
  let bad = deepcopy(g:fixture.verified)
  call remove(bad.review.comments, 0)
  call g:requests[-1].Done({'ok': 1, 'data': bad})
  call assert_false(revue#pending#Find(revue#session#Inspect(g:id).snapshot, '7').complete)
  ReviewVerifyPending
  let stale = g:requests[-1]
  ReviewRefresh
  call g:requests[-1].Done({'ok': 1, 'data': g:fixture.first})
  call stale.Done({'ok': 1, 'data': g:fixture.verified})
  call assert_match('refresh changed', revue#session#Inspect(g:id).pending_verification.error)
  call assert_false(revue#pending#Find(revue#session#Inspect(g:id).snapshot, '7').complete)
  ReviewCancelRefresh
  ReviewVerifyPending
  ReviewHelp
  let helpwin = win_getid()
  call g:requests[-1].Done({'ok': 1, 'data': g:fixture.verified})
  call assert_equal(helpwin, win_getid())
  call assert_equal('help', b:revue_view)
  ReviewClose
  call assert_true(revue#pending#Find(revue#session#Inspect(g:id).snapshot, '7').complete)
  call assert_equal('202', get(get(revue#session#Inspect(g:id).pendingrows[string(line('.'))], 'target', {}), 'message', ''))
  " Full publication can now be prepared, without sending anything.
  call revue#session#PublishPending('COMMENT')
  call assert_equal('submit_pending', revue#session#Inspect(g:id).drafts[-1].kind)
  call assert_equal(4, len(revue#session#Inspect(g:id).drafts[-1].pending_comments))
  call assert_equal(g:fixture.verified.review.version, revue#session#Inspect(g:id).drafts[-1].expected_version)
  call assert_equal([], filter(copy(g:requests), {_, r -> r.request.op ==# 'mutate'}))
  " Header changes and forged comment targets invalidate the entire page.
  for badfield in ['actor', 'read_version', 'total', 'body', 'message']
    let sample = deepcopy(g:fixture.first)
    let data = deepcopy(g:fixture.page)
    if badfield ==# 'actor' | let data.pending_reviews.actor = 'foreign' | endif
    if badfield ==# 'read_version' | let data.pending_reviews.items[0].read_version = 'changed' | endif
    if badfield ==# 'total' | let data.pending_reviews.items[0].total = 1 | endif
    if badfield ==# 'body' | let data.pending_reviews.items[0].comments[0].body = 'forged' | endif
    if badfield ==# 'message' | let data.pending_reviews.items[0].comments[0].message = 'foreign' | endif
    let failed = 0
    try
      call revue#feedback#Merge(sample, data, sample.feedback.cursor)
    catch
      let failed = 1
    endtry
    call assert_true(failed, badfield)
  endfor
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
