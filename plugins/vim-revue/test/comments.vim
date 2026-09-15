set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = tempname()
let g:mutations = 0
let g:fixture = {'version': 1, 'key': 'fixture/cards', 'display_id': '#1', 'title': 'Card fixture', 'author': 'author', 'state': 'open', 'body': '', 'url': '', 'reviewers': [], 'base': 'base', 'head': 'head', 'snapshot': 'fixture', 'conversation': [], 'review_actions': [], 'files': [{'id': 'f', 'path': 'example.py', 'old_path': 'example.py', 'status': 'modified', 'patch': "@@ -1,3 +1,3 @@\n one\n-old\n+new\n three"}], 'threads': [{'id': 't1', 'path': 'example.py', 'side': 'head', 'line': 2, 'start': 2, 'outdated': 0, 'comments': [{'author': 'Reviewer', 'created': '2026-09-13', 'body': "Please explain this argument. Unicode: café 日本語.\n\nA_very_long_identifier_that_should_wrap_without_changing_coordinates."}]}]}
function! Host(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': {'base': {'kind': 'text', 'lines': ['one', 'old', 'three']}, 'head': {'kind': 'text', 'lines': ['one', 'new', 'three']}}})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': g:fixture})
  else
    let g:mutations += 1
    throw 'Test must not post'
  endif
