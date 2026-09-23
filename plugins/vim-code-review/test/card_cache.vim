set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let thread = deepcopy(fixture.snapshot.threads[0])
let context = {'lines': deepcopy(fixture.content.head.lines), 'inline_styles': 1, 'body_cache': {}}
function! CompareCard(thread, width, context) abort
  let plain = copy(a:context)
  call remove(plain, 'body_cache')
  let expected = revue#comments#Rows(a:thread, a:width, plain)
  let actual = revue#comments#Rows(a:thread, a:width, a:context)
  call assert_equal(expected, actual, 'cached body matches fresh text, colors and spans')
  return actual
endfunction
function! CardCacheHost(request, Done) abort
  call a:Done({'ok': 1, 'data': deepcopy(a:request.op ==# 'file' ? g:cache_fixture.content : g:cache_fixture.snapshot)})
endfunction
try
  call CompareCard(thread, 80, context)
  " Returned rows must not alias retained rows; outer-width changes must not
  " stretch the next cached render or shift its Markdown spans.
  let rows = CompareCard(thread, 80, context)
  let rows[4].text = 'caller mutation'
  let context.outer_width = 140
  call CompareCard(thread, 80, context)
  let context.outer_width = 90
  call CompareCard(thread, 80, context)
  call CompareCard(thread, 24, context)
  let thread.comments[0].body = "Changed **body** 界 é\n\n[x][r]\n\n[r]: https://example.test/first"
  call CompareCard(thread, 80, context)
  let context.references = {'r': 'https://example.test/second'}
  call CompareCard(thread, 80, context)
  let context.inline_styles = 0
  call CompareCard(thread, 80, context)
  let context.quoted = 1
  call CompareCard(thread, 80, context)
  let context.quoted = 0
  let context.lines[2] = 'replacement original source'
  call CompareCard(thread, 80, context)
  let thread.start = 2
  let thread.line = 4
  call CompareCard(thread, 80, context)
  let thread.outdated = 1
  call CompareCard(thread, 80, context)
  let thread.comments[0].author = 'Changed author'
  let thread.resolved = 1
  let thread.capabilities = {'reply': {'enabled': 0, 'reason': 'Permission changed'}}
  let context.reply_hint = ':CustomReply'
  let context.state_hint = ':CustomReopen'
  let context.author = 'Changed author'
  let context.unread = {revue#activity#Key(thread.id, thread.comments[0]): 1}
  let rows = CompareCard(thread, 80, context)
  call assert_match('Permission changed', join(map(copy(rows), {_, r -> r.text}), "\n"))
  " Entry budget does not truncate rendering, and removed bodies are evicted.
  let thread.comments = []
  for i in range(513)
    call add(thread.comments, {'id': string(i), 'body': 'Unique body ' . i, 'author': 'alex', 'created': ''})
  endfor
  let rows = CompareCard(thread, 80, context)
  call assert_equal(512, len(context.body_cache.items))
  call assert_match('Unique body 512', join(map(copy(rows), {_, r -> r.text}), "\n"))
  let thread.comments = [thread.comments[-1]]
  call CompareCard(thread, 80, context)
  call assert_equal(1, len(context.body_cache.items))
  " A body above the retained byte budget is still rendered in full.
  let thread.comments[0].body = repeat(repeat('x', 60) . "\n", 6500)
  let rows = revue#comments#Rows(thread, 80, context)
  call assert_true(len(rows) > 6500)
  call assert_equal({}, context.body_cache.items)
  let thread.comments = []
  call assert_equal([], revue#comments#Rows(thread, 80, context))
  call assert_equal({}, context.body_cache)
  " The reader also retains hundreds of small bodies, with exact relative
  " spans after a body changes or the messages are reordered.
  new
  let reader = bufnr()
  let thread.comments = []
  for i in range(250)
    call add(thread.comments, {'id': string(i), 'body': 'Body ' . i . ' **strong** and `code`', 'author': 'alex', 'created': ''})
  endfor
  let view = revue#discussion#Threads([thread], '# Long discussion')
  call setline(1, view.lines)
  call revue#markdown#View(reader, view)
  call assert_equal(250, len(b:revue_markdown_cache), 'small bodies beyond 128 stay cached')
  let original_key = sha256(thread.comments[-1].body)
  let thread.comments[-1].body = 'Changed **last message**'
  call reverse(thread.comments)
  let view = revue#discussion#Threads([thread], '# Long discussion')
  %delete _
  call setline(1, view.lines)
  call revue#markdown#View(reader, view)
  call assert_false(has_key(b:revue_markdown_cache, original_key))
  let cached_props = prop_list(1, {'end_lnum': line('$')})
  call prop_clear(1, line('$'))
  let b:revue_markdown_cache = {}
  call revue#markdown#View(reader, view)
  call assert_equal(cached_props, prop_list(1, {'end_lnum': line('$')}), 'cached reader equals a fresh parse after reorder/edit')
  call assert_true(len(b:revue_markdown_cache) <= 512)
  let cache_bytes = 0
  for saved in values(b:revue_markdown_cache) | let cache_bytes += saved.bytes | endfor
  call assert_true(cache_bytes <= 1048576)
  bwipeout!
  " Retention belongs to the displayed file, never the durable outbox. More
  " threads than the cache budget remain present in the discussion inventory.
  let g:cache_fixture = deepcopy(fixture)
  let g:cache_fixture.snapshot.threads = []
  for i in range(9)
    let entry = deepcopy(fixture.snapshot.threads[0])
    let entry.id = 'cache-thread-' . i
    let entry.comments = [deepcopy(entry.comments[0])]
    let entry.comments[0].id = 'cache-message-' . i
    call add(g:cache_fixture.snapshot.threads, entry)
  endfor
  let g:revue_auto_focus = 0
  let g:revue_draft_dir = tempname()
  let id = revue#session#Open(g:cache_fixture.snapshot, function('CardCacheHost'), 0)
  let state = revue#session#Inspect(id)
  call assert_equal(8, len(state.card_body_caches))
  call assert_equal(9, len(state.snapshot.threads))
  ReviewRefresh
  call assert_notmatch('card_body_caches', join(readfile(revue#session#Inspect(id).draftpath), "\n"))
  let g:cache_fixture.snapshot.threads = []
  ReviewRefresh
  call assert_equal({}, revue#session#Inspect(id).card_body_caches)
  call revue#session#Close()
  call delete(g:revue_draft_dir, 'rf')
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
if !empty(v:errors) | call writefile(v:errors, '/dev/stderr') | cquit | endif
qa!
