" Suggestions are ordinary comment drafts with explicit authoring intent.
function! revue#suggestion#Label(draft) abort
  if a:draft.kind ==# 'service_viewed' | return 'personal service Viewed update' | endif
  if a:draft.kind ==# 'start_pending' | return 'pending review summary' | endif
  if a:draft.kind ==# 'delete_message' | return 'message deletion' | endif
  if a:draft.kind ==# 'delete_pending_comment' | return 'private comment deletion' | endif
  if a:draft.kind ==# 'discard_pending' | return 'pending review discard' | endif
  if a:draft.kind ==# 'submit_pending' | return 'pending review publication' | endif
  if a:draft.kind ==# 'capture' | return 'new capture' | endif
  let label = get(a:draft, 'suggestion', 0) ? 'suggestion' : a:draft.kind ==# 'file_comment' ? 'file comment' : a:draft.kind
  return (empty(get(a:draft, 'pending_mode', '')) ? '' : 'private ') . label
endfunction

function! revue#suggestion#Seed(lines) abort
  let longest = 2
  for line in a:lines
    let offset = 0
    while 1
      let match = matchstrpos(line, '`\+', offset)
      if match[1] < 0 | break | endif
      let longest = max([longest, strlen(match[0])])
      let offset = match[2]
    endwhile
  endfor
  let fence = repeat('`', longest + 1)
  return join([fence . 'suggestion'] + a:lines + [fence], "\n")
endfunction

function! revue#suggestion#Parse(body) abort
  let lines = split(a:body, "\n", 1)
  let blocks = []
  let index = 0
  while index < len(lines)
    let fence = matchlist(lines[index], '^ \{0,3}\(`\{3,}\|\~\{3,}\)\s*\(.*\)$')
    if empty(fence) | let index += 1 | continue | endif
    let suggestion = trim(fence[2]) ==# 'suggestion'
    let closing = '^ \{0,3}' . escape(strpart(fence[1], 0, 1), '~') . '\{' . strlen(fence[1]) . ',}\s*$'
    let replacement = []
    let index += 1
    while index < len(lines) && lines[index] !~# closing
      call add(replacement, lines[index])
      let index += 1
    endwhile
    if suggestion
      if index == len(lines) | return {'error': 'Close the suggestion fence before submitting.'} | endif
      call add(blocks, replacement)
    endif
    let index += 1
  endwhile
  if len(blocks) != 1 | return {'error': 'Keep exactly one suggestion block for the selected range.'} | endif
  return {'error': '', 'lines': blocks[0]}
endfunction

function! revue#suggestion#Error(snapshot, draft, body) abort
  let rule = get(get(a:snapshot, 'capabilities', {}), 'suggestion', {})
  if !get(rule, 'enabled', 0) | return get(rule, 'reason', 'This backend does not support suggestion creation.') | endif
  if a:draft.kind !=# 'comment' || index(get(rule, 'sides', ['head']), get(a:draft, 'side', '')) < 0
    return 'Suggestions are not supported on this source side.'
  endif
  return a:body ? revue#suggestion#Parse(a:draft.body).error : ''
endfunction
