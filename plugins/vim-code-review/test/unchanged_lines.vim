set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.content.base.lines = map(range(1, 80), {_, n -> 'unchanged source ' . n})
let g:fixture.content.head.lines = copy(g:fixture.content.base.lines)
let g:fixture.content.head.lines[4] = 'changed source 5'
let g:fixture.snapshot.files[0].patch = "@@ -4,3 +4,3 @@\n unchanged source 4\n-unchanged source 5\n+changed source 5\n unchanged source 6"
let g:fixture.snapshot.files[0].old_path = 'old-completion.vim'
let g:fixture.snapshot.files[0].status = 'renamed'
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'suggestion': {'enabled': 1, 'sides': ['head']},
      \ 'batch': {'enabled': 1, 'mode': 'atomic', 'kinds': ['comment']}}
let g:fixture.snapshot.threads = [{'id': 'outside-root', 'path': 'completion.vim', 'side': 'head', 'start': 48, 'line': 50, 'outdated': 0,
      \ 'comments': [{'id': 'outside-root', 'kind': 'comment', 'author': 'sam', 'created': '', 'body': 'This unchanged code needs an update too.'}]}]
let g:writes = []
function! UnchangedHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:writes, deepcopy(a:request))
    call a:Done(a:request.reconcile ? {'ok': 1, 'data': {'id': 'receipt', 'recovered': 1}} : {'ok': 0, 'unknown': 1, 'error': 'Fixture accepted; reply lost'})
  endif
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('UnchangedHost'), 0)
  let state = revue#session#Inspect(g:id)
  if filereadable($REVUE_CAP_STORE . '/frozen')
    let g:frozen = json_decode(readfile($REVUE_CAP_STORE . '/frozen')[0])
    call assert_equal('unknown', filter(copy(state.drafts), {_, d -> d.id ==# g:frozen.id})[0].state)
    ReviewDiscussions Unchanged draft
    call search('## Local draft', 'W')
    ReviewOpenDiscussion
    call assert_equal(g:frozen.body, join(getline(1, '$'), "\n"))
    call assert_false(&modifiable)
    ReviewCheckReceipt
    call assert_equal(1, len(g:writes))
    call assert_equal(1, g:writes[0].reconcile)
    call assert_equal(extend(deepcopy(g:frozen), {'state': 'submitting'}), g:writes[0].draft)
    call assert_equal([], filter(revue#session#Inspect(g:id).drafts, {_, d -> d.id ==# g:frozen.id}))
  else
    let target = {'kind': 'comment', 'path': 'completion.vim', 'old_path': 'old-completion.vim', 'side': 'head', 'start': 48, 'end': 50}
    call assert_match('returned diff hunks', revue#anchor#Error(g:fixture.snapshot, target, g:fixture.content.head))
    call assert_false(revue#anchor#InDiff(g:fixture.snapshot.files[0], target))
    call assert_true(len(filter(prop_list(50, {'bufnr': state.head}), {_, p -> p.type ==# 'RevueCardBorder'})) > 0, 'received outside-hunk comments render even with creation disabled')
    call cursor(48, 1)
    ReviewComment
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    call cursor(1, 1)
    normal! zM
    call assert_true(foldclosed(50) > 0)
    ReviewNextThread
    call assert_equal(50, line('.'))
    call assert_equal(-1, foldclosed(50), 'thread motion opens the native code fold')
    ReviewThread
    call assert_match('head:48-50', getline(4))
    ReviewNextMessage
    ReviewQuote
    call assert_equal('outside-root', revue#session#Inspect(g:id).drafts[0].thread)
    ReviewClose
    ReviewJump
    call assert_equal(50, line('.'))
    call assert_equal(-1, foldclosed(50))
    let g:fixture.snapshot.capabilities.comment.anchors = {'scope': 'changed_file', 'sides': ['base', 'head']}
    ReviewRefresh
    let before = deepcopy(g:fixture.content)
    call assert_equal('', revue#anchor#Error(g:fixture.snapshot, target, before.head))
    for fields in [{'path': 'absent.vim'}, {'old_path': 'wrong.vim'}, {'side': 'other'}, {'start': 0}, {'end': 81}, {'start': v:true}]
      call assert_false(empty(revue#anchor#Error(g:fixture.snapshot, extend(copy(target), fields), before.head)))
    endfor
    for kind in ['binary', 'unavailable', 'absent']
      call assert_match('Source text is unavailable', revue#anchor#Error(g:fixture.snapshot, target, {'kind': kind, 'lines': []}))
    endfor
    let policy = deepcopy(g:fixture.snapshot)
    let policy.capabilities.comment.anchors.sides = ['base']
    call assert_match('head side', revue#anchor#Error(policy, target))
    let policy.capabilities.comment.anchors = {'scope': 'unknown'}
    call assert_match('unsupported line-anchor policy', revue#anchor#Error(policy, target))
    let policy.capabilities.comment.anchors = {'scope': 'diff', 'reason': ''}
    call assert_false(empty(revue#anchor#Error(policy, target)), 'empty reason cannot enable invalid anchors')
    call setpos("'<", [0, 50, 1, 0])
    call setpos("'>", [0, 48, 1, 0])
    call revue#session#Comment(1)
    call setline(1, ['Unchanged draft', 'Preserve this multiline feedback'])
    call revue#session#SaveDraft()
    let g:draft = deepcopy(revue#session#Inspect(g:id).drafts[-1])
    call assert_equal([48, 50, 'old-completion.vim'], [g:draft.start, g:draft.end, g:draft.old_path])
    ReviewPreview
    call assert_match('Outside the diff hunks', join(getline(1, '$'), "\n"))
    call assert_match('48 │ unchanged source 48', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewClose
    48,50ReviewSuggest
    call assert_equal(before.head.lines[47:49], revue#suggestion#Parse(join(getline(1, '$'), "\n")).lines)
    ReviewPreview
    call assert_match('Suggested change', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewClose
    call win_gotoid(state.basewin)
    48,50ReviewComment
    call assert_equal('base', revue#session#Inspect(g:id).drafts[-1].side)
    call setline(1, 'Original-side feedback')
    ReviewClose
    call win_gotoid(state.headwin)
    ReviewDiscussions Unchanged draft
    call search('## Local draft', 'W')
    ReviewOpenDiscussion
    let g:fixture.snapshot.capabilities.comment.anchors = {'scope': 'diff', 'reason': 'Unchanged-line comments are no longer supported.'}
    call revue#session#Refresh()
    ReviewSend
    call assert_equal([], g:writes)
    call assert_equal(g:draft.body, join(getline(1, '$'), "\n"))
    call assert_match('no longer supported', revue#batch#Error(g:fixture.snapshot, [g:draft]))
    ReviewPreview
    call assert_match('Unchanged-line comments are no longer supported', join(getline(1, '$'), "\n"))
    ReviewClose
    let g:fixture.snapshot.capabilities.comment.anchors.scope = 'changed_file'
    call revue#session#Refresh()
    call assert_equal('', revue#batch#Error(g:fixture.snapshot, [g:draft]))
    ReviewSend
    call assert_equal(1, len(g:writes))
    call assert_equal([48, 50, 'completion.vim', 'old-completion.vim'], [g:writes[0].draft.start, g:writes[0].draft.end, g:writes[0].draft.path, g:writes[0].draft.old_path])
    call assert_equal(before, g:fixture.content)
    call assert_equal(before.head.lines, getbufline(state.head, 1, '$'))
    let frozen = filter(revue#session#Inspect(g:id).drafts, {_, d -> d.id ==# g:draft.id})[0]
    call writefile([json_encode(frozen)], $REVUE_CAP_STORE . '/frozen')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
