vim9script

var session = ''
var serial = 0
var identities: dict<string> = {}
var disk: dict<string> = {}
var events: list<dict<any>> = []
var cursor = 0
var selection: dict<any> = {}
var history: list<dict<any>> = []
const MAX_BYTES = 2000000

# Early Vim9 requires a return after a throw; later Vim9 rejects that return
# as unreachable. A void helper keeps both compilers happy.
export def Fail(message: string)
  throw message
enddef

export def SetSession(value: string)
  session = value
enddef

export def Session(): string
  return session
enddef

export def DiskStamp(name: string): string
  if empty(name) || !filereadable(name)
    return 'missing'
  endif
  if getfsize(name) > MAX_BYTES
    return 'large:' .. getftime(name) .. ':' .. getfsize(name)
  endif
  return sha256(join(readfile(name, 'b'), "\n"))
enddef

export def Identity(n: number): string
  if !bufexists(n)
    throw 'buffer_not_found'
  endif
  var key = string(n)
  if !has_key(identities, key)
    serial += 1
    identities[key] = printf('b%d-%d', n, serial)
    disk[identities[key]] = DiskStamp(fnamemodify(bufname(n), ':p'))
  endif
  return identities[key]
enddef

export def Forget(n: number)
  var key = string(n)
  if has_key(identities, key)
    var id = remove(identities, key)
    if has_key(disk, id)
      remove(disk, id)
    endif
  endif
enddef

export def Resolve(id: string): number
  for [key, value] in items(identities)
    if value == id && bufloaded(str2nr(key))
      return str2nr(key)
    endif
  endfor
  Fail('buffer_not_found: buffer was unloaded or replaced')
  return -1
enddef

export def Revision(n: number): string
  return Identity(n) .. ':' .. getbufvar(n, 'changedtick')
enddef

export def Check(n: number, revision: string)
  if Revision(n) != revision
    throw 'stale_revision: reread the live buffer'
  endif
enddef

export def ReadAll(n: number): list<string>
  if !bufloaded(n)
    throw 'buffer_not_loaded'
  endif
  if getbufinfo(n)[0].linecount > 50000
    throw 'too_large: buffer exceeds 50000 lines'
  endif
  var lines = getbufline(n, 1, '$')
  if strlen(join(lines, "\n")) > MAX_BYTES
    throw 'too_large: buffer exceeds 2 MB'
  endif
  if getbufvar(n, '&binary')
    throw 'binary_buffer_unsupported'
  endif
  for text in lines
    if stridx(text, "\n") >= 0
      throw 'binary_buffer_unsupported'
    endif
  endfor
  return lines
enddef

export def Describe(n: number): dict<any>
  return {buffer: Identity(n), revision: Revision(n), name: bufname(n), path: empty(bufname(n)) ? '' : fnamemodify(bufname(n), ':p'), modified: !!getbufvar(n, '&modified'), loaded: !!bufloaded(n), filetype: getbufvar(n, '&filetype'), line_count: getbufinfo(n)[0].linecount}
enddef

export def Snapshot(args: dict<any>): dict<any>
  var n = Resolve(args.buffer)
  var first: number = get(args, 'start_line', 1)
  var count: number = get(args, 'limit', 200)
  var lines = getbufline(n, first, first + count - 1)
  var bytes = 0
  var bounded: list<string> = []
  for text in lines
    if bytes + strlen(text) > 1000000
      if empty(bounded)
        throw 'line_too_large'
      endif
      break
    endif
    add(bounded, text)
    bytes += strlen(text)
  endfor
  var info = Describe(n)
  return extend(info, {lines: bounded, start_line: first, next_line: first + len(bounded) <= info.line_count ? first + len(bounded) : 0})
enddef

export def PositionOffset(lines: list<string>, pos: dict<any>): number
  var lnum: number = pos.line
  var byte: number = pos.byte
  if lnum == len(lines) + 1 && byte == 0
    return strlen(join(lines, "\n"))
  endif
  if lnum < 1 || lnum > len(lines) || byte < 0 || byte > strlen(lines[lnum - 1])
    throw 'invalid_range'
  endif
  var text = lines[lnum - 1]
  if byte < strlen(text) && byteidxcomp(text, charidx(text, byte, true)) != byte
    throw 'invalid_byte_boundary'
  endif
  var offset = byte
  if lnum > 1
    for line in lines[0 : lnum - 2]
      offset += strlen(line) + 1
    endfor
  endif
  return offset
