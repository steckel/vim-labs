set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:current = deepcopy(g:fixture.snapshot)
let g:current.capabilities = {'timeline': {'enabled': 1}, 'comparisons': {'enabled': 1, 'refresh_on_open': 1}, 'comment': {'enabled': 1}}
let g:old = deepcopy(g:current)
let g:old.snapshot = 'reviewed-comparison'
let g:old.head = 'reviewed-head'
let g:event = {'id': 'old-review', 'kind': 'review', 'title': 'Reviewed earlier capture', 'actor': 'alex', 'created': '2026-09-14',
      \ 'body': 'Review of retained source', 'url': '', 'details': [], 'provenance': 'Fixture',
      \ 'reviewed_head': g:old.head, 'reviewed_comparison': revue#comparisons#Reference(g:old), 'comparison_provenance': 'Verified retained capture'}
let g:other = deepcopy(g:event)
let g:other.id = 'other-review'
let g:unverified = deepcopy(g:event)
let g:unverified.id = 'unknown-base'
call remove(g:unverified, 'reviewed_comparison')
let g:requests = []
function! ComparisonEventHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'timeline'
    call a:Done({'ok': 1, 'data': {'cursor': '', 'next_cursor': '', 'complete': v:true, 'scope': 'Fixture', 'items': [g:event, g:other, g:unverified]}})
  elseif a:request.op ==# 'comparison'
    call add(g:requests, {'request': a:request, 'Done': a:Done})
  else
    throw 'Unexpected read or mutation: ' . a:request.op
  endif
endfunction
function! PickComparisonEvent(id) abort
  for row in sort(keys(revue#session#Inspect(g:id).timelinerows), 'n')
    if revue#session#Inspect(g:id).timelinerows[row].id ==# a:id | call cursor(str2nr(row) + 1, 1) | return | endif
  endfor
  throw 'Missing event'
endfunction
function! ComparisonEventSelection() abort
  let target = revue#session#Inspect(g:id).timelinerows[string(line('.'))]
  return [target.id, line('.') - target.first]
endfunction
function! ComparisonEventItem() abort
  return filter(revue#session#ActionGuide(), {_, item -> item.id ==# 'event-comparison'})[0]
endfunction
try
  let g:id = revue#backend#Open({'id': 'fixture', 'connection': 'event-comparison', 'review': 'review', 'snapshot': g:current, 'Request': function('ComparisonEventHost')}, 0)
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call cursor(3, 1)
  RevueComment
  call setline(1, 'Retain current-source draft')
  RevueClose
  RevueTimeline
  call PickComparisonEvent('unknown-base')
  call assert_match('head alone', ComparisonEventItem().reason)
  RevueEventComparison
  call assert_equal([], g:requests)
  call PickComparisonEvent('old-review')
  call assert_equal('', ComparisonEventItem().reason)
  let choice = index(map(revue#session#ActionGuide(), {_, i -> i.id}), 'event-comparison') + 1
  call feedkeys(choice . "\<CR>", 't')
  RevueReviewActions
  call assert_equal(g:event.reviewed_comparison, g:requests[-1].request.reference)
  call g:requests[-1].Done({'ok': 0, 'error': 'Source unavailable'})
  call assert_equal(['old-review', 1], ComparisonEventSelection())
  call assert_equal({}, get(revue#session#Inspect(g:id), 'context_return', {}))
  RevueEventComparison
  let malformed = deepcopy(g:old)
  let malformed.files = [0]
  call g:requests[-1].Done({'ok': 1, 'data': malformed})
  call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
  RevueEventComparison
  call g:requests[-1].Done({'ok': 1, 'data': deepcopy(g:old)})
  call assert_equal(g:old.snapshot, b:revue_comparison)
  call assert_equal('old-review', revue#session#Inspect(g:id).context_return.timeline_target.id)
  close
  RevueReturnContext
  call assert_equal('timeline', b:revue_view)
  call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
  call assert_equal(['old-review', 1], ComparisonEventSelection())
  " Same screen row after history reload must not authorize late navigation.
  RevueEventComparison
  RevueReloadTimeline
  call PickComparisonEvent('old-review')
  call g:requests[-1].Done({'ok': 1, 'data': deepcopy(g:old)})
  call assert_equal('timeline', b:revue_view)
  call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
  RevueEventComparison
  call PickComparisonEvent('other-review')
  call g:requests[-1].Done({'ok': 1, 'data': deepcopy(g:old)})
  call assert_equal(['other-review', 1], ComparisonEventSelection())
  call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
  RevueEventComparison
  RevueHelp
  call g:requests[-1].Done({'ok': 1, 'data': deepcopy(g:old)})
  call assert_equal('help', b:revue_view)
  RevueClose
  call assert_equal(['other-review', 1], ComparisonEventSelection())
  " A reused snapshot ID with different endpoints cannot replace cached identity.
  let g:other.reviewed_comparison.base = 'conflicting-base'
  RevueReloadTimeline
  call PickComparisonEvent('other-review')
  call assert_match('conflicts', ComparisonEventItem().reason)
  let calls = len(g:requests)
  RevueEventComparison
  call assert_equal(calls, len(g:requests))
  " An event for the already displayed comparison still enters source view.
  let g:other.reviewed_comparison = revue#comparisons#Reference(g:current)
  let g:other.reviewed_head = g:current.head
  RevueReloadTimeline
  call PickComparisonEvent('other-review')
  RevueEventComparison
  call g:requests[-1].Done({'ok': 1, 'data': deepcopy(g:current)})
  call assert_equal('head', b:revue_role)
  RevueReturnContext
  call assert_equal(['other-review', 1], ComparisonEventSelection())
  " Empty retained comparisons remain inspectable and returnable.
  let empty_source = deepcopy(g:old)
  let empty_source.snapshot = 'empty-comparison'
  let empty_source.head = 'empty-head'
  let empty_source.files = []
  let empty_source.threads = []
  let g:other.reviewed_comparison = revue#comparisons#Reference(empty_source)
  let g:other.reviewed_head = empty_source.head
  RevueReloadTimeline
  call PickComparisonEvent('other-review')
  RevueEventComparison
  call g:requests[-1].Done({'ok': 1, 'data': empty_source})
  call assert_equal('empty-comparison', revue#session#Inspect(g:id).snapshot.snapshot)
  RevueReturnContext
  call assert_equal(['other-review', 1], ComparisonEventSelection())
  call assert_equal('Retain current-source draft', revue#session#Inspect(g:id).drafts[0].body)
  call assert_equal(g:current.snapshot, revue#session#Inspect(g:id).drafts[0].snapshot)
  " Missing provenance, partial references and commit excerpts are invalid pages.
  for mode in ['base', 'provenance', 'head', 'context']
    let event = deepcopy(g:event)
    if mode ==# 'base' | call remove(event.reviewed_comparison, 'base') | endif
    if mode ==# 'provenance' | call remove(event, 'comparison_provenance') | endif
    if mode ==# 'head' | let event.reviewed_head = 'different' | endif
    if mode ==# 'context' | let event.reviewed_comparison.context = {} | endif
    let state = deepcopy(revue#session#Inspect(g:id).timeline)
    let before = deepcopy(state)
    call assert_false(empty(revue#timeline#Apply(state, {'cursor': '', 'items': [event], 'next_cursor': '', 'complete': v:true, 'scope': 'Invalid'}, '', 1)))
    call assert_equal(before, state)
  endfor
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
