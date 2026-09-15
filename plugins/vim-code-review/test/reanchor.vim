set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
set columns=120 lines=40
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:a = deepcopy(g:fixture.snapshot)
let g:a.capabilities = {'reanchor_draft': {'enabled': 1, 'kinds': ['comment', 'file_comment']},
      \ 'comment': {'enabled': 1, 'anchors': {'scope': 'changed_file'}}, 'file_comment': {'enabled': 1},
      \ 'suggestion': {'enabled': 1, 'sides': ['head']}}
let g:b = deepcopy(g:a)
let g:b.snapshot = 'comparison-b'
let g:b.head = 'head-b'
let g:b.base_tip = 'base-tip-b'
let g:b.files[0].path = 'renamed.vim'
let g:b.files[0].status = 'renamed'
let g:latest = deepcopy(g:a)
let g:body = "Please keep this exact text.\n\tUnicode 界\n> Quote stays"
function! ReanchorHost(request, Done) abort
  if a:request.op ==# 'file'
    let data = deepcopy(g:fixture.content)
    for side in ['base', 'head'] | let data[side].lines[0] = a:request.snapshot.snapshot . ' ' . side | endfor
    call a:Done({'ok': 1, 'data': data})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:latest)})
  else
    throw 'Moving a local draft must never call a mutation'
  endif
endfunction
function! PickTarget() abort
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  1,2RevueReanchorHere
  call assert_equal('reanchor', b:revue_view)
endfunction
try
  if filereadable($REVUE_CAP_STORE . '/accepted') | let g:latest = deepcopy(g:b) | endif
  let g:id = revue#session#Open(g:latest, function('ReanchorHost'), 0)
  if filereadable($REVUE_CAP_STORE . '/accepted')
    let saved = json_decode(readfile($REVUE_CAP_STORE . '/accepted')[0])
    let draft = revue#session#Inspect(g:id).drafts[0]
    call assert_equal(saved, draft)
    call assert_equal(g:body, draft.body)
    call assert_equal(g:a.snapshot, draft.reanchored_from.snapshot)
    call assert_equal('renamed.vim', draft.path)
    RevueActivity
    call search('## Pending', 'w')
    RevueOpenOperation
    call assert_equal(split(g:body, "\n", 1), getline(1, '$'))
    call assert_equal(g:b.snapshot, draft.snapshot)
    " A move selection is ephemeral; restarting cannot implicitly accept it.
    RevueReanchorDraft
    call cursor(3, 1)
    RevueReanchorHere
    call assert_equal(draft, revue#session#Inspect(g:id).drafts[0])
  else
    call win_gotoid(revue#session#Inspect(g:id).headwin)
    call cursor(3, 1)
    RevueComment
    call setline(1, split(g:body, "\n", 1))
    call revue#session#SaveDraft()
    let old = deepcopy(revue#session#Inspect(g:id).drafts[0])
    let g:latest = deepcopy(g:b)
    RevueRefresh
    let editor = bufnr()
    RevueReanchorDraft
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call PickTarget()
    let text = join(getline(1, '$'), "\n")
    call assert_match('From · completion.vim', text)
    call assert_match('To · renamed.vim', text)
    call assert_match('head-b', text)
    call assert_equal(old, revue#session#Inspect(g:id).drafts[0])
    call assert_false(&modifiable)
    RevueHelp
    RevueClose
    call assert_equal('reanchor', b:revue_view)
    RevueHelp
    RevueCancelReanchor
    call assert_equal(editor, bufnr())
    call assert_equal(old, revue#session#Inspect(g:id).drafts[0])
    RevueReanchorDraft
    call PickTarget()
    " A refreshed review invalidates acceptance even if its source ID is unchanged.
    RevueRefresh
    RevueAcceptReanchor
    call assert_equal(old, revue#session#Inspect(g:id).drafts[0])
    RevueClose
    call PickTarget()
    " Another writer prevents any in-memory or durable half-move.
    let path = revue#session#Inspect(g:id).draftpath
    call mkdir(path . '.lock')
    RevueAcceptReanchor
    call assert_equal(old, revue#session#Inspect(g:id).drafts[0])
    call assert_equal(old, json_decode(join(readfile(path), "\n")).drafts[0])
    call delete(path . '.lock', 'd')
    RevueAcceptReanchor
    let draft = deepcopy(revue#session#Inspect(g:id).drafts[0])
    call assert_notequal(old.id, draft.id)
    call assert_equal('renamed.vim', draft.path)
    call assert_equal([1, 2], [draft.start, draft.end])
    call assert_equal(g:body, draft.body)
    call assert_equal(old.id, draft.reanchored_from.id)
    call assert_equal('draft', draft.state)
    call assert_equal(draft.id, b:revue_draft)
    call assert_equal(split(g:body, "\n", 1), getline(1, '$'))
    RevueClose
    call assert_equal('renamed.vim', b:revue_file)
    call writefile([json_encode(draft)], $REVUE_CAP_STORE . '/accepted')
    for fields in [{'state': 'unknown'}, {'state': 'submitting'}, {'pending_mode': 'add'}, {'kind': 'reply'}, {'kind': 'edit'}, {'kind': 'batch'}]
      call assert_false(empty(revue#reanchor#Error(g:b, extend(deepcopy(draft), fields))))
    endfor
    let denied = deepcopy(g:b)
    let denied.capabilities.reanchor_draft.enabled = 0
    call assert_false(empty(revue#reanchor#Error(denied, draft)))
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