enddef

export def OffsetPosition(lines: list<string>, offset: number): dict<number>
  var remaining = offset
  for i in range(len(lines))
    if remaining <= strlen(lines[i])
      return {line: i + 1, byte: remaining}
    endif
    remaining -= strlen(lines[i]) + 1
  endfor
  return {line: len(lines), byte: strlen(lines[-1])}
enddef

export def Target(n: number, start: dict<any>, finish: dict<any>): dict<any>
  return {buffer: Identity(n), revision: Revision(n), start: start, end: finish}
enddef

export def Range(target: dict<any>): dict<any>
  var n = Resolve(target.buffer)
  Check(n, target.revision)
  var lines = ReadAll(n)
  var first = PositionOffset(lines, target.start)
  var last = PositionOffset(lines, target.end)
  if first > last
    throw 'invalid_range'
  endif
  return {bufnr: n, lines: lines, first: first, last: last, text: strpart(join(lines, "\n"), first, last - first)}
enddef

export def Event(kind: string, n: number)
  cursor += 1
  var value: dict<any> = {cursor: cursor, kind: kind, bufnr: n}
  if bufloaded(n)
    try
      value.buffer = Identity(n)
      value.revision = Revision(n)
    catch
      value.error = v:exception
    endtry
  endif
  add(events, value)
  if len(events) > 256
    remove(events, 0)
  endif
enddef

export def Events(after: number): dict<any>
  return {cursor: cursor, gap: !empty(events) && after < events[0].cursor - 1, events: filter(copy(events), (_, e) => e.cursor > after)}
enddef

export def Record(id: string, method: string, result: dict<any>)
  add(history, {request_id: id, method: method, ok: get(result, 'ok', false), code: get(result, 'code', ''), timestamp: localtime()})
  if len(history) > 100
    remove(history, 0)
  endif
enddef

export def History(): list<dict<any>>
  return copy(history)
enddef

export def CaptureSelection()
  var n = bufnr()
  var first = getpos("'<")
  var last = getpos("'>")
  var kind = visualmode()
  var lines = ReadAll(n)
  var targets: list<dict<any>> = []
  if first[1] < 1 || last[1] < 1
    throw 'no_selection'
  endif
  if kind == 'V'
    add(targets, Target(n, {line: first[1], byte: 0}, {line: last[1], byte: strlen(lines[last[1] - 1])}))
  elseif kind == "\<C-V>"
    var lo = min([virtcol("'<"), virtcol("'>")])
    var hi = max([virtcol("'<"), virtcol("'>")])
    if &selection == 'exclusive' && hi > lo
      hi -= 1
    endif
    var exact = true
    var display: list<string> = []
    for lnum in range(first[1], last[1])
      var startcol = virtcol2col(0, lnum, lo)
      var endcol = virtcol2col(0, lnum, hi)
      var line = lines[lnum - 1]
      var startbyte = max([0, min([startcol - 1, strlen(line)])])
      var endbyte = max([0, min([endcol - 1, strlen(line)])])
      endbyte += strlen(matchstr(strpart(line, endbyte), '^.'))
      var width = strdisplaywidth(line)
      if width < lo
        startbyte = strlen(line)
        endbyte = startbyte
      endif
      if width < hi || (startbyte < strlen(line) && virtcol([lnum, startbyte + 1], true)[0] != lo) || (endbyte > 0 && virtcol([lnum, max([1, endcol])], true)[1] != hi)
        exact = false
      endif
      var text = ''
      var cell = 1
      for char in split(line, '\zs')
        var size = strdisplaywidth(char, cell - 1)
        var overlap = min([cell + size - 1, hi]) - max([cell, lo]) + 1
        if overlap > 0
          text ..= overlap == size && char != "\t" ? char : repeat(' ', overlap)
        endif
        cell += size
      endfor
      if cell <= hi
        text ..= repeat(' ', hi - max([cell, lo]) + 1)
      endif
      add(display, text)
      add(targets, Target(n, {line: lnum, byte: startbyte}, {line: lnum, byte: endbyte}))
    endfor
    selection = {shape: 'block', targets: exact ? targets : [], covering_targets: targets, editable: exact, virtual_start: lo, virtual_end_inclusive: hi, text: display}
  else
    var endbyte = min([last[2] - 1, strlen(lines[last[1] - 1])])
    if &selection != 'exclusive'
      endbyte += strlen(matchstr(strpart(lines[last[1] - 1], endbyte), '^.'))
    endif
    add(targets, Target(n, {line: first[1], byte: first[2] - 1}, {line: last[1], byte: endbyte}))
  endif
  if kind != "\<C-V>"
    selection = {shape: kind == 'V' ? 'line' : 'character', targets: targets, editable: true}
  endif
  if exists('*getregion')
    selection.text = call('getregion', [first, last, {type: kind}])
  elseif kind != "\<C-V>"
    selection.text = flattennew(map(copy(targets), (_, target) => split(Range(target).text, "\n", true)))
    if empty(selection.text)
      selection.text = ['']
    endif
  endif
  selection.raw_start = first
  selection.raw_end = last
  selection.selection_option = &selection
  selection.tabstop = &tabstop
  selection.session = session
  Event('selection', n)
