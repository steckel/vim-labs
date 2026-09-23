set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = tempname()
let g:rich = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:mutations = 0
function! InteractionHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:rich.content})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:rich.snapshot)})
  else
    let g:mutations += 1
    throw 'Interaction fixture cannot publish'
  endif
endfunction
try
  let id = revue#session#Open(g:rich.snapshot, function('InteractionHost'), 0)
  let s = revue#session#Inspect(id)
  call win_gotoid(s.treewin)
  call assert_equal([], getcompletion('Revue', 'command'))
  call assert_equal(2, exists(':ReviewOpenFile'))
  call assert_notequal(2, exists(':ReviewOpen'), 'File action must not shadow the GitHub URL command')
  call win_gotoid(s.basewin)
  call cursor(3, 4)
  let origin = winsaveview()
  call assert_equal('', maparg(']c', 'n'))
  call assert_equal('', maparg('[c', 'n'))
  call assert_equal('', maparg('?', 'n'))
  call assert_equal('<Plug>(revue-next-thread)', maparg(']t', 'n'))
  call revue#session#Threads()
  let panel = bufnr()
  call assert_equal('threads', b:revue_view)
  call assert_true(exists(':ReviewReply') == 2)
  call assert_equal([], getcompletion('Revue', 'command'))
  call revue#session#Help()
  call assert_equal('help', b:revue_view)
  call assert_equal({}, revue#session#Inspect(id).threadmap)
  call assert_equal('', maparg('r', 'n'))
  call assert_equal(0, exists(':ReviewReply'))
  call cursor(4, 1)
  call revue#session#Reply()
  call revue#session#NewConversation()
  call revue#session#JumpThread()
  call assert_equal([], revue#session#Inspect(id).drafts)
  let help = getline(1, '$')
  call revue#session#Refresh()
  call assert_equal(help, getline(1, '$'))
  call assert_equal(4, line('.'))
  call revue#session#CloseView()
  call assert_equal('threads', b:revue_view, 'Help returns to its originating discussion')
  call revue#session#CloseView()
  call assert_equal(s.basewin, win_getid())
  call assert_equal(origin.lnum, line('.'))
  call assert_equal(origin.col, col('.') - 1)
  " Base-side comment closes back to base, with native editing keys intact.
  call revue#session#Comment(0)
  call assert_equal('', maparg('q', 'n'))
  call assert_equal('', maparg('?', 'n'))
  call assert_equal('', maparg('r', 'n'))
  call setline(1, 'Retain this draft and source context.')
  call revue#session#CloseView()
  call assert_equal(s.basewin, win_getid())
  call assert_equal('Retain this draft and source context.', revue#session#Inspect(id).drafts[-1].body)
  " Conversation mode cannot use stale thread targets either.
  call revue#session#Threads()
  call revue#session#Conversation()
  call assert_equal('conversation', b:revue_view)
  let before = len(revue#session#Inspect(id).drafts)
  call revue#session#Reply()
  call assert_equal(before, len(revue#session#Inspect(id).drafts))
  call revue#session#Refresh()
  call assert_equal('conversation', b:revue_view)
  call revue#session#CloseView()
  " Message identity, body selection, quoting, and refresh anchoring.
  call win_gotoid(s.headwin)
  call cursor(3, 1)
  ReviewThread
  call assert_equal('local-thread', revue#session#Inspect(id).panelthread)
  call cursor(1, 1)
  ReviewNextMessage
  call assert_match('morgan', getline('.'))
  ReviewNextMessage
  call assert_match('alex', getline('.'))
  let selected = revue#discussion#Selected(revue#session#Inspect(id), line('.'))
  call assert_equal('local-reply-1', selected.comment)
  ReviewCopyMessage a
  call assert_match('Yes. I', getreg('a'))
  call setreg('b', 'retain register')
  ReviewCopyLink b
  call assert_equal('retain register', getreg('b'))
  let g:rich.snapshot.threads[0].comments[1].url = 'https://example.test/review#reply-1'
  call revue#session#Refresh()
  ReviewCopyLink b
  call assert_equal('https://example.test/review#reply-1', getreg('b'))
  call feedkeys("2\<CR>", 't')
  ReviewActions
  call assert_match('Yes. I', getreg('"'))
  call cursor(selected.body_end, 1)
  call feedkeys('VQ', 'xt')
  call assert_equal('draft', b:revue_role)
  call assert_match('^> Yes. I', getline(1))
  call assert_equal('local-thread', revue#session#Inspect(id).drafts[-1].thread)
  call append('$', 'My additional reply.')
  let text_before_preview = getline(1, '$')
  let composer = win_getid()
  let discussion_win = revue#session#Inspect(id).panelwin
  ReviewPreview
  call assert_equal('preview', b:revue_view)
  call assert_match('Reply · completion.vim', join(getline(1, '$'), "\n"))
  call assert_match('My additional reply.', join(getline(1, '$'), "\n"))
  call assert_equal(0, &modifiable)
  call assert_equal(0, exists(':ReviewSend'))
  call assert_true(win_id2tabwin(discussion_win)[0] > 0)
  call revue#session#Refresh()
  call assert_equal('preview', b:revue_view)
  ReviewClose
  call assert_equal(composer, win_getid())
  call assert_equal(text_before_preview, getline(1, '$'))
  call assert_true(len(filter(prop_list(1), {_, p -> p.type ==# 'RevueDraftContext'})) > 0)
  ReviewClose
  call assert_equal('threads', b:revue_view)
  ReviewQuote
  call assert_match('My additional reply.', join(getline(1, '$'), "\n"))
  call assert_match('> Could we keep prefix', join(getline(1, '$'), "\n"))
  ReviewClose
  let selected = revue#discussion#Selected(revue#session#Inspect(id), line('.'))
  call assert_equal('local-reply-1', selected.comment)
  " An earlier message growing must not shift selection onto a different reply.
  let g:rich.snapshot.threads[0].comments[0].body .= "\n\nExtra context before the selected reply."
  call revue#session#Refresh()
  let selected = revue#discussion#Selected(revue#session#Inspect(id), line('.'))
  call assert_equal('local-reply-1', selected.comment)
  call cursor(selected.body_start, 1)
  call setpos("'<", [0, selected.body_start, 1, 0])
  call setpos("'>", [0, selected.end + 1, 1, 0])
  let before = len(revue#session#Inspect(id).drafts)
  call revue#session#Quote(1)
  call assert_equal('threads', b:revue_view)
  call assert_equal(before, len(revue#session#Inspect(id).drafts))
  " Reply can be invoked anywhere within a multiline source range.
  call win_gotoid(s.headwin)
  let g:rich.snapshot.threads[0].start = 2
  call revue#session#Refresh()
  call cursor(2, 1)
  ReviewReply
  call assert_equal('local-thread', revue#session#Inspect(id).drafts[-1].thread)
  ReviewClose
  call assert_equal(s.headwin, win_getid())
  call assert_equal(2, line('.'))
  " If the originating source window is closed, restore its side and anchor.
  call win_gotoid(s.basewin)
  call cursor(3, 1)
  ReviewComment
  let composer = win_getid()
  call win_gotoid(s.basewin)
  close
  call win_gotoid(composer)
  ReviewClose
  call assert_equal(revue#session#Inspect(id).basewin, win_getid())
  call assert_equal('base', b:revue_side)
  call assert_equal(3, line('.'))
  " Explicit mappings work with all shipped defaults disabled.
  call revue#session#Close()
  let g:revue_no_default_mappings = 1
  let g:revue_mappings = {'reply': 'gr'}
  let id = revue#session#Open(g:rich.snapshot, function('InteractionHost'), 0)
  let s = revue#session#Inspect(id)
  call win_gotoid(s.headwin)
  for key in ['q', 'c', 'r', 't', 'R', 'g?', ']t', ']f']
    call assert_equal('', maparg(key, 'n'), key)
  endfor
  call assert_equal('<Plug>(revue-reply)', maparg('gr', 'n'))
  call assert_equal(2, exists(':ReviewThreads'))
  call assert_false(empty(maparg('<Plug>(revue-threads)', 'n')))
  ReviewThreads
  call assert_equal('threads', b:revue_view)
  call assert_equal('', maparg('<CR>', 'n'))
  ReviewJump
  call assert_equal(s.headwin, win_getid())
  ReviewComment
  call setline(1, ['```suggestion', 'replacement from the original comparison', '```'])
  let draft_id = revue#session#Inspect(id).drafts[-1].id
  let composer = win_getid()
  let lock = revue#session#Inspect(id).draftpath . '.lock'
  call mkdir(lock)
  ReviewClose
  call assert_equal(composer, win_getid())
  call assert_equal(1, &modified)
  call assert_match('SAVE FAILED', &statusline)
  call delete(lock, 'd')
  ReviewClose
  call assert_equal(s.headwin, win_getid())
  call revue#session#Close()
  " A restored old draft must not preview new source as its removed lines.
  let g:rich.snapshot.snapshot = 'new-comparison'
  let g:rich.snapshot.head = 'newhead'
  let g:rich.content.head.lines[2] = '__NEW_REVISION__'
  let id = revue#session#Open(g:rich.snapshot, function('InteractionHost'), 0)
  let s = revue#session#Inspect(id)
  call win_gotoid(s.treewin)
  for [row, target] in items(s.rows)
    if get(target, 'id', '') ==# draft_id
      call cursor(str2nr(row), 1)
      call revue#session#Activate()
      break
    endif
  endfor
  call assert_equal('draft', b:revue_role)
  ReviewPreview
  call assert_match('Original source is not loaded', join(getline(1, '$'), "\n"))
  call assert_notmatch('__NEW_REVISION__', join(getline(1, '$'), "\n"))
  for row in range(1, line('$'))
    call assert_equal([], filter(prop_list(row), {_, p -> p.type ==# 'RevueCardDelete'}))
  endfor
  call assert_equal(0, g:mutations)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call delete(g:revue_draft_dir, 'rf')
if !empty(v:errors) | call writefile(v:errors, '/dev/stderr') | cquit | endif
qa!
