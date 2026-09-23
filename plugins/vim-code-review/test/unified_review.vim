set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_local_dir = $REVIEW_UNIFIED_DIR . '/store'
let g:revue_draft_dir = $REVIEW_UNIFIED_DIR . '/drafts'
let g:revue_auto_focus = 0
let g:fixture = json_decode(join(readfile($REVIEW_UNIFIED_DIR . '/config.json'), "\n"))
runtime plugin/revue.vim
function! WaitFor(Fn) abort
  let start = reltime()
  while !a:Fn() && reltimefloat(reltime(start)) < 15 | sleep 10m | endwhile
  if !a:Fn() | throw 'Timed out: ' . execute('messages') | endif
endfunction
try
  call assert_equal([], getcompletion('ReviewLocal', 'command'))
  call assert_equal([], getcompletion('Revue', 'command'))
  if $REVIEW_UNIFIED_PHASE ==# 'create'
    Review
  elseif $REVIEW_UNIFIED_PHASE ==# 'resume'
    execute 'ReviewResume ' . readfile($REVIEW_UNIFIED_DIR . '/review')[0]
  else
    ReviewSaved
    call WaitFor({-> !empty(get(b:, 'revue_local_reviews', []))})
    call assert_equal(1, len(b:revue_local_reviews))
    call cursor(3, 1)
    call feedkeys("\<CR>", 'xt')
  endif
  call WaitFor({-> !empty(get(b:, 'revue_session', ''))})
  let g:id = b:revue_session
  call WaitFor({-> !empty(revue#session#Inspect(g:id).loaded)})
  let s = revue#session#Inspect(g:id)
  call win_gotoid(s.headwin)
  call assert_equal('local', s.snapshot.backend.id)
  call assert_equal(g:fixture.changed, getline(1, '$'))
  call assert_false(&modifiable)
  if $REVIEW_UNIFIED_PHASE ==# 'create'
    call cursor(2, 1)
    call feedkeys('c', 'xt')
    call assert_true(exists('b:revue_draft'))
    call setline(1, ['Explain this change.', '', 'Keep this feedback across restarts.'])
    write
    ReviewClose
    call win_gotoid(s.basewin)
    call cursor(2, 1)
    call feedkeys('Vjc', 'xt')
    let d = revue#session#Inspect(g:id).drafts[-1]
    call assert_equal(['base', 2, 3], [d.side, d.start, d.end])
    call setline(1, 'Base range feedback.')
    ReviewClose
    call writefile([s.snapshot.backend.review], $REVIEW_UNIFIED_DIR . '/review')
  endif
  let s = revue#session#Inspect(g:id)
  call assert_equal(2, len(revue#local_feedback#Cards(s)), 'Both comments are persistent Pending cards')
  call assert_equal(g:fixture.original, getbufline(s.base, 1, '$'))
  call assert_equal(g:fixture.changed, getbufline(s.head, 1, '$'))
  call assert_true(len(filter(prop_list(2, {'bufnr': s.head}), {_, p -> p.type ==# 'RevueCardBorder'})) > 0)
  call win_gotoid(s.headwin)
  ReviewBatch
  ReviewSelectFeedback
  ReviewExportMarkdown
  call assert_equal('markdown', &filetype)
  let markdown = join(getline(1, '$'), "\n")
  call assert_match('Explain this change.', markdown)
  call assert_match('Base range feedback.', markdown)
  call assert_match('example.py', markdown)
  call assert_equal(2, len(revue#session#Inspect(g:id).drafts), 'Export preserves pending feedback')
  let exported = bufnr()
  call win_gotoid(s.headwin)
  call revue#session#Close()
  call assert_true(bufexists(exported), 'Export survives closing the review')
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVIEW_UNIFIED_DIR . '/errors')
if !empty(v:errors) | cquit | endif
qa!