enddef

export def Context(args: dict<any>): dict<any>
  var buffers: list<dict<any>> = []
  for item in getbufinfo({'bufloaded': 1})
    if getbufvar(item.bufnr, '&buftype') == ''
      add(buffers, Describe(item.bufnr))
    endif
  endfor
  var offset: number = get(args, 'offset', 0)
  var limit: number = get(args, 'limit', 50)
  var current = Describe(bufnr())
  return {session: session, cwd: getcwd(), mode: mode(true), current: current, cursor: {line: line('.'), byte: col('.') - 1}, context: Snapshot({buffer: current.buffer, start_line: max([1, line('.') - 10]), limit: 21}), buffers: buffers[offset : offset + limit - 1], next_offset: offset + limit < len(buffers) ? offset + limit : -1, windows: map(getwininfo(), (_, w) => ({id: w.winid, bufnr: w.bufnr, tab: w.tabnr, first_line: w.topline, last_line: w.botline})), selection: deepcopy(selection), event_cursor: cursor}
enddef

export def RefreshDisk(n: number)
  disk[Identity(n)] = DiskStamp(fnamemodify(bufname(n), ':p'))
enddef

export def CheckDisk(n: number)
  if getfsize(fnamemodify(bufname(n), ':p')) > MAX_BYTES
    throw 'too_large: saving files above 2 MB requires manual Vim save'
  endif
  if DiskStamp(fnamemodify(bufname(n), ':p')) != get(disk, Identity(n), 'unknown')
    throw 'external_file_changed: reread/reconcile the file before saving'
  endif
enddef

export def InBuffer(n: number, Fn: func(): any): any
  var old = bufnr()
  var oldHidden = getbufvar(old, '&bufhidden')
  var targetHidden = getbufvar(n, '&bufhidden')
  var view = winsaveview()
  var search = getreg('/')
  var result: any
  try
    if n != old
      # Reviewing a diff uses wipe-on-hide scratch buffers. A background edit
      # must not destroy the currently displayed review (or a hidden target).
      setbufvar(old, '&bufhidden', 'hide')
      setbufvar(n, '&bufhidden', 'hide')
      execute 'noautocmd keepalt keepjumps hide buffer ' .. n
    endif
    result = Fn()
  finally
    if bufexists(old) && bufnr() != old
      execute 'noautocmd keepalt keepjumps hide buffer ' .. old
    endif
    winrestview(view)
    setreg('/', search)
    if bufexists(old)
      setbufvar(old, '&bufhidden', oldHidden)
    endif
    if n != old && bufexists(n)
      setbufvar(n, '&bufhidden', targetHidden)
    endif
  endtry
  return result
enddef

defcompile
