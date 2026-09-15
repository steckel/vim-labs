vim9script
import './model.vim' as M

var sets: dict<dict<any>> = {}
var order: list<string> = []
var sequence = 0

def ApplyText(lines: list<string>): dict<any>
  var old = getline(1, '$')
  if lines == old
    return {changed: false, undo_sequence: undotree().seq_cur}
  endif
  if !&modifiable || &readonly || &buftype != ''
    throw 'buffer_not_writable'
  endif
  if &undolevels < 0
    throw 'undo_disabled'
  endif
  var prefix = 0
  while prefix < min([len(old), len(lines)]) && old[prefix] == lines[prefix]
    prefix += 1
  endwhile
  var suffix = 0
  while suffix < min([len(old), len(lines)]) - prefix && old[len(old) - 1 - suffix] == lines[len(lines) - 1 - suffix]
    suffix += 1
  endwhile
  var oldcount = len(old) - prefix - suffix
  var newcount = len(lines) - prefix - suffix
  var common = min([oldcount, newcount])
  var did = false
  &g:undolevels = &g:undolevels
  try
    if common > 0
      if setline(prefix + 1, lines[prefix : prefix + common - 1]) != 0
        throw 'write_failed'
      endif
      did = true
    endif
    if newcount > common
      if did
        undojoin
      endif
      if append(prefix + common, lines[prefix + common : prefix + newcount - 1]) != 0
        throw 'append_failed'
      endif
      did = true
    endif
    if oldcount > common
      if did
        undojoin
      endif
      if deletebufline(bufnr(), prefix + common + 1, prefix + oldcount) != 0
        throw 'delete_failed'
      endif
    endif
    if getline(1, '$') != lines
      throw 'verification_failed'
    endif
  finally
    &g:undolevels = &g:undolevels
  endtry
  return {changed: true, undo_sequence: undotree().seq_cur}
enddef

def Render(before: list<string>, edits: list<dict<any>>): list<string>
  var text = join(before, "\n")
  var previous = strlen(text) + 1
  for edit in reverse(copy(edits))
    if edit.last > previous
      throw 'overlapping_edits'
    endif
    var expected = strpart(text, edit.first, edit.last - edit.first)
    if has_key(edit, 'expected') && expected != edit.expected
      throw 'expected_text_mismatch'
    endif
    text = strpart(text, 0, edit.first) .. edit.text .. strpart(text, edit.last)
    previous = edit.first
  endfor
  var result = split(text, "\n", true)
  return empty(result) ? [''] : result
enddef

export def Prepare(args: dict<any>): dict<any>
  if empty(args.changes)
    throw 'empty_change_set'
  endif
  sequence += 1
  var id = 'change-' .. sequence
  var changes: list<dict<any>> = []
  var seen: dict<bool> = {}
  var bytes = 0
  for input in args.changes
    if has_key(seen, input.buffer)
      throw 'duplicate_buffer: combine edits for one buffer'
    endif
    seen[input.buffer] = true
    var n = M.Resolve(input.buffer)
    M.Check(n, input.revision)
    var before = M.ReadAll(n)
    var edits: list<dict<any>> = []
    var index = 0
    for inputedit in input.edits
      var first = M.PositionOffset(before, inputedit.start)
      var last = M.PositionOffset(before, inputedit.end)
      if first > last
        throw 'invalid_range'
      endif
      index += 1
      var edit = extend(copy(inputedit), {first: first, last: last, hunk: input.buffer .. ':' .. index})
      add(edits, edit)
    endfor
    sort(edits, (a, b) => a.first - b.first)
    for i in range(1, len(edits) - 1)
      if edits[i].first == edits[i - 1].first || edits[i].first < edits[i - 1].last
        throw 'overlapping_edits'
      endif
    endfor
    var after = Render(before, edits)
    bytes += strlen(join(before, "\n")) + strlen(join(after, "\n"))
    if bytes > 4000000
      throw 'change_set_too_large'
    endif
    add(changes, {buffer: input.buffer, revision: input.revision, path: bufname(n), before: before, after: after, edits: edits, state: 'prepared'})
  endfor
  sets[id] = {change_id: id, title: get(args, 'title', 'Agent changes'), changes: changes, bytes: bytes}
  add(order, id)
  var total = 0
  for value in values(sets)
    total += value.bytes
  endfor
  while len(order) > 32 || total > 16000000
    var removed = remove(sets, remove(order, 0))
    total -= removed.bytes
  endwhile
  return deepcopy(sets[id])
enddef

export def Get(id: string): dict<any>
  if !has_key(sets, id)
    throw 'change_not_found: expired or unknown preview'
  endif
  return sets[id]
enddef

