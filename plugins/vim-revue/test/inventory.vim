set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:latest = deepcopy(g:fixture.snapshot)
let g:latest.inventory = {'files': {'state': 'complete', 'total': 1},
      \ 'threads': {'state': 'partial', 'total': 3, 'reason': 'More feedback is available.'},
      \ 'conversation': {'state': 'unsupported', 'reason': 'This backend supplies inline feedback only.'}}
let g:ReadDone = 0
function! InventoryHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    let g:ReadDone = a:Done
  else
    throw 'Inventory fixture cannot mutate'
  endif
endfunction
function! InventoryText() abort
  return join(getbufline(revue#session#Inspect(g:id).panel, 1, '$'), "\n")
endfunction
function! InventoryTarget() abort
  return get(revue#session#Inspect(g:id).discoveryrows, string(line('.')), {})
endfunction
function! InventoryPick(message) abort
  for row in sort(keys(revue#session#Inspect(g:id).discoveryrows), 'n')
    if get(revue#session#Inspect(g:id).discoveryrows[row], 'message', '') ==# a:message
      call cursor(str2nr(row), 1)
      return
    endif
  endfor
  throw 'Missing inventory target'
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'coverage', 'review': 'review', 'snapshot': g:latest, 'Request': function('InventoryHost')}, 0)
  call cursor(3, 1)
  RevueComment
  call setline(1, 'Unsent text survives inventory reads')
  RevueClose
  RevueDiscussions
  call assert_match('Threads: 1/3 loaded · partial', InventoryText())
  call assert_match('Conversation: 0 loaded · unsupported', InventoryText())
  call assert_match('excludes unloaded pages', InventoryText())
  call InventoryPick('local-reply-2')
  let selected = revue#discovery#Key(InventoryTarget())
  RevueRefresh
  call assert_match('Refreshing review', InventoryText())
  call assert_equal(selected, revue#discovery#Key(InventoryTarget()))
  call g:ReadDone({'ok': 0, 'error': 'Second page failed'})
  call assert_match('previously loaded feedback retained', InventoryText())
  call assert_equal(selected, revue#discovery#Key(InventoryTarget()))
  call assert_equal('Unsent text survives inventory reads', revue#session#Inspect(g:id).drafts[0].body)
  RevueRefresh
  let more = deepcopy(g:latest.threads[0])
  let more.id = 'next-thread'
  let more.comments = [extend(deepcopy(more.comments[0]), {'id': 'next-root', 'body': 'New page needle'})]
  call add(g:latest.threads, more)
  let g:latest.inventory.threads = {'state': 'complete', 'total': 2}
  call g:ReadDone({'ok': 1, 'data': deepcopy(g:latest)})
  call assert_match('Threads: 2/2 loaded · complete', InventoryText())
  call assert_match('completion.vim.*\[2\].*\[1 new\]', join(getbufline(revue#session#Inspect(g:id).tree, 1, '$'), "\n"))
  call assert_equal(selected, revue#discovery#Key(InventoryTarget()))
  call assert_notmatch('Refresh failed', InventoryText())
  RevueDiscussions New page needle
  call assert_match('1 matching threads (1 matching messages)', InventoryText())
  call InventoryPick('next-root')
  RevueOpenDiscussion
  call assert_equal('next-root', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  RevueClose
  RevueDiscussions not-present
  call assert_match('No discussions match in loaded feedback', InventoryText())
  " Missing and malformed coverage never imply an empty complete review.
  for metadata in [{}, [], {'threads': []}, {'threads': {'state': 'complete', 'total': 0}}, {'threads': {'state': 'complete', 'total': '2'}}]
    let sample = deepcopy(g:latest)
    let sample.inventory = metadata
    let entry = revue#inventory#Entry(sample, 'threads')
    call assert_equal('unknown', entry.state)
    call assert_equal(2, entry.loaded)
  endfor
  for state in ['complete', 'partial', 'failed', 'loading', 'unsupported', 'unknown']
    let sample = deepcopy(g:latest)
    let sample.inventory.threads = {'state': state, 'total': 2, 'reason': "Do not\nforge rows"}
    call assert_equal(state, revue#inventory#Entry(sample, 'threads').state)
    call assert_notmatch("\n", revue#inventory#Entry(sample, 'threads').reason)
  endfor
  " A late successful refresh while editing must preserve buffer/focus/body.
  RevueDiscussionFilter clear
  call InventoryPick('local-reply-2')
  RevueRefresh
  RevueOpenDiscussion
  RevueReply
  call setline(1, 'Keep editing while coverage updates')
  let editing = win_getid()
  call g:ReadDone({'ok': 1, 'data': deepcopy(g:latest)})
  call assert_equal(editing, win_getid())
  call assert_equal('Keep editing while coverage updates', getline(1))
  RevueClose
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
