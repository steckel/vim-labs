set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
set columns=140 lines=45
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:a = deepcopy(g:fixture.snapshot)
let g:a.key = 'local/discovery-tests'
let g:a.threads[0].resolved = v:false
for [id, path, status] in [['other', 'src/other file.vim', 'added'], ['renamed', 'renamed[1].vim', 'renamed']]
  call add(g:a.files, extend(deepcopy(g:a.files[0]), {'id': id, 'path': path, 'old_path': id ==# 'renamed' ? 'old name.vim' : path, 'status': status}))
endfor
let thread = extend(deepcopy(g:a.threads[0]), {'id': 'other-thread', 'path': g:a.files[1].path, 'resolved': v:true})
let thread.comments[-1].id = 'deep-reply'
let thread.comments[-1].body = repeat('Earlier prose. ', 40) . 'DEEP_NEEDLE unicode café'
call add(g:a.threads, thread)
let missing = extend(deepcopy(thread), {'id': 'missing-thread', 'path': 'gone.vim', 'outdated': v:true})
call remove(missing, 'resolved')
let missing.comments = [extend(deepcopy(thread.comments[0]), {'id': 'missing-root', 'body': 'Absent file discussion'})]
call add(g:a.threads, missing)
let g:a.conversation = [
      \ {'id': 'same', 'kind': 'comment', 'author': 'alex', 'created': '', 'body': 'General comment'},
      \ {'id': 'same', 'kind': 'review', 'author': 'morgan', 'created': '', 'body': 'Review summary'}]
let g:b = deepcopy(g:a)
let g:b.snapshot = 'discovery-b'
let g:b.head = 'new-head'
let g:latest = deepcopy(g:a)
let g:calls = []
let g:defer = ''
let g:pending = []
function! Content(snapshot, file) abort
  let content = deepcopy(g:fixture.content)
  if a:snapshot.snapshot ==# g:b.snapshot && a:file.id ==# g:a.files[0].id
    let content.head.lines[0] = 'Changed content'
  endif
  return content
endfunction
function! DiscoveryHost(request, Done) abort
  call add(g:calls, deepcopy(a:request))
  if a:request.op ==# 'file'
    if a:request.file.id ==# g:defer
      call add(g:pending, {'Done': a:Done, 'request': deepcopy(a:request)})
    else
      call a:Done({'ok': 1, 'data': Content(a:request.snapshot, a:request.file)})
    endif
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:latest)})
  else
    throw 'Discovery fixture prohibits mutations: ' . a:request.op
  endif
endfunction
function! State() abort
  return revue#session#Inspect(g:id)
endfunction
function! SelectFile(index) abort
  let state = State()
  call win_gotoid(state.treewin)
  for [row, target] in items(state.rows)
    if target.kind ==# 'file' && target.index == a:index
      call cursor(str2nr(row), 1)
      return
    endif
  endfor
  throw 'Fixture could not find file ' . a:index
