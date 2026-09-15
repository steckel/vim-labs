" File targets have no source coordinates. Missing subject_type means legacy line.
function! revue#anchor#IsFile(thread) abort
  return get(a:thread, 'subject_type', 'line') ==# 'file'
endfunction

function! revue#anchor#InDiff(file, draft) abort
  let allowed = revue#session#Commentable(get(a:file, 'patch', ''), get(a:draft, 'side', ''))
  if a:draft.end - a:draft.start + 1 > len(allowed) | return 0 | endif
  for row in range(a:draft.start, a:draft.end)
    if !has_key(allowed, string(row)) | return 0 | endif
  endfor
  return 1
endfunction

" Creation and revalidation share the backend's immutable-file anchor policy.
" Optional source is required for creation; the backend rechecks its own bytes.
function! revue#anchor#Error(snapshot, draft, ...) abort
  if get(a:draft, 'kind', '') !=# 'comment' | return '' | endif
  let side = get(a:draft, 'side', '')
  let start = get(a:draft, 'start', 0)
  let end = get(a:draft, 'end', 0)
  if index(['base', 'head'], side) < 0 || type(start) != v:t_number || type(end) != v:t_number || start < 1 || end < start
    return 'Select a valid source side and line range.'
  endif
  let files = filter(copy(get(a:snapshot, 'files', [])), {_, f -> f.path ==# get(a:draft, 'path', '')})
  if empty(files) || get(a:draft, 'old_path', '') !=# files[0].old_path
    return 'This source target is not in the loaded changed-file comparison. The original draft is retained.'
  endif
  if a:0
    if get(a:1, 'kind', '') !=# 'text' | return 'Source text is unavailable on this side. Use :RevueFileComment for whole-file feedback.' | endif
    if end > len(a:1.lines) | return 'Select a line range within the immutable source.' | endif
  endif
  let policy = get(get(get(a:snapshot, 'capabilities', {}), 'comment', {}), 'anchors', {})
  if index(get(policy, 'sides', ['base', 'head']), side) < 0
    return 'This backend does not support line comments on the ' . side . ' side.'
  endif
  let scope = get(policy, 'scope', 'diff')
  if scope ==# 'changed_file' | return '' | endif
  if scope !=# 'diff' | return 'This backend supplied an unsupported line-anchor policy.' | endif
  if revue#anchor#InDiff(files[0], a:draft) | return '' | endif
  let reason = get(policy, 'reason', '')
  return empty(reason) ? 'This backend supports line comments only within the returned diff hunks. Use :RevueFileComment or open the review in your browser.' : reason
endfunction

function! revue#anchor#Label(thread) abort
  return revue#anchor#IsFile(a:thread) ? 'File discussion' : a:thread.side . ':' . a:thread.start . '-' . a:thread.line
endfunction

function! revue#anchor#FileFirst(threads) abort
  return filter(copy(a:threads), {_, t -> revue#anchor#IsFile(t)}) + filter(copy(a:threads), {_, t -> !revue#anchor#IsFile(t)})
endfunction
