set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
set columns=140 lines=45
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:a = deepcopy(g:fixture.snapshot)
let g:a.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}}
let second = deepcopy(g:a.files[0])
let second.id = 'second'
let second.path = 'other.vim'
let second.old_path = 'other.vim'
call add(g:a.files, second)
let g:b = deepcopy(g:a)
let g:b.snapshot = 'comparison-b'
let g:b.head = 'head-b'
let g:b.base = 'base-b'
let g:b.base_tip = 'base-tip-b'
let g:b.files[0].path = 'renamed.vim'
let g:b.files[0].status = 'renamed'
let g:b.threads[0].outdated = v:true
let g:b.threads[0].line = 0
let g:latest = deepcopy(g:a)
let g:defer = 0
let g:requests_pending = []
let g:calls = []
let g:reads = []
function! Contents(request) abort
  let result = deepcopy(g:fixture.content)
  for side in ['base', 'head']
    let result[side].lines[0] = a:request.snapshot.snapshot . ' ' . a:request.file.path . ' ' . side
  endfor
  return result
endfunction
function! ComparisonHost(request, Done) abort
  if a:request.op ==# 'file'
    call add(g:reads, deepcopy(a:request))
    if g:defer
      call add(g:requests_pending, {'Done': a:Done, 'request': deepcopy(a:request)})
    else
      call a:Done({'ok': 1, 'data': Contents(a:request)})
    endif
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:latest)})
  else
    call add(g:calls, deepcopy(a:request))
    call assert_equal('reply', a:request.draft.kind)
    call assert_equal('local-thread', a:request.draft.thread)
    call assert_equal(g:a.snapshot, a:request.draft.snapshot)
    call a:Done({'ok': 1, 'data': {'id': 'accepted-old-thread-reply'}})
  endif