endfunction
function! SelectResult(fields) abort
  for [row, target] in items(State().discoveryrows)
    if empty(filter(copy(a:fields), {key, value -> get(target, key, '') !=# value}))
      call cursor(str2nr(row), 1)
      return
    endif
  endfor
  throw 'Fixture could not find result ' . string(a:fields)
endfunction
function! Progress(index) abort
  let state = State()
  return revue#progress#State(state, state.snapshot, state.snapshot.files[a:index])
endfunction
try
  let restarting = filereadable($REVUE_CAP_STORE . '/restart')
  if !restarting
    call mkdir(g:revue_draft_dir, 'p', 0700)
    let child = {'id': 'frozen-child', 'kind': 'reply', 'thread': 'missing-thread', 'body': 'Frozen feedback',
          \ 'state': 'draft', 'snapshot': g:a.snapshot, 'head': g:a.head, 'base_tip': g:a.base}
    let frozen = {'id': 'frozen-batch', 'kind': 'batch', 'items': [child], 'body': '',
          \ 'state': 'unknown', 'snapshot': g:a.snapshot, 'head': g:a.head, 'base_tip': g:a.base}
    call writefile([json_encode({'version': 1, 'key': g:a.key, 'drafts': [frozen]})], g:revue_draft_dir . '/' . sha256(g:a.key) . '.json')
  endif
  let g:id = revue#session#Open(restarting ? g:b : g:a, function('DiscoveryHost'), 0)
  sleep 40m
  if restarting
    call assert_equal('unviewed', Progress(0), 'changed content is not viewed')
    call assert_equal('viewed', Progress(1), 'unchanged file keeps acknowledgement across process/revision')
    call assert_equal('viewed', Progress(2))
    call assert_equal({}, State().filefilters, 'filters are session-local')
    call assert_equal({}, State().discussionfilters)
    RevueViewed
    call assert_equal('viewed', Progress(0))
    RevueUnviewed
    call assert_equal('unviewed', Progress(0))
    let disk = join(readfile(State().draftpath), "\n")
    call assert_notmatch('Earlier prose', disk)
    call assert_notmatch('Changed content', disk)
    call assert_notmatch('function! s:CompleteRefs', disk, 'progress stores hashes, not source')
  else
    call assert_equal(['', '', ''], [maparg('/', 'n'), maparg('?', 'n'), maparg('<CR>', 'n')])
    let source = win_getid()
    RevueFileFilter path other file
    call assert_equal([1], revue#discovery#Files(State()))
    call assert_equal([source, 0], [win_getid(), State().index])
    RevueNextFile
    call assert_equal(1, State().index)
    RevueFileFilter status added
    RevueFileFilter status invalid
    call assert_equal('added', State().filefilters.status)
    RevueFileFilter clear
    RevueFileFilter path old name
    call assert_equal([2], revue#discovery#Files(State()), 'old rename path is searchable')
    RevueFileFilter path [1]
    call assert_equal([2], revue#discovery#Files(State()), 'path text is literal, not a regex')
    RevueFileFilter clear
    RevueFileFilter threads resolved
    call assert_equal([1], revue#discovery#Files(State()))
    RevueFileFilter threads none
    call assert_equal([2], revue#discovery#Files(State()))
    RevueFileFilter threads unresolved
    call assert_equal([0], revue#discovery#Files(State()))
    RevueFileFilter path no matches
    let before = State().index
    RevueNextFile
    call assert_equal(before, State().index)
    call assert_match('No files match', join(getbufline(State().tree, 1, '$'), "\n"))
    RevueFileFilter clear
    call SelectFile(1)
    RevueFileFilter status modified
    call assert_equal(6, line('.'), 'disappearing tree target returns to inert header')
    RevueOpen
    call assert_equal(before, State().index)
    RevueDiscussions DEEP_NEEDLE
    call assert_notmatch('\n', join(getline(1, '$'), ''), 'excerpts contain no embedded newlines/NUL cells')
    call SelectResult({'message': 'deep-reply'})
    RevueOpenDiscussion
    call assert_equal('deep-reply', State().messagemap[string(line('.'))].comment)
    call assert_equal('src/other file.vim', State().snapshot.files[State().index].path)
    call assert_true(has_key(State().revealed_files, 'other'))
    RevueClose
    call assert_equal('discussions', b:revue_view)
    call assert_equal('deep-reply', State().discoveryrows[string(line('.'))].message)
    " Insert another matching message above the selected reply, then remove it.
    call insert(g:latest.threads[1].comments, {'id': 'inserted', 'kind': 'comment', 'author': 'lee', 'created': '', 'body': 'DEEP_NEEDLE first'}, 0)
    RevueRefresh
    call assert_equal('deep-reply', State().discoveryrows[string(line('.'))].message)
    let g:latest.threads[1].comments[-1].body = 'No longer matches'
    RevueRefresh
    call assert_equal(1, line('.'), 'vanished selection must not retarget to a different message')
    RevueOpenDiscussion
    call assert_equal('discussions', b:revue_view)
    RevueDiscussionFilter clear
    call assert_notmatch('\n', join(getline(1, '$'), ''), 'multiline root excerpts are flattened without control cells')
    call SelectResult({'message': 'deep-reply'})
    let selected_author = g:latest.threads[1].comments[-1].author
    execute 'RevueDiscussionFilter author ' . selected_author
    call assert_equal('deep-reply', State().discoveryrows[string(line('.'))].message, 'filter retains matching message identity')
    RevueDiscussionFilter author nobody
    call assert_equal(1, line('.'))
    call assert_match('No discussions match', join(getline(1, '$'), "\n"))
    RevueDiscussionFilter clear
    RevueDiscussionFilter anchor outdated
    call SelectResult({'message': 'missing-root'})
    let before = State().index
    RevueOpenDiscussion
    call assert_equal(before, State().index, 'absent file discussion does not guess a source')
    call assert_equal('missing-thread', State().panelthread)
    RevueClose
    RevueDiscussionFilter clear
    RevueDiscussionFilter anchor none
    call SelectResult({'message': 'same', 'message_kind': 'review'})
    RevueOpenDiscussion
    call assert_equal('review', State().messagemap[string(line('.'))].kind, 'message namespace matters')
    RevueClose
    RevueHelp
    call assert_equal(0, exists(':RevueOpenDiscussion'))
    RevueRefresh
    call assert_equal('help', b:revue_view)
    RevueClose
    RevueDiscussionFilter clear
    RevueFileFilter clear
    call assert_equal({}, State().revealed_files)
    RevueDiscussions Frozen feedback
    call SelectResult({'kind': 'draft', 'item': 'frozen-child'})
    call assert_equal('outdated', State().discoveryrows[string(line('.'))].anchor)
    RevueOpenDiscussion
    call assert_equal('batch', b:revue_view)
    call assert_equal('frozen-batch', State().batchid)
    call assert_equal('frozen-child', State().batchrows[string(line('.'))])
    call assert_false(&modifiable)
    RevueClose
    call assert_equal('frozen-child', State().discoveryrows[string(line('.'))].item)
    RevueDiscussionFilter clear
    " Save a reply and find its existing editable draft in the index.
    call revue#session#Threads('local-thread')
    RevueReply
    call setline(1, 'Retained draft body')
    RevueClose
    RevueDiscussions Retained draft
    call SelectResult({'kind': 'draft'})
    let draft_id = State().discoveryrows[string(line('.'))].draft
    RevueOpenDiscussion
    call assert_equal(['Retained draft body'], getline(1, '$'))
    RevueClose
    call assert_equal('discussions', b:revue_view)
    call assert_equal(draft_id, State().discoveryrows[string(line('.'))].draft)
    " Refresh with an open editor cannot move focus or discard unsaved typing.
    RevueOpenDiscussion
    let editor = win_getid()
    call setline(1, 'Changed unsaved draft')
    call revue#session#Refresh()
    call assert_equal(editor, win_getid())
    call assert_equal(['Changed unsaved draft'], getline(1, '$'))
    RevueClose
    RevueDiscussionFilter clear
    " Marking the selected tree file leaves source/focus alone.
    call SelectFile(0)
    let before = State().index
    let treewin = win_getid()
    RevueViewed
    call assert_equal('viewed', Progress(0))
    call assert_equal([before, treewin], [State().index, win_getid()])
    RevueFileFilter viewed unviewed
    call assert_equal(6, line('.'), 'Viewed removes a filtered item without selecting a neighbor')
    RevueFileFilter clear
    call SelectFile(1)
    RevueViewed
    call assert_equal('viewed', Progress(1))
    " A deferred background request coalesces mark/unmark intent and never opens code.
    call SelectFile(2)
    let g:defer = 'renamed'
    RevueViewed
    sleep 30m
    call assert_equal(1, len(g:pending))
    call assert_equal('checking', Progress(2))
    RevueUnviewed
    let job = remove(g:pending, 0)
    call job.Done({'ok': 0, 'error': 'Offline'})
    call assert_equal('unavailable', Progress(2))
    call assert_equal(treewin, win_getid())
    RevueViewed
    sleep 30m
    let job = remove(g:pending, 0)
    RevueUnviewed
    call job.Done({'ok': 1, 'data': Content(job.request.snapshot, job.request.file)})
    call assert_equal('unviewed', Progress(2), 'late mark cannot override newer unmark')
    RevueViewed
    call assert_equal('viewed', Progress(2))
    let g:defer = ''
    " Compare both sides and binary/newline metadata in the content model.
    let model = State()
    let f = model.snapshot.files[0]
    let cmp = deepcopy(model.snapshot)
    let cmp.snapshot = 'model-only'
    let content = Content(g:a, f)
    call revue#progress#Observe(model, cmp, f, content)
    call assert_equal('viewed', revue#progress#State(model, cmp, f))
    let content.base.lines[0] = 'Changed base'
    call revue#progress#Observe(model, cmp, f, content)
    call assert_equal('unviewed', revue#progress#State(model, cmp, f))
    let content = Content(g:a, f)
    let content.head.final_newline = 1
    call revue#progress#Observe(model, cmp, f, content)
    call revue#progress#Set(model, cmp, f, 1)
    let content.head.final_newline = 0
    call revue#progress#Observe(model, cmp, f, content)
    call assert_equal('unviewed', revue#progress#State(model, cmp, f))
    let content = {'base': {'kind': 'absent'}, 'head': {'kind': 'binary', 'hash': 'one'}}
    call revue#progress#Observe(model, cmp, f, content)
    call revue#progress#Set(model, cmp, f, 1)
    let content.head.hash = 'two'
    call revue#progress#Observe(model, cmp, f, content)
    call assert_equal('unviewed', revue#progress#State(model, cmp, f))
    " Switch while unchanged-file verification is delayed, then deliver the old read.
    let g:latest = deepcopy(g:b)
    RevueRefresh
    let g:defer = 'other'
    RevueLatest
    sleep 30m
    call assert_equal('unviewed', Progress(0))
    call assert_equal('checking', Progress(1))
    call assert_equal(1, len(g:pending))
    RevuePreviousComparison
    let oldwin = win_getid()
    let oldtext = getline(1, '$')
    let job = remove(g:pending, 0)
    call job.Done({'ok': 1, 'data': Content(job.request.snapshot, job.request.file)})
    call assert_equal([g:a.snapshot, oldwin, oldtext], [State().snapshot.snapshot, win_getid(), getline(1, '$')])
    let g:defer = ''
    sleep 30m
    RevueLatest
    sleep 30m
    call assert_equal('viewed', Progress(1))
    call assert_equal('viewed', Progress(2))
    call writefile(['restart'], $REVUE_CAP_STORE . '/restart')
  endif
  call assert_equal([], filter(copy(g:calls), {_, request -> index(['file', 'refresh'], request.op) < 0}), 'no provider mutations')
  call revue#session#Close()
  " Closing during a verification cancels its unsaved intent; late reads are harmless.
  let fresh = deepcopy(g:a)
  let fresh.key = 'local/discovery-close'
  let g:id = revue#session#Open(fresh, function('DiscoveryHost'), 0)
  let g:defer = 'renamed'
  call SelectFile(2)
  RevueViewed
  sleep 30m
  let job = remove(g:pending, 0)
  call revue#session#Close()
  let afterclose = win_getid()
  call job.Done({'ok': 1, 'data': Content(job.request.snapshot, job.request.file)})
  call assert_equal({}, State())
  call assert_equal(afterclose, win_getid())
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
