set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'reply': {'enabled': 1}, 'thread_state': {'enabled': 1, 'body_required': 0}}
let g:calls = []
let g:mode = 'ok'
let g:refresh_failed = 0
function! StateRules(resolved) abort
  let thread = g:fixture.snapshot.threads[0]
  let thread.resolved = a:resolved ? v:true : v:false
  let thread.resolved_by = a:resolved ? 'reviewer' : ''
  let thread.capabilities = {'reply': {'enabled': 1}, 'resolve': {'enabled': !a:resolved}, 'reopen': {'enabled': a:resolved}}
endfunction
call StateRules(0)
function! StateHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  elseif a:request.op ==# 'refresh'
    call a:Done(g:refresh_failed ? {'ok': 0, 'error': 'Fixture refresh unavailable'} : {'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    call assert_equal('thread_state', a:request.draft.kind)
    call assert_equal('', a:request.draft.body)
    call assert_equal('local-thread', a:request.draft.thread)
    call assert_equal(v:t_bool, type(a:request.draft.resolved))
    if g:mode ==# 'reject' || g:mode ==# 'read-failed'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Fixture access denied'})
    elseif g:mode ==# 'malformed'
      call a:Done({'ok': 1, 'data': {'thread': 'wrong-thread', 'resolved': v:true}})
    elseif g:mode ==# 'wrong-type'
      call a:Done({'ok': 1, 'data': {'id': a:request.draft.id, 'thread': a:request.draft.thread, 'resolved': 1}})
    elseif g:mode ==# 'deferred'
      let g:Deferred = a:Done
    elseif g:mode ==# 'throw'
      throw 'Fixture transport interrupted'
    else
      call StateRules(a:request.draft.resolved)
      if g:mode ==# 'unknown'
        call a:Done({'ok': 0, 'unknown': 1, 'error': 'Connection lost after acceptance'})
      else
        call a:Done({'ok': 1, 'data': {'id': a:request.draft.id, 'thread': a:request.draft.thread,
              \ 'resolved': a:request.draft.resolved, 'observed': a:request.reconcile}})
      endif
    endif
  endif
endfunction
function! ResolutionWhileTyping(timer) abort
  try
    let g:typing_before = [mode(1), win_getid(), bufnr()]
    call StateRules(1)
    call g:Deferred({'ok': 1, 'data': {'id': g:typing_operation, 'thread': 'local-thread', 'resolved': v:true}})
    let g:typing_after = [mode(1), win_getid(), bufnr()]
  catch
    call add(v:errors, v:exception . ' at ' . v:throwpoint)
  finally
    call feedkeys("\<Esc>", 'n')
  endtry
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('StateHost'), 0)
  let g:source = revue#session#Inspect(g:id).headwin
  call cursor(3, 1)
  if filereadable($REVUE_CAP_STORE . '/pending-state')
    let pending = json_decode(readfile($REVUE_CAP_STORE . '/pending-state')[0])
    call assert_equal(pending, revue#session#Inspect(g:id).drafts[-1])
    let g:fixture.snapshot.capabilities.thread_state.enabled = 0
    call revue#session#Refresh()
    let g:mode = 'read-failed'
    " Recovery has an explicit action, even after access loss.
    RevueResolve
    call assert_equal([], g:calls)
    RevueCheckThreadState
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    call assert_equal(0, &modifiable)
    call assert_match('Outcome unknown', revue#session#Inspect(g:id).message)
    RevueCheckThreadState
    call assert_equal(2, len(g:calls))
    call assert_equal(1, g:calls[-1].reconcile)
    call assert_equal(pending.id, g:calls[-1].draft.id)
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    " Missing feedback retains an Activity route to the same frozen operation.
    let saved_threads = g:fixture.snapshot.threads
    let g:fixture.snapshot.threads = []
    RevueRefresh
    let call_count = len(g:calls)
    RevueCheckThreadState
    call assert_equal(call_count, len(g:calls))
    RevueActivity
    call search('## Pending', 'W')
    RevueOpenOperation
    call assert_equal(pending.id, b:revue_draft)
    RevueDiscard
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    RevueCheckReceipt
    call assert_equal(pending.id, g:calls[-1].draft.id)
    call assert_equal(1, g:calls[-1].reconcile)
    let g:fixture.snapshot.threads = saved_threads
    let g:mode = 'ok'
    RevueCheckReceipt
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    call assert_equal('Requested thread state observed.', revue#session#Inspect(g:id).last_outcome)
    call assert_equal(v:true, revue#session#Inspect(g:id).snapshot.threads[0].resolved)
  else
    " Missing state and missing target permission cannot create operations.
    call remove(g:fixture.snapshot.threads[0], 'resolved')
    call revue#session#Refresh()
    RevueResolve
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    call StateRules(0)
    let g:fixture.snapshot.threads[0].capabilities.resolve.enabled = 0
    call revue#session#Refresh()
    RevueResolve
    call assert_equal([], g:calls)
    call StateRules(0)
    " Overlapping threads require selection; no arbitrary target.
    let overlap = deepcopy(g:fixture.snapshot.threads[0])
    let overlap.id = 'overlap'
    call add(g:fixture.snapshot.threads, overlap)
    call revue#session#Refresh()
    RevueResolve
    call assert_equal('threads', b:revue_view)
    call assert_equal([], g:calls)
    call remove(g:fixture.snapshot.threads, -1)
    call revue#session#Refresh()
    call revue#session#Help()
    call revue#session#ChangeThreadState(1)
    call assert_equal([], g:calls)
    call win_gotoid(g:source)
    call cursor(3, 1)
    RevueThread
    call cursor(1, 1)
    RevueNextMessage
    let reader = win_getid()
    let reader_buffer = bufnr()
    let selected_message = revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment
    let @z = 'preserve native register'
    let g:mode = 'deferred'
    " Menu action is permission-aware and targets the selected thread.
    call feedkeys("4\<CR>", 't')
    RevueActions
    call assert_equal('submitting', revue#session#Inspect(g:id).drafts[-1].state)
    call assert_equal(reader, win_getid())
    call assert_equal(reader_buffer, bufnr())
    call assert_false(exists('b:revue_draft'))
    call assert_equal(selected_message, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    call assert_match('Resolve in progress', join(getline(1, '$'), "\n"))
    let before_calls = len(g:calls)
    RevueResolve
    RevueReopen
    call assert_equal(before_calls, len(g:calls))
    call assert_equal('preserve native register', @z)
    call assert_equal(v:false, revue#session#Inspect(g:id).snapshot.threads[0].resolved)
    call assert_equal(0, &modifiable)
    call StateRules(1)
    let g:refresh_failed = 1
    call g:Deferred({'ok': 1, 'data': {'id': g:calls[-1].draft.id, 'thread': 'local-thread', 'resolved': v:true}})
    call assert_equal('Thread resolved.', revue#session#Inspect(g:id).last_outcome)
    call assert_match('refresh unavailable', revue#session#Inspect(g:id).message)
    call assert_equal(v:false, revue#session#Inspect(g:id).snapshot.threads[0].resolved)
    let g:refresh_failed = 0
    call revue#session#Refresh()
    call assert_equal('threads', b:revue_view)
    call assert_match('1 resolved', join(getline(1, '$'), "\n"))
    call assert_match('Could we keep prefix', join(getline(1, '$'), "\n"))
    call assert_equal('Thread resolved.', revue#session#Inspect(g:id).last_outcome)
    let rows = revue#comments#Rows(revue#session#Inspect(g:id).snapshot.threads[0], 80, {'state_hint': ':RevueReopen reopen thread'})
    call assert_match('RevueReopen', join(map(copy(rows), {_, r -> r.text}), ' '))
    " Reopening is separate from replying and does not hide content.
    let g:mode = 'ok'
    RevueReopen
    call assert_equal(v:false, revue#session#Inspect(g:id).snapshot.threads[0].resolved)
    call assert_match('1 unresolved', join(getline(1, '$'), "\n"))
    let count_before = len(g:calls)
    RevueReopen
    call assert_equal(count_before, len(g:calls), 'Already-desired state does not write')
    let g:mode = 'wrong-type'
    RevueResolve
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    let g:mode = 'ok'
    RevueCheckThreadState
    RevueReopen
    " Completion while composing preserves actual Insert mode and text.
    let g:mode = 'deferred'
    RevueResolve
    let g:typing_operation = g:calls[-1].draft.id
    RevueReply
    call setline(1, 'Human draft λ')
    let composer = [win_getid(), bufnr()]
    call timer_start(30, function('ResolutionWhileTyping'))
    call feedkeys('A typed during resolution', 'xt!')
    call assert_match('^i', g:typing_before[0])
    call assert_equal(g:typing_before, g:typing_after)
    call assert_equal(composer, [win_getid(), bufnr()])
    call assert_equal('Human draft λ typed during resolution', getline(1))
    call assert_equal('preserve native register', @z)
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    RevueDiscard
    let g:mode = 'ok'
    RevueReopen
    " A completed attempt cannot overwrite a newer operation's status.
    call g:Deferred({'ok': 0, 'unknown': 1, 'error': 'Late duplicate callback'})
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    call assert_equal(v:false, revue#session#Inspect(g:id).snapshot.threads[0].resolved)
    let g:mode = 'throw'
    RevueResolve
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    call assert_match('transport interrupted', revue#session#Inspect(g:id).message)
    let guide = revue#session#ActionGuide()
    call assert_equal(1, len(filter(copy(guide), {_, item -> item.id ==# 'check-thread-state'})))
    let g:mode = 'ok'
    RevueCheckThreadState
    RevueReopen
    let g:mode = 'reject'
    RevueResolve
    let rejected = deepcopy(revue#session#Inspect(g:id).drafts[-1])
    call assert_equal('failed', rejected.state)
    call assert_equal(0, &modifiable)
    call assert_equal(v:false, revue#session#Inspect(g:id).snapshot.threads[0].resolved)
    let g:mode = 'malformed'
    RevueResolve
    call assert_equal(rejected.id, revue#session#Inspect(g:id).drafts[-1].id)
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    let g:mode = 'ok'
    RevueCheckThreadState
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    RevueReopen
    let g:fixture.snapshot.threads[0].outdated = v:true
    call revue#session#Refresh()
    let g:mode = 'unknown'
    RevueResolve
    let pending = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', pending.state)
    call assert_match('outdated', join(getline(1, '$'), "\n"))
    call writefile([json_encode(pending)], $REVUE_CAP_STORE . '/pending-state')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