export def Apply(args: dict<any>): dict<any>
  var set = Get(args.change_id)
  var selected: list<string> = get(args, 'hunks', [])
  var known = flattennew(map(copy(set.changes), (_, c) => map(copy(c.edits), (_, e) => e.hunk)))
  if has_key(args, 'hunks') && empty(selected)
    throw 'empty_hunks'
  endif
  for hunk in selected
    if index(known, hunk) < 0
      throw 'unknown_hunk'
    endif
  endfor
  var work: list<dict<any>> = []
  for change in set.changes
    var edits = filter(copy(change.edits), (_, e) => empty(selected) || index(selected, e.hunk) >= 0)
    if empty(edits)
      continue
    endif
    if change.state != 'prepared'
      throw 'already_applied: prepare a new change set'
    endif
    var n = M.Resolve(change.buffer)
    M.Check(n, change.revision)
    if !getbufvar(n, '&modifiable') || getbufvar(n, '&readonly') || getbufvar(n, '&buftype') != ''
      throw 'buffer_not_writable'
    endif
    add(work, {bufnr: n, change: change, after: Render(change.before, edits)})
  endfor
  var results: list<dict<any>> = []
  for item in work
    try
      M.Check(item.bufnr, item.change.revision)
      var after: list<string> = item.after
      var result = M.InBuffer(item.bufnr, () => ApplyText(after))
      item.change.state = 'applied'
      item.change.applied_revision = M.Revision(item.bufnr)
      item.change.undo_sequence = result.undo_sequence
      item.change.changed = result.changed
      add(results, {buffer: item.change.buffer, ok: true, revision: item.change.applied_revision, changed: result.changed, undo_sequence: result.undo_sequence})
      M.Event('changed', item.bufnr)
    catch
      item.change.state = 'failed'
      add(results, {buffer: item.change.buffer, ok: false, message: v:exception, outcome: 'inspect_buffer'})
      return {ok: false, code: 'partial_application', results: results}
    endtry
  endfor
  return {ok: true, change_id: args.change_id, results: results}
enddef

def UndoCurrent(change: dict<any>): dict<any>
  if undotree().seq_cur != change.undo_sequence
    throw 'undo_history_changed'
  endif
  silent undo
  if getline(1, '$') != change.before
    throw 'undo_verification_failed'
  endif
  return {ok: true}
enddef

export def Undo(args: dict<any>): dict<any>
  var set = Get(args.change_id)
  for change in set.changes
    if change.buffer == args.buffer
      if change.state != 'applied' || !change.changed
        throw 'not_undoable'
      endif
      var n = M.Resolve(args.buffer)
      M.Check(n, change.applied_revision)
      var result = M.InBuffer(n, () => UndoCurrent(change))
      change.state = 'undone'
      return extend(result, {revision: M.Revision(n)})
    endif
  endfor
  M.Fail('buffer_not_in_change_set')
  return {}
enddef

export def Review(args: dict<any>): dict<any>
  var set = Get(args.change_id)
  var change = set.changes[0]
  for item in set.changes
    if item.buffer == get(args, 'buffer', '')
      change = item
    endif
  endfor
  M.Check(M.Resolve(change.buffer), change.revision)
  tabnew
  setlocal buftype=nofile bufhidden=wipe noswapfile
  setline(1, change.before)
  execute 'file ' .. fnameescape('[MCP before ' .. args.change_id .. ']')
  setlocal nomodifiable
  diffthis
  vnew
  setlocal buftype=nofile bufhidden=wipe noswapfile
  setline(1, change.after)
  execute 'file ' .. fnameescape('[MCP after ' .. args.change_id .. ']')
  setlocal nomodifiable
  diffthis
  return {ok: true, change_id: args.change_id, buffer: change.buffer}
enddef

export def Search(args: dict<any>): dict<any>
  var findings: list<dict<any>> = []
  var limit: number = get(args, 'limit', 100)
  var pattern: string = get(args, 'regex', false) ? args.query : '\V' .. escape(args.query, '\')
  for target in args.targets
    var range = M.Range(target)
    var offset = 0
    while offset <= strlen(range.text)
      # The fourth argument keeps ^ anchored to the original string rather
      # than interpreting each new offset as a fresh string beginning.
      var match = matchstrpos(range.text, pattern, offset, 1)
      if match[1] < 0
        break
      endif
      var first = range.first + match[1]
      var last = range.first + match[2]
      add(findings, {location: M.Target(range.bufnr, M.OffsetPosition(range.lines, first), M.OffsetPosition(range.lines, last)), message: strpart(match[0], 0, 500), source: 'vim-search'})
      if len(findings) >= limit
        return {findings: findings, truncated: true}
      endif
      offset = match[2] > match[1] ? match[2] : match[2] + max([1, strlen(matchstr(strpart(range.text, match[2]), '^.'))])
    endwhile
  endfor
  return {findings: findings, truncated: false}
enddef

export def Transform(args: dict<any>): dict<any>
  var grouped: dict<dict<any>> = {}
  for target in args.targets
    var range = M.Range(target)
    var text: string = range.text
    var op: string = args.operation
    if op == 'substitute'
      if !has_key(args, 'query') || empty(args.query)
        throw 'query_required'
      endif
      var replacement: string = get(args, 'replacement', '')
      if stridx(replacement, '\=') == 0
        throw 'expression_replacement_disabled'
      endif
      if !get(args, 'regex', false)
        replacement = escape(replacement, '\&~')
      endif
      var pattern: string = get(args, 'regex', false) ? args.query : '\V' .. escape(args.query, '\')
      text = substitute(text, pattern, replacement, 'g')
    elseif op == 'uppercase'
      text = toupper(text)
    elseif op == 'lowercase'
      text = tolower(text)
    elseif op == 'trim'
      text = join(map(split(text, "\n", true), (_, value) => trim(value)), "\n")
    elseif op == 'sort_lines'
      text = join(sort(split(text, "\n", true)), "\n")
    endif
    if !has_key(grouped, target.buffer)
      grouped[target.buffer] = {buffer: target.buffer, revision: target.revision, edits: []}
    endif
    add(grouped[target.buffer].edits, {start: target.start, end: target.end, text: text, expected: range.text})
  endfor
  return Prepare({changes: values(grouped), title: 'Transform: ' .. args.operation})
enddef

defcompile
