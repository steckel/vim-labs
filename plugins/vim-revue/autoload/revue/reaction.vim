" Reaction counts and the current actor's state are distinct facts.
function! revue#reaction#Summary(message) abort
  let labels = []
  for item in get(get(a:message, 'reactions', {}), 'items', [])
    if get(item, 'count', 0) > 0
      call add(labels, revue#message#OneLine(get(item, 'label', item.id)) . ' ' . item.count . (get(item, 'mine', 0) ? ' [you]' : ''))
    endif
  endfor
  return empty(labels) ? '' : 'Reactions: ' . join(labels, ' · ')
endfunction

function! revue#reaction#Valid(data) abort
  if type(a:data) != v:t_dict || type(get(a:data, 'items', 0)) != v:t_list || get(a:data, 'complete', 0) != 1 || type(get(a:data, 'actor', 0)) != v:t_string | return 0 | endif
  let seen = {}
  for item in a:data.items
    if type(item) != v:t_dict || type(get(item, 'id', 0)) != v:t_string || empty(item.id) || has_key(seen, item.id) || type(get(item, 'label', 0)) != v:t_string || type(get(item, 'count', '')) != v:t_number || item.count < 0 | return 0 | endif
    if has_key(item, 'mine') && (type(item.mine) != v:t_bool || (item.mine && (item.count == 0 || empty(a:data.actor)))) | return 0 | endif
    if has_key(item, 'members')
      let members = item.members
      if type(members) != v:t_dict || type(get(members, 'items', 0)) != v:t_list || type(get(members, 'unavailable', '')) != v:t_number || members.unavailable < 0 || len(members.items) + members.unavailable != item.count | return 0 | endif
      let people = {}
      for person in members.items
        if type(person) != v:t_dict || type(get(person, 'id', 0)) != v:t_string || empty(person.id) || has_key(people, person.id) || type(get(person, 'label', 0)) != v:t_string || empty(person.label) | return 0 | endif
        let people[person.id] = 1
      endfor
    endif
    let seen[item.id] = 1
  endfor
  return 1
endfunction

function! revue#reaction#Error(snapshot, draft) abort
  let message = revue#edit#Message(a:snapshot, a:draft)
  if empty(message) | return 'The message is no longer available.' | endif
  let rule = get(get(message, 'capabilities', {}), 'reaction', {})
  if !get(rule, 'enabled', 0) | return get(rule, 'reason', 'Reactions are unavailable on this message.') | endif
  if empty(get(a:draft, 'actor', '')) || empty(get(a:draft, 'reaction', '')) || type(get(a:draft, 'present', 0)) != v:t_bool
    return 'Load the reaction chooser to select an explicit reaction and actor.'
  endif
  return ''
endfunction

function! revue#reaction#Pending(session, target, id) abort
  for draft in a:session.drafts
    if draft.kind ==# 'reaction' && draft.message ==# a:target.message && draft.message_kind ==# a:target.message_kind && draft.thread ==# a:target.thread && draft.reaction ==# a:id
      return draft
    endif
  endfor
  return {}
endfunction

" Receipt recovery remains reachable when fresh counts or permissions disappear.
function! revue#reaction#View(session, error) abort
  let target = a:session.reaction_target
  let data = a:session.reaction_data
  let message = revue#edit#Message(a:session.snapshot, target)
  let lines = ['# Reactions' . (empty(message) ? '' : ' · ' . revue#message#Header(message, a:session.snapshot.author)),
        \ target.message_kind . ' message #' . target.message,
        \ empty(a:error) ? 'Actor: ' . revue#message#OneLine(get(data, 'actor_label', get(data, 'actor', ''))) : a:error,
        \ ':RevueReact executes the selected action · :RevueClose returns', '']
  let choices = deepcopy(get(data, 'items', []))
  let ids = map(copy(choices), {_, item -> item.id})
  for draft in a:session.drafts
    if draft.kind ==# 'reaction' && index(ids, draft.reaction) < 0 && !empty(revue#reaction#Pending(a:session, target, draft.reaction))
      call add(choices, {'id': draft.reaction, 'label': draft.reaction_label})
      call add(ids, draft.reaction)
    endif
  endfor
  let rows = {}
  for item in choices
    let pending = revue#reaction#Pending(a:session, target, item.id)
    let known = empty(a:error) && has_key(item, 'mine') && !empty(get(data, 'actor', ''))
    let intent = empty(pending) ? (get(item, 'mine', 0) ? 'Remove' : 'Add') . ' your ' . item.label : (pending.present ? 'Add' : 'Remove') . ' ' . pending.reaction_label . ' as ' . get(pending, 'actor_label', pending.actor)
    let reason = ''
    if !empty(pending) && pending.state ==# 'unknown'
      let label = 'Check outcome · ' . intent . ' (unknown)'
    elseif !empty(pending) && pending.state ==# 'submitting'
      let label = 'Waiting · ' . intent
      let reason = 'This reaction operation is already in progress.'
    else
      let label = empty(pending) ? intent : (pending.state ==# 'failed' ? 'Retry · ' : 'Send saved intent · ') . intent
      let fields = empty(pending) ? extend(deepcopy(target), {'kind': 'reaction', 'actor': get(data, 'actor', ''), 'reaction': item.id, 'present': get(item, 'mine', 0) ? v:false : v:true}) : pending
      let reason = !known ? 'Your current reaction state is unavailable.' : !empty(pending) && pending.actor !=# data.actor ? 'Actor changed; inspect the saved operation in Activity.' : revue#capabilities#Error(a:session.snapshot, fields, 0)
    endif
    let count_text = has_key(item, 'count') ? printf(' · %d%s', item.count, get(item, 'mine', 0) ? ' [you]' : '') : ''
    call add(lines, label . count_text . (empty(reason) ? '' : ' · unavailable'))
    let row = len(lines)
    if known || !empty(pending)
      let rows[string(row)] = extend(deepcopy(item), {'reason': reason, 'action_label': label})
    endif
    if !empty(reason) | call add(lines, '  ' . reason) | endif
  endfor
  if empty(a:error)
    call extend(lines, ['', '## People who reacted', 'As of this read · :RevueReactions reloads'])
    let positive = filter(deepcopy(get(data, 'items', [])), {_, item -> item.count > 0})
    if empty(positive) | call add(lines, 'No reactions.') | endif
    for item in positive
      call add(lines, '')
      call add(lines, revue#message#OneLine(item.label) . ' · ' . item.count)
      if !has_key(item, 'members')
        call add(lines, '  Participant details unavailable.')
        continue
      endif
      for person in item.members.items
        call add(lines, '  ' . revue#message#OneLine(person.label) . (person.id ==# get(data, 'actor', '') ? ' [you]' : ''))
      endfor
      if item.members.unavailable
        call add(lines, printf('  %d account(s) unavailable.', item.members.unavailable))
      endif
    endfor
  endif
  return {'lines': lines, 'rows': rows}
endfunction
