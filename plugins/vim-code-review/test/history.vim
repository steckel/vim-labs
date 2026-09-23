set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
set columns=140 lines=45
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:a = deepcopy(g:fixture.snapshot)
let g:a.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'comparisons': {'enabled': 1}}
let g:b = deepcopy(g:a)
let g:b.snapshot = 'comparison-b'
let g:b.head = 'head-b'
let g:d = deepcopy(g:a)
let g:d.snapshot = 'comparison-d'
let g:d.head = 'head-d'
let g:all = {g:a.snapshot: g:a, g:b.snapshot: g:b, g:d.snapshot: g:d}
let g:mode = 'ok'
let g:history_mode = 'ok'
let g:calls = []
function! HistoryHost(request, Done) abort
  call add(g:calls, deepcopy(a:request))
  if a:request.op ==# 'file'
    let content = deepcopy(g:fixture.content)
    let content.head.lines[0] = a:request.snapshot.snapshot
    call a:Done({'ok': 1, 'data': content})
  elseif a:request.op ==# 'comparisons'
    if g:history_mode ==# 'deferred'
      let g:HistoryDone = a:Done
      return
    endif
    call a:Done({'ok': 1, 'data': {'items': map([g:a, g:b, g:d], {_, s -> revue#comparisons#Reference(s)}), 'latest': deepcopy(g:b), 'complete': 1, 'scope': 'Fixture history'}})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:d)})
  elseif a:request.op ==# 'comparison'
    if g:mode ==# 'failed'
      call a:Done({'ok': 0, 'error': 'Historical commit unavailable'})
    elseif g:mode ==# 'wrong'
      call a:Done({'ok': 1, 'data': deepcopy(g:b)})
    elseif g:mode ==# 'deferred'
      let g:CompareDone = a:Done
      let g:requested = deepcopy(a:request.reference)
    else
      call a:Done({'ok': 1, 'data': deepcopy(g:all[a:request.reference.snapshot])})
    endif
  else
    throw 'History fixture must not mutate'
  endif
endfunction
function! OpenFixture(snapshot) abort
  return revue#backend#Open({'id': 'fixture', 'connection': 'history-test', 'review': 'review-1',
        \ 'snapshot': a:snapshot, 'Request': function('HistoryHost')}, 0)
endfunction
try
  let restarting = filereadable($REVUE_CAP_STORE . '/restart')
  let g:id = OpenFixture(restarting ? g:b : g:a)
  let state = revue#session#Inspect(g:id)
  let qualified = state.snapshot.key
  if restarting
    call assert_equal(g:b.snapshot, state.snapshot.snapshot, 'startup does not silently choose historical code')
    call assert_false(has_key(state.comparisons[g:a.snapshot], 'snapshot'))
    call assert_equal(g:a.snapshot, state.resume_comparison)
    call assert_equal(g:a.snapshot, state.drafts[0].snapshot)
    let g:mode = 'failed'
    ReviewResumeComparison
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call assert_match('Historical commit unavailable', revue#session#Inspect(g:id).history_status)
    let g:mode = 'wrong'
    ReviewResumeComparison
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call assert_match('different comparison', revue#session#Inspect(g:id).history_status)
    let g:mode = 'deferred'
    ReviewResumeComparison
    ReviewHelp
    let helpwin = win_getid()
    call g:CompareDone({'ok': 1, 'data': deepcopy(g:a)})
    call assert_equal(helpwin, win_getid())
    call assert_equal('help', b:revue_view)
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call assert_true(has_key(revue#session#Inspect(g:id).comparisons[g:a.snapshot], 'snapshot'))
    ReviewResumeComparison
    call assert_equal(g:a.snapshot, b:revue_comparison)
    call assert_equal([6, 2], [line('.'), col('.')])
    call assert_equal(qualified, revue#session#Inspect(g:id).snapshot.key)
    call assert_equal('fixture', revue#session#Inspect(g:id).snapshot.backend.id)
    " A different saved reference loads and opens directly when navigation stays put.
    let g:mode = 'ok'
    call revue#session#OpenComparison(g:d.snapshot)
    call assert_equal(g:d.snapshot, b:revue_comparison)
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).latest_comparison, 'historical lookup never assigns latest')
    ReviewActivity
    call search('## Pending', 'w')
    ReviewOpenOperation
    call assert_equal(['Resume this old draft'], getline(1, '$'))
    ReviewDraftComparison
    call assert_equal(g:a.snapshot, b:revue_comparison)
    " A late history response cannot roll back a newer refresh's latest pointer.
    let g:history_mode = 'deferred'
    ReviewComparisons
    call assert_true(revue#session#Inspect(g:id).history_busy)
    ReviewRefresh
    call assert_equal(g:d.snapshot, revue#session#Inspect(g:id).latest_comparison)
    call g:HistoryDone({'ok': 1, 'data': {'items': [], 'latest': deepcopy(g:b), 'complete': 1, 'scope': 'Old request'}})
    call assert_equal(g:d.snapshot, revue#session#Inspect(g:id).latest_comparison)
    call assert_equal(g:a.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call revue#session#Close()
  else
    call cursor(3, 1)
    ReviewComment
    call setline(1, 'Resume this old draft')
    ReviewClose
    call cursor(6, 2)
    let source = win_getid()
    ReviewComparisons
    let state = revue#session#Inspect(g:id)
    call assert_equal(g:a.snapshot, state.snapshot.snapshot)
    call assert_equal(g:b.snapshot, state.latest_comparison)
    call assert_equal(3, len(state.comparisons))
    call assert_equal(qualified, state.comparisons[g:b.snapshot].snapshot.key)
    call assert_match('Not loaded', join(getline(1, '$'), "\n"))
    call assert_match('Fixture history', join(getline(1, '$'), "\n"))
    call search('\[latest\]', 'w')
    ReviewCopyComparison x
    call assert_equal(g:b.snapshot, json_decode(@x).snapshot)
    call cursor(1, 1)
    let @x = 'untouched'
    ReviewCopyComparison x
    call assert_equal('untouched', @x)
    " Editing the same composer while history loads also cancels the focus jump.
    ReviewActivity
    call search('## Pending', 'w')
    ReviewOpenOperation
    let editor = win_getid()
    let g:mode = 'deferred'
    call revue#session#OpenComparison(g:d.snapshot)
    call setline(1, 'Edited while history loads')
    call g:CompareDone({'ok': 1, 'data': deepcopy(g:d)})
    call assert_equal(editor, win_getid())
    call assert_equal('draft', b:revue_role)
    call assert_equal(['Edited while history loads'], getline(1, '$'))
    call assert_equal(g:a.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call setline(1, 'Resume this old draft')
    call win_gotoid(source)
    call cursor(6, 2)
    let path = state.draftpath
    call revue#session#Close()
    let saved = json_decode(join(readfile(path), "\n"))
    call assert_equal(g:a.snapshot, saved.navigation.selected)
    call assert_equal(3, len(saved.navigation.references))
    call assert_equal(6, saved.navigation.references[g:a.snapshot].views.refs.head.lnum)
    call assert_false(has_key(saved.navigation.references[g:a.snapshot], 'cache'))
    call assert_false(has_key(saved.navigation.references[g:a.snapshot], 'threads'))
    call assert_notmatch('Could we keep prefix', join(readfile(path), "\n"), 'published conversation body must not enter the outbox')
    call writefile(['restart'], $REVUE_CAP_STORE . '/restart')
  endif
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
