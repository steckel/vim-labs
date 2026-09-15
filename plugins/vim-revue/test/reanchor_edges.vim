set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'reanchor_draft': {'enabled': 1, 'kinds': ['comment', 'file_comment']},
      \ 'comment': {'enabled': 1, 'anchors': {'scope': 'changed_file'}}, 'file_comment': {'enabled': 1},
      \ 'suggestion': {'enabled': 1, 'sides': ['head']}}
let second = deepcopy(g:fixture.snapshot.files[0])
let second.id = 'file-two'
let second.path = 'another.vim'
let second.old_path = 'another.vim'
call add(g:fixture.snapshot.files, second)
function! MoveEdgeHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    throw 'No mutations in draft movement'
  endif
endfunction
try
  let g:id = revue#session#Open(g:fixture.snapshot, function('MoveEdgeHost'), 0)
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3,1)
  RevueSuggest
  let original = deepcopy(revue#session#Inspect(g:id).drafts[0])
  let editor = bufnr()
  RevueReanchorDraft
  RevueReanchorHere
  call assert_false(has_key(revue#session#Inspect(g:id).reanchor, 'proposal'), 'same anchor is not a move')
  call win_gotoid(revue#session#Inspect(g:id).basewin)
  call cursor(1,1)
  RevueReanchorHere
  call assert_false(has_key(revue#session#Inspect(g:id).reanchor, 'proposal'), 'suggestions cannot move to an unsupported side')
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  1,2RevueReanchorHere
  call assert_match('Suggestion replacement is unchanged', join(getline(1, '$'), "\n"))
  call assert_equal(original.body, revue#session#Inspect(g:id).reanchor.proposal.body)
  call setbufline(editor, 1, 'Edited while choosing a location')
  RevueAcceptReanchor
  call assert_equal(original.id, revue#session#Inspect(g:id).drafts[0].id)
  call assert_match('Edited while choosing', revue#session#Inspect(g:id).drafts[0].body)
  RevueCancelReanchor
  call assert_equal(editor, bufnr())
  call assert_equal('Edited while choosing a location', getline(1))
  RevueClose
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  RevueFileComment
  call setline(1, 'This concerns the whole file.')
  RevueReanchorDraft
  RevueNextFile
  RevueReanchorHere
  call assert_equal('reanchor', b:revue_view)
  call assert_match('whole file', join(getline(1, '$'), "\n"))
  let before = deepcopy(revue#session#Inspect(g:id).drafts)
  let g:fixture.snapshot.capabilities.reanchor_draft.enabled = 0
  RevueRefresh
  RevueAcceptReanchor
  call assert_equal(before, revue#session#Inspect(g:id).drafts)
  let g:fixture.snapshot.capabilities.reanchor_draft.enabled = 1
  RevueRefresh
  RevueClose
  RevueReanchorHere
  RevueAcceptReanchor
  let moved = revue#session#Inspect(g:id).drafts[-1]
  call assert_equal('another.vim', moved.path)
  call assert_false(has_key(moved, 'side'))
  call assert_false(has_key(moved, 'start'))
  call assert_equal('This concerns the whole file.', moved.body)
  let state = {'original': original, 'proposal': original, 'old_source': {}, 'new_source': g:fixture.content.head}
  call assert_match('Original source is not loaded', join(map(revue#reanchor#View(state, ''), {_, row -> row.text}), "\n"))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
