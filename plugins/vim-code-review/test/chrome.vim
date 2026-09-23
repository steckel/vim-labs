set nocompatible nomore laststatus=2
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = tempname()
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:fixture.snapshot.capabilities = {'reply': {'enabled': 1}, 'save_pending': {'enabled': 1, 'kinds': ['reply']}}
let g:fixture.snapshot.pending_reviews = {'available': v:true, 'actor': 'fixture:alex', 'items': [{'id': '7', 'head': g:fixture.snapshot.head, 'actor': 'fixture:alex', 'body': '', 'comments': [], 'version': 'v1'}]}
let g:fixture.snapshot.threads[0].capabilities = {'pending_reply': {'enabled': 1}}
function! ChromeHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  else
    throw 'Chrome fixture prohibits writes'
  endif
endfunction
function! RenderBar(window) abort
  let g:statusline_winid = a:window
  try
    return eval(strpart(revue#layout#Get(a:window, '&statusline'), 2))
  finally
    unlet g:statusline_winid
  endtry
endfunction
try
  for width in [80, 120]
    let &columns = width
    let &lines = width == 80 ? 24 : 40
    let id = revue#session#Open(g:fixture.snapshot, function('ChromeHost'), 0)
    let source = revue#session#Inspect(id).headwin
    call cursor(3, 1)
    ReviewThread
    call cursor(1, 1)
    ReviewNextMessage
    ReviewNextMessage
    let message = revue#discussion#Selected(revue#session#Inspect(id), line('.')).comment
    ReviewReplyPending
    call setline(1, ['A concise reply for the selected discussion.', '', 'Keep this exact text.'])
    let editor = win_getid()
    call revue#session#SaveDraft()
    if get(revue#session#Inspect(id), 'focus_win', 0) != editor | call revue#session#Focus() | endif
    call assert_match('Save privately', RenderBar(editor))
    if win_id2tabwin(source)[0] == tabpagenr()
      call assert_equal('%#RevueQuietBar# ', RenderBar(source))
    else
      call assert_match('head', RenderBar(source), 'Hidden source keeps its own context')
      call assert_equal(1, winnr('$'), 'Narrow composer occupies its whole tab')
    endif
    call assert_true(len(filter(prop_list(1), {_, p -> p.type ==# 'RevueDraftContext'})) <= 6, 'compact context leaves room for the reply')
    let body = getline(1, '$')
    ReviewPreview
    call assert_equal('# Reply preview', getline(1))
    let header = search('Draft preview', 'nW')
    call assert_true(header > 0 && header <= 9, 'body starts near the top')
    let details = search('^## Full review context', 'nW')
    call assert_true(details > search('Keep this exact text.', 'nW'))
    call assert_match('Actor: fixture:alex', join(getline(details, '$'), "\n"))
    call assert_match('only this draft', join(getline(1, header), "\n"))
    ReviewClose
    call assert_equal(editor, win_getid())
    call assert_equal(body, getline(1, '$'))
    ReviewClose
    call assert_equal(message, revue#discussion#Selected(revue#session#Inspect(id), line('.')).comment)
    ReviewClose
    ReviewRestoreLayout
    call assert_match('head', RenderBar(source))
    call assert_equal(g:fixture.content.head.lines, getbufline(winbufnr(source), 1, '$'))
    call revue#session#Close()
  endfor
  " Long identity remains readable text, and permission loss stays above body.
  let path = repeat('long-directory/', 8) . "quoted'%{1+1}.vim"
  let g:fixture.snapshot.files[0].path = path
  let g:fixture.snapshot.files[0].old_path = path
  let g:fixture.snapshot.threads[0].path = path
  let id = revue#session#Open(g:fixture.snapshot, function('ChromeHost'), 0)
  let source = revue#session#Inspect(id).headwin
  call cursor(3, 1)
  ReviewReplyPending
  call setline(1, 'Long-path reply remains editable.')
  let g:fixture.snapshot.capabilities.save_pending = {'enabled': 0, 'reason': 'Private permission changed'}
  ReviewRefresh
  ReviewPreview
  let header = search('Draft preview', 'nW')
  call assert_match(escape(path, '\.*$^~[]'), join(getline(1, header), "\n"))
  call assert_true(search('Unavailable: Private permission changed', 'nW') < header)
  ReviewClose
  call assert_equal('Long-path reply remains editable.', getline(1))
  ReviewClose
  ReviewRestoreLayout
  call assert_match("quoted''%%{1+1}", getwinvar(source, '&statusline'))
  call assert_match('%%{1+1}', RenderBar(source))
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call delete(g:revue_draft_dir, 'rf')
if !empty(v:errors) | call writefile(v:errors, '/dev/stderr') | cquit | endif
qa!
