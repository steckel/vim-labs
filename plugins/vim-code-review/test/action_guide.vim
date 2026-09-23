set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:revue_mappings = {'review-actions': 'gA', 'comment': 'gc'}
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'save_pending': {'enabled': 1, 'kinds': ['comment', 'reply']}, 'start_pending': {'enabled': 1, 'body_required': 0}}
let g:fixture.snapshot.pending_reviews = {'available': v:true, 'actor': 'fixture:alex', 'items': []}
let g:calls = []
function! GuideHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    throw 'Action guide fixture cannot mutate'
  endif
endfunction
function! GuideItem(id) abort
  return get(filter(revue#session#ActionGuide(), {_, i -> i.id ==# a:id}), 0, {})
endfunction
function! GuideChoose(id) abort
  let items = revue#session#ActionGuide()
  let choice = index(map(copy(items), {_, i -> i.id}), a:id) + 1
  call assert_true(choice > 0, a:id)
  call feedkeys(choice . "\<CR>", 't')
  ReviewReviewActions
endfunction
function! GuideChanged(timer) abort
  let g:fixture.snapshot.capabilities.comment = {'enabled': 0, 'reason': 'Review access changed'}
  ReviewRefresh
  call feedkeys(g:choice . "\<CR>", 't')
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('GuideHost'), 0)
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
  call assert_equal('<Plug>(revue-review-actions)', maparg('gA', 'n'))
  call assert_equal('gc', GuideItem('comment').key)
  call assert_equal('', GuideItem('comment').reason)
  call assert_match('whole.file', GuideItem('file-comment').label)
  call assert_false(empty(GuideItem('file-comment').reason))
  " Native input prompt runs a refresh timer: stale selection must do nothing.
  let g:choice = index(map(revue#session#ActionGuide(), {_, i -> i.id}), 'comment') + 1
  call timer_start(80, function('GuideChanged'))
  ReviewReviewActions
  call assert_equal([], revue#session#Inspect(g:id).drafts)
  call assert_equal('Review access changed', GuideItem('comment').reason)
  call GuideChoose('comment')
  call assert_equal([], revue#session#Inspect(g:id).drafts)
  let g:fixture.snapshot.capabilities.comment.enabled = 1
  let g:fixture.snapshot.capabilities.comment.reason = ''
  ReviewRefresh
  call GuideChoose('comment')
  call assert_equal('draft', b:revue_role)
  call assert_match('Publish feedback', GuideItem('send').label)
  call setline(1, 'Keep my feedback while I inspect the available actions.')
  call GuideChoose('save-local')
  call assert_false(&modified)
  call assert_equal(getline(1), revue#session#Inspect(g:id).drafts[-1].body)
  call assert_equal([], g:calls)
  call GuideChoose('save-pending')
  call assert_equal('preview', b:revue_view)
  ReviewClose
  call assert_match('Save privately', GuideItem('send').label)
  call assert_match('Review private-save target', GuideItem('save-pending').label)
  ReviewHelp
  call assert_match('Save privately', join(getline(1, '$'), "\n"))
  call assert_match('Save draft locally', join(getline(1, '$'), "\n"))
  ReviewClose
  call assert_equal('draft', b:revue_role)
  ReviewClose
  " Choosing message actions retains the second reply, even with two menus.
  ReviewThread
  call cursor(1, 1)
  ReviewNextMessage
  ReviewNextMessage
  let selected = revue#discussion#Selected(revue#session#Inspect(g:id), line('.'))
  call assert_equal('local-reply-1', selected.comment)
  let choice = index(map(revue#session#ActionGuide(), {_, i -> i.id}), 'actions') + 1
  call feedkeys(choice . "\<CR>2\<CR>", 't')
  ReviewReviewActions
  call assert_equal(selected.message.body, getreg('"'))
  call assert_equal(selected.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  " A selected private reply on a published root still has private intent.
  let g:fixture.snapshot.pending_reviews.items = [{'id': '7', 'actor': 'fixture:alex', 'author': 'alex', 'head': g:fixture.snapshot.head, 'version': 'v1', 'body': '', 'comments': []}]
  let g:fixture.snapshot.threads[0].comments[1].publication = 'pending'
  let g:fixture.snapshot.threads[0].capabilities = {'reply': {'enabled': 0}, 'pending_reply': {'enabled': 1}}
  ReviewRefresh
  call assert_equal('Compose a private reply', GuideItem('reply').label)
  call assert_equal('', GuideItem('reply').reason)
  call GuideChoose('reply')
  " Existing private creation is surfaced before a new reply can be prepared.
  call assert_equal('comment', revue#session#Inspect(g:id).drafts[0].kind)
  call assert_match('Keep my feedback', getline(1))
  call GuideChoose('save-pending')
  ReviewClose
  ReviewClose
  call GuideChoose('reply')
  call setline(1, 'Retained private reply after access changes.')
  call GuideChoose('save-local')
  ReviewClose
  let g:fixture.snapshot.pending_reviews.items = []
  let g:fixture.snapshot.capabilities.save_pending.enabled = 0
  ReviewRefresh
  call assert_equal('', GuideItem('reply-pending').reason, 'existing reply remains reachable after permission loss')
  call assert_match('Continue existing reply', GuideItem('reply-pending').label)
  call GuideChoose('reply-pending')
  call assert_match('Retained private reply', getline(1))
  call assert_false(empty(GuideItem('send').reason))
  ReviewClose
  ReviewClose
  " The outbox opens its selected draft through the same guide.
  call win_gotoid(revue#session#Inspect(g:id).treewin)
  let original = revue#session#Inspect(g:id).drafts[0].id
  for [row, target] in items(revue#session#Inspect(g:id).rows)
    if get(target, 'kind', '') ==# 'draft' && target.id ==# original
      call cursor(str2nr(row), 1)
      call GuideChoose('open')
      break
    endif
  endfor
  call assert_equal('draft', b:revue_role)
  call assert_match('Keep my feedback', getline(1))
  call assert_equal([], g:calls)
  call revue#session#Close()
  let g:revue_no_default_mappings = 1
  let g:revue_mappings = {}
  let g:id = revue#session#Open(g:fixture.snapshot, function('GuideHost'), 0)
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call assert_equal('', maparg('gA', 'n'))
  call assert_equal('', GuideItem('comment').key)
  call assert_equal(2, exists(':ReviewReviewActions'))
  call assert_false(empty(maparg('<Plug>(revue-review-actions)', 'n')))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
