vim9script
import './model.vim' as M
import './engine.vim' as Engine

var socket: channel
var connected = false
var enabled = false
var timer = -1
var retry = 0
var queue: list<dict<any>> = []
var listeners: dict<number> = {}
const root = fnamemodify(expand('<sfile>'), ':h:h:h')

export def Runtime(): string
  var configured: string = get(g:, 'vim9_mcp_runtime', $VIM9_MCP_RUNTIME)
  if !empty(configured)
    return configured
  endif
  var base = empty($TMPDIR) ? '/tmp' : substitute($TMPDIR, '/$', '', '')
  return base .. '/vim9-mcp-' .. trim(system('id -u'))
enddef

def Send(message: dict<any>)
  if connected && ch_status(socket) == 'open'
    var payload = json_encode(message)
    if strlen(payload) > 7000000
      payload = json_encode({type: 'response', id: get(message, 'id', ''), result: {ok: false, code: 'response_too_large'}})
    endif
    ch_sendraw(socket, payload .. "\n")
  endif
enddef

def OnMessage(ch: channel, line: string)
  try
    var message = json_decode(line)
    if message.type == 'welcome'
      M.SetSession(message.session)
      g:vim9_mcp_last_error = ''
    elseif message.type == 'request'
      if len(queue) >= 128
        Send({type: 'response', id: message.id, result: {ok: false, code: 'editor_busy'}})
      else
        add(queue, message)
      endif
    elseif message.type == 'cancel'
      for i in range(len(queue))
        if queue[i].id == message.id
          remove(queue, i)
          Send({type: 'response', id: message.id, result: {ok: false, code: 'cancelled'}})
          break
        endif
      endfor
    endif
  catch
    g:vim9_mcp_last_error = v:exception
  endtry
enddef

def OnClose(ch: channel)
  connected = false
  M.SetSession('')
  queue = []
enddef

def TryConnect()
  var path = Runtime() .. '/broker.sock'
  if getftype(path) != 'socket'
    return
  endif
  try
    socket = ch_open('unix:' .. path, {mode: 'nl', callback: OnMessage, close_cb: OnClose})
    connected = ch_status(socket) == 'open'
    if connected
      Send({type: 'hello', protocol: 1, role: 'vim', pid: getpid(), cwd: getcwd(), version: v:versionlong, capabilities: ['vim9', 'snapshots', 'targets', 'changes', 'quickfix', 'events', 'providers', 'jobs']})
    endif
  catch
    g:vim9_mcp_last_error = v:exception
  endtry
enddef

def Pump(id: number)
  if !enabled
    return
  endif
  if !connected
    retry += 1
    if retry % 30 == 1
      TryConnect()
    endif
    return
  endif
  if empty(queue)
    return
  endif
  var request = queue[0]
  var selected = 0
  var editorMode = mode(true)
  # Batch Ex mode permits integration tests and headless Vim; interactive command
  # lines, insert/select/operator modes, prompts, and pending input are deferred.
  if request.mutation && !((editorMode == 'n' && empty(getcmdtype()) && empty(state('m'))) || editorMode == 'ce')
    selected = -1
    for i in range(len(queue))
      if !queue[i].mutation
        selected = i
        break
      endif
    endfor
    if selected < 0
      return
    endif
    request = queue[selected]
  endif
  remove(queue, selected)
  var result = Engine.Dispatch(request.method, request.args)
  M.Record(request.id, request.method, result)
  Send({type: 'response', id: request.id, result: result})
enddef

def OnError(ch: channel, message: string)
  g:vim9_mcp_last_error = message
enddef

export def Connect()
  if enabled
    return
  endif
  enabled = true
  for item in getbufinfo({bufloaded: 1})
    Lifecycle('enter', item.bufnr)
  endfor
  var node: string = get(g:, 'vim9_mcp_node', 'node')
  if !executable(node)
    enabled = false
    throw 'vim9-mcp: Node.js 22+ is required'
  endif
  job_start([node, root .. '/bin/vim9-mcp.js', 'ensure'], {env: {VIM9_MCP_RUNTIME: Runtime()}, out_io: 'null', err_cb: OnError})
  timer = timer_start(30, Pump, {repeat: -1})
  TryConnect()
enddef

export def Disconnect()
  enabled = false
  if timer >= 0
    timer_stop(timer)
    timer = -1
  endif
  queue = []
  if connected
    ch_close(socket)
  endif
  connected = false
  M.SetSession('')
enddef

export def Status(): dict<any>
  return {enabled: enabled, connected: connected, session: M.Session(), queued: len(queue), socket: Runtime() .. '/broker.sock', last_error: get(g:, 'vim9_mcp_last_error', '')}
enddef

def Changed(n: number, start: number, finish: number, added: number, changes: list<dict<any>>)
  M.Event('changed', n)
enddef

export def Lifecycle(kind: string, n: number)
  try
    M.Event(kind, n)
    if kind == 'unload' || kind == 'wipe'
      var key = string(n)
      if has_key(listeners, key)
        listener_remove(remove(listeners, key))
      endif
      M.Forget(n)
    elseif bufloaded(n) && getbufvar(n, '&buftype') == ''
      if !has_key(listeners, string(n))
        listeners[string(n)] = listener_add(Changed, n)
      endif
      if kind == 'read' || kind == 'saved'
        M.RefreshDisk(n)
      endif
    endif
  catch
    g:vim9_mcp_last_error = v:exception
  endtry
enddef

defcompile
