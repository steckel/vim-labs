" Local Viewed acknowledgements are scoped to file identity and compared content.
function! revue#progress#Identity(file) abort
  return sha256(json_encode([a:file.path, a:file.old_path]))
endfunction

function! s:Meta(file) abort
  return sha256(json_encode([a:file.path, a:file.old_path, a:file.status, get(a:file, 'patch', ''), get(a:file, 'mode', '')]))
endfunction

function! s:Stamp(file, content) abort
  let parts = [s:Meta(a:file)]
  for side in ['base', 'head']
    let content = get(a:content, side, {})
    let kind = get(content, 'kind', 'unavailable')
    if kind ==# 'absent'
      call add(parts, ['absent'])
    elseif kind ==# 'text'
      call add(parts, [kind, get(content, 'hash', ''), get(content, 'lines', []), get(content, 'final_newline', 'unknown'), get(content, 'fileformat', 'unknown'), get(content, 'mode', '')])
    elseif kind ==# 'binary' && !empty(get(content, 'hash', ''))
      call add(parts, [kind, content.hash, get(content, 'mode', '')])
    else
      return ''
    endif
  endfor
  return sha256(json_encode(parts))
endfunction

function! revue#progress#Observe(session, snapshot, file, content) abort
  let id = a:snapshot.snapshot
  if !has_key(a:session.progress.observed, id) | let a:session.progress.observed[id] = {} | endif
  let stamp = s:Stamp(a:file, a:content)
  if empty(stamp) && !empty(revue#progress#Stamp(a:session, a:snapshot, a:file)) | return | endif
  let a:session.progress.observed[id][a:file.id] = {'meta': s:Meta(a:file), 'stamp': stamp}
endfunction

function! revue#progress#Stamp(session, snapshot, file) abort
  let entry = get(get(a:session.progress.observed, a:snapshot.snapshot, {}), a:file.id, {})
  return get(entry, 'meta', '') ==# s:Meta(a:file) ? get(entry, 'stamp', '') : ''
endfunction

function! revue#progress#State(session, snapshot, file) abort
  let identity = revue#progress#Identity(a:file)
  let stamp = revue#progress#Stamp(a:session, a:snapshot, a:file)
  if !empty(stamp) | return has_key(get(a:session.progress.marks, identity, {}), stamp) ? 'viewed' : 'unviewed' | endif
  if has_key(get(a:session, 'progress_queue', {}), json_encode([a:snapshot.snapshot, a:file.id])) | return 'checking' | endif
  let entry = get(get(a:session.progress.observed, a:snapshot.snapshot, {}), a:file.id, {})
  if get(entry, 'meta', '') ==# s:Meta(a:file) | return 'unavailable' | endif
  return empty(get(a:session.progress.marks, identity, {})) ? 'unviewed' : 'checking'
endfunction

function! revue#progress#Set(session, snapshot, file, viewed) abort
  let stamp = revue#progress#Stamp(a:session, a:snapshot, a:file)
  if empty(stamp) | return 0 | endif
  let identity = revue#progress#Identity(a:file)
  if !has_key(a:session.progress.marks, identity) | let a:session.progress.marks[identity] = {} | endif
  if a:viewed
    let a:session.progress.marks[identity][stamp] = 1
  elseif has_key(a:session.progress.marks[identity], stamp)
    call remove(a:session.progress.marks[identity], stamp)
  endif
  return 1
endfunction
