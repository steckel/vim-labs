set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'reactions': {'enabled': 1}, 'reaction': {'enabled': 1, 'body_required': 0}}
let g:fixture.snapshot.capabilities.reply = {'enabled': 1}
for message in g:fixture.snapshot.threads[0].comments
  let message.capabilities = {'reactions': {'enabled': 1}, 'reaction': {'enabled': 1}}
endfor
let g:data = {'actor': 'fixture:me', 'actor_label': 'Me', 'complete': v:true, 'items': [
      \ {'id': '+1', 'label': 'Thumbs up', 'count': 2, 'mine': v:false}, {'id': 'heart', 'label': 'Heart', 'count': 1, 'mine': v:true}]}
let g:calls = []
let g:mode = 'ok'
let g:delay = 0
function! ReactionHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  elseif a:request.op ==# 'reactions'
    if g:delay
      let g:Delayed = a:Done
    else
      call a:Done({'ok': 1, 'data': deepcopy(g:data)})
    endif
  else
    call add(g:calls, deepcopy(a:request))
    let d = a:request.draft
    call assert_equal('reaction', d.kind)
    call assert_equal('', d.body)
    if g:mode ==# 'hold'
      let g:MutateDone = a:Done
      let g:mutation_request = deepcopy(a:request)
    elseif g:mode ==# 'throw'
      throw 'Fixture transport interrupted'
    elseif g:mode ==# 'reject'
      call a:Done({'ok': 0, 'unknown': 0, 'error': 'Actor unavailable'})
    elseif g:mode ==# 'bad'
      call a:Done({'ok': 1, 'data': {'id': d.id}})
    else
      for item in g:data.items
        if item.id ==# d.reaction
          let item.count += d.present - item.mine
          let item.mine = d.present
        endif
      endfor
      let receipt = {'observed': v:true}
      for key in ['id', 'message', 'message_kind', 'thread', 'actor', 'reaction', 'present'] | let receipt[key] = d[key] | endfor
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
function! PendingReactions() abort
  return filter(copy(revue#session#Inspect(g:id).drafts), {_, draft -> draft.kind ==# 'reaction'})
endfunction
function! PickReaction(id) abort
  for [row, item] in items(revue#session#Inspect(g:id).reactionrows)
    if item.id ==# a:id | call cursor(str2nr(row), 1) | return | endif
  endfor
  throw 'Reaction row missing: ' . a:id
endfunction
try
  call assert_equal('Reactions: Thumbs up 2 · Heart 1 [you]', revue#reaction#Summary({'reactions': g:data}))
  let invalid = deepcopy(g:data)
  let invalid.items[0].mine = 'yes'
  call assert_false(revue#reaction#Valid(invalid))
  call assert_true(revue#reaction#Valid(g:data))
  let g:id = revue#session#Open(g:fixture.snapshot, function('ReactionHost'), 0)
  call cursor(3, 1)
  RevueThread
  call cursor(1, 1)
  RevueNextMessage
  RevueNextMessage
  let selected = deepcopy(revue#discussion#Selected(revue#session#Inspect(g:id), line('.')))
  if !filereadable($REVUE_CAP_STORE . '/pending-reaction')
    RevueReply
    call setline(1, ['Unrelated human reply.', 'Keep these draft bytes.'])
    let reply_buffer = bufnr()
    RevueClose
  else
    let replies = filter(copy(revue#session#Inspect(g:id).drafts), {_, draft -> draft.kind ==# 'reply'})
    call assert_equal("Unrelated human reply.\nKeep these draft bytes.\nTyping during a reaction request.", replies[0].body)
  endif
  RevueReactions
  call assert_equal('reactions', b:revue_view)
  if !filereadable($REVUE_CAP_STORE . '/pending-reaction')
    call assert_match('Add your Thumbs up · 2', join(getline(1, '$'), "\n"))
  endif
  call assert_match('Remove your Heart · 1 \[you\]', join(getline(1, '$'), "\n"))
  call assert_equal([], g:calls, 'Opening the chooser never mutates')
  call PickReaction('heart')
  let guide = filter(revue#session#ActionGuide(), {_, item -> item.id ==# 'react'})
  call assert_equal('Remove your Heart', guide[0].label)
  let g:revue_no_default_mappings = 1
  let g:revue_mappings = {'react': 'gx'}
  call revue#maps#Apply('reactions')
  call assert_equal('', maparg('<CR>', 'n'))
  call assert_equal('<Plug>(revue-react)', maparg('gx', 'n'))
  call assert_equal(2, exists(':RevueReact'))
  unlet g:revue_no_default_mappings g:revue_mappings
  call revue#maps#Apply('reactions')
  if filereadable($REVUE_CAP_STORE . '/pending-reaction')
    let pending = json_decode(readfile($REVUE_CAP_STORE . '/pending-reaction')[0])
    let g:mode = 'reject'
    call PickReaction('+1')
    RevueReact
    call assert_equal('reactions', b:revue_view)
    call assert_equal(pending.id, g:calls[-1].draft.id)
    let g:fixture.snapshot.capabilities.reaction.enabled = 0
    let g:fixture.snapshot.capabilities.reactions.enabled = 0
    RevueRefresh
    call PickReaction('+1')
    RevueReact
    call assert_equal(pending, revue#session#Inspect(g:id).drafts[-1])
    call assert_equal(1, g:calls[-1].reconcile)
    call assert_match('no longer available', join(getline(1, '$'), "\n"))
    let g:mode = 'ok'
    call PickReaction('+1')
    RevueReact
    call assert_equal([], PendingReactions())
  else
    call PickReaction('+1')
    let g:mode = 'hold'
    let chooser = win_getid()
    let @z = 'register retained'
    RevueReact
    let draft = deepcopy(revue#session#Inspect(g:id).drafts[-1])
    call assert_equal(selected.comment, draft.message)
    call assert_equal(v:true, draft.present)
    call assert_equal('reactions', b:revue_view)
    call assert_equal(chooser, win_getid())
    call assert_equal('register retained', @z)
    call assert_false(exists('b:revue_draft'))
    let call_count = len(g:calls)
    call PickReaction('+1')
    RevueReact
    call assert_equal(call_count, len(g:calls), 'Repeated activation cannot duplicate an in-flight mutation')
    let Callback = g:MutateDone
    let g:mode = 'ok'
    execute 'sbuffer ' . reply_buffer
    call append('$', 'Typing during a reaction request.')
    let editing_window = win_getid()
    let editing_bytes = getline(1, '$')
    call ReactionHost(g:mutation_request, Callback)
    call assert_equal(editing_window, win_getid(), 'Reaction callback cannot steal composer focus')
    call assert_equal(editing_bytes, getline(1, '$'))
    let human = filter(copy(revue#session#Inspect(g:id).drafts), {_, draft -> draft.kind ==# 'reply'})[0]
    call assert_equal(join(editing_bytes, "\n"), human.body, 'Normal draft autosave retains every byte')
    RevueClose
    RevueReactions
    call Callback({'ok': 0, 'unknown': 1, 'error': 'Duplicate late callback'})
    call assert_equal([], PendingReactions())
    call assert_equal(3, g:data.items[0].count)
    call assert_true(g:data.items[0].mine)
    call assert_equal('reactions', b:revue_view)
    " A known rejection keeps the same intent; actor changes cannot retarget it.
    let g:mode = 'reject'
    call PickReaction('+1')
    RevueReact
    let rejected = deepcopy(revue#session#Inspect(g:id).drafts[-1])
    call assert_equal('failed', rejected.state)
    call assert_match('Retry · Remove Thumbs up as Me', join(getline(1, '$'), "\n"))
    let g:data.actor = 'fixture:someone-else'
    RevueReactions
    let call_count = len(g:calls)
    call PickReaction('+1')
    RevueReact
    call assert_equal(call_count, len(g:calls))
    call assert_match('Actor changed', join(getline(1, '$'), "\n"))
    let g:data.actor = 'fixture:me'
    let g:mode = 'ok'
    RevueReactions
    call PickReaction('+1')
    RevueReact
    call assert_equal(rejected.id, g:calls[-1].draft.id)
    call assert_equal(rejected.present, g:calls[-1].draft.present)
    call PickReaction('+1')
    RevueReact
    call assert_true(g:data.items[0].mine)
    call PickReaction('heart')
    RevueReact
    call assert_equal(v:false, g:calls[-1].draft.present)
    call assert_equal(0, g:data.items[1].count)
    RevueClose
    call assert_equal('threads', b:revue_view)
    call assert_equal(selected.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    call assert_match('Reactions: Thumbs up 3 \[you\]', join(getline(1, '$'), "\n"))
    RevueCopyMessage z
    call assert_equal(selected.message.body, @z)
    " A late detail read must not replace Help or the returned discussion.
    let g:delay = 1
    RevueReactions
    let Callback = g:Delayed
    RevueHelp
    let help = getline(1, '$')
    call Callback({'ok': 1, 'data': deepcopy(g:data)})
    call assert_equal(help, getline(1, '$'))
    let g:delay = 0
    RevueClose
    call assert_equal('reactions', b:revue_view)
    call assert_match('Thumbs up', join(getline(1, '$'), "\n"))
    RevueClose
    let g:delay = 1
    RevueReactions
    let Callback = g:Delayed
    RevueClose
    let text = getline(1, '$')
    call Callback({'ok': 1, 'data': deepcopy(g:data)})
    call assert_equal(text, getline(1, '$'))
    let g:delay = 0
    RevueReactions
    " A missing actor has counts but no actionable row.
    let original = deepcopy(g:data)
    let g:data.actor = ''
    for item in g:data.items | call remove(item, 'mine') | endfor
    RevueReactions
    call assert_equal({}, revue#session#Inspect(g:id).reactionrows)
    let g:data = original
    RevueReactions
    let g:delay = 1
    RevueReactions
    let Callback = g:Delayed
    let g:fixture.snapshot.threads[0].comments[1].capabilities.reactions.enabled = 0
    RevueRefresh
    call Callback({'ok': 1, 'data': deepcopy(g:data)})
    call assert_equal({}, revue#session#Inspect(g:id).reactionrows)
    call assert_match('no longer available', join(getline(1, '$'), "\n"))
    let g:delay = 0
    let g:fixture.snapshot.threads[0].comments[1].capabilities.reactions.enabled = 1
    RevueRefresh
    " Local persistence failure must stop the mutation before it reaches the host.
    let lock = revue#session#Inspect(g:id).draftpath . '.lock'
    call mkdir(lock)
    let call_count = len(g:calls)
    call PickReaction('+1')
    RevueReact
    call assert_equal(call_count, len(g:calls))
    call assert_equal([], PendingReactions())
    call delete(lock, 'd')
    let g:mode = 'throw'
    call PickReaction('+1')
    RevueReact
    call assert_equal('unknown', revue#session#Inspect(g:id).drafts[-1].state)
    let g:mode = 'bad'
    call PickReaction('+1')
    RevueReact
    let pending = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal('unknown', pending.state)
    call assert_match('Check outcome', join(getline(1, '$'), "\n"))
    call writefile([json_encode(pending)], $REVUE_CAP_STORE . '/pending-reaction')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
