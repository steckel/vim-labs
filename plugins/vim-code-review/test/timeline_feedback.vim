set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:latest = deepcopy(g:fixture.snapshot)
let g:latest.threads = []
let g:latest.feedback = {'cursor': 'first'}
let g:latest.capabilities = {'feedback_page': {'enabled': 1}, 'timeline': {'enabled': 1}, 'comment': {'enabled': 1}, 'reply': {'enabled': 1}}
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
  elseif a:request.op ==# 'feedback_page'
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
  ReviewRefresh
  ReviewTimeline
  call PickEvent('b')
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'event-feedback', 'review': 'review', 'snapshot': g:latest, 'Request': function('EventHost')}, 0)
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
  ReviewComment
  call setline(1, 'Unsent text retained through history retrieval')
  ReviewClose
  ReviewTimeline
  call cursor(1, 1)
  call assert_equal({}, EventItem('load-event-discussion'))
  call PickEvent('b')
  call assert_match('LoadEventDiscussion', EventItem('event-discussion').reason)
  call assert_equal('', EventItem('load-event-discussion').reason)
  let selection = EventSelection()
  let choice = index(map(revue#session#ActionGuide(), {_, item -> item.id}), 'load-event-discussion') + 1
  call feedkeys(choice . "\<CR>", 't')
  ReviewReviewActions
  call assert_match('Loading more feedback', join(getline(1, '$'), "\n"))
  ReviewLoadEventDiscussion
  call assert_equal(1, len(g:pages), 'One bounded request; repeated action does not duplicate it')
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('first', 'second', 0)})
  call assert_equal('timeline', b:revue_view)
  call assert_equal(selection, EventSelection())
  call assert_equal(1, len(g:pages), 'Does not automatically drain the review')
  ReviewLoadEventDiscussion
  call assert_equal('second', g:pages[-1].request.cursor)
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('second', '', 1)})
  call assert_equal('local-reply-2', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  call assert_equal(len(g:fixture.snapshot.threads[0].comments), len(revue#session#Inspect(g:id).snapshot.threads[-1].comments))
  ReviewClose
  call assert_equal(selection, EventSelection())
  call assert_equal({}, EventItem('load-event-discussion'))
  " Cancel/error/malformed results keep the event and permit retry.
  call ResetEvent()
  ReviewLoadEventDiscussion
  let cancelled = g:pages[-1]
  ReviewCancelFeedback
  call cancelled.Done({'ok': 1, 'data': EventPage('first', '', 1)})
  call assert_equal([], revue#session#Inspect(g:id).snapshot.threads)
  ReviewLoadEventDiscussion
  call g:pages[-1].Done({'ok': 0, 'error': 'Network unavailable'})
  call assert_match('Network unavailable', join(getline(1, '$'), "\n"))
  call assert_equal(selection, EventSelection())
  ReviewLoadEventDiscussion
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('wrong', '', 1)})
  call assert_equal([], revue#session#Inspect(g:id).snapshot.threads)
  " A different selected event must not be replaced by late navigation.
  ReviewLoadEventDiscussion
  call PickEvent('a')
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('first', '', 1)})
  call assert_equal('timeline', b:revue_view)
  call assert_equal(['a', 1], EventSelection())
  " Help focus is preserved even when a whole discussion arrives.
  call ResetEvent()
  ReviewLoadEventDiscussion
  ReviewHelp
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('first', '', 1)})
  call assert_equal('help', b:revue_view)
  ReviewClose
  call assert_equal(selection, EventSelection())
  ReviewEventDiscussion
  call assert_equal('local-reply-2', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  ReviewClose
  " Refresh invalidates late page results, even with the same source.
  call ResetEvent()
  ReviewLoadEventDiscussion
  ReviewReloadTimeline
  call PickEvent('b')
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('first', '', 1)})
  call assert_equal('timeline', b:revue_view, 'Reloaded history invalidates automatic follow')
  call ResetEvent()
  ReviewLoadEventDiscussion
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
  ReviewComment
  call setline(1, 'Typing while an event discussion arrives')
  let composer = win_getid()
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('first', '', 1)})
  call assert_equal(composer, win_getid())
  call assert_equal('Typing while an event discussion arrives', getline(1))
  ReviewClose
  ReviewTimeline
  call ResetEvent()
  ReviewLoadEventDiscussion
  let old = g:pages[-1]
  ReviewRefresh
  call old.Done({'ok': 1, 'data': EventPage('first', '', 1)})
  call assert_equal([], revue#session#Inspect(g:id).snapshot.threads)
  call assert_equal('timeline', b:revue_view)
  " Exhausting pages cannot imply deletion or fabricate the requested message.
  ReviewLoadEventDiscussion
  call g:pages[-1].Done({'ok': 1, 'data': EventPage('first', '', 0)})
  call assert_equal('timeline', b:revue_view)
  call assert_match('All available feedback', EventItem('load-event-discussion').reason)
  call assert_match('unavailable', EventItem('event-discussion').reason)
  call assert_equal('Unsent text retained through history retrieval', revue#session#Inspect(g:id).drafts[0].body)
  call assert_equal(1, len(filter(revue#session#Inspect(g:id).drafts, {_, draft -> draft.body ==# 'Typing while an event discussion arrives'})))
  call assert_equal([], revue#activity#Unread(revue#session#Inspect(g:id)))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
