set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = tempname()
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.threads[0].comments[0].body = join([
      \ '[guide](https://example.test/a_(b)?x=1&y=2#here)',
      \ '> Compare <https://example.test/日本語!>.',
      \ '`https://example.test/code` and https://example.test/a_(b)?x=1&y=2#here',
      \ '[ref]: https://example.test/reference "A reference"'], "\n")
let g:opened = []
function! LinkHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    throw 'Link fixture prohibits publication'
  endif
endfunction
function! ChangeLinkTarget(timer) abort
  ReviewNextMessage
  call feedkeys("1\<CR>", 't')
endfunction
function! ChangeLinkBody(timer) abort
  let g:fixture.snapshot.threads[0].comments[0].body = 'Replacement https://example.test/updated'
  ReviewRefresh
  call feedkeys("2\<CR>", 't')
endfunction
" Intercept browser dispatch: no real browser or network in this test.
let g:stub = tempname()
call mkdir(g:stub . '/autoload', 'p')
call writefile(['function! netrw#BrowseX(url, remote) abort',
      \ 'call add(g:opened, [a:url, a:remote])', 'endfunction'], g:stub . '/autoload/netrw.vim')
execute 'source ' . fnameescape(g:stub . '/autoload/netrw.vim')
try
  let urls = revue#links#Body(g:fixture.snapshot.threads[0].comments[0].body)
  call assert_equal([
        \ {'url': 'https://example.test/a_(b)?x=1&y=2#here', 'line': 1},
        \ {'url': 'https://example.test/日本語!', 'line': 2},
        \ {'url': 'https://example.test/code', 'line': 3},
        \ {'url': 'https://example.test/reference', 'line': 4}], urls)
  call assert_equal(['https://e.test/a', 'https://e.test/b', 'https://e.test/c', 'HTTP://e.test/D'],
        \ map(revue#links#Body('(https://e.test/a). https://e.test/b, [https://e.test/c]; HTTP://e.test/D!'), {_, u -> u.url}))
  call assert_equal(['https://e.test/end?', 'https://e.test/end.'],
        \ map(revue#links#Body('[exact](https://e.test/end?) <https://e.test/end.>'), {_, u -> u.url}))
  call assert_equal([], revue#links#Body('file:///tmp/a javascript:alert(1) #42 ../blob/main/a mailto:x@y.test https://'))
  for bad in ['file:///tmp/a', 'javascript:alert(1)', "https://a\nother", 'https://', 'https://?x=1', 'https://a/`command`', 'https://a/"x"']
    call assert_false(revue#links#IsWeb(bad), bad)
  endfor
  let g:id = revue#session#Open(g:fixture.snapshot, function('LinkHost'), 0)
  call cursor(3, 1)
  ReviewThread
  call cursor(1, 1)
  ReviewNextMessage
  let initial = [win_getid(), bufnr(), winsaveview()]
  let target = revue#discussion#Selected(revue#session#Inspect(g:id), line('.'))
  call assert_equal(2, exists(':ReviewBodyLinks'))
  call assert_match('BodyLinks', maparg('<Plug>(revue-body-links)', 'n'))
  let @" = 'keep'
  call feedkeys("0\<CR>", 't')
  ReviewBodyURLs
  call assert_equal('keep', @")
  call feedkeys("1\<CR>0\<CR>", 't')
  ReviewBodyURLs
  call assert_equal('keep', @")
  call feedkeys("2\<CR>2\<CR>", 't')
  ReviewBodyURLs
  call assert_equal(urls[1].url, @")
  call assert_equal([], g:opened)
  call feedkeys("6\<CR>4\<CR>2\<CR>", 't')
  ReviewActions
  call assert_equal(urls[3].url, @", 'message action routes to the body chooser')
  call feedkeys("1\<CR>1\<CR>", 't')
  ReviewBodyURLs
  call assert_equal([[urls[0].url, 0]], g:opened)
  call assert_equal(initial, [win_getid(), bufnr(), winsaveview()], 'chooser preserves discussion view')
  call assert_equal(target.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  " Selection changes while the menu is up must not open the old target.
  call feedkeys("1\<CR>", 't')
  call timer_start(20, function('ChangeLinkTarget'))
  ReviewBodyURLs
  call assert_equal(1, len(g:opened))
  call assert_notequal(target.comment, revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  ReviewPreviousMessage
  let @" = 'retained through refresh'
  call feedkeys("1\<CR>", 't')
  call timer_start(20, function('ChangeLinkBody'))
  ReviewBodyURLs
  call assert_equal('retained through refresh', @", 'updated message cannot copy stale URL')
  call assert_match('Replacement', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).message.body)
  ReviewHelp
  let @" = 'still keep'
  call revue#session#BodyLinks()
  call assert_equal('still keep', @")
  call assert_equal(1, len(g:opened), 'Help cannot act on stale message targets')
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call delete(g:revue_draft_dir, 'rf')
call delete(g:stub, 'rf')
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
