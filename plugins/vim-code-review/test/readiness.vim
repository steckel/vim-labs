set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:revue_mappings = {'readiness': 'gS'}
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'readiness': {'enabled': 1}, 'comment': {'enabled': 1}, 'reply': {'enabled': 1}}
let g:pending = []
function! ReadyPage(ids, cursor, next) abort
  return {'reference': revue#comparisons#Reference(g:fixture.snapshot), 'head': g:fixture.snapshot.head, 'base_tip': get(g:fixture.snapshot, 'base_tip', 'base-tip'),
        \ 'observed_at': '2026-09-14T12:00:00Z', 'url': 'https://example.test/review', 'scope': 'Reported checks only; other requirements may be absent.',
        \ 'facts': [{'id': 'review', 'name': 'Code review', 'value': 'Review required', 'detail': 'Full policy unavailable.', 'url': 'https://example.test/review'}],
        \ 'checks': map(copy(a:ids), {_, id -> {'id': id, 'name': 'Tests ' . id, 'state': 'failed', 'required': v:true, 'detail': 'Expected behavior differs', 'url': 'https://example.test/check/' . id}}),
        \ 'total': 2, 'cursor': a:cursor, 'next_cursor': a:next, 'complete': empty(a:next) ? v:true : v:false}
endfunction
function! ReadinessHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'readiness'
    if get(g:, 'throw_read', 0) | throw 'Fixture transport unavailable' | endif
    call add(g:pending, {'Done': a:Done, 'request': deepcopy(a:request)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    throw 'Readiness fixture cannot mutate'
  endif
endfunction
function! ReadyPick(id) abort
  for row in sort(keys(revue#session#Inspect(g:id).readinessrows), 'n')
    if revue#session#Inspect(g:id).readinessrows[row].id ==# a:id | call cursor(str2nr(row), 1) | return | endif
  endfor
  throw 'Missing readiness row ' . a:id
endfunction
function! ReadyID() abort
  return get(get(revue#session#Inspect(g:id), 'readinessrows', {}), string(line('.')), {}).id
endfunction
function! ReadyWhileTyping(timer) abort
  try
    let g:typing_before = [mode(1), win_getid(), bufnr()]
    call g:pending[-1].Done({'ok': 1, 'data': ReadyPage(['b', 'a'], '', '')})
    let g:typing_after = [mode(1), win_getid(), bufnr()]
  finally
    call feedkeys("\<Esc>", 'n')
  endtry
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'readiness', 'review': 'review', 'snapshot': g:fixture.snapshot, 'Request': function('ReadinessHost')}, 0)
  call cursor(3, 1)
  let source = [win_getid(), bufnr(), line('.')]
  call assert_equal('<Plug>(revue-readiness)', maparg('gS', 'n'))
  call assert_equal('', filter(revue#session#ActionGuide(), {_, item -> item.id ==# 'readiness'})[0].reason)
  RevueComment
  call setline(1, 'Preserve this unpublished draft')
  RevueClose
  call setreg('a', 'keep register a')
  RevueReadiness
  call assert_equal('readiness', b:revue_view)
  call assert_false(&modifiable)
  call assert_match('Loading checks', join(getline(1, '$'), "\n"))
  let read = g:pending[-1]
  call assert_equal(revue#comparisons#Reference(g:fixture.snapshot), read.request.reference)
  RevueReloadReadiness
  call assert_equal(1, len(g:pending), 'No duplicate while loading')
  call read.Done({'ok': 1, 'data': ReadyPage(['a'], '', 'next')})
  call assert_equal(1, len(revue#session#Inspect(g:id).readiness.data.checks))
  call assert_match('more available', join(getline(1, '$'), "\n"))
  call ReadyPick('check:a')
  RevueCopyReadinessLink
  call assert_equal('https://example.test/check/a', getreg('"'))
  RevueMoreChecks
  call assert_equal('next', g:pending[-1].request.cursor)
  let cancelled = g:pending[-1]
  RevueCancelReadiness
  call cancelled.Done({'ok': 1, 'data': ReadyPage(['b'], 'next', '')})
  call assert_equal(1, len(revue#session#Inspect(g:id).readiness.data.checks))
  call assert_equal('check:a', ReadyID())
  RevueMoreChecks
  call g:pending[-1].Done({'ok': 0, 'error': 'Network unavailable'})
  call assert_equal('check:a', ReadyID())
  call assert_match('Network unavailable', join(getline(1, '$'), "\n"))
  RevueMoreChecks
  call g:pending[-1].Done({'ok': 1, 'data': ReadyPage(['b'], 'next', '')})
  call assert_equal('check:a', ReadyID())
  call assert_equal(2, len(revue#session#Inspect(g:id).readiness.data.checks))
  call ReadyPick('check:b')
  RevueReloadReadiness
  let refreshed = g:pending[-1]
  RevueHelp
  let helpwin = win_getid()
  call refreshed.Done({'ok': 1, 'data': ReadyPage(['b', 'a'], '', '')})
  call assert_equal(helpwin, win_getid())
  call assert_equal('help', b:revue_view)
  RevueClose
  call assert_equal('check:b', ReadyID(), 'Return follows check identity after reordering')
  call refreshed.Done({'ok': 0, 'error': 'Duplicate callback'})
  call assert_equal('', revue#session#Inspect(g:id).readiness.error)
  RevueReloadReadiness
  let reader = win_getid()
  call win_gotoid(source[0])
  RevueComment
  let composer = win_getid()
  call setline(1, 'Another draft')
  call timer_start(30, function('ReadyWhileTyping'))
  call feedkeys('A while typing', 'xt!')
  call assert_match('^i', g:typing_before[0])
  call assert_equal(g:typing_before, g:typing_after)
  call assert_equal(composer, win_getid())
  call assert_equal('Another draft while typing', getline(1))
  RevueClose
  call win_gotoid(reader)
  RevueReloadReadiness
  let malformed = ReadyPage(['a', 'b'], '', '')
  let malformed.checks[0].required = 1
  call g:pending[-1].Done({'ok': 1, 'data': malformed})
  call assert_match('Invalid check', revue#session#Inspect(g:id).readiness.error)
  call assert_equal('b', revue#session#Inspect(g:id).readiness.data.checks[0].id)
  let g:throw_read = 1
  RevueReloadReadiness
  call assert_false(revue#session#Inspect(g:id).readiness.loading)
  call assert_match('transport unavailable', revue#session#Inspect(g:id).readiness.error)
  let g:throw_read = 0
  RevueReloadReadiness
  let stale = ReadyPage(['a', 'b'], '', '')
  let stale.head = 'different-live-head'
  call g:pending[-1].Done({'ok': 1, 'data': stale})
  call assert_match('STALE for the selected comparison', join(getline(1, '$'), "\n"))
  RevueClose
  call assert_equal(source, [win_getid(), bufnr(), line('.')])
  call assert_equal('keep register a', getreg('a'))
  call assert_equal('Preserve this unpublished draft', revue#session#Inspect(g:id).drafts[0].body)
  call assert_equal('Another draft while typing', revue#session#Inspect(g:id).drafts[1].body)
  RevueReadiness
  RevueReloadReadiness
  let late = g:pending[-1]
  let old_page = ReadyPage(['a', 'b'], '', '')
  let g:fixture.snapshot.head = 'new-reviewed-head'
  let g:fixture.snapshot.snapshot = 'new-comparison'
  RevueRefresh
  let deadline = reltime()
  while revue#session#Inspect(g:id).latest_comparison !=# 'new-comparison' && reltimefloat(reltime(deadline)) < 3
    sleep 10m
  endwhile
  call assert_equal('new-comparison', revue#session#Inspect(g:id).latest_comparison)
  call late.Done({'ok': 1, 'data': old_page})
  call assert_match('comparison changed', revue#session#Inspect(g:id).readiness.error)
  call assert_match('STALE', join(getline(1, '$'), "\n"))
  RevueLatest
  let deadline = reltime()
  while revue#session#Inspect(g:id).snapshot.snapshot !=# 'new-comparison' && reltimefloat(reltime(deadline)) < 3
    sleep 10m
  endwhile
  call assert_equal('new-comparison', revue#session#Inspect(g:id).snapshot.snapshot)
  RevueReadiness
  let g:fixture.snapshot.capabilities.readiness = {'enabled': 0, 'reason': 'No CI for this backend'}
  RevueRefresh
  let deadline = reltime()
  while revue#session#Inspect(g:id).snapshot.capabilities.readiness.enabled && reltimefloat(reltime(deadline)) < 3
    sleep 10m
  endwhile
  let request_count = len(g:pending)
  RevueReloadReadiness
  call assert_equal(request_count, len(g:pending))
  call assert_match('No CI', join(getline(1, '$'), "\n"))
  call assert_match('No CI', filter(revue#session#ActionGuide(), {_, item -> item.id ==# 'reload-readiness'})[0].reason)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
