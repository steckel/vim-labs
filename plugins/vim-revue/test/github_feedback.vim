set nocompatible nomore
let g:root = expand('<sfile>:p:h:h')
execute 'set runtimepath^=' . fnameescape(g:root)
execute 'set runtimepath^=' . fnameescape(fnamemodify(g:root, ':h') . '/vim-reviewhub')
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:reviewhub_command = ['python3', g:root . '/test/github_feedback_provider.py']
let g:connection = {'host': 'fixture.test', 'repo': 'team/project'}
let g:opened = {}
function! GotOpen(result) abort
  let g:opened = a:result
endfunction
function! Await(Check) abort
  let start = reltime()
  while !a:Check() && reltimefloat(reltime(start)) < 8
    sleep 10m
  endwhile
  if !a:Check() | throw 'Transport callback timed out' | endif
endfunction
try
  call reviewhub#transport#Request({'op': 'open', 'connection': g:connection, 'number': 42}, function('GotOpen'))
  call Await({-> !empty(g:opened)})
  call assert_true(g:opened.ok)
  call reviewhub#bridge#Open(g:connection, g:opened.data, 0)
  let g:id = t:revue_session
  call Await({-> !empty(revue#session#Inspect(g:id).loaded)})
  call assert_match('Thread counts and filters cover loaded feedback', join(getbufline(revue#session#Inspect(g:id).tree, 1, '$'), "\n"))
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(1, 1)
  let guide = filter(revue#session#ActionGuide(), {_, item -> item.id ==# 'thread'})
  call assert_match('No loaded discussion', guide[0].reason)
  RevueDiscussions Second page from
  call assert_match('No discussions match in loaded feedback', join(getline(1, '$'), "\n"))
  RevueLoadMoreFeedback
  call Await({-> !revue#session#Inspect(g:id).feedback_read.loading})
  call assert_equal('', revue#session#Inspect(g:id).feedback_read.error)
  call assert_match('Second page from the ReviewHub transport', join(getline(1, '$'), "\n"))
  call assert_equal(2, len(revue#session#Inspect(g:id).snapshot.threads))
  call assert_equal(3, len(revue#session#Inspect(g:id).snapshot.threads[1].comments), 'All replies remain in the loaded unit')
  RevueRefresh
  call Await({-> !revue#session#Inspect(g:id).busy})
  let requests = map(readfile($REVUE_CAP_STORE . '/github-requests.jsonl'), {_, line -> json_decode(line)})
  let refresh = filter(requests, {_, r -> r.op ==# 'open'})[-1]
  call assert_true(refresh.incremental, 'Capable refresh requests a bounded first page')
  call assert_equal('partial refresh', revue#session#Inspect(g:id).refresh_state.status)
  call assert_equal(2, len(revue#session#Inspect(g:id).snapshot.threads), 'Retain the previously loaded second page')
  RevueContinueRefresh
  call Await({-> !revue#session#Inspect(g:id).busy})
  call assert_equal('succeeded', revue#session#Inspect(g:id).refresh_state.status)
  let g:opened = {}
  call reviewhub#bridge#Request(g:connection, 42, {'op': 'refresh'}, function('GotOpen'))
  call Await({-> !empty(g:opened)})
  call assert_equal(2, len(g:opened.data.threads), 'Legacy callers retain complete refresh')
  call assert_equal(2, len(revue#session#Inspect(g:id).snapshot.threads))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
