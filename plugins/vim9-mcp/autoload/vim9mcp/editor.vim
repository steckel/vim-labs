vim9script
import './model.vim' as M

var navigation: list<dict<any>> = []
var providers: dict<dict<any>> = {}
var jobs: dict<dict<any>> = {}
var jobSerial = 0

export def Register(name: string, schema: dict<any>, Fn: func(dict<any>): dict<any>, kind: string = 'custom')
  if name !~# '^[a-zA-Z][a-zA-Z0-9_.-]*$'
    throw 'invalid_provider_name'
  endif
  providers[name] = {name: name, inputSchema: schema, Fn: Fn, kind: kind}
enddef

export def Providers(): list<dict<any>>
  return map(values(copy(providers)), (_, p) => ({name: p.name, inputSchema: p.inputSchema, kind: p.kind}))
enddef

export def Invoke(args: dict<any>): dict<any>
  if !has_key(providers, args.provider)
    throw 'provider_unavailable'
  endif
  var provider = providers[args.provider]
  return call(provider.Fn, [args.input])
enddef

export def Navigate(args: dict<any>): dict<any>
  if get(args, 'back', false)
    if empty(navigation)
      throw 'navigation_history_empty'
    endif
    var previous = remove(navigation, -1)
    if !win_gotoid(previous.winid)
      throw 'window_no_longer_exists'
    endif
    var n = M.Resolve(previous.buffer)
    execute 'keepalt keepjumps hide buffer ' .. n
    winrestview(previous.view)
    return {ok: true}
  endif
  if !has_key(args, 'location')
    throw 'location_required'
  endif
  var range = M.Range(args.location)
  add(navigation, {winid: win_getid(), buffer: M.Identity(bufnr()), view: winsaveview()})
  if len(navigation) > 50
    remove(navigation, 0)
  endif
  execute 'keepalt keepjumps hide buffer ' .. range.bufnr
  cursor(args.location.start.line, args.location.start.byte + 1)
  normal! zv
  return {ok: true, location: args.location}
enddef

export def Publish(args: dict<any>): dict<any>
  var entries: list<dict<any>> = []
  for finding in args.findings
    var n = M.Resolve(finding.location.buffer)
    M.Check(n, finding.location.revision)
    var severity: string = get(finding, 'severity', 'info')
    add(entries, {bufnr: n, lnum: finding.location.start.line, col: finding.location.start.byte + 1, end_lnum: finding.location.end.line, end_col: finding.location.end.byte, text: finding.message, type: severity == 'error' ? 'E' : severity == 'warning' ? 'W' : 'I', user_data: finding})
  endfor
  var spec = {title: 'MCP: ' .. args.title, items: entries, context: {owner: 'vim9-mcp', session: M.Session()}}
  var kind: string = get(args, 'kind', 'quickfix')
  if kind == 'location'
    setloclist(0, [], ' ', spec)
    return {ok: true, list_id: getloclist(0, {id: 0}).id, count: len(entries)}
  endif
  setqflist([], ' ', spec)
  return {ok: true, list_id: getqflist({id: 0}).id, count: len(entries)}
enddef

def WriteCurrent(): dict<any>
  if empty(bufname()) || &buftype != '' || &readonly || !&modifiable
    throw 'buffer_not_writable'
  endif
  M.CheckDisk(bufnr())
  silent keepalt write
  M.RefreshDisk(bufnr())
  return {ok: true, revision: M.Revision(bufnr()), modified: !!&modified, path: expand('%:p')}
enddef

export def Save(args: dict<any>): dict<any>
  var n = M.Resolve(args.buffer)
  M.Check(n, args.revision)
  return M.InBuffer(n, () => WriteCurrent())
enddef

export def Open(args: dict<any>): dict<any>
  var n: number
  if get(args, 'unnamed', false)
    n = bufadd('')
  else
    var path: string = get(args, 'path', '')
    if empty(path) || path =~# '^/' || path =~# '\(^\|/\)\.\.\(/\|$\)' || path =~# "[\r\n]"
      throw 'invalid_project_path'
    endif
    var root = resolve(fnamemodify(getcwd(), ':p'))
    var full = resolve(fnamemodify(root .. '/' .. path, ':p'))
    if stridx(full, substitute(root, '/$', '', '') .. '/') != 0
      throw 'path_outside_project'
    endif
    n = bufadd(full)
  endif
  bufload(n)
  setbufvar(n, '&buflisted', 1)
  return M.Describe(n)
