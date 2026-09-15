set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'timeline': {'enabled': 1}, 'reply': {'enabled': 1}, 'comment': {'enabled': 1}}
let g:pending = []
function! Event(id) abort
  return {'id': a:id, 'kind': 'review', 'title': 'Reviewed ' . a:id, 'actor': 'alex',
        \ 'created': '2026-09-14T01:00:00Z', 'body': "> quoted feedback\n\nA review response.", 'url': 'https://example.test/event/' . a:id,
        \ 'provenance': 'Fixture review backend', 'details': ['Historical event; current discussion permissions apply.'],
        \ 'target': {'kind': 'thread', 'thread': 'local-thread', 'message': 'local-reply-2', 'message_kind': 'comment'}}
endfunction
function! Page(ids, cursor, next) abort
  return {'cursor': a:cursor, 'items': map(copy(a:ids), {_, id -> Event(id)}), 'next_cursor': a:next,
        \ 'complete': empty(a:next) ? v:true : v:false, 'total': 3, 'scope': 'Fixture history; newest first.'}
endfunction
function! TimelineHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'timeline'
    call add(g:pending, {'Done': a:Done, 'request': a:request})
  else
    throw 'Timeline fixture cannot mutate'
  endif
endfunction
function! TimelinePick(id) abort
  for row in sort(keys(revue#session#Inspect(g:id).timelinerows), 'n')
    if revue#session#Inspect(g:id).timelinerows[row].id ==# a:id | call cursor(str2nr(row) + 2, 1) | return | endif
  endfor
  throw 'Missing timeline event'
endfunction
function! TimelineID() abort
  return get(get(revue#session#Inspect(g:id), 'timelinerows', {}), string(line('.')), {}).id
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'timeline', 'review': 'review', 'snapshot': g:fixture.snapshot, 'Request': function('TimelineHost')}, 0)
  call cursor(3, 1)
  RevueComment
  call setline(1, 'Keep this unsent draft')
  RevueClose
  RevueTimeline
  call assert_match('Loading history', join(getline(1, '$'), "\n"))
  call g:pending[-1].Done({'ok': 1, 'data': Page(['b', 'c'], '', 'older')})
  call assert_equal(2, len(revue#session#Inspect(g:id).timeline.items))
  call TimelinePick('c')
  RevueCopyEventLink
  call assert_equal('https://example.test/event/c', getreg('"'))
  RevueOlderEvents
  call assert_equal('older', g:pending[-1].request.cursor)
  call assert_equal('c', TimelineID())
  call g:pending[-1].Done({'ok': 0, 'error': 'Network unavailable'})
  call assert_equal('c', TimelineID())
  call assert_match('Network unavailable', join(getline(1, '$'), "\n"))
  RevueOlderEvents
  let cancelled = g:pending[-1]
  RevueCancelTimeline
  call cancelled.Done({'ok': 1, 'data': Page(['a', 'b'], 'older', '')})
  call assert_equal(2, len(revue#session#Inspect(g:id).timeline.items))
  RevueOlderEvents
  let older = g:pending[-1]
  RevueHelp
  let helpwin = win_getid()
  call older.Done({'ok': 1, 'data': Page(['a', 'b'], 'older', '')})
  call assert_equal(helpwin, win_getid())
  call assert_equal('help', b:revue_view)
  RevueClose
  call assert_equal('timeline', b:revue_view)
  call assert_equal('c', TimelineID())
  call assert_equal(['a', 'b', 'c'], map(copy(revue#session#Inspect(g:id).timeline.items), {_, e -> e.id}))
  call assert_match('Oldest available event reached', join(getline(1, '$'), "\n"))
  RevueEventDiscussion
  call assert_equal('local-reply-2', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  RevueReply
  call setline(1, 'Reply from history; do not publish')
  RevueClose
  RevueClose
  call assert_equal('timeline', b:revue_view)
  call assert_equal('c', TimelineID())
  RevueReloadTimeline
  let superseded = g:pending[-1]
  RevueReloadTimeline
  call superseded.Done({'ok': 1, 'data': Page(['wrong'], '', '')})
  call assert_equal('c', TimelineID())
  call g:pending[-1].Done({'ok': 1, 'data': Page(['c', 'd'], '', 'next')})
  call assert_equal('c', TimelineID())
  call assert_equal(['c', 'd'], map(copy(revue#session#Inspect(g:id).timeline.items), {_, e -> e.id}))
  RevueOlderEvents
  call g:pending[-1].Done({'ok': 1, 'data': Page(['a'], 'WRONG', '')})
  call assert_equal(['c', 'd'], map(copy(revue#session#Inspect(g:id).timeline.items), {_, e -> e.id}))
  call assert_equal('c', TimelineID())
  " Invalid pages cannot partially replace a valid event cache.
  for invalid in [-1, 2, 'true', [], {}, v:null]
    let page = Page(['a'], '', '')
    let page.complete = invalid
    let state = deepcopy(revue#session#Inspect(g:id).timeline)
    let before = deepcopy(state)
    call assert_false(empty(revue#timeline#Apply(state, page, '', 1)))
    call assert_equal(before, state)
  endfor
  for bad in [[], {'cursor': '', 'items': []}]
    let state = deepcopy(revue#session#Inspect(g:id).timeline)
    let before = deepcopy(state)
    call assert_false(empty(revue#timeline#Apply(state, bad, '', 1)))
    call assert_equal(before, state)
  endfor
  for mode in ['duplicate', 'bad-target', 'bad-body', 'stalled']
    let page = Page(['a'], 'next', '')
    if mode ==# 'duplicate' | call add(page.items, Event('a')) | endif
    if mode ==# 'bad-target' | let page.items[0].target = [] | endif
    if mode ==# 'bad-body' | let page.items[0].body = {} | endif
    if mode ==# 'stalled' | let page.complete = v:false | let page.next_cursor = 'next' | endif
    let state = deepcopy(revue#session#Inspect(g:id).timeline)
    let before = deepcopy(state)
    call assert_false(empty(revue#timeline#Apply(state, page, 'next', 0)), mode)
    call assert_equal(before, state)
  endfor
  call assert_equal('Keep this unsent draft', revue#session#Inspect(g:id).drafts[0].body)
  let disk = join(readfile(revue#session#Inspect(g:id).draftpath), "\n")
  call assert_notmatch('Fixture review backend', disk, 'Timeline bodies are not persisted in the outbox')
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
