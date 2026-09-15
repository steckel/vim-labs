set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:latest = deepcopy(g:fixture.snapshot)
let g:latest.capabilities = {'conversation': {'enabled': 1}}
for i in range(100)
  call add(g:latest.conversation, {'id': string(i), 'kind': 'comment', 'author': 'alex', 'created': '2026-09-14', 'body': 'Message ' . i . "\n\n> Quote\n\n```vim\necho 'example'\n```"})
endfor
function! UnchangedHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:fixture.content})
  else
    let g:ReadDone = a:Done
  endif
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'unchanged', 'review': 'review', 'snapshot': g:latest, 'Request': function('UnchangedHost')}, 0)
  RevueConversation
  let panel = bufnr()
  RevueNewConversation
  call setline(1, 'Unsent local text')
  let composer = bufnr()
  let panel_tick = getbufvar(panel, 'changedtick')
  call assert_equal(100, len(getbufvar(panel, 'revue_markdown_cache')))
  let draft_tick = b:changedtick
  let pos = getpos('.')
  RevueRefresh
  call assert_equal(panel_tick, getbufvar(panel, 'changedtick'), 'starting a refresh does not rebuild conversation')
  call assert_match('Refreshing', revue#session#RefreshLabel(g:id))
  call g:ReadDone({'ok': 1, 'data': deepcopy(g:latest)})
  call assert_equal(panel_tick, getbufvar(panel, 'changedtick'), 'unchanged snapshot leaves rich content intact')
  call assert_equal(draft_tick, b:changedtick)
  call assert_equal(pos, getpos('.'))
  call assert_equal('', revue#session#RefreshLabel(g:id))
  call assert_equal('succeeded', revue#session#Inspect(g:id).refresh_state.status)
  " A changed message must repaint even while another buffer is being edited.
  RevueRefresh
  let old_body = g:latest.conversation[4].body
  let g:latest.conversation[4].body = 'New reply body from server **updated**'
  call g:ReadDone({'ok': 1, 'data': deepcopy(g:latest)})
  call assert_true(getbufvar(panel, 'changedtick') > panel_tick)
  call assert_match('New reply body from server', join(getbufline(panel, 1, '$'), "\n"))
  call assert_false(has_key(getbufvar(panel, 'revue_markdown_cache'), sha256(old_body)), 'changed bodies leave no obsolete parse entry')
  let updated_row = index(getbufline(panel, 1, '$'), g:latest.conversation[4].body) + 1
  call assert_true(!empty(filter(prop_list(updated_row, {'bufnr': panel}), {_, p -> p.type ==# 'RevueInlineStrong'})), 'new body has current formatting')
  call assert_equal(composer, bufnr())
  call assert_equal('Unsent local text', getline(1))
  RevueRefresh
  let g:latest.capabilities.conversation.enabled = 0
  call g:ReadDone({'ok': 1, 'data': deepcopy(g:latest)})
  call assert_false(empty(filter(revue#session#ActionGuide(), {_, item -> item.id ==# 'send'})[0].reason))
  call assert_equal('Unsent local text', getline(1))
  " Failure status remains visible without destroying the retained conversation.
  let panel_tick = getbufvar(panel, 'changedtick')
  RevueRefresh
  call g:ReadDone({'ok': 0, 'error': 'Offline'})
  call assert_equal(panel_tick, getbufvar(panel, 'changedtick'))
  call assert_match('Refresh failed', revue#session#RefreshLabel(g:id))
  RevueCancelRefresh
  call assert_equal('', revue#session#RefreshLabel(g:id))
  RevueHelp
  call assert_equal({}, getbufvar(panel, 'revue_markdown_cache'), 'changing panel role clears retained parses')
  RevueClose
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