enddef

export def Inspect(args: dict<any>): dict<any>
  var kind: string = args.kind
  var query: string = get(args, 'query', '')
  if kind == 'marks'
    return {items: getmarklist(bufnr()) + getmarklist()}
  elseif kind == 'jumps'
    var jumps = getjumplist()
    return {items: jumps[0], index: jumps[1]}
  elseif kind == 'folds'
    var folds: list<dict<any>> = []
    var lnum = line('w0')
    while lnum <= line('w$') && len(folds) < 100
      var finish = foldclosedend(lnum)
      if finish > 0
        add(folds, {location: M.Target(bufnr(), {line: lnum, byte: 0}, {line: finish, byte: strlen(getline(finish))}), level: foldlevel(lnum)})
        lnum = finish + 1
      else
        lnum += 1
      endif
    endwhile
    return {items: folds}
  elseif kind == 'tags'
    if empty(query)
      throw 'query_required'
    endif
    return {items: taglist('\V' .. escape(query, '\'))[: 99]}
  elseif kind == 'mappings'
    var mappings = maplist()
    return {items: filter(mappings, (_, item) => empty(query) || stridx(item.lhs, query) >= 0)[: 99]}
  elseif kind == 'commands'
    return {items: getcompletion(query, 'command')[: 99]}
  elseif kind == 'registers'
    var registers: dict<any> = {}
    for name in split(empty(query) ? 'abcdefghijklmnopqrstuvwxyz' : query, '\zs')
      if name =~# '^[a-z0-9"/+*]$'
        var contents = getreg(name)
        registers[name] = {text: strpart(contents, 0, 4096), type: getregtype(name), truncated: strlen(contents) > 4096}
      endif
    endfor
    return {registers: registers}
  elseif kind == 'options'
    return {options: {filetype: &filetype, encoding: &encoding, fileencoding: &fileencoding, fileformat: &fileformat, tabstop: &tabstop, expandtab: &expandtab, shiftwidth: &shiftwidth, selection: &selection, virtualedit: &virtualedit, undolevels: &undolevels}}
  endif
  M.Fail('unsupported_inspection')
  return {}
enddef

export def Help(topic: string): dict<any>
  var matches = getcompletion(topic, 'help')[: 19]
  if empty(matches)
    return {matches: [], excerpt: []}
  endif
  var tag = matches[0]
  for tags in globpath(&runtimepath, 'doc/tags', false, true)
    for entry in readfile(tags)
      var fields = split(entry, "\t")
      if len(fields) >= 2 && fields[0] == tag
        var file = fnamemodify(tags, ':h') .. '/' .. fields[1]
        if getfsize(file) > 2000000
          continue
        endif
        var lines = readfile(file)
        for i in range(len(lines))
          if stridx(lines[i], '*' .. tag .. '*') >= 0
            return {matches: matches, file: file, line: i + 1, excerpt: lines[max([0, i - 2]) : min([len(lines) - 1, i + 35])]}
          endif
        endfor
      endif
    endfor
  endfor
  return {matches: matches, excerpt: []}
enddef

def JobOutput(id: string, channel: channel, text: string)
  if !has_key(jobs, id)
    return
  endif
  var record = jobs[id]
  record.bytes += strlen(text)
  if record.bytes <= 128000 && len(record.output) < 1000
    add(record.output, text)
  else
    record.truncated = true
  endif
enddef

def JobExit(id: string, job: job, status: number)
  if has_key(jobs, id)
    jobs[id].status = 'completed'
    jobs[id].exit_code = status
  endif
enddef

export def StartJob(name: string): dict<any>
  var config: dict<any> = get(g:, 'vim9_mcp_jobs', {})
  if !has_key(config, name)
    throw 'job_unavailable: configure g:vim9_mcp_jobs'
  endif
  var active = filter(values(copy(jobs)), (_, j) => j.status == 'running')
  if len(active) >= 4
    throw 'too_many_jobs'
  endif
  jobSerial += 1
  var id = 'job-' .. jobSerial
  var spec = config[name]
  if type(spec.argv) != v:t_list || empty(spec.argv)
    throw 'invalid_job_configuration'
  endif
  var record: dict<any> = {job_id: id, name: name, status: 'running', output: [], bytes: 0, truncated: false, cwd: get(spec, 'cwd', getcwd()), errorformat: get(spec, 'errorformat', &errorformat), exit_code: v:null}
  record.snapshots = {}
  for item in getbufinfo({bufloaded: 1})
    if getbufvar(item.bufnr, '&buftype') == '' && !empty(bufname(item.bufnr))
      record.snapshots[fnamemodify(bufname(item.bufnr), ':p')] = M.Describe(item.bufnr)
    endif
  endfor
  jobs[id] = record
  var handle = job_start(spec.argv, {cwd: record.cwd, out_mode: 'nl', err_mode: 'nl', out_cb: (ch, msg) => JobOutput(id, ch, msg), err_cb: (ch, msg) => JobOutput(id, ch, msg), exit_cb: (job, code) => JobExit(id, job, code)})
  record.handle = handle
  if job_status(handle) == 'fail'
    record.status = 'failed'
    throw 'job_start_failed'
  endif
  if len(jobs) > 32
    for [key, value] in items(copy(jobs))
      if key != id && value.status != 'running'
        remove(jobs, key)
        break
      endif
    endfor
  endif
  return {job_id: id, status: 'running'}
enddef

export def GetJob(id: string): dict<any>
  if !has_key(jobs, id)
    throw 'job_not_found'
  endif
  var record = jobs[id]
  # Parse with getqflist(lines=...) without changing the user's current list.
  var parsed = getqflist({lines: ['vim9-mcp-directory: ' .. record.cwd] + record.output, efm: '%Dvim9-mcp-directory: %f,' .. record.errorformat}).items
  var findings: list<dict<any>> = []
  for item in parsed
    if item.valid && item.lnum > 0
      var finding: dict<any> = {message: item.text, source: record.name, severity: item.type == 'E' ? 'error' : item.type == 'W' ? 'warning' : 'info', disk_location: {path: bufname(item.bufnr), line: item.lnum, byte: max([0, item.col - 1])}}
      var path = fnamemodify(bufname(item.bufnr), ':p')
      if has_key(record.snapshots, path)
        var snapshot = record.snapshots[path]
        finding.location = {buffer: snapshot.buffer, revision: snapshot.revision, start: {line: item.lnum, byte: max([0, item.col - 1])}, end: {line: item.lnum, byte: max([0, item.col - 1])}}
        finding.stale = !bufloaded(item.bufnr) || M.Revision(item.bufnr) != snapshot.revision
      endif
      add(findings, finding)
    endif
  endfor
  return {job_id: id, status: record.status, exit_code: record.exit_code, output: record.output, truncated: record.truncated, findings: findings}
enddef

export def StopJob(id: string): dict<any>
  if !has_key(jobs, id)
    throw 'job_not_found'
  endif
  return {requested: !!job_stop(jobs[id].handle)}
enddef

export def Advanced(command: string): dict<any>
  if !get(g:, 'vim9_mcp_advanced', false)
    throw 'advanced_disabled: set g:vim9_mcp_advanced explicitly'
  endif
  return {output: execute('legacy execute ' .. string(command)), guarantees: 'unrestricted'}
enddef

export def Macro(args: dict<any>, run: bool): dict<any>
  if args.register !~# '^[a-z]$'
    throw 'invalid_register'
  endif
  if run
    return Advanced('normal! @' .. args.register)
  endif
  setreg(args.register, args.keys, 'v')
  return {register: args.register, executed: false}
enddef

export def Workspace(args: dict<any>): dict<any>
  if args.action == 'unload'
    var n = M.Resolve(get(args, 'buffer', ''))
    if getbufvar(n, '&modified')
      throw 'unsaved_changes'
    endif
    execute 'bunload ' .. n
  elseif index(['split', 'vsplit', 'tabnew', 'close', 'tabclose'], args.action) >= 0
    execute args.action
  else
    throw 'unknown_workspace_action'
  endif
  return {ok: true, window: win_getid()}
enddef

defcompile