endfunction
try
  " Wrapping must retain grapheme bytes at the ASCII/Unicode boundary.
  " Vim regex classes can overlook attached combining marks, so check the
  " actual expected chunks, including a mark immediately after the cut.
  for width in [1, 3, 7, 76]
    let accented = repeat('a', width) . nr2char(0x301)
    call assert_equal([accented, repeat('b', width)],
          \ revue#comments#Wrap(accented . repeat('b', width), width))
    call assert_equal([repeat('a', width), 'b' . nr2char(0x301) . repeat('c', width - 1), 'c'],
          \ revue#comments#Wrap(repeat('a', width) . 'b' . nr2char(0x301) . repeat('c', width), width))
  endfor
  call assert_equal(['one', 'two', 'three'], revue#comments#Wrap('one two three', 7))
  call assert_equal(['ab界', 'cd界', 'ef'], revue#comments#Wrap('ab界cd界ef', 4))
  call assert_equal(['a    bc'], revue#comments#Wrap("a\tbc", 8))
  let g:id = revue#session#Open(g:fixture, function('Host'), 0)
  let s = revue#session#Inspect(g:id)
  call win_gotoid(s.headwin)
  call cursor(2, 1)
  let props = prop_list(2)
  call assert_true(len(props) > 5)
  call assert_equal(['one', 'new', 'three'], getline(1, '$'))
  call assert_equal(0, &modifiable)
  for width in [12, 24, 48, 90]
    for row in revue#comments#Rows(g:fixture.threads[0], width)
      call assert_equal(width, strdisplaywidth(row.text))
    endfor
  endfor
  let rich_fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
  let thread = rich_fixture.snapshot.threads[0]
  let context = {'lines': rich_fixture.content.head.lines, 'author': rich_fixture.snapshot.author}
  let original = deepcopy(thread)
  for width in [12, 24, 48, 90]
    let rows = revue#comments#Rows(thread, width, context)
    for row in rows | call assert_equal(width, strdisplaywidth(row.text), row.text) | endfor
    call assert_true(len(filter(copy(rows), {_, r -> r.type ==# 'RevueCardQuote'})) > 0)
    call assert_true(len(filter(copy(rows), {_, r -> r.type ==# 'RevueCardCode'})) > 0)
    call assert_true(len(filter(copy(rows), {_, r -> r.type ==# 'RevueCardDelete'})) > 0)
    call assert_true(len(filter(copy(rows), {_, r -> r.type ==# 'RevueCardAdd'})) > 0)
    call assert_notmatch('```', join(map(copy(rows), {_, r -> r.text}), "\n"))
  endfor
  let text = join(map(copy(rows), {_, r -> r.text}), "\n")
  call assert_match('alex \[Author\]', text)
  call assert_match('let use_fuzzy = !empty(a:query)', text)
  call assert_match('let use_fuzzy = strchars(a:query) >= 2', text)
  let headers = filter(copy(rows), {_, r -> r.type ==# 'RevueCardHeader'})
  call assert_equal(3, len(headers))
  for author in ['morgan', 'alex', 'sam']
    call assert_match(author, join(map(copy(headers), {_, r -> r.text}), "\n"))
  endfor
  call assert_notmatch('▾\|▸\|Enter collapse', text)
  call assert_equal(original, thread)
  " Missing or outdated snapshots must never invent the removed code.
  let thread.outdated = 1
  call assert_equal([], filter(revue#comments#Rows(thread, 90, context), {_, r -> r.type ==# 'RevueCardDelete'}))
  let thread.outdated = 0
  call assert_equal([], filter(revue#comments#Rows(thread, 90), {_, r -> r.type ==# 'RevueCardDelete'}))
  " A shorter fence inside code cannot end a longer fence.
  let thread.comments = [{'author': 'code', 'body': "````vim\n```\n  echo 'literal'\n````"}]
  let rows = revue#comments#Rows(thread, 60)
  call assert_match('```', join(map(filter(copy(rows), {_, r -> r.type ==# 'RevueCardCode'}), {_, r -> r.text}), "\n"))
  " Enter keeps normal code navigation and never hides discussion rows.
  call assert_equal({}, maparg('<CR>', 'n', 0, 1))
  call feedkeys("\<CR>", 'xt')
  call assert_equal(len(props), len(prop_list(2)))
  call assert_equal(3, line('.'))
  call cursor(2, 1)
  call feedkeys('r', 'xt')
  call assert_equal('t1', revue#session#Inspect(g:id).drafts[-1].thread)
  close
  call win_gotoid(s.headwin)
  call feedkeys('Vjc', 'xt')
  let draft = revue#session#Inspect(g:id).drafts[-1]
  call assert_equal(['head', 2, 3], [draft.side, draft.start, draft.end])
  close
  call win_gotoid(s.headwin)
  call cursor(2, 1)
  call revue#session#Refresh()
  " Native window closes can change wrapping. Count complete frames instead
  " of assuming the number of virtual body rows stays constant at every width.
  call assert_equal(3, len(filter(prop_list(2), {_, p -> p.type ==# 'RevueCardBorder'})))
  call assert_equal(['one', 'new', 'three'], getline(1, '$'))
  " Independent discussions at one anchor remain visible and selectable.
  let another = deepcopy(g:fixture.threads[0])
  let another.id = 't2'
  call add(g:fixture.threads, another)
  call revue#session#Refresh()
  call assert_equal(6, len(filter(prop_list(2), {_, p -> p.type ==# 'RevueCardBorder'})))
  let drafts_before = len(revue#session#Inspect(g:id).drafts)
  call feedkeys('r', 'xt')
  call assert_equal(drafts_before, len(revue#session#Inspect(g:id).drafts))
  call assert_match('# Threads:', getline(1))
  call feedkeys('r', 'xt')
  call assert_equal('t2', revue#session#Inspect(g:id).drafts[-1].thread)
  close
  call revue#session#Threads()
  call feedkeys("\<CR>", 'xt')
  call assert_equal(s.headwin, win_getid())
  call assert_equal(2, line('.'))
  call win_gotoid(s.treewin)
  call cursor(7, 1)
  call feedkeys("\<CR>", 'xt')
  call assert_equal(s.headwin, win_getid())
  call assert_equal(6, len(filter(prop_list(2), {_, p -> p.type ==# 'RevueCardBorder'})))
  call revue#session#Help()
  call assert_notmatch('collapse', join(getline(1, '$'), "\n"))
  call assert_equal(0, g:mutations)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call delete(g:revue_draft_dir, 'rf')
if !empty(v:errors) | call writefile(v:errors, '/dev/stderr') | endif
if !empty(v:errors) | cquit | endif
qa!
