set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'comment': {'enabled': 1}, 'suggestion': {'enabled': 1, 'sides': ['head']}}
let g:writes = []
function! SuggestHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    call add(g:writes, deepcopy(a:request))
    if a:request.reconcile
      call a:Done({'ok': 1, 'data': {'id': 'receipt', 'recovered': 1}})
    else
      call a:Done({'ok': 0, 'unknown': 1, 'error': 'Fixture connection lost after acceptance'})
    endif
  endif
endfunction
function! SetBody(lines) abort
  call assert_equal('draft', b:revue_role)
  call setline(1, a:lines)
  if line('$') > len(a:lines) | call deletebufline(bufnr(), len(a:lines) + 1, '$') | endif
endfunction
try
  for lines in [[], ['  a', "\tb", '日本語'], ['```', '```suggestion', '````', '~~~'], ['']]
    let seeded = revue#suggestion#Seed(lines)
    call assert_equal({'error': '', 'lines': lines}, revue#suggestion#Parse(seeded))
  endfor
  call assert_false(empty(revue#suggestion#Parse("```suggestion\na").error))
  call assert_false(empty(revue#suggestion#Parse("```suggestion\na\n```\n```suggestion\nb\n```").error))
  call assert_false(empty(revue#suggestion#Parse("> ```suggestion\n> quoted\n> ```").error))
  call assert_false(empty(revue#suggestion#Parse("````text\n```suggestion\nnot real\n```\n````").error))
  let g:id = revue#session#Open(g:fixture.snapshot, function('SuggestHost'), 0)
  let state = revue#session#Inspect(g:id)
  if filereadable($REVUE_CAP_STORE . '/frozen')
    let frozen = json_decode(readfile($REVUE_CAP_STORE . '/frozen')[0])
    call assert_equal(frozen, state.drafts[0])
    let g:fixture.snapshot.capabilities.suggestion.enabled = 0
    RevueRefresh
    2,3RevueSuggest
    call assert_equal('draft', b:revue_role, 'existing frozen suggestion remains inspectable after permission loss')
    call assert_false(&modifiable)
    call assert_equal(split(frozen.body, "\n", 1), getline(1, '$'))
    RevueSend
    call assert_equal(1, len(g:writes))
    call assert_equal(1, g:writes[0].reconcile)
    call assert_equal(frozen.body, g:writes[0].draft.body)
    call assert_equal(frozen.id, g:writes[0].draft.id)
    call assert_equal([], revue#session#Inspect(g:id).drafts)
  else
    let before = deepcopy(g:fixture.content)
    let g:fixture.snapshot.capabilities.suggestion.enabled = 0
    RevueRefresh
    RevueSuggest
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    let g:fixture.snapshot.capabilities.suggestion.enabled = 1
    RevueRefresh
    call win_gotoid(state.basewin)
    call cursor(3, 1)
    RevueSuggest
    call assert_equal([], revue#session#Inspect(g:id).drafts, 'base-side suggestions unavailable on this backend')
    call win_gotoid(state.headwin)
    call revue#session#Suggest(0, 9, 10)
    call assert_equal([], revue#session#Inspect(g:id).drafts)
    let g:revue_mappings = {'suggest': '<LocalLeader>s'}
    call revue#maps#Apply('head')
    call assert_equal('<Plug>(revue-suggest)', maparg('<LocalLeader>s', 'x'))
    call setpos("'<", [0, 3, 1, 0])
    call setpos("'>", [0, 2, 1, 0])
    call revue#session#Suggest(1)
    call assert_equal(2, line('.'))
    let draft = revue#session#Inspect(g:id).drafts[0]
    call assert_equal(['comment', v:true, 'head', 2, 3, 'completion.vim'], [draft.kind, draft.suggestion, draft.side, draft.start, draft.end, draft.path])
    call assert_equal(before.head.lines[1:2], revue#suggestion#Parse(draft.body).lines)
    call assert_equal(before.head.lines, getbufline(state.head, 1, '$'), 'authoring never edits source')
    call SetBody(['Explanation outside the replacement.', '', '```suggestion', '  let items = sort(copy(a:items))', '  let use_fuzzy = strchars(a:query) >= 2', '```'])
    let edited = getline(1, '$')
    call revue#session#SaveDraft()
    let snapshot = deepcopy(g:fixture.snapshot)
    let snapshot.capabilities.batch = {'enabled': 1, 'mode': 'atomic', 'kinds': ['comment']}
    let item = deepcopy(revue#session#Inspect(g:id).drafts[0])
    call assert_equal('', revue#batch#Error(snapshot, [item]))
    let selected = {}
    let selected[item.id] = 1
    call assert_match('\[x\] suggestion', revue#batch#View([item], selected, 0).lines[0])
    let item.body = 'missing fenced replacement'
    call assert_match('exactly one suggestion', revue#batch#Error(snapshot, [item]))
    RevueClose
    2,3RevueSuggest
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts), 'same anchor reopens the existing draft')
    call assert_equal(edited, getline(1, '$'))
    let editor = win_getid()
    RevuePreview
    call assert_match('Suggestion preview', getline(1))
    call assert_match('let items = copy(a:items)', join(getline(1, '$'), "\n"))
    call assert_match('sort(copy(a:items))', join(getline(1, '$'), "\n"))
    RevueClose
    call assert_equal([editor, edited], [win_getid(), getline(1, '$')])
    call SetBody(['```suggestion', 'unfinished'])
    RevueSend
    call assert_equal([], g:writes, 'malformed suggestion is not published')
    RevuePreview
    call assert_match('Cannot submit: Close the suggestion fence', join(getline(1, '$'), "\n"))
    RevueClose
    call SetBody(['```suggestion', '```'])
    RevuePreview
    let additions = 0
    let deletions = 0
    for row in range(1, line('$'))
      let additions += len(filter(prop_list(row), {_, p -> p.type ==# 'RevueCardAdd'}))
      let deletions += len(filter(prop_list(row), {_, p -> p.type ==# 'RevueCardDelete'}))
    endfor
    call assert_equal(0, additions, 'empty replacement is a deletion')
    call assert_true(deletions >= 2)
    RevueClose
    call SetBody(edited)
    let g:fixture.snapshot.capabilities.suggestion.enabled = 0
    call revue#session#Refresh()
    RevueSend
    call assert_equal([], g:writes)
    call assert_equal(edited, getline(1, '$'))
    let g:fixture.snapshot.capabilities.suggestion.enabled = 1
    let original = deepcopy(g:fixture.snapshot)
    let g:fixture.snapshot.snapshot = 'new-comparison'
    let g:fixture.snapshot.head = 'new-head'
    call revue#session#Refresh()
    RevueSend
    call assert_equal([], g:writes, 'stale suggestions retain original anchors')
    let g:fixture.snapshot = original
    call revue#session#Refresh()
    RevueSend
    call assert_equal(1, len(g:writes))
    call assert_equal(join(edited, "\n"), g:writes[0].draft.body)
    call assert_equal(v:true, g:writes[0].draft.suggestion)
    call assert_false(&modifiable)
    call assert_equal(before, g:fixture.content)
    call writefile([json_encode(revue#session#Inspect(g:id).drafts[0])], $REVUE_CAP_STORE . '/frozen')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
