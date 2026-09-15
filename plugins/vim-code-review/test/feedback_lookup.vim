set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:latest = deepcopy(g:fixture.snapshot)
let g:latest.threads = []
let g:latest.feedback = {'cursor': 'first'}
let g:latest.capabilities = {'feedback_page': {'enabled': 1}, 'feedback_lookup': {'enabled': 1}, 'timeline': {'enabled': 1}, 'comment': {'enabled': 1}, 'reply': {'enabled': 1}}
let g:pages = []
function! LoadEvent(id) abort
  return {'id': a:id, 'kind': 'comment', 'title': 'Discussion ' . a:id, 'actor': 'alex', 'created': '2026-09-14',
        \ 'body': 'Review feedback', 'url': 'https://example.test/' . a:id, 'details': [], 'provenance': 'Fixture',
        \ 'target': {'kind': 'thread', 'thread': 'local-thread', 'message': 'local-reply-2', 'message_kind': 'comment'}}
endfunction
function! EventHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'timeline'
    call a:Done({'ok': 1, 'data': {'cursor': '', 'items': [LoadEvent('a'), LoadEvent('b')], 'next_cursor': '', 'complete': v:true, 'scope': 'Fixture'}})
  elseif index(['feedback_page', 'feedback_lookup'], a:request.op) >= 0
    call add(g:pages, {'request': a:request, 'Done': a:Done})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:latest)})
  else
    throw 'Read-only history fixture: unexpected ' . a:request.op
  endif
