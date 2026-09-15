function! reviewhub#bridge#Request(connection, number, request, Done) abort
  let req = copy(a:request)
  let req.connection = a:connection
  let req.number = a:number
  if req.op ==# 'refresh'
    let req.op = 'open'
    let req.incremental = get(req, 'incremental', v:false)
  endif
  return reviewhub#transport#Request(req, a:Done)
endfunction

function! reviewhub#bridge#Open(connection, snapshot, index) abort
  try
    return revue#review#OpenReview(a:snapshot,
          \ function('reviewhub#bridge#Request', [a:connection, a:snapshot.number]), a:index)
  catch /^Vim\%((\a\+)\)\=:E117/
    echoerr 'ReviewHub: install vim-revue to view code. PR browsing is available with :Reviews.'
    return ''
  endtry
endfunction
