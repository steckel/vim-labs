set nocompatible nomore columns=80 lines=24
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_reading_layout = 'tab'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:reads = 0
function! ResizeHost(request, Done) abort
  if a:request.op ==# 'file'
    let g:reads += 1
    call a:Done({'ok':1,'data':deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok':1,'data':deepcopy(g:fixture.snapshot)})
  else
    throw 'Fixture cannot write'
  endif
endfunction
function! CardProperties(state) abort
  return prop_list(1, {'bufnr':a:state.head,'end_lnum':len(g:fixture.content.head.lines)})
endfunction
try
  let id = revue#session#Open(g:fixture.snapshot,function('ResizeHost'),0)
  let source = revue#session#Inspect(id)
  call win_gotoid(source.headwin)
  call cursor(3,2)
  let source_view = winsaveview()
  let source_width = winwidth(0)
  let source_props = CardProperties(source)
  let generation = source.generation
  call assert_true(len(source_props)>10)
  RevueThread
  let reader = win_getid()
  call assert_equal(source_props,CardProperties(source),'Entering a tab must not repaint hidden source cards')
  call assert_match('local-reply-2',string(revue#session#Inspect(id).messagemap))
  RevueClose
  call assert_equal(source.headwin,win_getid())
  call assert_equal(source_width,winwidth(0))
  call assert_equal(source_view.lnum,line('.'))
  call assert_equal(source_view.col,col('.')-1)
  call assert_equal(generation,revue#session#Inspect(id).generation,'Returning to loaded source must not select/reload it')
  call assert_equal(source_props,CardProperties(source),'Final source size is unchanged; retain the complete cards')
  call assert_equal(0,revue#session#Inspect(id).defer_card_resize)

  " Native tab/window return must reflow the now-visible, unfocused panes.
  RevueThread
  let reader = win_getid()
  call win_gotoid(source.headwin)
  call assert_notequal(source_width,winwidth(0))
  let visible = revue#session#Inspect(id)
  let info = getwininfo(source.headwin)[0]
  call assert_equal(max([12,info.width-info.textoff-2]),visible.cardpanewidths[1])
  call assert_notequal(source_props,CardProperties(source))
  call win_gotoid(reader)
  " Refreshing actual message data still updates hidden source annotations.
  let g:fixture.snapshot.threads[0].comments[2].body = 'Changed while the source tab is hidden: λ界'
  RevueRefresh
  call assert_equal(reader,win_getid())
  call assert_match('Changed while the source tab is hidden',join(getline(1,'$'),"\n"))
  let current = revue#session#Inspect(id)
  let cache = current.card_body_caches[g:fixture.snapshot.files[0].id . ':' . g:fixture.snapshot.threads[0].id]
  call assert_true(has_key(cache.items,sha256(g:fixture.snapshot.threads[0].comments[2].body)))
  RevueClose
  call assert_equal(source.headwin,win_getid())
  call assert_equal(g:fixture.content.head.lines,getline(1,'$'))
  call assert_equal(0,revue#session#Inspect(id).defer_card_resize)
  call assert_equal(1,g:reads)
  call revue#session#Close()
catch
  call add(v:errors,v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors,$REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
