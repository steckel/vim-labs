set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:first = deepcopy(g:fixture.snapshot)
let g:first.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'capture': {'enabled': 1, 'body_required': 0},
      \ 'comparisons': {'enabled': 1, 'refresh_on_open': 1}}
let g:first.capture_context = {'workspace': '/fixture/workspace', 'base': g:first.base, 'untracked': v:false, 'options_known': v:true}
let g:second = deepcopy(g:first)
let g:second.snapshot = 'second-local-capture'
let g:second.head = 'second-local-head'
let g:second.threads[0].outdated = v:true
let g:second.threads[0].original_context = ['3 │   let use_fuzzy = !empty(a:query)']
let g:second.threads[0].original_comparison = revue#comparisons#Reference(g:first)
let g:latest = filereadable($REVUE_CAP_STORE . '/accepted') ? deepcopy(g:second) : deepcopy(g:first)
let g:writes = []
let g:history_reads = 0
let g:extra_reply = 0
let g:missing_original = 0
function! CaptureHost(request, Done) abort
  if a:request.op ==# 'file'
    let content = deepcopy(g:fixture.content)
    if a:request.snapshot.snapshot ==# g:second.snapshot | let content.head.lines[2] = '  let use_fuzzy = strchars(a:query) >= 2' | endif
    call a:Done({'ok': 1, 'data': content})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:latest)})
  elseif a:request.op ==# 'comparison'
    let g:history_reads += 1
    let snapshot = deepcopy(a:request.reference.snapshot ==# g:first.snapshot ? g:first : g:second)
    if g:missing_original | let snapshot.files = [] | endif
    if g:extra_reply
      call add(snapshot.threads[0].comments, {'id': 'later-reply', 'kind': 'reply', 'author': 'sam', 'created': '', 'body': 'A later reply on the same original source'})
    endif
    call a:Done({'ok': 1, 'data': snapshot})
  elseif a:request.op ==# 'comparisons'
    call a:Done({'ok': 1, 'data': {'items': [revue#comparisons#Reference(g:first), revue#comparisons#Reference(g:second)], 'latest': deepcopy(g:latest), 'complete': 1}})
  else
    call add(g:writes, deepcopy(a:request))
    let receipt = {'id': a:request.draft.id, 'previous_snapshot': a:request.draft.snapshot, 'snapshot': g:second.snapshot, 'changed': v:true}
    let g:latest = deepcopy(g:second)
    if !a:request.reconcile
      call writefile([json_encode(a:request.draft)], $REVUE_CAP_STORE . '/accepted')
      " A truncated success response must freeze the capture instead of guessing.
      call a:Done({'ok': 1, 'data': {'id': a:request.draft.id}})
    else
      call a:Done({'ok': 1, 'data': receipt})
    endif
  endif
endfunction
try
  let g:id = revue#session#Open(g:latest, function('CaptureHost'), 0)
  let state = revue#session#Inspect(g:id)
  if filereadable($REVUE_CAP_STORE . '/accepted')
    let g:accepted = json_decode(readfile($REVUE_CAP_STORE . '/accepted')[0])
    let g:latest.capabilities.capture.enabled = 0
    RevueRefresh
    RevueCapture
    call assert_equal('draft', b:revue_role)
    call assert_false(&modifiable)
    call assert_match('delivery still unknown', join(getline(1, '$'), "\n"))
    RevueCheckReceipt
    call assert_equal(1, len(g:writes))
    call assert_equal(1, g:writes[0].reconcile)
    call assert_equal(g:accepted, g:writes[0].draft)
    let state = revue#session#Inspect(g:id)
    call assert_equal(1, len(state.drafts), 'the old comment draft survives capture recovery')
    call assert_equal(g:first.snapshot, state.drafts[0].snapshot)
    call assert_equal(g:second.snapshot, state.last_receipt.snapshot)
    call assert_equal(g:second.snapshot, state.activity[-1].receipt.snapshot)
    RevueThreads
    call assert_match('Original source:', join(getline(1, '$'), "\n"))
    let g:missing_original = 1
    RevueThreadComparison
    call assert_equal(g:second.snapshot, revue#session#Inspect(g:id).snapshot.snapshot, 'missing original file does not redirect to another file')
    let g:missing_original = 0
    RevueThreadComparison
    call assert_equal(g:first.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call assert_equal(3, line('.'), 'original comparison command targets the original source line')
    call assert_equal(g:fixture.content.head.lines, getbufline(state.head, 1, '$'))
    let g:extra_reply = 1
    let reads_before = g:history_reads
    call revue#session#OpenComparison(g:first.snapshot)
    call assert_equal(reads_before + 1, g:history_reads, 'cached original source still refreshes shared conversation')
    call assert_equal('later-reply', revue#session#Inspect(g:id).snapshot.threads[0].comments[-1].id)
    RevueDiscussions Before capture
    call search('## Local draft', 'W')
    RevueOpenDiscussion
    call assert_equal('Before capture: retain this draft', getline(1))
    RevueSend
    call assert_equal(1, len(g:writes), 'old draft cannot be retargeted to the newer capture')
  else
    call assert_match('does not support', revue#capabilities#Error({}, {'kind': 'capture'}, 0))
    call cursor(3, 1)
    RevueComment
    call setline(1, 'Before capture: retain this draft')
    RevueClose
    RevueCapture tracked
    call assert_false(&modifiable)
    call assert_match('Exclude untracked', join(getline(1, '$'), "\n"))
    let fields = deepcopy(revue#session#Inspect(g:id).drafts[-1])
    call assert_equal('', fields.body)
    call assert_equal(v:false, fields.untracked)
    RevuePreview
    call assert_match('Capture preview', getline(1))
    call assert_notmatch('Draft preview', join(getline(1, '$'), "\n"))
    RevueClose
    call assert_false(&modifiable)
    RevueClose
    RevueCapture!
    call assert_equal(2, len(revue#session#Inspect(g:id).drafts))
    call assert_equal(v:false, revue#session#Inspect(g:id).drafts[-1].untracked, 'existing pending capture retains its settings')
    RevueSend
    call assert_equal(1, len(g:writes))
    call assert_equal('', g:writes[0].draft.body, 'preview text is not serialized as feedback')
    call assert_false(&modifiable)
    let state = revue#session#Inspect(g:id)
    call assert_equal(g:first.snapshot, state.snapshot.snapshot, 'capture never switches the source automatically')
    call assert_equal('unknown', state.drafts[-1].state)
    call assert_equal(g:fixture.content.head.lines, getbufline(state.head, 1, '$'))
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
