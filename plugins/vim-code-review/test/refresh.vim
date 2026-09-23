set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:initial = deepcopy(g:fixture.snapshot)
let g:initial.capabilities = {'feedback_page': {'enabled': 1}, 'feedback_refresh': {'enabled': 1}, 'reply': {'enabled': 1}}
let g:late = deepcopy(g:initial.threads[0])
let g:late.id = 'later-thread'
for message in g:late.comments | let message.id = 'later-' . message.id | endfor
call add(g:initial.threads, g:late)
let g:requests = []
function! RefreshHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  else
    call add(g:requests, {'request': deepcopy(a:request), 'Done': a:Done})
  endif
endfunction
function! RefreshPick(message) abort
  for row in sort(keys(revue#session#Inspect(g:id).discoveryrows), 'n')
    if get(revue#session#Inspect(g:id).discoveryrows[row], 'message', '') ==# a:message | call cursor(str2nr(row), 1) | return | endif
  endfor
  throw 'Target absent'
endfunction
function! FirstRefresh() abort
  let first = deepcopy(g:initial)
  let first.threads = [deepcopy(first.threads[0])]
  let first.threads[0].comments[0].body = 'Fresh body'
  let first.feedback = {'cursor': 'second'}
  let first.inventory = {'threads': {'state': 'partial', 'total': 2}, 'conversation': {'state': 'complete', 'total': 0}}
  return first
endfunction
function! LastRefresh() abort
  return {'snapshot': g:initial.snapshot, 'cursor': 'second', 'next_cursor': '', 'complete': v:true, 'threads': [deepcopy(g:late)], 'conversation': []}
endfunction
function! SelectedRefresh() abort
  return revue#discovery#Key(get(revue#session#Inspect(g:id).discoveryrows, string(line('.')), {}))
endfunction
function! RefreshWhileTyping(timer) abort
  let g:typing_before = [mode(1), win_getid(), bufnr(), getpos('.')]
  call g:requests[-1].Done({'ok': 1, 'data': LastRefresh()})
  let g:typing_after = [mode(1), win_getid(), bufnr(), getpos('.')]
  call feedkeys("\<Esc>", 't')
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'refresh', 'review': 'review', 'snapshot': g:initial, 'Request': function('RefreshHost')}, 0)
  ReviewDiscussions
  call RefreshPick('later-local-reply-2')
  let selected = SelectedRefresh()
  let before = deepcopy(revue#session#Inspect(g:id).snapshot)
  ReviewRefresh
  call assert_true(g:requests[-1].request.incremental)
  let request_count = len(g:requests)
  ReviewRefresh
  call assert_equal(request_count, len(g:requests), 'one outstanding request')
  call g:requests[-1].Done({'ok': 1, 'data': FirstRefresh()})
  call assert_equal(request_count, len(g:requests), 'never chase pages automatically')
  call assert_equal('partial refresh', revue#session#Inspect(g:id).refresh_state.status)
  call assert_equal(before, revue#session#Inspect(g:id).snapshot)
  call assert_match('Refresh paused.*ContinueRefresh', revue#layout#Bar(' Discussion'))
  call assert_equal(selected, SelectedRefresh())
  call assert_match('previously loaded', join(getline(1, '$'), "\n"))
  call assert_equal(1, len(filter(revue#session#ActionGuide(), {_, a -> a.id ==# 'continue-refresh' && empty(a.reason)})))
  ReviewLoadMoreFeedback
  call assert_equal(request_count, len(g:requests), 'do not append old pages during replacement')
  ReviewContinueRefresh
  call assert_equal('feedback_page', g:requests[-1].request.op)
  let cancelled = g:requests[-1]
  ReviewCancelRefresh
  ReviewRefresh
  let active = g:requests[-1]
  call cancelled.Done({'ok': 1, 'data': LastRefresh()})
  call assert_true(revue#session#Inspect(g:id).busy, 'old callback cannot clear a new request')
  call active.Done({'ok': 1, 'data': FirstRefresh()})
  ReviewContinueRefresh
  call g:requests[-1].Done({'ok': 0, 'error': 'Read failed'})
  call assert_equal(before, revue#session#Inspect(g:id).snapshot)
  call assert_match('ContinueRefresh retries', join(getline(1, '$'), "\n"))
  ReviewContinueRefresh
  let bad = LastRefresh()
  let bad.threads[0].comments[0].body = {}
  call g:requests[-1].Done({'ok': 1, 'data': bad})
  call assert_equal(before, revue#session#Inspect(g:id).snapshot)
  ReviewContinueRefresh
  ReviewHelp
  let helpwin = win_getid()
  call g:requests[-1].Done({'ok': 1, 'data': LastRefresh()})
  call assert_equal(helpwin, win_getid())
  call assert_equal('help', b:revue_view)
  ReviewClose
  call assert_equal(selected, SelectedRefresh())
  call assert_equal('Fresh body', revue#session#Inspect(g:id).snapshot.threads[0].comments[0].body)
  call assert_equal({}, revue#session#Inspect(g:id).refresh_read)
  call assert_equal('succeeded', revue#session#Inspect(g:id).refresh_state.status)
  " A full candidate commits in place while a draft stays editable and unchanged.
  ReviewOpenDiscussion
  ReviewReply
  call setline(1, ['Quoted reply stays exact', "\tUnicode λ"])
  call cursor(2, 4)
  let draftwin = win_getid()
  let draftbuf = bufnr()
  let pos = getpos('.')
  ReviewRefresh
  call g:requests[-1].Done({'ok': 1, 'data': FirstRefresh()})
  call assert_equal(draftwin, win_getid())
  call assert_equal(draftbuf, bufnr())
  ReviewContinueRefresh
  call g:requests[-1].Done({'ok': 1, 'data': LastRefresh()})
  call assert_equal(pos, getpos('.'))
  call assert_equal(['Quoted reply stays exact', "\tUnicode λ"], getline(1, '$'))
  call assert_true(&modifiable)
  ReviewRefresh
  call g:requests[-1].Done({'ok': 1, 'data': FirstRefresh()})
  ReviewContinueRefresh
  call timer_start(80, function('RefreshWhileTyping'))
  call feedkeys('A typed', 'xt!')
  call assert_match('^i', g:typing_before[0], 'callback runs during Insert mode')
  call assert_equal(g:typing_before, g:typing_after, 'refresh preserves Insert mode and cursor')
  call assert_match(' typed$', getline(2))
  " Missing messages become unavailable only after exhausting a fresh inventory.
  ReviewClose
  ReviewClose
  ReviewDiscussions
  call RefreshPick('later-local-reply-2')
  ReviewRefresh
  call g:requests[-1].Done({'ok': 1, 'data': FirstRefresh()})
  ReviewContinueRefresh
  let removed = LastRefresh()
  let removed.threads = []
  call g:requests[-1].Done({'ok': 1, 'data': removed})
  call assert_equal(1, len(revue#session#Inspect(g:id).snapshot.threads))
  call assert_match('no longer reported', revue#session#Inspect(g:id).message)
  " Different source is observed, not selected; drafts retain their original anchor.
  let source = revue#session#Inspect(g:id).snapshot.snapshot
  ReviewRefresh
  let newer = FirstRefresh()
  let newer.snapshot = 'new-source'
  let newer.head = 'new-head'
  call g:requests[-1].Done({'ok': 1, 'data': newer})
  call assert_equal(source, revue#session#Inspect(g:id).snapshot.snapshot)
  call assert_equal('new-source', revue#session#Inspect(g:id).latest_comparison)
  call assert_equal(source, revue#session#Inspect(g:id).drafts[0].snapshot)
  " A source switch while refresh runs cannot rewrite the newly selected view.
  ReviewRefresh
  let previous_read = g:requests[-1]
  ReviewLatest
  let changed_source = revue#session#Inspect(g:id).snapshot.snapshot
  call previous_read.Done({'ok': 1, 'data': FirstRefresh()})
  call assert_equal(changed_source, revue#session#Inspect(g:id).snapshot.snapshot)
  call assert_match('Comparison changed', revue#session#Inspect(g:id).refresh_state.error)
  ReviewCancelRefresh
  " An invalid first read does not replace good feedback; cancellation still works.
  ReviewRefresh
  let malformed = FirstRefresh()
  let malformed.threads = 'invalid'
  call g:requests[-1].Done({'ok': 1, 'data': malformed})
  call assert_equal('failed', revue#session#Inspect(g:id).refresh_state.status)
  ReviewCancelRefresh
  ReviewRefresh
  let malformed = deepcopy(revue#session#Inspect(g:id).snapshot)
  let malformed.base = 'wrong-base-for-the-same-identity'
  call g:requests[-1].Done({'ok': 1, 'data': malformed})
  call assert_match('source identity conflicts', revue#session#Inspect(g:id).refresh_state.error)
  ReviewCancelRefresh
  call assert_equal({}, revue#session#Inspect(g:id).refresh_read)
  call assert_equal([], filter(revue#session#ActionGuide(), {_, a -> index(['continue-refresh', 'cancel-refresh'], a.id) >= 0}))
  call assert_notmatch('Fresh body', join(readfile(revue#session#Inspect(g:id).draftpath), "\n"), 'candidate bodies are not stored in outbox')
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