endfunction
try
  let restart = filereadable($REVUE_CAP_STORE . '/restart')
  if restart | let g:latest = deepcopy(g:b) | endif
  let g:id = revue#session#Open(g:latest, function('ComparisonHost'), 0)
  let state = revue#session#Inspect(g:id)
  if restart
    call assert_equal(g:b.snapshot, state.snapshot.snapshot)
    call assert_equal(1, len(filter(values(state.comparisons), {_, c -> has_key(c, 'snapshot')})), 'only the initial snapshot is loaded; saved history contains references')
    call assert_false(has_key(state.comparisons[g:a.snapshot], 'snapshot'))
    call assert_equal(g:a.snapshot, state.drafts[0].snapshot)
    ReviewActivity
    call search('## Pending', 'w')
    ReviewOpenOperation
    call assert_equal(['Keep this original inline draft'], getline(1, '$'))
    ReviewSend
    call assert_equal([], g:calls)
    call assert_equal(g:a.snapshot, revue#session#Inspect(g:id).drafts[0].snapshot)
    call revue#session#Close()
  else
    " Composer return restores its original file, side and cursor after a file switch.
    call win_gotoid(state.basewin)
    call cursor(3, 4)
    ReviewComment
    call setline(1, 'Keep this original inline draft')
    let editor = win_getid()
    call win_gotoid(state.headwin)
    ReviewNextFile
    call assert_equal('other.vim', b:revue_file)
    call win_gotoid(editor)
    ReviewClose
    call assert_equal('completion.vim', b:revue_file)
    call assert_equal('base', b:revue_side)
    call assert_equal([3, 4], [line('.'), col('.')])
    " Refresh sees B while A's source and draft stay frozen.
    let g:latest = deepcopy(g:b)
    let previous = win_getid()
    ReviewRefresh
    let state = revue#session#Inspect(g:id)
    call assert_equal(previous, win_getid())
    call assert_equal(g:a.snapshot, state.snapshot.snapshot)
    call assert_equal(g:b.snapshot, state.latest_comparison)
    call assert_match('historical', &statusline)
    call assert_match('ReviewLatest', join(getbufline(state.tree, 1, '$'), "\n"))
    ReviewComparisons
    call assert_match('comparison-b', join(getline(1, '$'), "\n"))
    call search('\[latest\]', 'w')
    ReviewOpenComparison
    call assert_equal(g:b.snapshot, b:revue_comparison)
    call assert_equal('renamed.vim', b:revue_file)
    call assert_match('comparison-b renamed.vim', getline(1))
    call assert_match('base-b', getwinvar(revue#session#Inspect(g:id).basewin, '&statusline'))
    call cursor(6, 2)
    ReviewPreviousComparison
    call assert_equal(g:a.snapshot, b:revue_comparison)
    call assert_equal('completion.vim', b:revue_file)
    call assert_match(g:a.snapshot, getline(1))
    ReviewLatest
    call assert_equal([6, 2], [line('.'), col('.')])
    " Source positions/caches cannot collide even when backend file IDs repeat.
    call assert_equal(3, len(g:reads))
    ReviewPreviousComparison
    call assert_equal(3, len(g:reads))
    call win_gotoid(revue#session#Inspect(g:id).headwin)
    call cursor(3, 1)
    ReviewThread
    ReviewNextMessage
    let selected = revue#discussion#Selected(revue#session#Inspect(g:id), line('.'))
    ReviewReply
    call setline(1, 'Reply to the original thread')
    let replywin = win_getid()
    " The original discussion window can be manually closed while composing.
    call win_gotoid(revue#session#Inspect(g:id).panelwin)
    close
    call win_gotoid(replywin)
    ReviewLatest
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call win_gotoid(replywin)
    ReviewClose
    call assert_equal(g:a.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call assert_equal(selected.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    ReviewActivity
    call search('## Pending · reply', 'w')
    ReviewOpenOperation
    call assert_equal(['Reply to the original thread'], getline(1, '$'))
    " Reply remains targeted by thread identity even though B is the latest source.
    ReviewSend
    call assert_equal(1, len(g:calls))
    call assert_equal(g:a.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    " A stale inline draft cannot be published while either A or B is displayed.
    ReviewActivity
    call search('## Pending', 'w')
    ReviewOpenOperation
    ReviewSend
    call assert_equal(1, len(g:calls))
    let olddraft = deepcopy(revue#session#Inspect(g:id).drafts[0])
    ReviewLatest
    call assert_equal(olddraft, revue#session#Inspect(g:id).drafts[0])
    " A delayed file response from B must not overwrite a return to A.
    let g:defer = 1
    ReviewNextFile
    call assert_equal(1, len(g:requests_pending))
    ReviewPreviousComparison
    let active = win_getid()
    let pending = remove(g:requests_pending, 0)
    call pending.Done({'ok': 1, 'data': Contents(pending.request)})
    call assert_equal(active, win_getid())
    call assert_equal(g:a.snapshot, b:revue_comparison)
    call assert_match(g:a.snapshot, getline(1))
    let g:defer = 0
    ReviewLatest
    " B second file was not cached from the discarded stale callback; load it now.
    if !empty(g:requests_pending)
      let pending = remove(g:requests_pending, 0)
      call pending.Done({'ok': 1, 'data': Contents(pending.request)})
    endif
    call assert_match('comparison-b other.vim', getline(1))
    " A comparison with no changed files clears the previous code and labels.
    let g:latest = deepcopy(g:b)
    let g:latest.snapshot = 'empty-comparison'
    let g:latest.head = 'empty-head'
    let g:latest.files = []
    ReviewRefresh
    ReviewLatest
    let state = revue#session#Inspect(g:id)
    call assert_equal(-1, state.index)
    call assert_equal(['No changed files in this comparison.'], getbufline(state.head, 1, '$'))
    call assert_match('empty-head', getwinvar(state.headwin, '&statusline'))
    ReviewPreviousComparison
    call assert_equal(g:b.snapshot, b:revue_comparison)
    call assert_equal(olddraft, revue#session#Inspect(g:id).drafts[0])
    let disk = json_decode(join(readfile(revue#session#Inspect(g:id).draftpath), "\n"))
    call assert_false(has_key(disk, 'comparisons'))
    call writefile(['restart'], $REVUE_CAP_STORE . '/restart')
    call revue#session#Close()
  endif
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
