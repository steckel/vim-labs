" Backend-declared application intent; presentation never chooses a destination.
function! revue#apply_suggestion#Error(snapshot, target) abort
  let rule = get(get(a:snapshot, 'capabilities', {}), 'apply_suggestion', {})
  if !get(rule, 'enabled', 0) | return get(rule, 'reason', 'This backend does not offer suggestion application. Use the message’s service link when available.') | endif
  if get(rule, 'destination', '') !=# 'workspace' || empty(get(rule, 'workspace', ''))
    return 'This application destination is not supported by this version of Revue.'
  endif
  let thread = get(filter(copy(a:snapshot.threads), {_, t -> t.id ==# get(a:target, 'thread', '')}), 0, {})
  if empty(thread) || get(thread, 'outdated', 1) || get(thread, 'side', '') !=# 'head' || revue#anchor#IsFile(thread)
    return 'Select a current head-side line discussion.'
  endif
  let message = revue#edit#Message(a:snapshot, a:target)
  if empty(message) || get(message, 'version', '') !=# get(a:target, 'expected_version', '') | return 'Suggestion message changed; select it again.' | endif
  return revue#suggestion#Parse(message.body).error
endfunction

function! revue#apply_suggestion#Validate(snapshot, target, plan) abort
  let error = revue#apply_suggestion#Error(a:snapshot, a:target)
  if !empty(error) | return error | endif
  let p = a:plan
  if type(p) != v:t_dict | return 'Invalid suggestion preview.' | endif
  let allowed = ['kind', 'body', 'destination', 'snapshot', 'head', 'base_tip', 'thread', 'message', 'message_kind', 'expected_version', 'original_body', 'workspace', 'path', 'side', 'before_hash', 'after_hash', 'line_ending', 'start', 'end', 'file_mode', 'before_lines', 'replacement', 'untracked', 'reference', 'id', 'state']
  if !empty(filter(keys(p), {_, key -> index(allowed, key) < 0})) | return 'Suggestion preview contains unsupported operation fields.' | endif
  for key in ['kind', 'body', 'destination', 'snapshot', 'head', 'base_tip', 'thread', 'message', 'message_kind', 'expected_version', 'original_body', 'workspace', 'path', 'side', 'before_hash', 'after_hash', 'line_ending']
    if type(get(p, key, 0)) != v:t_string | return 'Incomplete suggestion preview: ' . key | endif
  endfor
  for key in ['start', 'end', 'file_mode']
    if type(get(p, key, '')) != v:t_number | return 'Invalid suggestion preview: ' . key | endif
  endfor
  for key in ['before_lines', 'replacement']
    if type(get(p, key, 0)) != v:t_list || !empty(filter(copy(p[key]), {_, line -> type(line) != v:t_string || line =~# '[\r\n]'})) | return 'Invalid suggestion text.' | endif
  endfor
  if type(get(p, 'untracked', 0)) != v:t_bool || type(get(p, 'reference', 0)) != v:t_dict | return 'Invalid suggestion comparison.' | endif
  let thread = filter(copy(a:snapshot.threads), {_, t -> t.id ==# a:target.thread})[0]
  let message = revue#edit#Message(a:snapshot, a:target)
  let expected = {'kind': 'apply_suggestion', 'body': '', 'destination': 'workspace',
        \ 'reference': revue#comparisons#Reference(a:snapshot),
        \ 'snapshot': a:snapshot.snapshot, 'head': a:snapshot.head, 'base_tip': a:snapshot.base_tip,
        \ 'original_body': message.body, 'workspace': a:snapshot.capabilities.apply_suggestion.workspace,
        \ 'path': thread.path, 'side': 'head', 'start': thread.start, 'end': thread.line,
        \ 'replacement': revue#suggestion#Parse(message.body).lines}
  for key in ['thread', 'message', 'message_kind', 'expected_version'] | let expected[key] = a:target[key] | endfor
  for [key, value] in items(expected)
    if type(p[key]) != type(value) || p[key] !=# value | return 'Suggestion preview does not match the selected message or comparison.' | endif
  endfor
  if p.start < 1 || p.end < p.start || len(p.before_lines) != p.end - p.start + 1 || p.before_hash !~# '^\x\{64}$' || p.after_hash !~# '^\x\{64}$' || index(['LF', 'CRLF'], p.line_ending) < 0
    return 'Suggestion preview has an invalid source range or hash.'
  endif
  return ''
endfunction

function! revue#apply_suggestion#Unsaved(draft) abort
  let path = resolve(a:draft.workspace . '/' . a:draft.path)
  for buffer in getbufinfo()
    if empty(getbufvar(buffer.bufnr, '&buftype')) && !empty(buffer.name) && resolve(fnamemodify(buffer.name, ':p')) ==# path && buffer.changed
      return 'The target file has unsaved Vim edits. Save or discard them deliberately, then capture and review the file again.'
    endif
  endfor
  return ''
endfunction

function! revue#apply_suggestion#Preview(draft) abort
  let d = a:draft
  return ['# Apply suggestion to workspace',
        \ 'File: ' . d.workspace . '/' . d.path,
        \ printf('Head lines %d–%d · %s · mode %o', d.start, d.end, d.line_ending, d.file_mode),
        \ 'Message: ' . d.message . ' · thread ' . d.thread,
        \ 'Comparison: ' . d.snapshot,
        \ 'Saves this replacement to disk and records a new comparison of saved files.',
        \ (d.untracked ? 'Untracked files are included in that comparison.' : 'Untracked files are excluded from that comparison.'),
        \ 'No commit, push, publication or thread resolution. Unsaved buffers are not reloaded.',
        \ '', '--- Reviewed text'] + map(copy(d.before_lines), {_, line -> '- ' . line}) +
        \ ['+++ Suggested replacement'] + map(copy(d.replacement), {_, line -> '+ ' . line}) +
        \ (empty(d.replacement) ? ['(Delete the selected lines.)'] : [])
endfunction

function! revue#apply_suggestion#Receipt(draft, receipt) abort
  if type(a:receipt) != v:t_dict | return 0 | endif
  let expected = deepcopy(a:draft)
  call remove(expected, 'state')
  return get(a:receipt, 'id', '') ==# a:draft.id && s:Equal(get(a:receipt, 'intent', {}), expected) &&
        \ type(get(a:receipt, 'applied', 0)) == v:t_bool && type(get(a:receipt, 'observed', 0)) == v:t_bool &&
        \ type(get(a:receipt, 'result_snapshot', 0)) == v:t_string && type(get(a:receipt, 'capture_error', 0)) == v:t_string
endfunction

function! s:Equal(left, right) abort
  if type(a:left) != type(a:right) | return 0 | endif
  if type(a:left) == v:t_dict
    if sort(keys(a:left)) !=# sort(keys(a:right)) | return 0 | endif
    for key in keys(a:left)
      if !s:Equal(a:left[key], a:right[key]) | return 0 | endif
    endfor
    return 1
  elseif type(a:left) == v:t_list
    if len(a:left) != len(a:right) | return 0 | endif
    for i in range(len(a:left))
      if !s:Equal(a:left[i], a:right[i]) | return 0 | endif
    endfor
    return 1
  endif
  return a:left ==# a:right
endfunction
