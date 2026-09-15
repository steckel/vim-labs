" Backend-owned action rules. Missing v1 metadata retains legacy behavior.
function! revue#capabilities#Rule(snapshot, draft) abort
  let kind = get(a:draft, 'kind', '')
  if kind ==# 'service_viewed'
    let error = revue#service_progress#Error(a:snapshot, a:draft)
    return {'enabled': empty(error), 'body_required': 0, 'reason': error}
  endif
  if kind ==# 'apply_suggestion'
    let error = revue#apply_suggestion#Validate(a:snapshot, a:draft, a:draft)
    return {'enabled': empty(error), 'body_required': 0, 'reason': error}
  endif
  let rules = get(a:snapshot, 'capabilities', {})
  let rule = {'enabled': 1, 'body_required': 1, 'reason': ''}
  if kind ==# 'participant_run'
    let error = revue#runtime#Error(a:snapshot, a:draft)
    return {'enabled': empty(error), 'body_required': 0, 'reason': error}
  endif
  if kind ==# 'cancel_assignment'
    let error = revue#assignment#CancelError(a:snapshot, a:draft)
    return {'enabled': empty(error), 'body_required': 0, 'reason': error}
  endif
  if kind ==# 'assignment'
    let error = revue#assignment#Error(a:snapshot, a:draft)
    return {'enabled': empty(error), 'body_required': 0, 'reason': error}
  endif
  if kind ==# 'start_pending' || !empty(get(a:draft, 'pending_mode', ''))
    let private = get(rules, kind ==# 'start_pending' ? 'start_pending' : 'save_pending', {})
    if !get(private, 'enabled', 0) | return {'enabled': 0, 'body_required': 0, 'reason': get(private, 'reason', 'This backend does not support this private-save action.')} | endif
    if kind !=# 'start_pending' && index(get(private, 'kinds', []), kind) < 0
      return {'enabled': 0, 'body_required': 1, 'reason': 'This kind of feedback cannot be added to a pending review here.'}
    endif
    let error = revue#pending#SaveError(a:snapshot, a:draft)
    if !empty(error) | return {'enabled': 0, 'body_required': 0, 'reason': error} | endif
  endif
  if kind ==# 'delete_message'
    if !get(get(rules, kind, {}), 'enabled', 0) | return {'enabled': 0, 'body_required': 0, 'reason': 'Published message deletion is unavailable.'} | endif
    let error = revue#delete_message#Error(a:snapshot, a:draft)
    return {'enabled': empty(error), 'body_required': 0, 'reason': error}
  endif
  if kind ==# 'delete_pending_comment'
    if !get(get(rules, kind, {}), 'enabled', 0) | return {'enabled': 0, 'body_required': 0, 'reason': 'Individual private comment deletion is unavailable.'} | endif
    let error = revue#delete#Error(a:snapshot, a:draft)
    return {'enabled': empty(error), 'body_required': 0, 'reason': error}
  endif
  if kind ==# 'discard_pending' && !has_key(rules, kind)
    return {'enabled': 0, 'body_required': 0, 'reason': 'This backend does not support discarding native pending reviews.'}
  endif
  if kind ==# 'submit_pending' && !has_key(rules, kind)
    return {'enabled': 0, 'body_required': 1, 'reason': 'This backend does not support publishing native pending reviews.'}
  endif
  if kind ==# 'reaction' && !has_key(rules, kind)
    return {'enabled': 0, 'body_required': 0, 'reason': 'This backend does not support reactions.'}
  endif
  if kind ==# 'edit' && !has_key(rules, kind)
    return {'enabled': 0, 'body_required': 1, 'reason': 'This backend does not support editing published messages.'}
  endif
  if kind ==# 'capture' && !has_key(rules, kind)
    return {'enabled': 0, 'body_required': 0, 'reason': 'This backend does not support capturing a new local revision.'}
  endif
  if kind ==# 'file_comment' && !has_key(rules, kind)
    return {'enabled': 0, 'body_required': 1, 'reason': 'This backend does not support file comments. Use :RevueConversation then :RevueNewConversation for review-wide feedback.'}
  endif
  if has_key(a:snapshot, 'capabilities')
    let rule = extend(rule, get(rules, kind, {'enabled': 0, 'reason': 'This backend does not support ' . kind . '.'}))
  endif
  if kind ==# 'reply' && !empty(get(a:draft, 'pending_mode', ''))
    " Private delivery has its own capability and thread permission.
    let rule = {'enabled': 1, 'body_required': 1, 'reason': ''}
  endif
  if kind ==# 'thread_state' && !has_key(rules, kind)
    return {'enabled': 0, 'body_required': 0, 'reason': 'This backend does not support thread resolution.'}
  endif
  if kind ==# 'discard_pending'
    let error = revue#pending#Error(a:snapshot, a:draft)
    if !empty(error) | return {'enabled': 0, 'body_required': 0, 'reason': error} | endif
    let rule.body_required = 0
  elseif kind ==# 'submit_pending'
    let error = revue#pending#Error(a:snapshot, a:draft)
    if !empty(error) | return {'enabled': 0, 'body_required': 1, 'reason': error} | endif
    let actions = filter(copy(get(a:snapshot, 'review_actions', [])), {_, r -> r.id ==# get(a:draft, 'event', '')})
    if empty(actions) || !get(actions[0], 'enabled', 1)
      return {'enabled': 0, 'body_required': 1, 'reason': empty(actions) ? 'Review decision unavailable.' : get(actions[0], 'reason', 'Review decision unavailable.')}
    endif
    let rule.body_required = get(actions[0], 'body_required', 1) && empty(revue#pending#Find(a:snapshot, a:draft.pending_review).comments)
  elseif kind ==# 'reaction'
    let error = revue#reaction#Error(a:snapshot, a:draft)
    if !empty(error) | return {'enabled': 0, 'body_required': 0, 'reason': error} | endif
  elseif kind ==# 'edit'
    let error = revue#edit#Error(a:snapshot, a:draft)
    if !empty(error) | return {'enabled': 0, 'body_required': 1, 'reason': error} | endif
    let rule.body_required = get(get(get(revue#edit#Message(a:snapshot, a:draft), 'capabilities', {}), 'edit', {}), 'body_required', rule.body_required)
  elseif kind ==# 'review'
    let matches = filter(copy(get(a:snapshot, 'review_actions', [])), {_, action -> action.id ==# get(a:draft, 'event', '')})
    if empty(matches)
      return {'enabled': 0, 'body_required': 1, 'reason': 'This review decision is no longer available.'}
    endif
    let action = matches[0]
    let rule.body_required = get(action, 'body_required', rule.body_required)
    if !get(action, 'enabled', 1)
      let rule.enabled = 0
      let rule.reason = get(action, 'reason', 'This review decision is unavailable.')
    endif
  elseif kind ==# 'reply' || kind ==# 'thread_state'
    let threads = filter(copy(get(a:snapshot, 'threads', [])), {_, t -> t.id ==# get(a:draft, 'thread', '')})
    if empty(threads)
      return {'enabled': 0, 'body_required': 1, 'reason': 'This thread is no longer available.'}
    endif
    let private_reply = kind ==# 'reply' && !empty(get(a:draft, 'pending_mode', ''))
    let action = kind ==# 'reply' ? (private_reply ? 'pending_reply' : 'reply') : get(a:draft, 'resolved', 0) ? 'resolve' : 'reopen'
    if kind ==# 'thread_state' && !has_key(threads[0], 'resolved')
      return {'enabled': 0, 'body_required': 0, 'reason': 'Thread resolution state is unavailable. Refresh or inspect the provider.'}
    endif
    let target_rule = get(get(threads[0], 'capabilities', {}), action, kind ==# 'reply' && !private_reply ? {} : {'enabled': 0, 'reason': 'This thread does not offer ' . action . '.'})
    if !get(target_rule, 'enabled', 1)
      let rule.enabled = 0
      let rule.reason = get(target_rule, 'reason', 'This action is unavailable on this thread.')
    endif
  endif
  return rule
endfunction

function! revue#capabilities#Error(snapshot, draft, body) abort
  let rule = revue#capabilities#Rule(a:snapshot, a:draft)
  if !rule.enabled | return empty(rule.reason) ? 'This action is unavailable.' : rule.reason | endif
  if get(a:draft, 'suggestion', 0)
    let error = revue#suggestion#Error(a:snapshot, a:draft, a:body)
    if !empty(error) | return error | endif
  endif
  if a:body && rule.body_required && empty(trim(get(a:draft, 'body', '')))
    return 'Write a message first.'
  endif
  return ''
endfunction
