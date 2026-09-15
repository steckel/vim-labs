set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_mappings = {'thread': 'gt', 'actions': 'ga', 'next-message': 'gn', 'previous-message': 'gp', 'quote': 'gq'}
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'reply': {'enabled': 1}, 'comment': {'enabled': 1}}
let other = deepcopy(g:fixture.snapshot.threads[0])
let other.id = 'other-thread'
for message in other.comments | let message.id = 'other-' . message.id | endfor
let other.comments[0].body = 'A different discussion at the same source anchor.'
call add(g:fixture.snapshot.threads, other)
let g:original = deepcopy(g:fixture.snapshot)
let g:writes = 0
function! EntryHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    let g:writes += 1
    throw 'This fixture cannot write'
  endif
endfunction
function! EntryChange(timer) abort
  if g:change ==# 'reorder'
    call reverse(g:fixture.snapshot.threads)
    let earlier = deepcopy(g:fixture.snapshot.threads[0].comments[0])
    let earlier.id = 'new-earlier-message'
    call insert(g:fixture.snapshot.threads[0].comments, earlier, 0)
    RevueRefresh
  elseif g:change ==# 'removed'
    call remove(g:fixture.snapshot.threads, 1)
    RevueRefresh
  elseif g:change ==# 'moved'
    let g:fixture.snapshot.threads[1].start = 4
    let g:fixture.snapshot.threads[1].line = 4
    RevueRefresh
  elseif g:change ==# 'cursor'
    call cursor(4, 1)
  elseif g:change ==# 'view'
    RevueHelp
  endif
  call feedkeys("2\<CR>", 't')
endfunction
function! EntrySource() abort
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  let g:fixture.snapshot = deepcopy(g:original)
  RevueRefresh
  call cursor(3, 1)
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('EntryHost'), 0)
  call EntrySource()
  let source = [win_getid(), bufnr(), line('.'), col('.')]
  call assert_equal('<Plug>(revue-thread)', maparg('gt', 'n'))
  call feedkeys("2\<CR>", 't')
  RevueThread
  call assert_equal('other-thread', revue#session#Inspect(g:id).panelthread)
  call assert_equal(['other-thread'], uniq(sort(map(values(revue#session#Inspect(g:id).threadmap), {_, id -> id}))))
  call assert_match('Messages gp / gn · Actions ga · Quote gq', getline(2))
  call cursor(1, 1)
  RevueNextMessage
  RevueNextMessage
  let message = revue#discussion#Selected(revue#session#Inspect(g:id), line('.'))
  call assert_equal('other-local-reply-1', message.comment)
  call setreg('z', 'Retain this register')
  call cursor(message.body_start, 1)
  call feedkeys("V\<Esc>", 'xt')
  call revue#session#Quote(1)
  call assert_equal('other-thread', revue#session#Inspect(g:id).drafts[-1].thread)
  let quoted = join(getline(1, '$'), "\n")
  call assert_match('> Could we keep prefix', quoted)
  RevuePreview
  RevueClose
  call assert_equal(quoted, join(getline(1, '$'), "\n"))
  RevueClose
  call assert_equal(message.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  call assert_equal('Retain this register', getreg('z'))
  RevueClose
  call assert_equal(source, [win_getid(), bufnr(), line('.'), col('.')])
  " Selection follows the captured ID, not the refreshed ordinal.
  let g:change = 'reorder'
  call timer_start(80, function('EntryChange'))
  RevueThread
  call assert_equal('other-thread', revue#session#Inspect(g:id).panelthread)
  call assert_match('new-earlier-message', string(revue#session#Inspect(g:id).messagemap))
  RevueClose
  " Deleted/moved discussions and source navigation invalidate the chooser.
  for g:change in ['removed', 'moved', 'cursor', 'view']
    call EntrySource()
    call timer_start(80, function('EntryChange'))
    RevueThread
    call assert_notequal('threads', get(b:, 'revue_view', ''), g:change)
    if g:change ==# 'view'
      call assert_equal('help', b:revue_view)
      RevueClose
    endif
  endfor
  call EntrySource()
  call feedkeys("0\<CR>", 't')
  RevueThread
  call assert_equal('head', b:revue_role)
  " Command fallbacks remain visible when every default mapping is disabled.
  call revue#session#Close()
  let g:revue_no_default_mappings = 1
  let g:revue_mappings = {}
  let g:fixture.snapshot = deepcopy(g:original)
  let g:fixture.snapshot.threads = [g:fixture.snapshot.threads[0]]
  let g:id = revue#session#Open(g:fixture.snapshot, function('EntryHost'), 0)
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
  RevueThread
  call assert_match('Messages :RevuePreviousMessage / :RevueNextMessage', getline(2))
  call assert_match('Actions :RevueActions · Quote :RevueQuote', getline(2))
  call assert_equal(0, g:writes)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
