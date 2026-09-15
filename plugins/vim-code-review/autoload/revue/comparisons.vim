" Persist references/views only. Backend-owned snapshots and source stay in memory.
function! revue#comparisons#Reference(snapshot) abort
  let reference = {}
  for key in ['snapshot', 'base', 'head', 'base_tip', 'head_repo', 'base_repo', 'range', 'context']
    if has_key(a:snapshot, key) | let reference[key] = a:snapshot[key] | endif
  endfor
  return reference
endfunction

function! revue#comparisons#Init(session) abort
  let a:session.comparisons = {}
  let a:session.comparison_order = []
  let a:session.sourceviews = {}
  let a:session.latest_comparison = a:session.snapshot.snapshot
  let saved = get(a:session, 'saved_navigation', {})
  let a:session.range_selection = deepcopy(get(saved, 'range_selection', {}))
  let a:session.resume_comparison = get(saved, 'selected', '')
  for [id, entry] in items(get(saved, 'references', {}))
    if get(get(entry, 'reference', {}), 'snapshot', '') !=# id | continue | endif
    let a:session.comparisons[id] = {'reference': entry.reference, 'views': get(entry, 'views', {}),
          \ 'file': get(entry, 'file', ''), 'side': get(entry, 'side', 'head'), 'index': -1, 'cache': {}}
    call add(a:session.comparison_order, id)
  endfor
  let ordered = filter(copy(get(saved, 'order', [])), {_, id -> has_key(a:session.comparisons, id)})
  for id in a:session.comparison_order
    if index(ordered, id) < 0 | call add(ordered, id) | endif
  endfor
  let a:session.comparison_order = ordered
  call revue#comparisons#Observe(a:session, a:session.snapshot)
  let a:session.sourceviews = a:session.comparisons[a:session.snapshot.snapshot].views
endfunction

function! revue#comparisons#AddReference(session, reference) abort
  let id = a:reference.snapshot
  if !has_key(a:session.comparisons, id)
    call add(a:session.comparison_order, id)
    let a:session.comparisons[id] = {'cache': {}, 'views': {}, 'index': -1, 'file': '', 'side': 'head'}
  endif
  let a:session.comparisons[id].reference = deepcopy(a:reference)
endfunction

function! revue#comparisons#Observe(session, snapshot, ...) abort
  let id = a:snapshot.snapshot
  let reference = revue#comparisons#Reference(a:snapshot)
  let reference.label = get(get(get(a:session.comparisons, id, {}), 'reference', {}), 'label', '')
  call revue#comparisons#AddReference(a:session, reference)
  let a:session.comparisons[id].snapshot = deepcopy(a:snapshot)
  if !a:0 || a:1 | let a:session.latest_comparison = id | endif
endfunction

function! revue#comparisons#Remember(session) abort
  let entry = a:session.comparisons[a:session.snapshot.snapshot]
  let entry.cache = a:session.cache
  let entry.views = a:session.sourceviews
  let entry.index = a:session.index
  if get(b:, 'revue_session', '') ==# a:session.id && index(['base', 'head'], get(b:, 'revue_role', '')) >= 0
    let entry.side = b:revue_role
  endif
  if a:session.index >= 0 | let entry.file = a:session.snapshot.files[a:session.index].id | endif
endfunction

function! revue#comparisons#Navigation(session) abort
  let references = {}
  for [id, entry] in items(a:session.comparisons)
    let references[id] = {'reference': entry.reference, 'views': entry.views, 'file': get(entry, 'file', ''), 'side': get(entry, 'side', 'head')}
  endfor
  return {'selected': has_key(a:session, 'treewin') ? a:session.snapshot.snapshot : get(a:session.saved_navigation, 'selected', a:session.snapshot.snapshot), 'references': references, 'order': a:session.comparison_order, 'range_selection': deepcopy(get(a:session, 'range_selection', {}))}
endfunction

function! revue#comparisons#View(session) abort
  let view = {'lines': ['# Comparisons', ':RevueOpenComparison · :RevueLatest · :RevuePreviousComparison · :RevueClose',
        \ ':RevueLoadHistory · :RevueResumeComparison restores the last saved selection',
        \ 'Opening a comparison changes the source view; existing drafts keep their anchors.',
        \ get(a:session, 'history_status', 'Saved and observed references. Backend history is loaded when supported.')], 'rows': {}}
  let rule = get(get(a:session.comparisons[a:session.latest_comparison].snapshot, 'capabilities', {}), 'comparison_range', {})
  if !empty(rule) || !empty(get(a:session, 'range_selection', {}))
    call extend(view.lines, ['', 'Range: select an endpoint row, then :RevueRangeStart [base|head] / :RevueRangeEnd [base|head]',
          \ ':RevueOpenRange opens the selected endpoints · :RevueClearRange clears the selection',
          \ get(rule, 'semantics', 'Range support is determined by this backend.')])
    for name in ['from', 'to']
      let endpoint = get(get(a:session, 'range_selection', {}), name, {})
      let reference = get(endpoint, 'reference', {})
      call add(view.lines, (name ==# 'from' ? 'Start: ' : 'End: ') . (empty(endpoint) ? 'not selected' :
            \ get(endpoint, 'side', '?') . ' ' . get(reference, get(endpoint, 'side', ''), '?')))
    endfor
    if !empty(get(a:session, 'range_status', '')) | call add(view.lines, a:session.range_status) | endif
    call add(view.lines, '')
  endif
  let ordered = [a:session.latest_comparison] + reverse(filter(copy(a:session.comparison_order), {_, id -> id !=# a:session.latest_comparison}))
  for id in ordered
    let entry = a:session.comparisons[id]
    let reference = entry.reference
    let label = (id ==# a:session.snapshot.snapshot ? '[viewing] ' : '') . (id ==# a:session.latest_comparison ? '[latest] ' : '[historical] ')
    if has_key(reference, 'range') | let label .= '[range] ' | endif
    if has_key(reference, 'context') | let label .= '[original context] ' | endif
    let first = len(view.lines) + 1
    call add(view.lines, label . strpart(get(reference, 'base', '?'), 0, 12) . ' → ' . strpart(get(reference, 'head', '?'), 0, 12))
    if !empty(get(reference, 'label', '')) | call add(view.lines, '  ' . reference.label) | endif
    call add(view.lines, strlen(id) <= 50 ? '  Comparison ' . id : '  :RevueCopyComparison copies the full reference')
    if has_key(entry, 'snapshot')
      let files = len(entry.snapshot.files)
      let threads = len(entry.snapshot.threads)
      call add(view.lines, printf('  %d file%s · %d thread%s', files, files == 1 ? '' : 's', threads, threads == 1 ? '' : 's'))
      if !empty(get(entry.snapshot, 'comparison_note', ''))
        call add(view.lines, '  ' . revue#message#OneLine(entry.snapshot.comparison_note))
      endif
    else
      call add(view.lines, '  Not loaded · Enter fetches this immutable comparison')
    endif
    call add(view.lines, '')
    for row in range(first, len(view.lines)) | let view.rows[string(row)] = id | endfor
  endfor
  return view
endfunction
