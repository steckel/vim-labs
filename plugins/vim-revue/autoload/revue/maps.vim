" Actions have commands and Plug mappings even when default keys are disabled.
function! revue#maps#Apply(role) abort
  for item in get(b:, 'revue_owned_maps', [])
    let current = maparg(item.key, item.mode, 0, 1)
    if get(current, 'buffer', 0) && get(current, 'rhs', '') ==# item.rhs
      execute 'silent! ' . item.mode . 'unmap <buffer> ' . item.key
    endif
  endfor
  for name in get(b:, 'revue_commands', [])
    execute 'silent! delcommand -buffer ' . name
  endfor
  let b:revue_owned_maps = []
  let b:revue_commands = []
  let b:revue_bindings = []
  let actions = [['help', 'Help', 'g?', 'Help()'], ['close', 'Close', a:role ==# 'draft' ? '' : 'q', 'CloseView()']]
  call extend(actions, [['continue-refresh', 'ContinueRefresh', '', 'ContinueRefresh()'], ['cancel-refresh', 'CancelRefresh', '', 'CancelRefresh()']])
  call add(actions, ['cancel-verify-pending', 'CancelVerifyPending', '', 'CancelVerifyPending()'])
  call add(actions, ['review-actions', 'ReviewActions', '<LocalLeader>a', 'ReviewActions()'])
  call add(actions, ['assign', 'Assign', '', 'Assign()'])
  call add(actions, ['assignments', 'Assignments', '', 'Assignments()'])
  call add(actions, ['cancel-assignments-read', 'CancelAssignmentsRead', '', 'CancelAssignmentsRead()'])
  call add(actions, ['batch', 'Batch', '<LocalLeader>b', "Batch('', 'public')"])
  call add(actions, ['stage-batch', 'StageBatch', '', "Batch('', 'private')"])
  call add(actions, ['start-pending', 'StartPending', '', 'StartPending()'])
  call add(actions, ['pending', 'Pending', '', 'Pending()'])
  call extend(actions, [['activity', 'Activity', '', 'Activity()'], ['next-unread', 'NextUnread', '', 'NextUnread()']])
  call add(actions, ['timeline', 'Timeline', '', 'Timeline()'])
  call add(actions, ['readiness', 'Readiness', '', 'Readiness()'])
  call extend(actions, [['load-more-feedback', 'LoadMoreFeedback', '', 'LoadMoreFeedback()'],
        \ ['cancel-feedback', 'CancelFeedback', '', 'CancelFeedback()']])
  call extend(actions, [['discussions', 'Discussions', '', 'Discussions()'], ['file-filter', 'FileFilter', '', "Filter('file', '')"]])
  call extend(actions, [['comparisons', 'Comparisons', '', 'Comparisons()'], ['latest', 'Latest', '', 'Latest()'],
        \ ['previous-comparison', 'PreviousComparison', '', 'PreviousComparison()'], ['resume-comparison', 'ResumeComparison', '', 'ResumeComparison()'],
        \ ['return-context', 'ReturnContext', '', 'ReturnContext()']])
  call extend(actions, [['focus', 'Focus', '<LocalLeader>z', 'Focus()'],
        \ ['restore-layout', 'RestoreLayout', '', 'RestoreLayout()'], ['files', 'Files', '', 'ToggleFiles()']])
  call add(actions, ['cancel-reanchor', 'CancelReanchor', '', 'CancelReanchor()'])
  if a:role ==# 'draft' | call add(actions, ['reanchor-draft', 'ReanchorDraft', '', 'ReanchorDraft()']) | endif
  if a:role ==# 'reanchor' | call add(actions, ['accept-reanchor', 'AcceptReanchor', '', 'AcceptReanchor()']) | endif
  if index(['files', 'base', 'head'], a:role) >= 0 | call add(actions, ['reanchor-here', 'ReanchorHere', '', 'ReanchorHere(0)']) | endif
  if a:role !=# 'draft'
    call add(actions, ['capture', 'Capture', '', 'Capture(0)'])
    call extend(actions, [['refresh', 'Refresh', 'R', 'Refresh()'],
          \ ['next-file', 'NextFile', ']f', 'Next(1)'], ['previous-file', 'PreviousFile', '[f', 'Next(-1)'],
          \ ['conversation', 'Conversation', 'C', 'Conversation()'], ['review', 'Review', 's', 'Review()']])
  endif
  if index(['files', 'base', 'head', 'service-progress'], a:role) >= 0 | call add(actions, ['service-progress', 'ServiceProgress', '', 'ServiceProgress()']) | endif
  if a:role ==# 'service-progress'
    call extend(actions, [['mark-service-viewed', 'MarkServiceViewed', '', 'ServiceViewed(1)'], ['unmark-service-viewed', 'UnmarkServiceViewed', '', 'ServiceViewed(0)'], ['check-service-viewed', 'CheckServiceViewed', '', 'ServiceViewed(-1)']])
  endif
  if a:role ==# 'files'
    call add(actions, ['open', 'Open', '<CR>', 'Activate()'])
  elseif index(['base', 'head'], a:role) >= 0
    call extend(actions, [['comment', 'Comment', 'c', 'Comment(0)'], ['reply', 'Reply', 'r', 'Reply()'],
          \ ['suggest', 'Suggest', '', 'Suggest(0)'],
          \ ['thread', 'Thread', '<LocalLeader>t', 'FocusThread()'], ['threads', 'Threads', 't', 'Threads()'], ['next-thread', 'NextThread', ']t', 'NextThread(1)'],
          \ ['previous-thread', 'PreviousThread', '[t', 'NextThread(-1)']])
  elseif a:role ==# 'threads'
    call add(actions, ['thread-comparison', 'ThreadComparison', '', 'ThreadComparison()'])
    call extend(actions, [['reply', 'Reply', 'r', 'Reply()'], ['jump', 'Jump', '<CR>', 'JumpThread()']])
  elseif a:role ==# 'conversation'
    call add(actions, ['new-conversation', 'NewConversation', 'c', 'NewConversation()'])
  elseif a:role ==# 'draft'
    call add(actions, ['edit-base', 'EditBase', '', 'EditBase()'])
    call add(actions, ['save-pending', 'SavePending', '', 'SavePending()'])
    call add(actions, ['pending-base', 'PendingBase', '', 'PendingBase()'])
    call add(actions, ['refresh', 'Refresh', '', 'Refresh()'])
    call extend(actions, [['send', 'Send', '<C-S>', 'Send()'], ['discard', 'Discard', '', 'Discard()'],
          \ ['preview', 'Preview', '<LocalLeader>p', 'Preview()']])
  elseif index(['assignments', 'assignment'], a:role) >= 0
    call extend(actions, [['run-participant', 'RunParticipant', '', 'RunParticipant()'], ['abandon-run', 'AbandonRun', '', 'RunParticipant(1)']])
    call extend(actions, [['assignment-details', 'AssignmentDetails', '', 'AssignmentDetails()'],
          \ ['reload-assignments', 'ReloadAssignments', '', 'ReloadAssignments()'],
          \ ['cancel-assignment', 'CancelAssignment', '', 'CancelAssignment()'],
          \ ['assignment-comparison', 'AssignmentComparison', '', 'AssignmentComparison(0)']])
    if a:role ==# 'assignments'
      call add(actions, ['open-assignment', 'OpenAssignment', '<CR>', 'OpenAssignment()'])
    else
      call extend(actions, [['assignment-discussion', 'AssignmentDiscussion', '<CR>', 'AssignmentDiscussion(0)'],
            \ ['assignment-reply', 'AssignmentReply', '', 'AssignmentDiscussion(1)'],
            \ ['assignment-result', 'AssignmentResult', '', 'AssignmentComparison(1)']])
    endif
  elseif a:role ==# 'assignment-selection'
    call extend(actions, [['assignment-toggle', 'ToggleAssignment', '<Space>', 'ToggleAssignment()'],
          \ ['assignment-prepare', 'PrepareAssignment', '<CR>', 'PrepareAssignment()']])
  elseif a:role ==# 'batch'
    call extend(actions, [['batch-toggle', 'ToggleDraft', '<Space>', 'ToggleBatchDraft()'],
          \ ['batch-edit', 'EditDraft', '<CR>', 'EditBatchDraft()'],
          \ ['batch-send', 'SendBatch', 'S', 'SendBatch()'], ['batch-unpack', 'UnpackBatch', '', 'UnpackBatch()']])
  elseif a:role ==# 'activity'
    call extend(actions, [['open-operation', 'OpenOperation', '<CR>', 'OpenOperation()'],
          \ ['copy-receipt', 'CopyReceipt', '', 'CopyReceipt(v:register)']])
  elseif a:role ==# 'timeline'
    call extend(actions, [['older-events', 'OlderEvents', '', 'LoadTimeline(0)'],
          \ ['reload-timeline', 'ReloadTimeline', '', 'LoadTimeline(1)'], ['cancel-timeline', 'CancelTimeline', '', 'CancelTimeline()'],
          \ ['event-discussion', 'EventDiscussion', '<CR>', 'EventDiscussion()'],
          \ ['event-comparison', 'EventComparison', '', 'EventComparison()'],
          \ ['load-event-discussion', 'LoadEventDiscussion', '', 'LoadEventDiscussion()'],
          \ ['event-link', 'EventLink', 'gx', 'EventLink(0)'], ['copy-event-link', 'CopyEventLink', 'gy', 'EventLink(1)']])
  elseif a:role ==# 'readiness'
    call extend(actions, [['reload-readiness', 'ReloadReadiness', '', 'LoadReadiness(1)'],
          \ ['more-checks', 'MoreChecks', '', 'LoadReadiness(0)'], ['cancel-readiness', 'CancelReadiness', '', 'CancelReadiness()'],
          \ ['readiness-link', 'ReadinessLink', 'gx', 'ReadinessLink(0)'], ['copy-readiness-link', 'CopyReadinessLink', 'gy', 'ReadinessLink(1)']])
  elseif a:role ==# 'reactions'
    call extend(actions, [['react', 'React', '<CR>', 'React()'], ['reactions', 'Reactions', '', 'Reactions()']])
  elseif a:role ==# 'message-history'
    call extend(actions, [['reload-message-history', 'ReloadMessageHistory', '', 'LoadMessageHistory(1)'],
          \ ['older-message-edits', 'OlderMessageEdits', '', 'LoadMessageHistory(0)'],
          \ ['cancel-message-history', 'CancelMessageHistory', '', 'CancelMessageHistory()'],
          \ ['history-message-link', 'HistoryMessageLink', 'gx', 'HistoryMessageLink()']])
  elseif a:role ==# 'pending'
    call extend(actions, [['verify-pending', 'VerifyPending', '', 'VerifyPending()']])
    call extend(actions, [['edit-pending', 'EditPending', '', 'EditPending()'], ['discard-pending', 'DiscardPending', '', 'DiscardPending()'], ['open-pending', 'OpenPending', '<CR>', 'OpenPending()'], ['publish-pending', 'PublishPending', '', "PublishPending('')"]])
  elseif a:role ==# 'comparisons'
    call extend(actions, [['range-start', 'RangeStart', '', "RangeEndpoint('from', '')"], ['range-end', 'RangeEnd', '', "RangeEndpoint('to', '')"],
          \ ['open-range', 'OpenRange', '', 'OpenRange()'], ['clear-range', 'ClearRange', '', 'ClearRange()']])
    call add(actions, ['open-comparison', 'OpenComparison', '<CR>', 'OpenComparison()'])
    call add(actions, ['load-history', 'LoadHistory', '', 'LoadHistory()'])
    call add(actions, ['copy-comparison', 'CopyComparison', '', 'CopyComparison(v:register)'])
  elseif a:role ==# 'discussions'
    call extend(actions, [['open-discussion', 'OpenDiscussion', '<CR>', 'OpenDiscussion()'],
          \ ['discussion-filter', 'DiscussionFilter', '', "Filter('discussion', '')"]])
  endif
  if index(['files', 'base', 'head'], a:role) >= 0
    call extend(actions, [['file-comment', 'FileComment', '', 'FileComment()'], ['file-threads', 'FileThreads', '', 'FileThreads()']])
    call extend(actions, [['viewed', 'Viewed', '', 'Viewed(1)'], ['unviewed', 'Unviewed', '', 'Viewed(0)'], ['verify-viewed', 'VerifyViewed', '', 'VerifyViewed()']])
  endif
  if index(['threads', 'pending'], a:role) >= 0
    call add(actions, ['delete-pending-comment', 'DeletePendingComment', '', 'DeletePendingComment()'])
  endif
  if index(['threads', 'conversation'], a:role) >= 0
    call add(actions, ['delete-message', 'DeleteMessage', '', 'DeleteMessage()'])
    call add(actions, ['message-history', 'MessageHistory', '', 'MessageHistory()'])
    call add(actions, ['mark-read', 'MarkRead', '', 'MarkRead()'])
    call add(actions, ['edit-message', 'EditMessage', '', 'EditMessage()'])
    call add(actions, ['reactions', 'Reactions', '', 'Reactions()'])
    call extend(actions, [['actions', 'Actions', 'a', 'MessageActions()'], ['quote', 'Quote', 'Q', 'Quote(0)'],
          \ ['copy-message', 'CopyMessage', 'gy', 'CopyMessage(0, v:register)'],
          \ ['copy-link', 'CopyLink', '', 'CopyMessage(1, v:register)'],
          \ ['open-link', 'OpenLink', 'gx', 'OpenLink()'],
          \ ['body-links', 'BodyLinks', '', 'BodyLinks()'], ['body-urls', 'BodyURLs', '', 'BodyLinks(1)'],
          \ ['quote-attributed', 'QuoteAttributed', '', 'Quote(0, 0, 0, 1)'],
          \ ['next-message', 'NextMessage', ']m', 'NextMessage(1)'],
          \ ['previous-message', 'PreviousMessage', '[m', 'NextMessage(-1)']])
  endif
  if index(['threads', 'base', 'head'], a:role) >= 0
    call add(actions, ['reply-pending', 'ReplyPending', '', 'Reply(1)'])
    call add(actions, ['mark-thread-read', 'MarkThreadRead', '', 'MarkThreadRead()'])
    call extend(actions, [['resolve', 'Resolve', '', 'ChangeThreadState(1)'], ['reopen', 'Reopen', '', 'ChangeThreadState(0)']])
    call add(actions, ['check-thread-state', 'CheckThreadState', '', 'CheckThreadState()'])
  endif
  if a:role ==# 'threads'
    call add(actions, ['apply-suggestion', 'ApplySuggestion', '', 'ApplySuggestion()'])
  endif
  if index(['draft', 'batch'], a:role) >= 0
    call add(actions, ['check-receipt', 'CheckReceipt', '', 'CheckReceipt()'])
    call add(actions, ['draft-comparison', 'DraftComparison', '', 'DraftComparison()'])
  endif
  for action in actions
    let [id, name, default, invocation] = action
    let command = 'Revue' . name
    execute 'command! -buffer ' . command . ' call revue#session#' . invocation
    if id ==# 'copy-message' || id ==# 'copy-link'
      execute 'command! -buffer -register ' . command . ' call revue#session#CopyMessage(' . (id ==# 'copy-link' ? 1 : 0) . ', <q-reg>)'
    elseif id ==# 'copy-receipt'
      command! -buffer -register RevueCopyReceipt call revue#session#CopyReceipt(<q-reg>)
    elseif id ==# 'copy-comparison'
      command! -buffer -register RevueCopyComparison call revue#session#CopyComparison(<q-reg>)
    elseif id ==# 'discussions'
      command! -buffer -nargs=* RevueDiscussions call revue#session#Discussions(<q-args>)
    elseif id ==# 'range-start'
      command! -buffer -nargs=? RevueRangeStart call revue#session#RangeEndpoint('from', <q-args>)
    elseif id ==# 'range-end'
      command! -buffer -nargs=? RevueRangeEnd call revue#session#RangeEndpoint('to', <q-args>)
    elseif id ==# 'file-filter'
      command! -buffer -nargs=* -complete=customlist,revue#discovery#CompleteFile RevueFileFilter call revue#session#Filter('file', <q-args>)
    elseif id ==# 'discussion-filter'
      command! -buffer -nargs=* -complete=customlist,revue#discovery#CompleteDiscussion RevueDiscussionFilter call revue#session#Filter('discussion', <q-args>)
    elseif id ==# 'reanchor-here'
      command! -buffer -range RevueReanchorHere call revue#session#ReanchorHere(0, <line1>, <line2>)
    elseif id ==# 'comment'
      command! -buffer -range RevueComment call revue#session#Comment(0, <line1>, <line2>)
    elseif id ==# 'suggest'
      command! -buffer -range RevueSuggest call revue#session#Suggest(0, <line1>, <line2>)
    elseif id ==# 'capture'
      command! -buffer -nargs=? -bang RevueCapture call revue#session#Capture(<bang>0, <q-args>)
    elseif id ==# 'publish-pending'
      command! -buffer -nargs=? RevuePublishPending call revue#session#PublishPending(<q-args>)
    elseif id ==# 'quote-attributed'
      command! -buffer -range RevueQuoteAttributed call revue#session#Quote(<range> ? 2 : 0, <line1>, <line2>, 1)
    elseif id ==# 'quote'
      command! -buffer -range RevueQuote call revue#session#Quote(<range> ? 2 : 0, <line1>, <line2>)
    endif
    call add(b:revue_commands, command)
    let plug = '<Plug>(revue-' . id . ')'
    let rhs = '<Cmd>call revue#session#' . invocation . '<CR>'
    call s:Map('n', plug, rhs, 1)
    let key = get(get(g:, 'revue_mappings', {}), id, get(g:, 'revue_no_default_mappings', 0) ? '' : default)
    if !empty(key) | call s:Map('n', key, plug, 0) | endif
    call add(b:revue_bindings, {'key': key, 'plug': plug, 'command': command, 'id': id})
    if id ==# 'reanchor-here'
      call s:Map('x', plug, ':<C-U>call revue#session#ReanchorHere(1)<CR>', 1)
      if !empty(key) | call s:Map('x', key, plug, 0) | endif
    elseif id ==# 'comment'
      call s:Map('x', plug, ':<C-U>call revue#session#Comment(1)<CR>', 1)
      if !empty(key) | call s:Map('x', key, plug, 0) | endif
    elseif id ==# 'suggest'
      call s:Map('x', plug, ':<C-U>call revue#session#Suggest(1)<CR>', 1)
      if !empty(key) | call s:Map('x', key, plug, 0) | endif
    elseif id ==# 'quote-attributed'
      call s:Map('x', plug, ':<C-U>call revue#session#Quote(1, 0, 0, 1)<CR>', 1)
      if !empty(key) | call s:Map('x', key, plug, 0) | endif
    elseif id ==# 'quote'
      call s:Map('x', plug, ':<C-U>call revue#session#Quote(1)<CR>', 1)
      if !empty(key) | call s:Map('x', key, plug, 0) | endif
    elseif id ==# 'send'
      call s:Map('i', plug, '<Esc>' . rhs, 1)
      if !empty(key) | call s:Map('i', key, plug, 0) | endif
    endif
  endfor
endfunction

function! s:Map(mode, key, rhs, noremap) abort
  execute a:mode . (a:noremap ? 'noremap' : 'map') . ' <silent><buffer> ' . a:key . ' ' . a:rhs
  call add(b:revue_owned_maps, {'mode': a:mode, 'key': a:key, 'rhs': a:rhs})
endfunction

function! revue#maps#Help() abort
  return map(copy(get(b:, 'revue_bindings', [])), {_, a -> printf('%-14s :%-25s %s', empty(a.key) ? '(unmapped)' : a.key, a.command, a.plug)})
endfunction
