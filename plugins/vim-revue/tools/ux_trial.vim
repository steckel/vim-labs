" This script is sourced only by the isolated trial launcher.
set nocompatible nomore
let g:trial = json_decode(join(readfile(g:revue_trial_settings), "\n"))
execute 'set runtimepath^=' . fnameescape(g:trial.root)
let g:revue_draft_dir = g:trial.directory . '/drafts'
let g:fixture = json_decode(join(readfile(g:trial.directory . '/fixture.json'), "\n"))
if g:trial.remapped
  let g:revue_mappings = {'thread': 'gt', 'actions': 'ga', 'next-message': 'gn', 'previous-message': 'gp', 'quote': 'gq'}
endif
let g:trial_events = []
let g:trial_started = reltime()
let g:trial_state = []
let g:trial_write_attempts = []
function! TrialHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.content)})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:fixture.snapshot)})
  elseif a:request.op ==# 'mutate' && get(a:request.draft, 'kind', '') ==# 'thread_state'
    let draft = a:request.draft
    for thread in g:fixture.snapshot.threads
      if thread.id ==# draft.thread | let thread.resolved = draft.resolved | endif
    endfor
    call a:Done({'ok': 1, 'data': {'id': draft.id, 'thread': draft.thread, 'resolved': draft.resolved}})
  else
    call add(g:trial_write_attempts, {'operation': a:request.op, 'kind': get(get(a:request, 'draft', {}), 'kind', '')})
    call a:Done({'ok': 0, 'unknown': 0, 'error': 'Local trial: sending is disabled; the draft remains local.'})
  endif
endfunction
function! TrialObserve() abort
  if !exists('g:trial_session') | return | endif
  let session = revue#session#Inspect(g:trial_session)
  if empty(session) | return | endif
  let message = revue#discussion#Selected(session, line('.'))
  let state = [get(b:, 'revue_view', get(b:, 'revue_role', 'outside')), get(message, 'thread', ''), get(message, 'comment', '')]
  if state !=# g:trial_state
    let g:trial_state = state
    call add(g:trial_events, {'seconds': reltimefloat(reltime(g:trial_started)), 'view': state[0], 'thread': state[1], 'message': state[2], 'columns': &columns, 'lines': &lines})
  endif
endfunction
function! TrialSave() abort
  call TrialObserve()
  let session = revue#session#Inspect(g:trial_session)
  let result = {'status': 'trace-only-not-a-usability-result', 'events': g:trial_events, 'write_attempts': g:trial_write_attempts,
        \ 'final_view': g:trial_state, 'final_position': [win_getid(), bufnr(), getpos('.')], 'source_position': g:trial_source, 'service_calls': 0,
        \ 'remaining_drafts': get(session, 'drafts', []), 'human_observation': 'observer.json'}
  call writefile([json_encode(result)], g:trial.directory . '/trace.json')
endfunction
let g:trial_session = revue#session#Open(g:fixture.snapshot, function('TrialHost'), 0)
call cursor(3, 1)
let g:trial_source = [win_getid(), bufnr(), getpos('.')]
augroup RevueLocalTrial
  autocmd!
  autocmd BufEnter,CursorMoved * call TrialObserve()
  autocmd VimLeavePre * call TrialSave()
augroup END
call TrialObserve()
