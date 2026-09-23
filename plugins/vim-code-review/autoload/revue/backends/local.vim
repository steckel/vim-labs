" Bundled local review backend. SQLite and Git capture live in its companion;
" the shared UI and other backends never load that store.
let s:program = expand('<sfile>:p:h:h:h:h') . '/python/revue_local.py'
let s:jobs = {}
let s:serial = 0

function! revue#backends#local#Request(review, request, Done) abort
  call s:BoundRequest(s:Store(), a:review, a:request, a:Done)
endfunction

function! s:Store() abort
  return fnamemodify(expand(get(g:, 'revue_local_dir', '~/.vim/revue-local')), ':p')
endfunction

function! s:BoundRequest(store, review, request, Done) abort
  let request = deepcopy(a:request)
  let request.review = a:review
  call s:Call(request, a:Done, a:store)
endfunction

function! s:Call(request, Done, store) abort
  let s:serial += 1
  let id = string(s:serial)
  let state = {'Done': a:Done, 'lines': [], 'write': index(['mutate', 'assign', 'cancel_assignment', 'prepare_run', 'dispatch_run', 'abandon_run'], a:request.op) >= 0}
  let s:jobs[id] = state
  let argv = [get(g:, 'revue_python', 'python3'), s:program,
        \ '--store', a:store]
  let state.job = job_start(argv, {'in_mode': 'nl', 'out_mode': 'nl',
        \ 'out_cb': function('s:Output', [id]), 'err_io': 'null',
        \ 'close_cb': function('s:Closed', [id])})
  if job_status(state.job) ==# 'fail'
    call remove(s:jobs, id)
    call a:Done({'ok': 0, 'error': 'Cannot start local backend; check g:revue_python.', 'unknown': 0})
    return
  endif
  call ch_sendraw(job_getchannel(state.job), json_encode(a:request) . "\n")
  call ch_close_in(job_getchannel(state.job))
endfunction

function! s:Output(id, channel, message) abort
  if has_key(s:jobs, a:id) | call add(s:jobs[a:id].lines, a:message) | endif
endfunction

function! s:Closed(id, channel) abort
  if !has_key(s:jobs, a:id) | return | endif
  let state = remove(s:jobs, a:id)
  try
    let result = json_decode(join(state.lines, "\n"))
    if type(result) != v:t_dict || !has_key(result, 'ok') | throw 'Invalid response' | endif
  catch
    let result = {'ok': 0, 'error': 'Local backend stopped without a valid response.', 'unknown': state.write}
  endtry
  call state.Done(result)
endfunction

function! s:Notice(result) abort
  echohl ErrorMsg
  echom 'revue: ' . a:result.error
  echohl None
endfunction

function! s:Opened(store, result) abort
  if !a:result.ok | call s:Notice(a:result) | return | endif
  let data = a:result.data
  let backend = {'id': 'local', 'connection': data.connection, 'review': data.review,
        \ 'snapshot': data.snapshot, 'Request': function('s:BoundRequest', [a:store, data.review])}
  call revue#backend#Open(backend, empty(data.snapshot.files) ? -1 : 0)
endfunction

function! revue#backends#local#Open(base, untracked) abort
  " Saving a buffer is an explicit user action; capture reads disk only.
  if !empty(filter(getbufinfo(), {_, b -> b.changed && empty(getbufvar(b.bufnr, '&buftype'))}))
    echom 'revue: Capturing saved files only; unsaved buffers are excluded.'
  endif
  let store = s:Store()
  call s:Call({'op': 'create', 'cwd': getcwd(), 'base': empty(a:base) ? get(g:, 'revue_default_base', 'main') : a:base,
        \ 'untracked': a:untracked ? v:true : v:false}, function('s:Opened', [store]), store)
endfunction

function! revue#backends#local#Resume(review, ...) abort
  let store = a:0 ? a:1 : s:Store()
  call s:Call({'op': 'open', 'review': a:review}, function('s:Opened', [store]), store)
endfunction

function! revue#backends#local#List() abort
  let store = s:Store()
  call s:Call({'op': 'list'}, function('s:Listed', [store]), store)
endfunction

function! s:Listed(store, result) abort
  if !a:result.ok | call s:Notice(a:result) | return | endif
  if empty(a:result.data) | echom 'revue: No saved local reviews. Use :ReviewLocal.' | return | endif
  new
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted nomodeline nowrap
  let b:revue_local_reviews = a:result.data
  let b:revue_local_store = a:store
  call setline(1, ['Local reviews · Enter resume', ''] + map(copy(a:result.data), {_, r -> r.created . '  ' . r.title . '  ' . r.workspace}))
  setlocal nomodifiable nomodified
  nnoremap <silent><buffer> <CR> <Cmd>call revue#backends#local#Select()<CR>
  nnoremap <silent><buffer> q <Cmd>close<CR>
endfunction

function! revue#backends#local#Select() abort
  let index = line('.') - 3
  if index < 0 || index >= len(b:revue_local_reviews) | return | endif
  let review = b:revue_local_reviews[index].id
  let store = b:revue_local_store
  close
  call revue#backends#local#Resume(review, store)
endfunction
