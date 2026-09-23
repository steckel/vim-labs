set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'file_comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'thread_state': {'enabled': 1}}
let g:file_thread = {'id': 'file-root', 'subject_type': 'file', 'path': 'completion.vim', 'side': '', 'start': 0, 'line': 0, 'outdated': 0, 'resolved': 0,
      \ 'capabilities': {'reply': {'enabled': 1}, 'resolve': {'enabled': 1}},
      \ 'comments': [{'id': 'file-root', 'kind': 'comment', 'author': 'reviewer', 'created': '', 'body': 'Whole file concern'},
      \ {'id': 'file-reply', 'kind': 'reply', 'author': 'alex', 'created': '', 'body': 'File reply text'}]}
call add(g:fixture.snapshot.threads, deepcopy(g:file_thread))
for [path, status] in [['logo.png', 'modified'], ['deleted.vim', 'removed'], ['unavailable.vim', 'renamed']]
  call add(g:fixture.snapshot.files, {'id': path, 'path': path, 'old_path': status ==# 'renamed' ? 'previous.vim' : path, 'status': status, 'patch': ''})
  call add(g:fixture.snapshot.threads, extend(deepcopy(g:file_thread), {'id': path, 'path': path}))
endfor
let g:writes = []
let g:reads = []
function! FileHost(request, Done) abort
  if a:request.op ==# 'file'
    call add(g:reads, a:request.file.path)
    let content = deepcopy(g:fixture.content)
    if a:request.file.path ==# 'logo.png'
      let content = {'base': {'kind': 'binary', 'lines': []}, 'head': {'kind': 'binary', 'lines': []}}
    elseif a:request.file.path ==# 'deleted.vim'
      let content.head = {'kind': 'absent', 'lines': []}
    elseif a:request.file.path ==# 'unavailable.vim'
      call a:Done({'ok': 0, 'error': 'Fixture content unavailable'})
      return
    endif
    call a:Done({'ok': 1, 'data': content})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:writes, deepcopy(a:request))
    if a:request.reconcile
      call a:Done({'ok': 1, 'data': {'id': 'receipt', 'recovered': 1}})
    else
      call a:Done({'ok': 0, 'unknown': 1, 'error': 'Fixture accepted; connection interrupted'})
    endif
  endif
endfunction
function! FileRow(path) abort
  let state = revue#session#Inspect(g:id)
  call win_gotoid(bufwinid(state.tree))
  for [row, target] in items(state.rows)
    if get(target, 'kind', '') ==# 'file' && state.snapshot.files[target.index].path ==# a:path
      call cursor(str2nr(row), 1)
      return
    endif
  endfor
  throw 'Missing test file row'
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('FileHost'), 0)
  let state = revue#session#Inspect(g:id)
  if filereadable($REVUE_CAP_STORE . '/frozen')
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/frozen')[0])
    let g:fixture.snapshot.capabilities.file_comment.enabled = 0
    ReviewRefresh
    ReviewFileComment
    call assert_equal(frozen.body, join(getline(1, '$'), "\n"))
    call assert_false(&modifiable)
    ReviewCheckReceipt
    call assert_equal(1, len(g:writes))
    call assert_equal(1, g:writes[0].reconcile)
    call assert_equal(extend(deepcopy(frozen), {'state': 'submitting'}), g:writes[0].draft)
    call assert_equal([], filter(revue#session#Inspect(g:id).drafts, {_, d -> d.id ==# g:frozen.id}))
  else
    call assert_match('whole file', revue#activity#Target({'kind': 'file_comment', 'path': 'x'}))
    call assert_match('does not support file comments', revue#capabilities#Error({}, {'kind': 'file_comment'}, 0))
    call assert_true(len(filter(prop_list(1, {'bufnr': state.head}), {_, p -> p.type ==# 'RevueCardBorder'})) > 0, 'file card has virtual rows above source')
    call assert_equal(g:fixture.content.head.lines, getbufline(state.head, 1, '$'))
    call win_gotoid(bufwinid(state.tree))
    call cursor(1, 1)
    ReviewFileComment
    ReviewFileThreads
    call assert_equal([], revue#session#Inspect(g:id).drafts, 'file-list headings have no action target')
    call win_gotoid(state.headwin)
    ReviewFileThreads
    call assert_match('## File discussion', getline(4), 'file discussions precede line threads')
    call assert_notmatch(':0-0', join(getline(1, '$'), "\n"))
    ReviewNextMessage
    ReviewNextMessage
    call assert_equal('file-reply', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
    ReviewQuote
    call assert_equal('file-root', revue#session#Inspect(g:id).drafts[0].thread)
    call assert_match('> File reply text', join(getline(1, '$'), "\n"))
    ReviewPreview
    call assert_match('Reply · completion.vim · File discussion', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewClose
    ReviewJump
    call assert_equal(state.head, bufnr())
    call assert_equal(1, line('.'))
    ReviewFileComment
    call setline(1, ['Whole-file draft', '', 'Keep this text'])
    call revue#session#SaveDraft()
    let draft = deepcopy(revue#session#Inspect(g:id).drafts[-1])
    call assert_equal('file_comment', draft.kind)
    for key in ['side', 'start', 'end', 'line'] | call assert_false(has_key(draft, key)) | endfor
    ReviewPreview
    call assert_match('File comment preview', getline(1))
    call assert_match('Applies to the whole file', join(getline(1, '$'), "\n"))
    ReviewClose
    ReviewClose
    ReviewFileComment
    call assert_equal(draft.body, join(getline(1, '$'), "\n"))
    call assert_equal(2, len(revue#session#Inspect(g:id).drafts), 'same file reopens existing edits')
    let snap = deepcopy(g:fixture.snapshot)
    let snap.capabilities.batch = {'enabled': 1, 'mode': 'atomic', 'kinds': ['comment', 'review']}
    call assert_match('Send file comment drafts separately', revue#batch#Error(snap, [draft]))
    call add(snap.capabilities.batch.kinds, 'file_comment')
    call assert_equal('', revue#batch#Error(snap, [draft]))
    ReviewClose
    for path in ['logo.png', 'deleted.vim', 'unavailable.vim']
      call FileRow(path)
      let read_count = len(g:reads)
      ReviewFileComment
      call assert_equal(read_count, len(g:reads), 'file comments do not require source reads')
      call assert_equal(path, revue#session#Inspect(g:id).drafts[-1].path)
      call setline(1, 'Concern about ' . path)
      ReviewPreview
      call assert_match(path, join(getline(1, '$'), "\n"))
      if path ==# 'unavailable.vim' | call assert_match('Renamed from previous.vim', join(getline(1, '$'), "\n")) | endif
      ReviewClose
      ReviewClose
      ReviewFileThreads
      call assert_match('## File discussion', getline(4))
      call assert_match(path, getline(1))
      let state = revue#session#Inspect(g:id)
      let side = path ==# 'deleted.vim' ? 'base' : 'head'
      call assert_true(len(filter(prop_list(1, {'bufnr': state[side]}), {_, p -> p.type ==# 'RevueCardBorder'})) > 0)
      ReviewJump
      call assert_equal(state[side], bufnr())
    endfor
    call FileRow('completion.vim')
    ReviewOpenFile
    ReviewDiscussions Whole file concern
    call search('## completion.vim', 'W')
    ReviewOpenDiscussion
    call assert_match('File discussion', getline(4))
    ReviewRefresh
    call assert_match('File discussion', getline(4))
    ReviewClose
    call FileRow('completion.vim')
    ReviewOpenFile
    ReviewFileComment
    let g:fixture.snapshot.capabilities.file_comment = {'enabled': 0, 'reason': 'File comments disabled'}
    call revue#session#Refresh()
    ReviewSend
    call assert_equal([], g:writes)
    call assert_equal(draft.body, join(getline(1, '$'), "\n"))
    let g:fixture.snapshot.capabilities.file_comment.enabled = 1
    let g:fixture.snapshot.head = 'newhead'
    let g:fixture.snapshot.snapshot = 'newcomparison'
    call revue#session#Refresh()
    ReviewSend
    call assert_equal([], g:writes, 'stale file comments retain their original comparison')
    let g:fixture.snapshot.head = draft.head
    let g:fixture.snapshot.snapshot = draft.snapshot
    call revue#session#Refresh()
    ReviewSend
    call assert_equal(1, len(g:writes))
    call assert_false(&modifiable)
    let frozen = filter(revue#session#Inspect(g:id).drafts, {_, d -> d.id ==# g:draft.id})[0]
    call writefile([json_encode(frozen)], $REVUE_CAP_STORE . '/frozen')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
