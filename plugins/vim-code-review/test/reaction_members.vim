set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'reactions': {'enabled': 1}, 'reaction': {'enabled': 1}}
for message in g:fixture.snapshot.threads[0].comments
  let message.capabilities = {'reactions': {'enabled': 1}, 'reaction': {'enabled': 1}}
endfor
let g:data = {'actor': 'fixture:me', 'actor_label': 'Me', 'complete': v:true, 'items': [
      \ {'id': 'heart', 'label': 'Heart', 'count': 3, 'mine': v:true, 'members': {'items': [{'id': 'fixture:me', 'label': 'Me'}, {'id': 'fixture:alice', 'label': "Alice\nInjected heading"}], 'unavailable': 1}},
      \ {'id': '+1', 'label': 'Thumbs up', 'count': 1, 'mine': v:false}]}
let g:targets = []
let g:writes = 0
function! MemberHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'reactions'
    call add(g:targets, deepcopy(a:request.target))
    call a:Done({'ok': 1, 'data': deepcopy(g:data)})
  else
    let g:writes += 1
    throw 'Unexpected write'
  endif
endfunction
try
  call assert_true(revue#reaction#Valid(g:data))
  for bad in [{'items': [], 'unavailable': 0}, {'items': [], 'unavailable': -1}, {'items': 'bad', 'unavailable': 3}, {'items': [{'id': 'a', 'label': 'A'}, {'id': 'a', 'label': 'A'}], 'unavailable': 1}]
    let invalid = deepcopy(g:data)
    let invalid.items[0].members = bad
    call assert_false(revue#reaction#Valid(invalid))
  endfor
  let g:id = revue#session#Open(g:fixture.snapshot, function('MemberHost'), 0)
  call cursor(3, 1)
  ReviewThread
  call cursor(1, 1)
  ReviewNextMessage
  ReviewNextMessage
  let selected = deepcopy(revue#discussion#Selected(revue#session#Inspect(g:id), line('.')))
  let origin = [win_getid(), bufnr(), getpos('.')]
  let origin_role = b:revue_view
  ReviewReactions
  call assert_equal(selected.comment, g:targets[-1].message)
  call assert_match('Me \[you\]', join(getline(1, '$'), "\n"))
  call assert_equal(1, count(getline(1, '$'), '  Alice Injected heading'))
  call assert_match('1 account(s) unavailable', join(getline(1, '$'), "\n"))
  call assert_match('Participant details unavailable', join(getline(1, '$'), "\n"))
  call search('^  Me', 'w')
  ReviewReact
  call assert_equal(0, g:writes, 'A participant row is never an Add/Remove action')
  let g:data.actor = ''
  for item in g:data.items | unlet item.mine | endfor
  ReviewReactions
  call assert_match('  Me', join(getline(1, '$'), "\n"))
  call assert_notmatch('\[you\]', join(getline(1, '$'), "\n"))
  call assert_equal({}, revue#session#Inspect(g:id).reactionrows)
  ReviewClose
  call assert_equal(origin_role, b:revue_view)
  call assert_equal(origin[2], getpos('.'))
  call assert_equal(selected.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  call assert_equal(0, g:writes)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
