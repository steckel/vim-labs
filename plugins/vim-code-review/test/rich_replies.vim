set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:body = join(['Use **strong _nested_ text**, `code()` and ~~old behavior~~.',
      \ '日本語 [the guide](https://example.test/a_(b) "Guide") and [reference][Guide].',
      \ '[local](../guide.md) and [unsafe](javascript:alert(1)).',
      \ '> > **Nested quote** with `literal`.',
      \ '> ```suggestion', '> replacement', '> ```',
      \ '[Guide]: https://example.test/reference',
      \ '```vim', '" [not a link](https://example.test/code)', '```',
      \ '`https://example.test/same` then https://example.test/same'], "\n")
let g:fixture.snapshot.threads[0].comments[2].body = g:body
let g:fixture.snapshot.threads[0].comments[2].author = 'a_[x]*<name>'
let g:fixture.snapshot.threads[0].comments[2].url = 'https://example.test/review#reply-2'
let g:fixture.snapshot.threads[0].comments[2].resolved_links = {'../guide.md': 'https://example.test/source/guide.md'}
let g:fixture.snapshot.threads[0].comments += [{'id': 'last', 'author': 'last', 'body': 'Third reply remains readable.', 'created': ''}]
let g:link_mode = 'ok'
function! RichHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  elseif a:request.op ==# 'rendered_links'
    let target = a:request.target
    let g:LinkDone = a:Done
    let g:link_data = {'message': target.message, 'message_kind': target.message_kind, 'thread': target.thread, 'version': target.expected_version, 'links': [{'label': 'Server guide', 'url': 'https://server.test/resolved'}]}
    if g:link_mode ==# 'bad' | let g:link_data.message = 'wrong' | endif
    if g:link_mode !=# 'delay' | call a:Done({'ok': 1, 'data': deepcopy(g:link_data)}) | endif
  else
    throw 'Rich fixture forbids writes'
  endif
endfunction
function! SelectRich() abort
  call revue#session#Threads('local-thread')
  call search('^Use \*\*strong', 'w')
  call revue#session#MessageFocus()
endfunction
try
  let semantic = revue#links#Semantic(g:body, g:fixture.snapshot.threads[0].comments[2].resolved_links)
  call assert_equal(['the guide', 'reference', 'local', 'unsafe', 'https://example.test/same'], map(copy(semantic), {_, x -> x.label}))
  call assert_equal('https://example.test/source/guide.md', semantic[2].url)
  call assert_equal('', semantic[3].url)
  call assert_false(empty(semantic[3].reason))
  let parsed = revue#markdown#Scan(g:body)
  call assert_true(len(filter(copy(parsed.spans), {_, x -> x.kind ==# 'Code'})) >= 3)
  call assert_true(len(filter(copy(parsed.spans), {_, x -> x.kind ==# 'Emphasis'})) >= 1)
  call assert_equal('bold and code()', revue#markdown#Inline('**bold** and `code()`', {}, 0, 1).text)
  call assert_equal('a_[x]', revue#markdown#Inline('a\_\[x\]', {}, 0, 1).text)
  call assert_equal('foo_bar_baz', revue#markdown#Inline('foo_bar_baz', {}).text)
  call assert_equal('\*literal\*', revue#markdown#Inline('\*literal\*', {}).text)
  call assert_equal([], revue#markdown#Inline('``a ` single tick``', {}).links)
  call assert_equal('[broken](https://x.test', revue#markdown#Inline('[broken](https://x.test', {}).text)
  let original = deepcopy(g:fixture.snapshot.threads[0])
  for width in [20, 40, 80, 120]
    let rows = revue#comments#Rows(original, width)
    for row in rows
      call assert_true(strdisplaywidth(row.text) <= width, 'row fits width ' . width)
      for span in get(row, 'spans', [])
        call assert_true(span.col > 0 && span.col + span.length - 1 <= strlen(row.text), 'span is within wrapped Unicode row')
      endfor
    endfor
    call assert_equal(original, g:fixture.snapshot.threads[0], 'rendering never modifies raw messages')
  endfor
  let g:id = revue#session#Open(g:fixture.snapshot, function('RichHost'), 0)
  let source = getbufline(revue#session#Inspect(g:id).head, 1, '$')
  call SelectRich()
  let selected = revue#discussion#Selected(revue#session#Inspect(g:id), line('.'))
  let bodyrow = selected.body_start
  call assert_true(!empty(filter(prop_list(bodyrow), {_, p -> p.type ==# 'RevueInlineCode'})))
  call assert_equal(g:body, join(getline(selected.body_start, selected.body_end), "\n"))
  ReviewCopyMessage
  call assert_equal(g:body, @")
  call feedkeys("3\<CR>2\<CR>", 't')
  ReviewBodyLinks
  call assert_equal('https://example.test/source/guide.md', @")
  call feedkeys("4\<CR>", 't')
  ReviewBodyLinks
  call assert_equal('https://example.test/source/guide.md', @", 'unsupported schemes do not act')
  let g:fixture.snapshot.capabilities = extend(get(g:fixture.snapshot, 'capabilities', {}), {'rendered_links': {'enabled': 1}, 'reply': {'enabled': 1}, 'conversation': {'enabled': 1}})
  ReviewRefresh
  call SelectRich()
  call feedkeys("1\<CR>2\<CR>", 't')
  ReviewBodyLinks
  call assert_equal('https://server.test/resolved', @")
  let g:link_mode = 'bad'
  ReviewBodyLinks
  call assert_equal('https://server.test/resolved', @", 'wrong backend identity is ignored')
  let g:link_mode = 'delay'
  ReviewBodyLinks
  ReviewNextMessage
  call g:LinkDone({'ok': 1, 'data': deepcopy(g:link_data)})
  call assert_equal('https://server.test/resolved', @", 'late link response cannot act on another message')
  call SelectRich()
  ReviewReply
  call setline(1, 'My existing response.')
  ReviewClose
  call SelectRich()
  ReviewQuoteAttributed
  call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
  let composed = join(getline(1, '$'), "\n")
  call assert_match('^My existing response.', composed)
  call assert_true(stridx(composed, '**a\_\[x\]\*\<name\>** wrote') >= 0, 'author Markdown is escaped')
  call assert_match('https://example.test/review#reply-2', composed)
  call assert_true(stridx(composed, '> > ```suggestion') >= 0, 'quoted suggestion remains in quote container')
  call assert_match('> Use \*\*strong', composed)
  ReviewPreview
  let preview = join(getline(1, '$'), "\n")
  call assert_match('Quoted suggestion', preview)
  call assert_notmatch('Suggested change', preview)
  let inline = []
  for row in range(1, line('$')) | call extend(inline, filter(prop_list(row), {_, p -> p.type ==# 'RevueInlineCode'})) | endfor
  call assert_true(!empty(inline))
  ReviewClose
  ReviewClose
  call SelectRich()
  let before = len(revue#session#Inspect(g:id).drafts)
  execute (bodyrow + 1) . ',' . (bodyrow + 1) . 'ReviewQuoteAttributed'
  call assert_equal(before, len(revue#session#Inspect(g:id).drafts))
  call assert_match('> 日本語', join(getline(1, '$'), "\n"))
  call assert_equal(source, getbufline(revue#session#Inspect(g:id).head, 1, '$'))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
