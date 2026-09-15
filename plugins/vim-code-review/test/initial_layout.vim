set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
function! InitialProperties(state) abort
  return prop_list(1,{'bufnr':a:state.head,'end_lnum':len(getbufline(a:state.head,1,'$'))})
endfunction
function! DeliverInitial(Done) abort
  call a:Done(g:mode ==# 'error' ? {'ok':0,'error':'Source unavailable'} : {'ok':1,'data':deepcopy(g:fixture.content)})
  let g:delivered_props = InitialProperties(revue#session#Inspect(g:request_id))
endfunction
function! InitialHost(request, Done) abort
  if a:request.op !=# 'file' | throw 'Initial layout fixture cannot write' | endif
  let g:request_id = b:revue_session
  let state = revue#session#Inspect(g:request_id)
  let g:requested_focus = get(state,'focus_win',0)
  let g:requested_width = winwidth(0)
  let g:saved_layout = deepcopy(get(state,'focus_layout',{}))
  if g:mode ==# 'delayed'
    let g:InitialDone = a:Done
  else
    call DeliverInitial(a:Done)
  endif
endfunction
try
  let user_window = win_getid()
  for settings in [json_decode($REVUE_INITIAL_SETTINGS)]
    let [&columns,&lines,g:revue_auto_focus] = settings
    let narrow = settings[2] && (settings[0]<120 || settings[1]<32)
    for g:mode in ['sync','delayed','error']
      let id = revue#session#Open(g:fixture.snapshot,function('InitialHost'),0)
      let state = revue#session#Inspect(id)
      call assert_equal(narrow ? state.headwin : 0,g:requested_focus,'Focus must be final before file delivery')
      call assert_equal(g:requested_width,winwidth(0),'Opening must not resize source after delivery')
      if g:mode ==# 'delayed'
        call assert_equal(['Loading completion.vim…'],getbufline(state.head,1,'$'))
        call win_gotoid(user_window)
        call DeliverInitial(g:InitialDone)
        call assert_equal(user_window,win_getid(),'Delayed completion must not steal focus')
        call win_gotoid(state.headwin)
      endif
      call assert_equal(g:delivered_props,InitialProperties(state),'Final-width cards must not be replaced after delivery')
      if g:mode ==# 'error'
        call assert_equal(['Source unavailable'],getbufline(state.head,1,'$'))
      else
        call assert_equal(g:fixture.content.head.lines,getbufline(state.head,1,'$'))
        call assert_true(len(g:delivered_props)>10)
      endif
      RevueRestoreLayout
      if narrow
        for window in g:saved_layout.windows
          let info = getwininfo(window.id)[0]
          call assert_equal([window.width,window.height],[info.width,info.height],'Original split geometry is retained')
        endfor
      endif
      call revue#session#Close()
    endfor
  endfor
catch
  call add(v:errors,v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors,$REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
