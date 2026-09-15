" Backend bindings are session-scoped. No global provider or storage singleton.
function! revue#backend#Open(backend, index) abort
  for field in ['id', 'connection', 'review', 'snapshot', 'Request']
    if !has_key(a:backend, field) | throw 'Missing backend field: ' . field | endif
  endfor
  if type(a:backend.Request) != v:t_func | throw 'Backend Request must be a Funcref' | endif
  let snapshot = deepcopy(a:backend.snapshot)
  let snapshot.backend = {'id': a:backend.id, 'connection': a:backend.connection, 'review': a:backend.review}
  " Existing version-1 providers retain their keys and saved drafts. New
  " backends use a qualified key, including connection and review identity.
  let snapshot.key = get(a:backend, 'legacy_key', json_encode([a:backend.id, a:backend.connection, a:backend.review]))
  return revue#session#Open(snapshot, function('s:Request', [deepcopy(a:backend), snapshot.key]), a:index)
endfunction

function! s:Request(backend, key, request, Done) abort
  call a:backend.Request(a:request, function('s:Result', [a:backend, a:key, a:request.op, a:Done]))
endfunction

function! s:Result(backend, key, op, Done, result) abort
  let result = deepcopy(a:result)
  if result.ok && a:op ==# 'feedback_lookup'
    if type(get(result, 'data', 0)) != v:t_dict || get(result.data, 'key', '') !=# a:backend.snapshot.key
      let result = {'ok': 0, 'error': 'Discussion lookup belongs to another backend review.'}
    else
      let result.data.key = a:key
    endif
  endif
  if result.ok && index(['refresh', 'comparison', 'comparison_range'], a:op) >= 0
    let result.data.key = a:key
    let result.data.backend = {'id': a:backend.id, 'connection': a:backend.connection, 'review': a:backend.review}
  endif
  if result.ok && a:op ==# 'comparisons' && has_key(get(result, 'data', {}), 'latest')
    let result.data.latest.key = a:key
    let result.data.latest.backend = {'id': a:backend.id, 'connection': a:backend.connection, 'review': a:backend.review}
  endif
  if result.ok && a:op ==# 'thread_context' && type(get(get(result, 'data', {}), 'snapshot', 0)) == v:t_dict
    let result.data.snapshot.key = a:key
    let result.data.snapshot.backend = {'id': a:backend.id, 'connection': a:backend.connection, 'review': a:backend.review}
  endif
  call a:Done(result)
endfunction