endfunction
function! PickEvent(id) abort
  for row in sort(keys(revue#session#Inspect(g:id).timelinerows), 'n')
    if revue#session#Inspect(g:id).timelinerows[row].id ==# a:id
      call cursor(str2nr(row) + 1, 1)
      return
    endif
  endfor
  throw 'Missing event'
endfunction
function! EventSelection() abort
  let target = get(revue#session#Inspect(g:id).timelinerows, string(line('.')), {})
  return [target.id, line('.') - target.first]
endfunction
function! EventItem(id) abort
  return get(filter(revue#session#ActionGuide(), {_, item -> item.id ==# a:id}), 0, {})
endfunction
function! EventPage(cursor, next, found) abort
  let threads = deepcopy(g:fixture.snapshot.threads)
  if !a:found
    let threads[0].id = 'unrelated-' . a:cursor
    for message in threads[0].comments | let message.id = 'unrelated-' . a:cursor . '-' . message.id | endfor
  endif
  return {'snapshot': g:latest.snapshot, 'cursor': a:cursor, 'next_cursor': a:next,
        \ 'complete': empty(a:next) ? v:true : v:false, 'threads': threads, 'conversation': []}
endfunction
function! ResetEvent() abort
  RevueRefresh
  RevueTimeline
  call PickEvent('b')
endfunction
function! LookupResult(request) abort
  return {'key': g:latest.key, 'target': deepcopy(a:request.target), 'reference': deepcopy(a:request.reference),
        \ 'thread': deepcopy(g:fixture.snapshot.threads[0])}
endfunction
function! FinishLookup() abort
  call g:pages[-1].Done({'ok': 1, 'data': LookupResult(g:pages[-1].request)})
endfunction
try
  let g:latest.inventory = {'threads': {'state': 'partial', 'total': 501}, 'conversation': {'state': 'complete', 'total': 0}, 'thread_state': {'state': 'partial', 'total': 501}}
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'event-lookup', 'review': 'review', 'snapshot': g:latest, 'Request': function('EventHost')}, 0)
  RevueTimeline
  call PickEvent('b')
  let selection = EventSelection()
  RevueLoadMoreFeedback
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('first', 'second', 0)})
  let before = revue#session#Inspect(g:id).snapshot
  RevueLoadEventDiscussion
  call assert_equal('feedback_lookup', g:pages[-1].request.op)
  call assert_match('Loading selected discussion', join(getline(1, '$'), "\n"))
  let request_count = len(g:pages)
  RevueLoadEventDiscussion
  call assert_equal(request_count, len(g:pages))
  call FinishLookup()
  let state = revue#session#Inspect(g:id)
  call assert_equal('', state.feedback_read.error)
  call assert_equal(['first'], state.feedback_read.seen, 'Lookup preserves earlier page cycle history')
  call assert_equal('local-reply-2', revue#discussion#Selected(state, line('.')).comment)
  call assert_equal('second', state.snapshot.feedback.cursor)
  call assert_equal(before.inventory, state.snapshot.inventory, 'One thread does not imply full coverage')
  call assert_equal(len(g:fixture.snapshot.threads[0].comments), len(state.snapshot.threads[-1].comments))
  call assert_equal([], revue#activity#Unread(state))
  RevueClose
  call assert_equal(selection, EventSelection())
  " A normal page can overlap a prior lookup once, without losing cycle checks.
  RevueLoadMoreFeedback
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('second', 'third', 1)})
  call assert_equal('third', revue#session#Inspect(g:id).snapshot.feedback.cursor)
  call assert_equal([], get(revue#session#Inspect(g:id).snapshot.feedback, 'lookups', []))
  RevueLoadMoreFeedback
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('third', 'fourth', 1)})
  call assert_match('no additional', revue#session#Inspect(g:id).feedback_read.error)
  RevueLoadMoreFeedback
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('third', 'first', 0)})
  call assert_match('repeated', revue#session#Inspect(g:id).feedback_read.error)
  " Foreign, malformed or missing exact-message responses never change the view.
  for invalid in ['key', 'reference', 'target', 'thread', 'message', 'comments', 'data']
    call ResetEvent()
    RevueLoadEventDiscussion
    let result = LookupResult(g:pages[-1].request)
    if invalid ==# 'key' | let result.key = 'other'
    elseif invalid ==# 'reference' | let result.reference.head = 'other'
    elseif invalid ==# 'target' | let result.target.message = 'other'
    elseif invalid ==# 'thread' | let result.thread.id = 'other'
    elseif invalid ==# 'message' | let result.thread.comments = [result.thread.comments[0]]
    elseif invalid ==# 'comments' | let result.thread.comments = 7
    else | let result = [] | endif
    call g:pages[-1].Done({'ok': 1, 'data': result})
    call assert_equal([], revue#session#Inspect(g:id).snapshot.threads, invalid)
    call assert_false(empty(revue#session#Inspect(g:id).feedback_read.error), invalid)
    call assert_equal(selection, EventSelection(), invalid)
  endfor
  call ResetEvent()
  RevueLoadEventDiscussion
  let cancelled = g:pages[-1]
  RevueCancelFeedback
  call cancelled.Done({'ok': 1, 'data': LookupResult(cancelled.request)})
  call assert_equal([], revue#session#Inspect(g:id).snapshot.threads)
  RevueLoadEventDiscussion
  call PickEvent('a')
  call FinishLookup()
  call assert_equal('timeline', b:revue_view)
  call assert_equal(['a', 1], EventSelection())
  call ResetEvent()
  RevueLoadEventDiscussion
  RevueHelp
  call FinishLookup()
  call assert_equal('help', b:revue_view)
  RevueClose
  call assert_equal(selection, EventSelection())
  call ResetEvent()
  RevueLoadEventDiscussion
  let old = g:pages[-1]
  RevueRefresh
  call old.Done({'ok': 1, 'data': LookupResult(old.request)})
  call assert_equal([], revue#session#Inspect(g:id).snapshot.threads)
  call ResetEvent()
  RevueLoadEventDiscussion
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
  RevueComment
  call setline(1, 'Typing while a targeted discussion arrives')
  let composer = win_getid()
  call FinishLookup()
  call assert_equal(composer, win_getid())
  call assert_equal('Typing while a targeted discussion arrives', getline(1))
  RevueClose
  RevueTimeline
  " Providers needing a native token fall back to the ordinary page route.
  let g:latest.capabilities.feedback_lookup.requires_token = 1
  call ResetEvent()
  RevueLoadEventDiscussion
  call assert_equal('feedback_page', g:pages[-1].request.op)
  RevueCancelFeedback
  let snapshot = deepcopy(g:latest)
  let snapshot.capabilities.feedback_lookup = {'enabled': 1, 'current_only': 1}
  let snapshot.context = {}
  call assert_false(revue#feedback#LookupSupported(snapshot, LoadEvent('x').target))
  unlet snapshot.context
  call assert_true(revue#feedback#LookupSupported(snapshot, LoadEvent('x').target))
  " Unexpected extra units invalidate formerly complete counts.
  let snapshot.inventory.threads = {'state': 'complete', 'total': 0}
  let request = {'target': LoadEvent('x').target, 'reference': revue#comparisons#Reference(snapshot)}
  let merged = revue#feedback#LookupMerge(snapshot, LookupResult(request), request.target, request.reference)
  call assert_equal('unknown', merged.inventory.threads.state)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
