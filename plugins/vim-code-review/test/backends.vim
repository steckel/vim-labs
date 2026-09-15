set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = tempname()
let g:revue_local_dir = tempname()
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:calls = []
function! BackendRequest(connection, request, Done) abort
  call add(g:calls, [a:connection, a:request.op])
  if a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': g:fixture.snapshot})
  elseif a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  endif
endfunction
try
  let ids = []
  for connection in ['one', 'two']
    let backend = {'id': 'fixture', 'connection': connection, 'review': 'same-id',
          \ 'snapshot': g:fixture.snapshot, 'Request': function('BackendRequest', [connection])}
    call add(ids, revue#backend#Open(backend, 0))
  endfor
  call assert_notequal(ids[0], ids[1])
  let first = revue#session#Inspect(ids[0])
  let second = revue#session#Inspect(ids[1])
  call assert_notequal(first.snapshot.key, second.snapshot.key)
  call assert_notequal(first.draftpath, second.draftpath)
  call revue#session#Refresh()
  call assert_equal(second.snapshot.key, revue#session#Inspect(ids[1]).snapshot.key)
  call assert_equal(second.snapshot.backend, revue#session#Inspect(ids[1]).snapshot.backend)
  call assert_equal(['two', 'refresh'], g:calls[-1])
  call revue#session#Close()
  call win_gotoid(first.headwin)
  call revue#session#Close()
  " Compatibility preserves original keys and existing saved drafts.
  let legacy = revue#review#OpenReview(g:fixture.snapshot, function('BackendRequest', ['legacy']), 0)
  call assert_equal(g:fixture.snapshot.key, revue#session#Inspect(legacy).snapshot.key)
  call revue#session#Refresh()
  call assert_equal(g:fixture.snapshot.key, revue#session#Inspect(legacy).snapshot.key)
  call revue#session#Close()
  call assert_false(isdirectory(g:revue_local_dir))
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call delete(g:revue_draft_dir, 'rf')
if !empty(v:errors) | call writefile(v:errors, '/dev/stderr') | cquit | endif
qa!
