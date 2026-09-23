set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = tempname()
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.submit_label = 'Save'
let g:fixture.snapshot.threads[0].comments[0].author_role = 'Contributor'
let g:fixture.snapshot.threads[0].comments[0].updated = '2026-09-14T10:00:00Z'
let g:fixture.snapshot.threads[0].comments[1].edited = 1
let g:fixture.snapshot.threads[0].comments[1].publication = 'local'
let g:reads = []
function! MessageHost(request, Done) abort
  call add(g:reads, a:request.op)
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    throw 'Message fixture prohibits publication'
  endif
endfunction
function! FocusMatches() abort
  return filter(getmatches(), {_, m -> m.group ==# 'RevueMessageFocus'})
endfunction
try
  let thread = deepcopy(g:fixture.snapshot.threads[0])
  let body = join(['# Rationale', '', 'Use `stable_order()` and [the guide](https://example.test/a_(b)).', '',
        \ '> An earlier example:', '> ```vim', '>   let 日本語 = 1', '> ```', '>',
        \ '> > Nested quote', '> > ```text', '> > preserve indentation', '> > ```', '',
        \ '> ```suggestion', '>   a quoted proposal', '> ```', '',
        \ '- [x] First task', '  - Nested bullet with enough words to wrap across several lines in a narrow card',
        \ '1. Preserve ordering', '   2. Preserve nested numbering', '',
        \ '<details>Unsupported HTML stays visible</details>', '| column | value |', '',
        \ '````vim', '```', '  echo "literal fence"', '````'], "\n")
  let thread.comments = [{'id': 'rich', 'author': 'helper', 'author_type': 'bot', 'author_role': 'Member',
        \ 'created': '2026-09-13T10:00:00Z', 'updated': '2026-09-14T10:00:00Z', 'publication': 'pending', 'body': body}]
  let original = deepcopy(thread)
  for width in [12, 16, 24, 48, 90]
    let rows = revue#comments#Rows(thread, width, {'lines': g:fixture.content.head.lines})
    for row in rows
      call assert_equal(width, strdisplaywidth(row.text), 'width=' . width . ': ' . row.text)
      call assert_notmatch('\n', row.text)
    endfor
  endfor
  let text = join(map(copy(rows), {_, r -> r.text}), "\n")
  call assert_equal(original, thread, 'rendering cannot rewrite backend Markdown')
  call assert_match('Member · Bot', text)
  call assert_match('Updated Sep 14, 2026', text)
  call assert_match('Pending review', text)
  call assert_notmatch('Edited', text, 'updated timestamp alone does not establish an edit')
  call assert_match('Quoted suggestion', text)
  call assert_equal([], filter(copy(rows), {_, r -> index(['RevueCardAdd', 'RevueCardDelete'], r.type) >= 0}), 'quoted suggestions are quotations, not this anchor replacement')
  let code = join(map(filter(copy(rows), {_, r -> r.type ==# 'RevueCardCode'}), {_, r -> r.text}), "\n")
  call assert_match('▎.*let 日本語 = 1', code)
  call assert_match('▎ ▎.*preserve indentation', code)
  call assert_match('```', code, 'short fence inside long fence is literal')
  call assert_match('• \[x\] First task', text)
  call assert_match('  • Nested bullet', text)
  call assert_match('   2. Preserve nested numbering', text)
  call assert_match('`stable_order()`', text, 'inline code remains visibly delimited')
  call assert_match('guide ↗', text, 'link label is readable; raw discussion retains the URL')
  call assert_match('<details>Unsupported HTML stays visible</details>', text)
  call assert_match('| column | value |', text)
  call assert_equal(1, len(filter(copy(rows), {_, r -> r.type ==# 'RevueCardHeading'})))
  let long = deepcopy(thread)
  let long.comments[0].author = repeat('長い名前', 12)
  let long.comments[0].author_role = "Custom\nrole"
  for row in revue#comments#Rows(long, 24)
    call assert_equal(24, strdisplaywidth(row.text), row.text)
    call assert_notmatch('\n', row.text)
  endfor
  let plain = {'author': 'same', 'body': '', 'created': '', 'edited': 1, 'publication': 'local'}
  call assert_equal('same [Author] · Edited · Saved locally', revue#message#Header(plain, 'same'))
  let g:id = revue#session#Open(g:fixture.snapshot, function('MessageHost'), 0)
  call cursor(3, 1)
  ReviewThread
  call cursor(1, 1)
  ReviewNextMessage
  let state = revue#session#Inspect(g:id)
  call assert_match('morgan \[Contributor\]', getline('.'))
  call assert_match('Updated', getline('.'))
  call assert_equal([[line('.')]], [FocusMatches()[0].pos1])
  ReviewNextMessage
  call assert_match('alex \[Author\]', getline('.'))
  call assert_match('Edited · Saved locally', getline('.'))
  let message = revue#discussion#Selected(revue#session#Inspect(g:id), line('.'))
  call cursor(message.body_start, 1)
  call revue#session#MessageFocus()
  call assert_equal([message.start], FocusMatches()[0].pos1, 'body focus identifies its author header')
  ReviewCopyMessage z
  call assert_equal(message.message.body, @z, 'metadata never contaminates raw-body copy')
  ReviewQuote
  call assert_match('^> > Could we keep prefix', getline(1))
  call assert_notmatch('Saved locally\|\[Author\]', join(getline(1, '$'), "\n"))
  let editor = win_getid()
  let drafttext = getline(1, '$')
  ReviewPreview
  call assert_match('Reply preview', getline(1))
  ReviewClose
  call assert_equal([editor, drafttext], [win_getid(), getline(1, '$')])
  ReviewClose
  call assert_equal(message.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  call assert_equal(1, len(FocusMatches()))
  call insert(g:fixture.snapshot.threads[0].comments, {'id': 'new', 'author': 'other', 'body': 'Inserted message', 'created': ''}, 0)
  ReviewRefresh
  let selected = revue#discussion#Selected(revue#session#Inspect(g:id), line('.'))
  call assert_equal(message.comment, selected.comment)
  call assert_equal([selected.start], FocusMatches()[0].pos1)
  ReviewHelp
  call assert_equal([], FocusMatches(), 'Help has no selected-message decoration')
  ReviewClose
  call assert_equal(1, len(FocusMatches()))
  ReviewClose
  call assert_equal([], FocusMatches(), 'source has no message header match')
  call cursor(3, 1)
  ReviewComment
  call setline(1, ['```suggestion', 'replacement', '```'])
  let comment_id = b:revue_draft
  ReviewClose
  let g:fixture.snapshot.snapshot = 'message-new-comparison'
  let g:fixture.snapshot.head = 'new-head'
  let g:fixture.content.head.lines[2] = '__NEW_CODE__'
  ReviewRefresh
  ReviewLatest
  let state = revue#session#Inspect(g:id)
  call win_gotoid(state.treewin)
  for [row, target] in items(state.rows)
    if get(target, 'id', '') ==# comment_id
      call cursor(str2nr(row), 1)
      ReviewOpenFile
      break
    endif
  endfor
  ReviewPreview
  call assert_match('Older comparison', join(getline(1, '$'), "\n"))
  call assert_match('let use_fuzzy = !empty(a:query)', join(getline(1, '$'), "\n"))
  call assert_notmatch('__NEW_CODE__', join(getline(1, '$'), "\n"), 'preview uses the cached original source')
  let removed = 0
  for row in range(1, line('$'))
    let removed += len(filter(prop_list(row), {_, p -> p.type ==# 'RevueCardDelete'}))
  endfor
  call assert_true(removed > 0, 'historical suggestion keeps its original before/after')
  call assert_equal([], filter(copy(g:reads), {_, op -> index(['file', 'refresh'], op) < 0}))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call delete(g:revue_draft_dir, 'rf')
if !empty(v:errors) | call writefile(v:errors, '/dev/stderr') | cquit | endif
qa!
