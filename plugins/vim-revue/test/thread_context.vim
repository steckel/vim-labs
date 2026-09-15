set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:current = deepcopy(g:fixture.snapshot)
let g:current.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'thread_context': {'enabled': 1}, 'comparisons': {'enabled': 1}}
let g:current.threads[0].original_source = {'token': 'anchor-1', 'available': 1, 'label': 'Inspect original context', 'lookup': 'opaque-backend-locator'}
let g:mode = 'ok'
let g:calls = []
function! ContextData() abort
  let snapshot = deepcopy(g:current)
  let snapshot.snapshot = 'context-fixture'
  let snapshot.base = 'original-parent'
  let snapshot.head = 'original-head'
  let snapshot.context = {'thread': 'local-thread', 'token': 'anchor-1', 'kind': 'original-head',
        \ 'note': 'Original head verified. Original PR base unavailable; parent context only.',
        \ 'label': 'Verified original head', 'basis': 'Original PR base unverified',
        \ 'path': 'original-name.vim', 'side': 'head', 'start': 3, 'line': 3}
  let snapshot.files[0].path = 'original-name.vim'
  let snapshot.files[0].old_path = 'original-name.vim'
  let snapshot.threads[0].path = 'original-name.vim'
  let snapshot.threads[0].outdated = v:false
  let snapshot.capabilities.comment = {'enabled': 0, 'reason': 'Return to Latest for new feedback'}
  return {'thread': 'local-thread', 'token': 'anchor-1', 'snapshot': snapshot,
        \ 'location': {'path': 'original-name.vim', 'side': 'head', 'start': 3, 'line': 3}}
endfunction
function! ContextHost(request, Done) abort
  call add(g:calls, deepcopy(a:request))
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'thread_context'
    call assert_equal(get(g:current.threads[0].original_source, 'lookup', ''), get(a:request.target, 'lookup', ''))
    if g:mode ==# 'delay'
      let g:ContextDone = a:Done
    elseif g:mode ==# 'failed'
      call a:Done({'ok': 0, 'error': 'Original base unavailable; read the original diff here.'})
    else
      let data = ContextData()
      if g:mode ==# 'wrong' | let data.token = 'wrong' | endif
      if g:mode ==# 'malformed' | let data.snapshot.context = [] | endif
      if g:mode ==# 'bad-line' | let data.location.line = -1 | let data.snapshot.context.line = -1 | endif
      if g:mode ==# 'file-string' | let data.snapshot.files = ['invalid'] | endif
      if g:mode ==# 'file-missing-path' | call remove(data.snapshot.files[0], 'path') | endif
      if g:mode ==# 'file-path-type' | let data.snapshot.files[0].path = [] | endif
      if g:mode ==# 'missing-file' | let data.snapshot.files = [] | endif
      call a:Done({'ok': 1, 'data': data})
    endif
  elseif a:request.op ==# 'comparison'
    call a:Done({'ok': 1, 'data': ContextData().snapshot})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:current)})
  else
    throw 'Context fixture cannot mutate'
  endif
endfunction
function! ContextMessage() abort
  return revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment
endfunction
try
  let restarting = filereadable($REVUE_CAP_STORE . '/restart')
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'original-context', 'review': 'review', 'snapshot': g:current, 'Request': function('ContextHost')}, 0)
  if restarting
    RevueResumeComparison
    call assert_equal('context-fixture', b:revue_comparison)
    call assert_equal(3, line('.'))
    call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).drafts[0].snapshot)
    call assert_true(has_key(revue#session#Inspect(g:id).drafts[1], 'context'))
    call assert_true(empty(filter(revue#session#ActionGuide(), {_, item -> item.id ==# 'return-context'})))
    RevueThread
    call assert_match('original code context', &statusline)
    call assert_match('Original PR base unavailable', join(getline(1, '$'), "\n"))
    call assert_match('RevueLatest opens', join(getline(1, '$'), "\n"))
  else
    call cursor(3, 1)
    RevueComment
    call setline(1, 'Preserve draft on current code')
    RevueClose
    RevueThread
    call assert_equal('local-root', ContextMessage())
    RevueNextMessage
    call assert_equal('local-reply-1', ContextMessage())
    RevueNextMessage
    let message = ContextMessage()
    call assert_equal('local-reply-2', message)
    for mode in ['failed', 'wrong', 'malformed', 'bad-line', 'file-string', 'file-missing-path', 'file-path-type', 'missing-file']
      let g:mode = mode
      RevueThreadComparison
      call assert_equal(message, ContextMessage(), mode)
      call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    endfor
    let g:mode = 'ok'
    RevueThreadComparison
    call assert_equal('original-name.vim', b:revue_file)
    call assert_equal(3, line('.'))
    call assert_match('original code context', &statusline)
    call assert_equal('fixture', revue#session#Inspect(g:id).snapshot.backend.id)
    RevueReturnContext
    call assert_equal(message, ContextMessage())
    call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    let g:mode = 'delay'
    RevueThreadComparison
    RevueHelp
    let helpwin = win_getid()
    call g:ContextDone({'ok': 1, 'data': ContextData()})
    call assert_equal(helpwin, win_getid())
    call assert_equal('help', b:revue_view)
    RevueClose
    call assert_equal(message, ContextMessage())
    " A delayed lookup may populate the cache, but cannot move another reply.
    RevueThreadComparison
    RevuePreviousMessage
    call assert_equal('local-reply-1', ContextMessage())
    call g:ContextDone({'ok': 1, 'data': ContextData()})
    call assert_equal('local-reply-1', ContextMessage())
    call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    RevueNextMessage
    RevueThreadComparison
    let g:current.threads[0].original_source.token = 'changed-anchor'
    RevueRefresh
    call g:ContextDone({'ok': 1, 'data': ContextData()})
    call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    let g:current.threads[0].original_source.token = 'anchor-1'
    RevueRefresh
    let g:mode = 'ok'
    RevueThreadComparison
    RevueReply
    call setline(1, 'Reply in original code context')
    call assert_true(has_key(revue#session#Inspect(g:id).drafts[-1], 'context'))
    RevueClose
    " Closing the source discussion manually does not lose exact return identity.
    let sourcewin = win_getid()
    call win_gotoid(revue#session#Inspect(g:id).panelwin)
    close
    call win_gotoid(sourcewin)
    RevueReturnContext
    call assert_equal(message, ContextMessage())
    RevueThreadComparison
    call writefile(['restart'], $REVUE_CAP_STORE . '/restart')
  endif
  call assert_equal([], filter(copy(g:calls), {_, call -> call.op ==# 'mutate'}))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
