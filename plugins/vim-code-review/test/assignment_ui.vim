set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:revue_participants = [{'id': 'test-agent', 'label': 'Test agent'}]
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'assignment': {'enabled': 1, 'max_targets': 50}, 'comment': {'enabled': 1}}
for thread in g:fixture.snapshot.threads
  for message in thread.comments
    let message.version = 'v1'
    let message.publication = 'local'
  endfor
endfor
let g:calls = []
let g:recover = filereadable($REVUE_CAP_STORE . '/assignment')
function! AssignmentHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    call assert_equal('assignment', a:request.draft.kind)
    call assert_equal('', a:request.draft.body)
    if !g:recover
      call writefile([json_encode(a:request.draft)], $REVUE_CAP_STORE . '/assignment')
      call a:Done({'ok': 1, 'data': {'id': a:request.draft.id, 'assignment': 'wrong-receipt'}})
    else
      call assert_equal(1, a:request.reconcile)
      let receipt = {'assignment': 'assignment-1', 'url': '', 'recovered': v:true}
      for key in ['id', 'participant', 'reference', 'targets'] | let receipt[key] = deepcopy(a:request.draft[key]) | endfor
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('AssignmentHost'), 0)
  if g:recover
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/assignment')[0])
    RevueActivity
    call search('unknown', 'w')
    let session = revue#session#Inspect(g:id)
    for row in keys(session.activityrows)
      if session.activityrows[row].operation ==# frozen.id | call cursor(str2nr(row), 1) | break | endif
    endfor
    RevueOpenOperation
    call assert_equal(frozen.id, b:revue_draft)
    call assert_false(&modifiable)
    let g:revue_participants = []
    RevueCheckReceipt
    let session = revue#session#Inspect(g:id)
    call assert_equal([], session.drafts)
    call assert_equal('assignment-1', session.last_receipt.assignment)
    call assert_match('No agent was started', session.last_outcome)
    call assert_equal('assignment-1', session.activity[-1].receipt.assignment)
  else
    RevueThreads
    RevueNextMessage
    let source = revue#discussion#Selected(revue#session#Inspect(g:id), line('.'))
    RevueAssign
    call assert_equal('assignment-selection', b:revue_view)
    RevueClose
    call assert_equal(source.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    RevueAssign
    call assert_equal(1, len(revue#session#Inspect(g:id).assignment_selection.selected))
    call assert_equal('<Plug>(revue-assignment-toggle)', maparg('<Space>', 'n'))
    call cursor(7, 1)
    RevueToggleAssignment
    call assert_equal(0, len(revue#session#Inspect(g:id).assignment_selection.selected))
    RevueToggleAssignment
    call cursor(10, 1)
    RevueToggleAssignment
    call assert_equal(2, len(revue#session#Inspect(g:id).assignment_selection.selected))
    let g:revue_mappings = {'assignment-toggle': 'x', 'assignment-prepare': 'p'}
    call revue#session#AssignmentSelection()
    call assert_equal('<Plug>(revue-assignment-toggle)', maparg('x', 'n'))
    let actions = revue#session#ActionGuide()
    call assert_equal('p', filter(copy(actions), {_, a -> a.id ==# 'assignment-prepare'})[0].key)
    RevueHelp
    let before = deepcopy(revue#session#Inspect(g:id).assignment_selection)
    call revue#session#ToggleAssignment()
    call assert_equal(before, revue#session#Inspect(g:id).assignment_selection)
    RevueClose
    call assert_equal('assignment-selection', b:revue_view)
    call assert_equal(2, len(revue#session#Inspect(g:id).assignment_selection.selected))
    let g:revue_participants = []
    RevuePrepareAssignment
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    let g:revue_participants = [{'id': 'test-agent', 'label': 'Test agent'}]
    call feedkeys("0\<CR>", 't')
    RevuePrepareAssignment
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    call feedkeys("1\<CR>", 't')
    RevuePrepareAssignment
    call assert_equal('preview', b:revue_view)
    call assert_match('2 selected messages', join(getline(1, '$'), "\n"))
    call assert_match('entire threads', join(getline(1, '$'), "\n"))
    call assert_equal(0, len(g:calls))
    RevueClose
    call assert_equal('draft', b:revue_role)
    call assert_false(&modifiable)
    let draft = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('', draft.body)
    let changed = deepcopy(g:fixture.snapshot)
    let changed.threads[0].comments[0].version = 'v2'
    call assert_match('message changed', revue#assignment#Error(changed, draft))
    let changed = deepcopy(g:fixture.snapshot)
    let changed.head = 'new-head'
    call assert_match('comparison changed', revue#assignment#Error(changed, draft))
    call assert_match('does not support', revue#assignment#Error({}, draft))
    let duplicate = deepcopy(draft)
    call add(duplicate.targets, deepcopy(draft.targets[0]))
    call assert_match('only once', revue#assignment#Error(g:fixture.snapshot, duplicate))
    let oversized = deepcopy(draft)
    let oversized.targets = repeat([draft.targets[0]], 51)
    call assert_match('between 1 and 50', revue#assignment#Error(g:fixture.snapshot, oversized))
    RevueSend
    let session = revue#session#Inspect(g:id)
    call assert_equal('unknown', session.drafts[-1].state)
    call assert_false(&modifiable)
    RevueDiscard
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    call assert_equal(1, len(g:calls))
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
