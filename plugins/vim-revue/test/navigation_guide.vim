set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_CAP_STORE . '/drafts'
let g:revue_auto_focus = 0
let g:revue_mappings = {'comparisons': 'gV', 'viewed': 'gM', 'conversation': 'gO'}
let g:fixture = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
let g:a = deepcopy(g:fixture.snapshot)
let g:a.capabilities = {'comment': {'enabled': 1}, 'reply': {'enabled': 1}}
let g:b = deepcopy(g:a)
let g:b.snapshot = 'later-comparison'
let g:b.head = 'later-head'
let g:b.threads[0].outdated = v:true
let g:b.threads[0].original_comparison = revue#comparisons#Reference(g:a)
let g:latest = deepcopy(g:a)
let g:writes = []
let g:history = []
let g:unavailable = 0
let g:defer = 0
function! NavigationHost(request, Done) abort
  if a:request.op ==# 'file'
    if g:defer
      let g:Deferred = a:Done
    else
      call a:Done({'ok': 1, 'data': g:unavailable ? {'base': {'kind': 'unavailable', 'lines': []}, 'head': {'kind': 'unavailable', 'lines': []}} : deepcopy(g:fixture.content)})
    endif
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:latest)})
  elseif a:request.op ==# 'comparisons'
    call a:Done({'ok': 1, 'data': {'items': deepcopy(g:history), 'latest': deepcopy(g:latest), 'complete': v:true}})
  else
    call add(g:writes, a:request)
    throw 'Navigation fixture permits only source and refresh reads'
  endif
