set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:a = deepcopy(g:fixture.snapshot)
let g:a.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}, 'comparisons': {'enabled': 1},
      \ 'comparison_range': {'enabled': 1, 'sides': ['base', 'head'], 'semantics': 'Fixture exact endpoints'}}
let g:b = deepcopy(g:a)
let g:b.head = 'later-head'
let g:b.snapshot = 'later-snapshot'
let g:mode = 'ok'
let g:calls = []
function! RangeData(selection) abort
  let data = deepcopy(g:b)
  let data.snapshot = 'range-fixture'
  let data.range = deepcopy(a:selection)
  let data.base = a:selection.from.reference[a:selection.from.side]
  let data.head = a:selection.to.reference[a:selection.to.side]
  let data.capabilities.comment = {'enabled': 0, 'reason': 'Open latest to create source feedback'}
  return data
endfunction
function! RangeHost(request, Done) abort
  call add(g:calls, deepcopy(a:request))
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'comparisons'
    call a:Done({'ok': 1, 'data': {'items': map([g:a, g:b], {_, s -> revue#comparisons#Reference(s)}), 'latest': deepcopy(g:b), 'complete': 1}})
  elseif a:request.op ==# 'comparison_range'
    let g:requested = deepcopy(a:request.selection)
    if g:mode ==# 'delay'
      let g:RangeDone = a:Done
    else
      let data = RangeData(a:request.selection)
      if g:mode ==# 'wrong' | let data.head = 'wrong-head' | endif
      call a:Done({'ok': 1, 'data': data})
    endif
  elseif a:request.op ==# 'comparison'
    let data = has_key(a:request.reference, 'range') ? RangeData(a:request.reference.range) : a:request.reference.snapshot ==# g:a.snapshot ? deepcopy(g:a) : deepcopy(g:b)
    call a:Done({'ok': 1, 'data': data})
  else
    throw 'Range fixture cannot write'
  endif
endfunction
function! PickComparison(id) abort
  for [row, id] in items(revue#session#Inspect(g:id).comparisonrows)
    if id ==# a:id | call cursor(str2nr(row), 1) | return | endif
  endfor
  throw 'Missing comparison ' . a:id
endfunction
function! ChooseEndpoints() abort
  RevueComparisons
  call PickComparison(g:a.snapshot)
  RevueRangeStart
  call PickComparison(g:b.snapshot)
  RevueRangeEnd
endfunction
try
  let restarting = filereadable($REVUE_CAP_STORE . '/restart')
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'ranges', 'review': 'review', 'snapshot': restarting ? g:b : g:a, 'Request': function('RangeHost')}, 0)
  if restarting
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call assert_equal('head', revue#session#Inspect(g:id).range_selection.from.side)
    RevueResumeComparison
    call assert_equal('range-fixture', b:revue_comparison)
    call assert_true(has_key(revue#session#Inspect(g:id).snapshot, 'range'))
    call assert_equal(g:a.snapshot, revue#session#Inspect(g:id).drafts[0].snapshot)
    call assert_equal('Keep original anchor', revue#session#Inspect(g:id).drafts[0].body)
  else
    call cursor(3, 1)
    RevueComment
    call setline(1, 'Keep original anchor')
    RevueClose
    RevueComparisons
    let before = len(g:calls)
    call cursor(1, 1)
    RevueRangeStart
    RevueOpenRange
    call assert_equal(before, len(g:calls))
    call PickComparison(g:a.snapshot)
    RevueRangeStart
    call assert_equal(g:a.snapshot, get(revue#session#Inspect(g:id).comparisonrows, string(line('.')), ''), 'endpoint selection must retain comparison identity after header growth')
    call PickComparison(g:b.snapshot)
    RevueRangeEnd base
    call assert_equal('base', revue#session#Inspect(g:id).range_selection.to.side)
    RevueRangeEnd invalid
    call assert_equal('base', revue#session#Inspect(g:id).range_selection.to.side)
    RevueRangeEnd
    call assert_equal(g:b.snapshot, get(revue#session#Inspect(g:id).comparisonrows, string(line('.')), ''))
    call assert_match('Start: head headfixture', join(getline(1, '$'), "\n"))
    call assert_match('End: head later-head', join(getline(1, '$'), "\n"))
    RevueOpenRange
    call assert_equal('range-fixture', b:revue_comparison)
    let state = revue#session#Inspect(g:id)
    call assert_equal(state.range_selection, state.snapshot.range)
    call assert_equal(g:b.snapshot, state.latest_comparison)
    call assert_equal(state.snapshot.backend, state.comparisons[g:b.snapshot].snapshot.backend)
    call assert_equal(g:a.snapshot, state.drafts[0].snapshot)
    RevueComment
    call assert_equal(1, len(revue#session#Inspect(g:id).drafts))
    call cursor(3, 1)
    RevueReply
    call assert_equal('range-fixture', revue#session#Inspect(g:id).drafts[-1].snapshot)
    call assert_equal(g:requested, revue#session#Inspect(g:id).drafts[-1].range)
    call setline(1, 'Reply stays in the same discussion')
    RevueClose
    RevueLatest
    call assert_equal(g:b.snapshot, b:revue_comparison)
    call ChooseEndpoints()
    let g:mode = 'wrong'
    RevueOpenRange
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call assert_match('different endpoints', revue#session#Inspect(g:id).range_status)
    let g:mode = 'delay'
    RevueOpenRange
    RevueHelp
    let helpwin = win_getid()
    call g:RangeDone({'ok': 1, 'data': RangeData(g:requested)})
    call assert_equal(helpwin, win_getid())
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    RevueClose
    RevueOpenRange
    RevueClearRange
    call g:RangeDone({'ok': 1, 'data': RangeData(g:requested)})
    call assert_equal({}, revue#session#Inspect(g:id).range_selection)
    call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
    call ChooseEndpoints()
    let g:mode = 'ok'
    RevueOpenRange
    RevueComparisons
    call PickComparison('range-fixture')
    let selected = deepcopy(revue#session#Inspect(g:id).range_selection)
    RevueRangeStart
    call assert_equal(selected, revue#session#Inspect(g:id).range_selection)
    RevueOpenComparison
    call writefile(['restart'], $REVUE_CAP_STORE . '/restart')
  endif
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
