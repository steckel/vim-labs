set nocompatible nomore
execute 'set runtimepath^=' . fnameescape($REVUE_ROOT)
execute 'set runtimepath^=' . fnameescape($REVIEWHUB_ROOT)
runtime plugin/revue.vim
runtime plugin/reviewhub.vim
let g:reviewhub_command = ['python3', $REVIEWHUB_ROOT . '/test/fixture_provider.py']
let g:revue_draft_dir = $REVUE_TEST_STORE . '/drafts'

function! Await(expression) abort
  let start = reltime()
  while !eval(a:expression)
    if reltimefloat(reltime(start)) > 8
      throw 'Timed out: ' . a:expression
    endif
    sleep 10m
  endwhile
endfunction

function! SetMessage(text) abort
  call setline(1, a:text)
  call revue#session#SaveDraft()
endfunction

try
  Reviews team/project
  call Await('len(reviewhub#Inspect().items) == 1')
  call assert_match('Improve example', join(getline(1, '$'), "\n"))
  call cursor(6, 1)
  normal o
  call Await('has_key(reviewhub#Inspect().expanded, "42")')
  call assert_match('Conversation (1)', join(getline(1, '$'), "\n"))
  call assert_match('src/example.py', join(getline(1, '$'), "\n"))
  let g:tree = reviewhub#Inspect()
  call cursor(9, 1)
  normal o
  let g:sid = t:revue_session
  call Await('!empty(revue#session#Inspect(g:sid).loaded)')
  let g:session = revue#session#Inspect(g:sid)
  " Narrow terminals focus a source pane; restoring exposes balanced diff panes.
  if revue#layout#Narrow()
    call assert_equal(g:session.headwin, get(g:session, 'focus_win', 0))
    call assert_true(winwidth(win_id2win(g:session.headwin)) > &columns - 10)
  endif
  call revue#session#RestoreLayout()
  call assert_true(abs(winwidth(win_id2win(g:session.headwin)) - winwidth(win_id2win(g:session.basewin))) <= 1)
  call assert_equal(['one', 'new', 'three', 'four'], getbufline(g:session.head, 1, '$'))
  call assert_equal(['one', 'old', 'three', 'four'], getbufline(g:session.base, 1, '$'))
  call assert_equal(0, getbufvar(g:session.head, '&modifiable'))
  call assert_equal(0, getbufvar(g:session.head, '&modeline'))
  call assert_true(len(prop_list(2, {'bufnr': g:session.head})) > 0)
  call win_gotoid(g:session.headwin)
  call cursor(2, 1)
  normal t
  call assert_match('Please explain', join(getline(1, '$'), "\n"))
  call assert_match('Old implementation', join(getline(1, '$'), "\n"))
  call cursor(5, 1)
  normal r
  call SetMessage('Reply from integration test')
  call assert_equal('reply', revue#session#Inspect(g:sid).drafts[0].kind)
  call assert_equal('101', revue#session#Inspect(g:sid).drafts[0].thread)
  call feedkeys("\<C-S>", 'xt')
  call Await('empty(revue#session#Inspect(g:sid).drafts)')
  call Await('!revue#session#Inspect(g:sid).busy')

  " Actual visual mapping, first selection, multiline source coordinates.
  call win_gotoid(g:session.headwin)
  call cursor(2, 1)
  call feedkeys('Vjc', 'xt')
  call SetMessage(['Two-line comment', 'Second paragraph'])
  let draft = revue#session#Inspect(g:sid).drafts[0]
  call assert_equal([2, 3, 'head'], [draft.start, draft.end, draft.side])
  call assert_equal('src/example.py', draft.path)
  call writefile(['failed'], $REVUE_TEST_STORE . '/fail')
  call revue#session#Send()
  call Await('revue#session#Inspect(g:sid).drafts[0].state ==# "failed"')
  call assert_equal("Two-line comment\nSecond paragraph", revue#session#Inspect(g:sid).drafts[0].body)
  call revue#session#Send()
  call Await('empty(revue#session#Inspect(g:sid).drafts)')
  call Await('!revue#session#Inspect(g:sid).busy')

  " Base-side anchor and unknown outcome are retained and reconciled.
  call win_gotoid(g:session.basewin)
  call cursor(2, 1)
  normal c
  call SetMessage('Base-side comment')
  call assert_equal('base', revue#session#Inspect(g:sid).drafts[0].side)
  call writefile(['unknown'], $REVUE_TEST_STORE . '/fail')
  call revue#session#Send()
  call Await('revue#session#Inspect(g:sid).drafts[0].state ==# "unknown"')
  call revue#session#Send()
  call Await('empty(revue#session#Inspect(g:sid).drafts)')
  call Await('!revue#session#Inspect(g:sid).busy')

  " Review decisions come from the provider, including non-GitHub action IDs.
  call win_gotoid(g:session.headwin)
  call feedkeys("1\<CR>", 't')
  call revue#session#Review()
  call SetMessage('Acknowledged in the fixture provider')
  call assert_equal('acknowledge', revue#session#Inspect(g:sid).drafts[0].event)
  call revue#session#Send()
  call Await('empty(revue#session#Inspect(g:sid).drafts)')
  call Await('!revue#session#Inspect(g:sid).busy')

  call win_gotoid(g:session.headwin)
  normal C
  call assert_match('Conversation message', join(getline(1, '$'), "\n"))
  normal c
  call SetMessage('Persist this conversation draft')
  call assert_equal('conversation', revue#session#Inspect(g:sid).drafts[0].kind)
  call revue#session#Close()
  call win_gotoid(g:tree.win)
  call cursor(9, 1)
  normal o
  let g:sid = t:revue_session
  call Await('!empty(revue#session#Inspect(g:sid).loaded)')
  let g:session = revue#session#Inspect(g:sid)
  call assert_equal('Persist this conversation draft', g:session.drafts[0].body)

  " Deleted and hostile filenames, no working-tree buffer edits.
  call revue#session#Next(1)
  call Await('!empty(revue#session#Inspect(g:sid).loaded)')
  call assert_equal('absent', revue#session#Inspect(g:sid).loaded.head.kind)
  call revue#session#Next(1)
  call Await('!empty(revue#session#Inspect(g:sid).loaded)')
  call assert_equal(['safe'], getbufline(g:session.head, 1, '$'))
  call assert_false(exists('g:injected'))

  " Process-backed refresh exposes an explicit new comparison without moving A.
  call writefile(['new revision'], $REVUE_TEST_STORE . '/revision-b')
  call revue#session#Refresh()
  call Await('!revue#session#Inspect(g:sid).busy')
  call assert_equal('a:b', revue#session#Inspect(g:sid).snapshot.snapshot)
  call assert_equal('a:d', revue#session#Inspect(g:sid).latest_comparison)
  call revue#session#Latest()
  call Await('!empty(revue#session#Inspect(g:sid).loaded)')
  call revue#session#Next(-2)
  call Await('!empty(revue#session#Inspect(g:sid).loaded)')
  call assert_equal('new revision', getbufline(g:session.head, 2)[0])
  call revue#session#PreviousComparison()
  call revue#session#Next(-2)
  call Await('!empty(revue#session#Inspect(g:sid).loaded)')
  call assert_equal('new', getbufline(g:session.head, 2)[0])
  call assert_equal('Persist this conversation draft', revue#session#Inspect(g:sid).drafts[0].body)
  call delete($REVUE_TEST_STORE . '/revision-b')

  " Reordering tabs must not close unrelated work.
  tabnew
  file unrelated-work
  let unrelated = bufnr()
  tabmove 0
  call win_gotoid(g:session.treewin)
  call revue#session#Close()
  call assert_true(bufwinid(unrelated) >= 0 || index(tabpagebuflist(1), unrelated) >= 0)
  call writefile(v:errors, $REVUE_TEST_STORE . '/errors')
catch
  call writefile([v:exception, v:throwpoint] + v:errors, $REVUE_TEST_STORE . '/errors')
endtry
call writefile(split(execute('messages'), "\n"), $REVUE_TEST_STORE . '/messages')
qa!
