" Durable resolution intent, presented beside the discussion it belongs to.
function! revue#thread_state#Pending(session, thread) abort
  for draft in a:session.drafts
    if draft.kind ==# 'thread_state' && draft.thread ==# a:thread | return draft | endif
  endfor
  return {}
endfunction

function! revue#thread_state#Status(draft) abort
  if empty(a:draft) | return '' | endif
  let verb = a:draft.resolved ? 'Resolve' : 'Reopen'
  if a:draft.state ==# 'submitting' | return verb . ' in progress; waiting for outcome.' | endif
  if a:draft.state ==# 'unknown' | return verb . ' outcome unknown; :RevueCheckThreadState checks the original operation.' | endif
  return verb . (a:draft.state ==# 'failed' ? ' failed' : ' prepared') . '; :Revue' . verb . ' retries. :RevueActivity has details.'
endfunction
