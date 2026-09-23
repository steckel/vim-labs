set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'edit': {'enabled': 1}, 'batch': {'enabled': 1, 'mode': 'atomic', 'kinds': ['comment']}}
for message in g:fixture.snapshot.threads[0].comments
  let message.version = 'original-' . message.id
  let message.capabilities = {'edit': {'enabled': 1}}
endfor
let g:calls = []
let g:mode = 'ok'
function! EditHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:calls, deepcopy(a:request))
    let draft = a:request.draft
    call assert_equal('edit', draft.kind)
    if g:mode ==# 'reject'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Permission lost at provider'})
    elseif g:mode ==# 'malformed'
      call a:Done({'ok': 1, 'data': {'id': draft.id, 'message': 'wrong'}})
    else
      let message = revue#edit#Message(g:fixture.snapshot, draft)
      let message.body = draft.body
      let message.version = 'accepted-' . draft.id
      let message.edited = 1
      call a:Done({'ok': 1, 'data': {'id': draft.id, 'message': draft.message, 'message_kind': draft.message_kind, 'thread': draft.thread, 'recovered': a:request.reconcile}})
    endif
  endif
endfunction
function! SelectReply() abort
  call cursor(3, 1)
  ReviewThread
  call cursor(1, 1)
  ReviewNextMessage
  ReviewNextMessage
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('EditHost'), 0)
  call SelectReply()
  let selected = deepcopy(revue#discussion#Selected(revue#session#Inspect(g:id), line('.')))
  if filereadable($REVUE_CAP_STORE . '/pending-edit')
    let pending = json_decode(readfile($REVUE_CAP_STORE . '/pending-edit')[0])
    call assert_equal(pending, revue#session#Inspect(g:id).drafts[-1])
    let g:fixture.snapshot.capabilities.edit.enabled = 0
    ReviewRefresh
    ReviewEditMessage
    call assert_equal(pending.id, b:revue_draft, 'existing edits remain accessible after permission loss')
    call assert_false(&modifiable)
    let g:mode = 'reject'
    ReviewCheckReceipt
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    call assert_equal(1, g:calls[-1].reconcile)
    ReviewEditBase
    ReviewDiscard
    call assert_equal(pending, revue#session#Inspect(g:id).drafts[-1])
    let g:mode = 'ok'
    ReviewCheckReceipt
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    call assert_equal(2, len(g:calls))
    call assert_equal(pending.body, revue#edit#Message(revue#session#Inspect(g:id).snapshot, pending).body)
  else
    let legacy = deepcopy(g:fixture.snapshot)
    call remove(legacy, 'capabilities')
    call assert_match('does not support', revue#capabilities#Error(legacy, {'kind': 'edit'}, 0))
    ReviewEditMessage
    let draft = deepcopy(revue#session#Inspect(g:id).drafts[-1])
    call assert_equal(selected.comment, draft.message)
    call assert_notequal(g:fixture.snapshot.threads[0].comments[0].id, draft.message, 'reply edit never targets root')
    call assert_equal(selected.message.body, join(getline(1, '$'), "\n"))
    call setline(1, ['My replacement', '', '> exact quoted text'])
    if line('$') > 3 | 4,$delete _ | endif
    let replacement = join(getline(1, '$'), "\n")
    let editor = win_getid()
    ReviewPreview
    let preview = join(getline(1, '$'), "\n")
    call assert_match('Original message', preview)
    call assert_match('Proposed replacement', preview)
    call assert_match('My replacement', preview)
    call assert_equal([], g:calls)
    ReviewClose
    call assert_equal(editor, win_getid())
    call assert_equal(replacement, join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewEditMessage
    call assert_equal(draft.id, b:revue_draft)
    call assert_equal(replacement, join(getline(1, '$'), "\n"), 'reopen never reseeds edited text')
    let message = revue#edit#Message(g:fixture.snapshot, draft)
    let message.version = 'concurrent'
    let message.body = 'Another editor changed this message.'
    ReviewRefresh
    ReviewSend
    call assert_equal([], g:calls, 'known version conflict is rejected before write')
    ReviewPreview
    call assert_match('Current message · changed', join(getline(1, '$'), "\n"))
    call assert_match('Another editor changed', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewEditBase
    let updated = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('concurrent', updated.expected_version)
    call assert_equal(replacement, updated.body)
    call assert_equal(message.body, updated.original_body)
    call assert_match('separately', revue#batch#Error(g:fixture.snapshot, [updated]))
    let message.capabilities.edit.enabled = 0
    ReviewRefresh
    ReviewSend
    call assert_equal([], g:calls)
    call assert_equal(replacement, join(getline(1, '$'), "\n"))
    let message.capabilities.edit.enabled = 1
    ReviewRefresh
    let g:mode = 'reject'
    ReviewSend
    call assert_equal('failed', revue#session#Inspect(g:id).drafts[-1].state)
    call assert_true(&modifiable)
    let g:mode = 'ok'
    ReviewSend
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    call assert_equal(replacement, revue#edit#Message(revue#session#Inspect(g:id).snapshot, draft).body)
    call assert_equal(g:fixture.snapshot.threads[0].comments[0].body, revue#session#Inspect(g:id).snapshot.threads[0].comments[0].body)
    call assert_equal(selected.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    ReviewEditMessage
    call setline(1, ['Uncertain replacement'])
    if line('$') > 1 | 2,$delete _ | endif
    let g:mode = 'malformed'
    ReviewSend
    call assert_false(&modifiable)
    let pending = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', pending.state)
    call writefile([json_encode(pending)], $REVUE_CAP_STORE . '/pending-edit')
    ReviewEditBase
    ReviewDiscard
    call assert_equal(pending, revue#session#Inspect(g:id).drafts[-1])
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
