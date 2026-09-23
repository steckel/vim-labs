set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'file_comment': {'enabled': 1}, 'start_pending': {'enabled': 1, 'body_required': 0},
      \ 'save_pending': {'enabled': 1, 'kinds': ['comment', 'file_comment']}, 'submit_pending': {'enabled': 1},
      \ 'batch': {'enabled': 1, 'mode': 'atomic', 'kinds': ['comment', 'file_comment']}}
let g:fixture.snapshot.review_actions = [{'id': 'COMMENT', 'enabled': 1}]
let g:fixture.snapshot.pending_reviews = {'available': v:true, 'actor': 'fixture:alex', 'items': []}
let g:native = {'id': '7', 'actor': 'fixture:alex', 'author': 'alex', 'head': g:fixture.snapshot.head, 'version': 'native', 'body': '', 'comments': []}
let g:calls = []
let g:mode = 'bad'
function! CreateHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    let draft = a:request.draft
    call assert_true(index(['create', 'add'], draft.pending_mode) >= 0)
    if g:mode ==# 'reject'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Private save unavailable'})
    elseif g:mode ==# 'bad'
      call a:Done({'ok': 1, 'data': {'id': draft.id, 'pending_review': 'wrong'}})
    else
      let g:fixture.snapshot.pending_reviews.items = [g:native]
      call a:Done({'ok': 1, 'data': {'id': draft.id, 'pending_mode': draft.pending_mode, 'actor': draft.actor, 'pending_review': '7'}})
    endif
  endif
endfunction
function! Source() abort
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
endfunction
try
  if filereadable($REVUE_CAP_STORE . '/file-add')
    let g:fixture.snapshot.pending_reviews.items = [g:native]
  endif
  let g:id = revue#session#Open(g:fixture.snapshot, function('CreateHost'), 0)
  if filereadable($REVUE_CAP_STORE . '/file-add')
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/file-add')[0])
    ReviewPending
    call cursor(5, 1)
    ReviewPublishPending COMMENT
    call assert_equal(frozen.id, b:revue_draft)
    ReviewSavePending
    ReviewDiscard
    call assert_equal(frozen, revue#session#Inspect(g:id).drafts[-1])
    let g:fixture.snapshot.capabilities.save_pending.enabled = 0
    ReviewRefresh
    let g:mode = 'ok'
    ReviewCheckReceipt
    call assert_equal(1, len(g:calls))
    call assert_equal(1, g:calls[0].reconcile)
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    call assert_equal('Keep local', revue#session#Inspect(g:id).drafts[0].body)
  elseif filereadable($REVUE_CAP_STORE . '/first-comment')
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/first-comment')[0])
    ReviewStartPending
    call assert_equal(frozen.id, b:revue_draft, 'start reuses uncertain first-comment creation')
    ReviewSavePending
    call assert_equal(frozen, revue#session#Inspect(g:id).drafts[-1])
    let g:mode = 'reject'
    ReviewCheckReceipt
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    let g:mode = 'ok'
    ReviewCheckReceipt
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    call Source()
    ReviewStartPending
    call assert_equal('pending', b:revue_view, 'existing native review resumes instead of creating another')
    call Source()
    ReviewComment
    call setline(1, 'Additional private line feedback')
    ReviewSavePending
    let draft = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('add', draft.pending_mode)
    call assert_equal('7', draft.pending_review)
    call assert_match('Add private feedback to pending review #7', join(getline(1, '$'), "\n"))
    call assert_match('cannot be published through a batch', revue#batch#Error(g:fixture.snapshot, [draft]))
    ReviewClose
    let g:native.head = 'old-source'
    ReviewRefresh
    ReviewSend
    call assert_equal(2, len(g:calls), 'different pending revision rejects addition')
    let g:native.head = g:fixture.snapshot.head
    ReviewRefresh
    ReviewSend
    call assert_equal('add', g:calls[-1].draft.pending_mode)
    call Source()
    ReviewFileComment
    call setline(1, 'Private whole-file concern')
    ReviewSavePending
    call assert_match('Private whole-file concern', join(getline(1, '$'), "\n"))
    ReviewClose
    let g:mode = 'bad'
    ReviewSend
    let frozen = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', frozen.state)
    call assert_false(has_key(frozen, 'start'))
    call writefile([json_encode(frozen)], $REVUE_CAP_STORE . '/file-add')
  else
    call Source()
    ReviewComment
    call setline(1, 'Keep local')
    ReviewClose
    ReviewStartPending
    call assert_equal('start_pending', revue#session#Inspect(g:id).drafts[-1].kind)
    call assert_equal('', revue#capabilities#Error(g:fixture.snapshot, revue#session#Inspect(g:id).drafts[-1], 1))
    ReviewDiscard
    call Source()
    ReviewComment
    call setline(1, 'First private line feedback')
    ReviewSavePending
    call assert_equal('preview', b:revue_view)
    call assert_match('Create a private pending review', join(getline(1, '$'), "\n"))
    call assert_notmatch('Keep local', join(getline(1, '$'), "\n"))
    ReviewClose
    let g:fixture.snapshot.pending_reviews.items = [g:native]
    ReviewRefresh
    ReviewSend
    call assert_equal([], g:calls, 'browser-started review blocks creating another')
    let g:fixture.snapshot.pending_reviews.items = []
    ReviewRefresh
    ReviewSend
    let frozen = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', frozen.state)
    call assert_equal('create', frozen.pending_mode)
    call writefile([json_encode(frozen)], $REVUE_CAP_STORE . '/first-comment')
    ReviewClose
    let g:fixture.snapshot.pending_reviews.items = [g:native]
    ReviewRefresh
    ReviewPending
    call cursor(5, 1)
    ReviewPublishPending COMMENT
    call assert_equal(frozen.id, b:revue_draft, 'unknown creation blocks publishing a newly visible review')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
