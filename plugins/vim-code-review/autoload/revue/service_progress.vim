" Service personal progress never replaces local compared-content evidence.
function! revue#service_progress#Reason(session) abort
  let s = a:session.snapshot
  if !get(get(get(s, 'capabilities', {}), 'service_progress', {}), 'enabled', 0) | return 'This backend does not expose personal service progress.' | endif
  if s.snapshot !=# a:session.latest_comparison || has_key(s, 'range') || has_key(s, 'context') | return 'Open the latest full comparison for service progress.' | endif
  return ''
endfunction

function! revue#service_progress#Valid(data, reference, path) abort
  let d = a:data
  if type(d) != v:t_dict || type(get(d, 'reference', 0)) != v:t_dict || get(d, 'reference', {}) !=# a:reference || get(d, 'path', '') !=# a:path || index(['viewed', 'unviewed', 'dismissed'], get(d, 'state', '')) < 0 | return 0 | endif
  for key in ['actor', 'actor_label', 'review_id']
    if type(get(d, key, 0)) != v:t_string || empty(d[key]) | return 0 | endif
  endfor
  return 1
endfunction

function! revue#service_progress#Error(snapshot, draft) abort
  if !get(get(get(a:snapshot, 'capabilities', {}), 'service_viewed', {}), 'enabled', 0) | return 'This backend cannot change your service Viewed state.' | endif
  let d = a:draft
  if type(get(d, 'reference', 0)) != v:t_dict || get(d, 'reference', {}) !=# revue#comparisons#Reference(a:snapshot) || has_key(d.reference, 'range') || has_key(d.reference, 'context') | return 'Service progress belongs to another comparison. Refresh and inspect the latest file.' | endif
  if empty(filter(copy(a:snapshot.files), {_, f -> f.path ==# get(d, 'path', '')})) | return 'The service Viewed file is no longer in this comparison.' | endif
  for key in ['actor', 'review_id']
    if type(get(d, key, 0)) != v:t_string || empty(d[key]) | return 'Load the service actor and file state first.' | endif
  endfor
  return type(get(d, 'viewed', 0)) != v:t_bool || get(d, 'body', '') !=# '' ? 'Invalid service Viewed intent.' : ''
endfunction

function! revue#service_progress#Receipt(draft, receipt) abort
  if type(a:receipt) != v:t_dict || type(get(a:receipt, 'observed', 0)) != v:t_bool || !a:receipt.observed | return 0 | endif
  for key in ['id', 'path', 'actor', 'review_id', 'reference', 'viewed']
    if type(get(a:receipt, key, 0)) != type(a:draft[key]) || a:receipt[key] !=# a:draft[key] | return 0 | endif
  endfor
  return 1
endfunction

function! revue#service_progress#View(session) abort
  let state = a:session.service_progress
  let lines = ['# Service Viewed state', revue#message#OneLine(state.path),
        \ ':ReviewServiceProgress reloads · :ReviewClose returns',
        \ ':ReviewMarkServiceViewed · :ReviewUnmarkServiceViewed',
        \ ':ReviewCheckServiceViewed checks an uncertain operation', '']
  if state.loading | call add(lines, 'Loading your service state…') | endif
  if !empty(state.error) | call add(lines, revue#message#OneLine(state.error)) | endif
  if !empty(state.data)
    call extend(lines, ['Actor: ' . revue#message#OneLine(state.data.actor_label),
          \ 'Service at last read: ' . (state.data.state ==# 'dismissed' ? 'changed since last viewed' : state.data.state),
          \ 'Observed for head ' . strpart(state.data.reference.head, 0, 12)])
  endif
  if state.reference !=# revue#comparisons#Reference(a:session.snapshot) || a:session.snapshot.snapshot !=# a:session.latest_comparison | call add(lines, 'STALE comparison. Refresh and reopen service progress.') | endif
  for draft in a:session.drafts
    if draft.kind ==# 'service_viewed' && draft.path ==# state.path
      call add(lines, 'Saved intent: ' . (draft.viewed ? 'mark viewed' : 'mark unviewed') . ' · ' . draft.state)
    endif
  endfor
  call extend(lines, ['', 'Service marks are personal to the displayed actor.',
        \ 'Local content-based Viewed marks remain independent.',
        \ 'Comments stay expanded; no review approval or resolution.'])
  return lines
endfunction
