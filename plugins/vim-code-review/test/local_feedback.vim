set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.backend = {'id': 'local', 'connection': 'fixture', 'review': 'pending-cards'}
let g:writes = []
function! FeedbackHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:writes, deepcopy(a:request))
    throw 'Pending cards and Markdown export must not send backend mutations'
  endif
endfunction
try
  let id = revue#session#Open(g:fixture.snapshot, function('FeedbackHost'), 0)
  let state = revue#session#Inspect(id)
  call win_gotoid(state.headwin)
  if empty(state.drafts)
    call cursor(3, 1)
    let before_props = len(prop_list(3, {'bufnr': state.head}))
    ReviewComment
    call setline(1, ['Why this approach?', '', '```rust', 'let value = "雪";', '```'])
    write
    let first = revue#session#Inspect(id).drafts[-1].id
    call assert_match('Pending', &statusline)
    call assert_equal(1, len(revue#local_feedback#Cards(revue#session#Inspect(id))))
    call assert_true(len(prop_list(3, {'bufnr': state.head})) > before_props, 'Pending card is attached to the source buffer immediately')
    ReviewClose
    call cursor(3, 1)
    ReviewEditFeedback
    call assert_equal(first, b:revue_draft)
    call append('$', 'Explain the alternatives.')
    call mkdir(state.draftpath . '.lock')
    let composer = bufnr()
    ReviewSend
    call assert_equal(composer, bufnr(), 'Failed save keeps feedback open')
    call assert_true(&modified)
    call delete(state.draftpath . '.lock', 'd')
    ReviewSend
    call assert_equal(state.headwin, win_getid())
    call assert_equal('draft', revue#session#Inspect(id).drafts[0].state)
    call cursor(2, 1)
    ReviewComment
    call setline(1, 'Leave this one out of the export.')
    ReviewClose
  endif
  let state = revue#session#Inspect(id)
  call assert_equal(2, len(revue#local_feedback#Cards(state)), 'Pending cards survive a process restart')
  let pending = revue#local_feedback#Cards(state)[0]
  let historical = deepcopy(state)
  for draft in historical.drafts | let draft.snapshot = 'older-comparison' | endfor
  call assert_equal([], revue#local_feedback#Cards(historical), 'Historical feedback must not attach to newer code')
  call assert_equal('older-comparison', revue#local_feedback#Items(historical)[0].snapshot)
  let rows = revue#comments#Rows(pending, 80, {})
  call assert_match('Pending', join(map(copy(rows), {_, r -> r.text}), "\n"))
  call assert_match('ReviewEditFeedback', join(map(copy(rows), {_, r -> r.text}), "\n"))
  let before = deepcopy(state.drafts)
  ReviewBatch
  call assert_equal('feedback', b:revue_view)
  call assert_match('Pending', join(getline(1, '$'), "\n"))
  call search('Why this approach?', 'W')
  ReviewToggleFeedback
  let collection = bufnr()
  ReviewExportMarkdown
  let export = bufnr()
  let markdown = join(getline(1, '$'), "\n")
  call assert_equal('markdown', &filetype)
  call assert_match('Why this approach?', markdown)
  call assert_match('Explain the alternatives.', markdown)
  call assert_match('let value = "雪";', markdown)
  call assert_match('completion.vim:3-3 (head)', markdown)
  call assert_notmatch('Leave this one out', markdown)
  execute 'write! ' . fnameescape($REVUE_CAP_STORE . '/export.md')
  call assert_equal(getline(1, '$'), readfile($REVUE_CAP_STORE . '/export.md'))
  call assert_equal(before, revue#session#Inspect(id).drafts, 'Export must not consume feedback')
  tabclose
  call assert_equal(collection, bufnr())
  ReviewSelectFeedback
  ReviewExportMarkdown
  call assert_match('Leave this one out', join(getline(1, '$'), "\n"))
  call assert_match('Status: Saved', join(getline(1, '$'), "\n"), 'Previously saved feedback is exportable too')
  tabclose
  ReviewClearFeedback
  let tabs = tabpagenr('$')
  ReviewExportMarkdown
  call assert_equal(tabs, tabpagenr('$'), 'Empty selection does not create an export')
  ReviewRefresh
  call assert_equal('feedback', b:revue_view)
  call assert_equal(before, revue#session#Inspect(id).drafts)
  call search('Why this approach?', 'w')
  ReviewEditFeedback
  call assert_equal('draft', b:revue_role)
  call append('$', 'Changed from the feedback picker.')
  ReviewClose
  call assert_equal('feedback', b:revue_view)
  call assert_match('Changed from the feedback picker.', join(getline(1, '$'), "\n"))
  ReviewSelectFeedback
  " An unsaved hidden composer must update the preview before it can export.
  let state = revue#session#Inspect(id)
  let buf = get(filter(copy(state.buffers), {_, b -> getbufvar(b, 'revue_draft', '') ==# g:state.drafts[0].id}), 0, 0)
  call setbufline(buf, 1, getbufline(buf, 1)[0] . ' Updated while collecting.')
  let tabs = tabpagenr('$')
  ReviewExportMarkdown
  call assert_equal(tabs, tabpagenr('$'))
  call assert_match('Updated while collecting.', join(getline(1, '$'), "\n"))
  ReviewExportMarkdown
  call assert_match('Updated while collecting.', join(getline(1, '$'), "\n"))
  tabclose
  call assert_equal([], g:writes)
  call revue#session#Close()
  call assert_true(bufexists(export), 'Export remains after review closes')
  call assert_equal(markdown, join(getbufline(export, 1, '$'), "\n"))
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
