set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:latest = deepcopy(g:fixture.snapshot)
let g:latest.capabilities = {'feedback_page': {'enabled': 1}, 'comment': {'enabled': 1}, 'reply': {'enabled': 1}}
let g:latest.feedback = {'cursor': 'first'}
let g:latest.inventory = {'threads': {'state': 'partial', 'total': 3}}
let g:requests = []
function! FeedbackHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif index(['feedback_page', 'refresh'], a:request.op) >= 0
    call add(g:requests, {'request': a:request, 'Done': a:Done})
  else
    throw 'Feedback fixture cannot mutate'
  endif
endfunction
function! FeedbackPick(message) abort
  for row in sort(keys(revue#session#Inspect(g:id).discoveryrows), 'n')
    if get(revue#session#Inspect(g:id).discoveryrows[row], 'message', '') ==# a:message
      call cursor(str2nr(row), 1)
      return
    endif
  endfor
  throw 'Missing feedback target'
endfunction
function! FeedbackSelected() abort
  return revue#discovery#Key(get(revue#session#Inspect(g:id).discoveryrows, string(line('.')), {}))
endfunction
function! FeedbackPage(cursor, next, id) abort
  let thread = deepcopy(g:fixture.snapshot.threads[0])
  let thread.id = a:id
  let thread.comments = [extend(deepcopy(thread.comments[0]), {'id': a:id . '-root', 'body': 'Additional feedback needle ' . a:id})]
  return {'snapshot': g:latest.snapshot, 'cursor': a:cursor, 'next_cursor': a:next,
        \ 'complete': empty(a:next) ? v:true : v:false, 'threads': [thread], 'conversation': []}
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'feedback-pages', 'review': 'review', 'snapshot': g:latest, 'Request': function('FeedbackHost')}, 0)
  call cursor(3, 1)
  ReviewComment
  call setline(1, 'Keep the draft through page loading')
  ReviewClose
  ReviewDiscussions
  call FeedbackPick('local-reply-2')
  let selected = FeedbackSelected()
  ReviewLoadMoreFeedback
  call assert_match('Loading more feedback', join(getline(1, '$'), "\n"))
  call assert_equal('first', g:requests[-1].request.cursor)
  ReviewLoadMoreFeedback
  call assert_equal(1, len(g:requests), 'Do not duplicate an outstanding read')
  call g:requests[-1].Done({'ok': 0, 'error': 'Network unavailable'})
  call assert_equal(selected, FeedbackSelected())
  call assert_match('Network unavailable', join(getline(1, '$'), "\n"))
  ReviewLoadMoreFeedback
  let cancelled = g:requests[-1]
  ReviewCancelFeedback
  call cancelled.Done({'ok': 1, 'data': FeedbackPage('first', 'second', 'cancelled')})
  call assert_equal(1, len(revue#session#Inspect(g:id).snapshot.threads))
  ReviewLoadMoreFeedback
  let pending = g:requests[-1]
  ReviewHelp
  let helpwin = win_getid()
  call pending.Done({'ok': 1, 'data': FeedbackPage('first', 'second', 'more')})
  call assert_equal(helpwin, win_getid())
  call assert_equal('help', b:revue_view)
  ReviewClose
  call assert_equal(selected, FeedbackSelected())
  call assert_equal(2, len(revue#session#Inspect(g:id).snapshot.threads))
  call assert_equal([], revue#activity#Unread(revue#session#Inspect(g:id)), 'Loading old feedback does not manufacture arrivals')
  ReviewDiscussions Additional feedback needle
  call FeedbackPick('more-root')
  ReviewOpenDiscussion
  call assert_equal('more-root', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  ReviewReply
  call setline(1, 'Typing while older feedback arrives')
  ReviewLoadMoreFeedback
  let composer = win_getid()
  let page = FeedbackPage('second', '', 'last')
  call add(page.threads, deepcopy(revue#session#Inspect(g:id).snapshot.threads[0]))
  call g:requests[-1].Done({'ok': 1, 'data': page})
  call assert_equal(composer, win_getid())
  call assert_equal('Typing while older feedback arrives', getline(1))
  call assert_equal(3, len(revue#session#Inspect(g:id).snapshot.threads), 'Overlapping complete threads replace by ID')
  ReviewClose
  ReviewClose
  ReviewDiscussions
  call assert_match('Threads: 3 loaded · complete', join(getline(1, '$'), "\n"))
  let calls = len(g:requests)
  ReviewLoadMoreFeedback
  call assert_equal(calls, len(g:requests))
  " A refresh supersedes page requests even when the source identity is unchanged.
  ReviewRefresh
  call g:requests[-1].Done({'ok': 1, 'data': deepcopy(g:latest)})
  ReviewLoadMoreFeedback
  let old = g:requests[-1]
  ReviewRefresh
  call assert_false(revue#session#Inspect(g:id).feedback_read.loading)
  call g:requests[-1].Done({'ok': 1, 'data': deepcopy(g:latest)})
  call old.Done({'ok': 1, 'data': FeedbackPage('first', '', 'stale')})
  call assert_equal(1, len(revue#session#Inspect(g:id).snapshot.threads))
  " Malformed pages leave all previous discussions intact.
  for invalid in ['cursor', 'snapshot', 'complete', 'duplicate', 'anchor', 'body', 'stuck']
    let page = FeedbackPage('first', 'second', 'bad')
    if invalid ==# 'cursor' | let page.cursor = 'wrong' | endif
    if invalid ==# 'snapshot' | let page.snapshot = 'another-source' | endif
    if invalid ==# 'complete' | let page.complete = 2 | endif
    if invalid ==# 'duplicate' | call add(page.threads, deepcopy(page.threads[0])) | endif
    if invalid ==# 'anchor' | let page.threads[0].line = [] | endif
    if invalid ==# 'body' | let page.threads[0].comments[0].body = {} | endif
    if invalid ==# 'stuck' | let page.next_cursor = 'first' | endif
    ReviewLoadMoreFeedback
    call g:requests[-1].Done({'ok': 1, 'data': page})
    call assert_equal(1, len(revue#session#Inspect(g:id).snapshot.threads), invalid)
    call assert_false(empty(revue#session#Inspect(g:id).feedback_read.error), invalid)
  endfor
  call assert_equal('Keep the draft through page loading', revue#session#Inspect(g:id).drafts[0].body)
  call assert_notmatch('Additional feedback needle', join(readfile(revue#session#Inspect(g:id).draftpath), "\n"))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
