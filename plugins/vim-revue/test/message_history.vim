set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'message_history': {'enabled': 1}, 'comment': {'enabled': 1}, 'reply': {'enabled': 1}}
for m in g:fixture.snapshot.threads[0].comments
  let m.version = 'v1'
  let m.capabilities = {'message_history': {'enabled': 1}}
endfor
let g:requests = []
function! EditHistoryHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'message_history'
    call add(g:requests, {'request': deepcopy(a:request), 'Done': a:Done})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    throw 'History fixture cannot mutate'
  endif
endfunction
function! EditPage(request, ids, next) abort
  let items = []
  for id in a:ids
    call add(items, {'id': id, 'kind': 'Edit', 'title': 'Message edited', 'actor': 'sam', 'created': '2026-09-14',
          \ 'body': "--- Before\n+++ After\n-old\n+new", 'url': '', 'details': ['Exact local diff'], 'provenance': 'Fixture history', 'content_state': 'available'})
  endfor
  return {'target': deepcopy(a:request.target), 'cursor': a:request.cursor, 'items': items, 'next_cursor': a:next,
        \ 'complete': empty(a:next) ? v:true : v:false, 'scope': 'Retained edits only', 'total': 3}
endfunction
function! EditPick(id) abort
  for row in sort(keys(revue#session#Inspect(g:id).historyrows), 'n')
    if revue#session#Inspect(g:id).historyrows[row].id ==# a:id | call cursor(str2nr(row) + 1, 1) | return | endif
  endfor
  throw 'Missing edit'
endfunction
function! EditSelection() abort
  return revue#session#Inspect(g:id).historyrows[string(line('.'))].id
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'edit-history', 'review': 'review', 'snapshot': g:fixture.snapshot, 'Request': function('EditHistoryHost')}, 0)
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
  RevueComment
  call setline(1, 'Keep unsent text while reading history')
  RevueClose
  RevueThreads
  call cursor(1, 1)
  RevueNextMessage
  RevueNextMessage
  RevueNextMessage
  call assert_equal('local-reply-2', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  let choice = index(map(revue#session#ActionGuide(), {_, i -> i.id}), 'message-history') + 1
  call feedkeys(choice . "\<CR>", 't')
  RevueReviewActions
  call assert_equal('message-history', b:revue_view)
  call assert_false(&modifiable)
  call assert_equal('local-reply-2', g:requests[-1].request.target.message)
  call g:requests[-1].Done({'ok': 0, 'error': 'Network unavailable'})
  call assert_match('Network unavailable', join(getline(1, '$'), "\n"))
  RevueReloadMessageHistory
  call g:requests[-1].Done({'ok': 1, 'data': EditPage(g:requests[-1].request, ['b', 'c'], 'older')})
  " Surface styling does not rewrite recorded text or depend on screen width.
  let raw = "\t```suggestion\n+literal 界 é\n> quoted source\n```"
  let decorated = EditPage(g:requests[-1].request, ['b', 'c'], 'older')
  let decorated.items[-1].body = raw
  call g:requests[-1].Done({'ok': 1, 'data': decorated})
  let bodyrow = search('```suggestion', 'nw')
  call assert_equal(split(raw, "\n", 1), getline(bodyrow, bodyrow + 3))
  let rendered = getline(1, '$')
  let &columns = 80
  let &lines = 24
  call assert_equal(rendered, getline(1, '$'), 'resize must not reflow recorded text into buffer lines')
  call assert_true(bodyrow < 9, 'recorded content remains near the top')
  call assert_true(len(sign_getplaced(bufnr(), {'group': 'RevueSurface'})[0].signs) > 0)
  call assert_equal('no', &l:signcolumn)
  call EditPick('c')
  RevueOlderMessageEdits
  let pending = g:requests[-1]
  RevueCancelMessageHistory
  call pending.Done({'ok': 1, 'data': EditPage(pending.request, ['a'], '')})
  call assert_equal(2, len(revue#session#Inspect(g:id).message_history.items))
  RevueOlderMessageEdits
  let pending = g:requests[-1]
  RevueHelp
  let page = EditPage(pending.request, ['a'], '')
  let page.items[0].content_state = 'redacted'
  let page.items[0].body = ''
  call pending.Done({'ok': 1, 'data': page})
  call assert_equal('help', b:revue_view)
  call assert_equal([], sign_getplaced(bufnr(), {'group': 'RevueSurface'})[0].signs, 'history backgrounds must not leak into Help')
  RevueClose
  call assert_equal('message-history', b:revue_view)
  call assert_equal('c', EditSelection())
  call assert_match('Revision content was redacted', join(getline(1, '$'), "\n"))
  let before = deepcopy(revue#session#Inspect(g:id).message_history.items)
  RevueReloadMessageHistory
  let invalid = EditPage(g:requests[-1].request, ['secret'], '')
  let invalid.items[0].content_state = 'redacted'
  call g:requests[-1].Done({'ok': 1, 'data': invalid})
  call assert_equal(before, revue#session#Inspect(g:id).message_history.items)
  call assert_match('must not be displayed', join(getline(1, '$'), "\n"))
  RevueReloadMessageHistory
  let pending = g:requests[-1]
  RevueClose
  call assert_equal('local-reply-2', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  RevuePreviousMessage
  RevueMessageHistory
  call assert_equal('local-reply-1', g:requests[-1].request.target.message)
  call pending.Done({'ok': 1, 'data': EditPage(pending.request, ['wrong-message'], '')})
  call assert_equal([], revue#session#Inspect(g:id).message_history.items)
  let page = EditPage(g:requests[-1].request, ['reply-one-edit'], '')
  call g:requests[-1].Done({'ok': 1, 'data': page})
  RevueReloadMessageHistory
  let pending = g:requests[-1]
  let g:fixture.snapshot.threads[0].comments[1].version = 'v2'
  let g:fixture.snapshot.threads[0].comments[1].body = 'Changed message'
  RevueRefresh
  call pending.Done({'ok': 1, 'data': EditPage(pending.request, ['stale'], '')})
  call assert_match('changed', revue#session#Inspect(g:id).message_history.error)
  RevueReloadMessageHistory
  call assert_equal('v2', g:requests[-1].request.target.expected_version)
  call g:requests[-1].Done({'ok': 1, 'data': EditPage(g:requests[-1].request, ['new'], '')})
  RevueClose
  call assert_equal('local-reply-1', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  call assert_equal('Keep unsent text while reading history', revue#session#Inspect(g:id).drafts[0].body)
  let disk = join(readfile(revue#session#Inspect(g:id).draftpath), "\n")
  call assert_notmatch('Fixture history', disk)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