endfunction
function! NavItem(id) abort
  return get(filter(revue#session#ActionGuide(), {_, i -> i.id ==# a:id}), 0, {})
endfunction
function! NavChoose(id) abort
  let choice = index(map(revue#session#ActionGuide(), {_, i -> i.id}), a:id) + 1
  call assert_true(choice > 0, a:id)
  call feedkeys(choice . "\<CR>", 't')
  RevueReviewActions
endfunction
function! NavChanged(timer) abort
  let g:history[0].label = 'History refreshed while choosing a comparison'
  RevueLoadHistory
  call feedkeys(g:choice . "\<CR>", 't')
endfunction
try
  let g:id = revue#session#Open(g:a, function('NavigationHost'), 0)
  let state = revue#session#Inspect(g:id)
  call win_gotoid(state.headwin)
  call cursor(3, 1)
  call assert_equal('gO', NavItem('conversation').key)
  call NavChoose('conversation')
  call assert_match(g:a.body, join(getline(1, '$'), "\n"))
  call assert_equal({}, NavItem('conversation'))
  RevueRefresh
  RevueClose
  call assert_equal(state.headwin, win_getid())
  call assert_equal(3, line('.'))
  call assert_equal('gV', NavItem('comparisons').key)
  call assert_equal({}, NavItem('latest'))
  call assert_equal({}, NavItem('previous-comparison'))
  call assert_equal('gM', NavItem('viewed').key)
  call NavChoose('viewed')
  call assert_equal({}, NavItem('viewed'))
  call assert_equal('', NavItem('unviewed').reason)
  call assert_match('locally', NavItem('unviewed').label)
  call assert_equal(3, line('.'))
  call NavChoose('unviewed')
  call assert_equal({}, NavItem('unviewed'))
  call assert_equal({}, NavItem('verify-viewed'))
  call win_gotoid(state.treewin)
  call cursor(1, 1)
  call assert_equal('Select a file first.', NavItem('viewed').reason)
  call win_gotoid(state.headwin)
  RevueComment
  call setline(1, 'Retain this draft on the first comparison.')
  call assert_equal('', NavItem('draft-comparison').reason)
  RevueClose
  let g:latest = deepcopy(g:b)
  RevueRefresh
  call assert_equal('', NavItem('latest').reason)
  call NavChoose('comparisons')
  call assert_equal('comparisons', b:revue_view)
  call assert_equal({}, NavItem('comparisons'))
  call cursor(1, 1)
  call assert_equal('Select a comparison first.', NavItem('open-comparison').reason)
  call assert_match('does not provide', NavItem('load-history').reason)
  call search('\[latest\]', 'w')
  call NavChoose('open-comparison')
  call assert_equal(g:b.snapshot, b:revue_comparison)
  call assert_equal({}, NavItem('latest'))
  call assert_equal('', NavItem('previous-comparison').reason)
  call NavChoose('previous-comparison')
  call assert_equal(g:a.snapshot, b:revue_comparison)
  call NavChoose('latest')
  call assert_equal(g:b.snapshot, b:revue_comparison)
  RevueThreads
  call cursor(1, 1)
  RevueNextMessage
  RevueNextMessage
  call assert_equal('local-reply-1', revue#discussion#Selected(revue#session#Inspect(g:id), line('.')).comment)
  call assert_equal('', NavItem('thread-comparison').reason)
  call NavChoose('thread-comparison')
  call assert_equal(g:a.snapshot, b:revue_comparison)
  call assert_equal(g:a.threads[0].line, line('.'))
  RevueThread
  RevueNextMessage
  call assert_match('does not provide the original comparison', NavItem('thread-comparison').reason)
  RevueClose
  RevueLatest
  let g:latest.capabilities.comparisons = {'enabled': 1}
  RevueRefresh
  let g:history = [revue#comparisons#Reference(g:a), {'snapshot': 'uncached', 'base': 'old-base', 'head': 'old-head'}]
  call NavChoose('comparisons')
  call search('\[historical\]', 'w')
  let g:choice = index(map(revue#session#ActionGuide(), {_, i -> i.id}), 'open-comparison') + 1
  call timer_start(80, function('NavChanged'))
  RevueReviewActions
  call assert_equal('comparisons', b:revue_view, 'reference changes during a menu must not switch source')
  call assert_equal(g:b.snapshot, revue#session#Inspect(g:id).snapshot.snapshot)
  " Uncached references remain visible but explain why they cannot be opened.
  let g:latest.capabilities.comparisons = {'enabled': 0}
  RevueRefresh
  RevueComparisons
  call search('Comparison uncached', 'w')
  call assert_match('cannot retrieve', NavItem('open-comparison').reason)
  call NavChoose('open-comparison')
  call assert_equal('comparisons', b:revue_view)
  let state = revue#session#Inspect(g:id)
  call assert_equal(g:a.snapshot, state.drafts[0].snapshot)
  call assert_equal('Retain this draft on the first comparison.', state.drafts[0].body)
  let g:latest.capabilities.comparisons = {'enabled': 0, 'refresh_on_open': 1, 'reason': 'History access changed'}
  RevueRefresh
  call assert_equal('History access changed', NavItem('previous-comparison').reason)
  call search('Comparison ' . g:a.snapshot, 'w')
  call assert_equal('History access changed', NavItem('open-comparison').reason)
  call assert_equal([], g:writes)
  call revue#session#Close()
  let g:unavailable = 1
  let g:a.snapshot = 'unverified-comparison'
  let g:a.head = 'unverified-head'
  let g:revue_no_default_mappings = 1
  let g:revue_mappings = {}
  let g:id = revue#session#Open(g:a, function('NavigationHost'), 0)
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  call assert_equal('', NavItem('comparisons').key)
  call assert_equal('', NavItem('conversation').key)
  call NavChoose('conversation')
  call assert_equal('conversation', b:revue_view)
  RevueClose
  call assert_equal('', NavItem('viewed').key)
  call assert_equal('', NavItem('verify-viewed').reason)
  let g:unavailable = 0
  call NavChoose('verify-viewed')
  sleep 20m
  call assert_equal({}, NavItem('verify-viewed'))
  call assert_equal([], g:writes)
  call revue#session#Close()
  " A pending mark can still be canceled before content verification returns.
  let g:a.snapshot = 'cancel-pending-mark'
  let g:a.head = 'cancel-pending-head'
  let g:unavailable = 1
  let g:id = revue#session#Open(g:a, function('NavigationHost'), 0)
  call win_gotoid(revue#session#Inspect(g:id).headwin)
  let g:unavailable = 0
  let g:defer = 1
  call NavChoose('viewed')
  sleep 20m
  call assert_equal({}, NavItem('viewed'))
  call assert_match('Cancel.*pending Viewed', NavItem('unviewed').label)
  call NavChoose('unviewed')
  call g:Deferred({'ok': 1, 'data': deepcopy(g:fixture.content)})
  let state = revue#session#Inspect(g:id)
  call assert_equal('unviewed', revue#progress#State(state, state.snapshot, state.snapshot.files[0]))
  call assert_equal({}, NavItem('unviewed'))
  call assert_equal([], g:writes)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
