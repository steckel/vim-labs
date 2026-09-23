" Participant runtime actions are explicit owner operations, not comment bodies.
function! revue#runtime#Fields(snapshot, assignment, ...) abort
  let item = a:assignment
  let previous = filter(copy(get(item, 'runs', [])), {_, run -> run.state !=# 'abandoned' && !(run.state ==# 'failed' && !get(run, 'execution_started', 1))})
  let last = get(previous, -1, {})
  let config = get(filter(deepcopy(get(g:, 'revue_participants', [])), {_, p -> type(p) == v:t_dict && get(p, 'id', '') ==# item.participant.id}), 0, {})
  let runtime = deepcopy(get(config, 'runtime', {}))
  let mode = 'start'
  if !empty(last) && last.state ==# 'prepared'
    let mode = 'dispatch'
    let runtime = deepcopy(last.runtime)
  elseif !empty(last) && !(last.state ==# 'abandoned' || (last.state ==# 'failed' && !get(last, 'execution_started', 1)))
    let mode = 'resume'
    let runtime = deepcopy(last.runtime)
  endif
  if a:0 && a:1
    let last = get(get(item, 'runs', []), -1, {})
    let mode = 'abandon'
    let runtime = deepcopy(get(last, 'runtime', {}))
  endif
  return {'kind': 'participant_run', 'body': '', 'run_mode': mode, 'assignment': item.id,
        \ 'expected_version': item.version, 'participant': deepcopy(item.participant), 'runtime': runtime,
        \ 'run': index(['dispatch', 'abandon'], mode) >= 0 ? get(last, 'id', '') : '', 'resume_run': mode ==# 'resume' ? last.id : '',
        \ 'thread': mode ==# 'start' ? '' : get(last, 'thread', ''), 'reference': deepcopy(item.reference), 'count': len(item.targets),
        \ 'workspace': mode ==# 'abandon' ? get(last, 'workspace', '') : get(get(a:snapshot, 'capture_context', {}), 'workspace', '')}
endfunction

function! revue#runtime#Error(snapshot, draft) abort
  let rule = get(get(a:snapshot, 'capabilities', {}), 'participant_run', {})
  if !get(rule, 'enabled', 0) | return 'This backend does not support participant runtime actions.' | endif
  if get(a:draft, 'run_mode', '') ==# 'abandon'
    return !get(rule, 'abandon', 0) ? 'This backend does not support abandoning prepared runs.' : empty(get(a:draft, 'run', '')) ? 'Select an unstarted prepared run.' : ''
  endif
  let runtime = get(a:draft, 'runtime', {})
  if type(runtime) != v:t_dict || index(get(rule, 'adapters', []), get(runtime, 'adapter', '')) < 0
    return 'Configure this participant’s runtime with adapter: codex before starting it.'
  endif
  if index(['read-only', 'workspace-write'], get(runtime, 'sandbox', 'workspace-write')) < 0 | return 'Choose read-only or workspace-write runtime access.' | endif
  if index(['start', 'resume', 'dispatch'], get(a:draft, 'run_mode', '')) < 0 || empty(get(a:draft, 'assignment', '')) || empty(get(a:draft, 'expected_version', '')) | return 'Select a current assignment before preparing a runtime action.' | endif
  if a:draft.run_mode ==# 'resume' && empty(get(a:draft, 'thread', '')) | return 'The previous execution has no verified Codex session ID. Inspect its outcome; a replacement will not start automatically.' | endif
  return ''
endfunction

function! revue#runtime#CurrentError(snapshot, item, draft) abort
  if empty(a:item) | return 'Reload assignments before starting a participant.' | endif
  let abandoning = get(a:draft, 'run_mode', '') ==# 'abandon'
  if a:item.cancelled && !abandoning | return 'Assignment cancelled; no participant can start.' | endif
  let last = get(get(a:item, 'runs', []), -1, {})
  if get(last, 'process_held', 0) || index(['running', 'launching'], get(last, 'state', '')) >= 0 | return 'The previous process is still owned. Reload its state instead of starting another.' | endif
  if abandoning && (get(last, 'state', '') !=# 'prepared' || get(last, 'execution_started', 1)) | return 'Only an unstarted prepared run can be abandoned.' | endif
  if !abandoning && get(last, 'state', '') ==# 'prepared' && get(last, 'expected_version', '') !=# a:item.version | return 'Prepared run uses an older assignment version; use :ReviewAbandonRun to release it before preparing another run.' | endif
  let fields = revue#runtime#Fields(a:snapshot, a:item, abandoning)
  for field in ['assignment', 'expected_version', 'runtime', 'run_mode', 'run', 'resume_run', 'thread', 'participant', 'reference', 'workspace', 'count']
    if type(get(a:draft, field, '')) != type(fields[field]) || get(a:draft, field, '') !=# fields[field] | return 'Assignment or run changed. Reload outcomes and prepare a new action.' | endif
  endfor
  return revue#runtime#Error(a:snapshot, a:draft)
endfunction

function! revue#runtime#Label(draft) abort
  return a:draft.run_mode ==# 'abandon' ? 'Abandon prepared run' : a:draft.run_mode ==# 'resume' ? 'Resume participant' : a:draft.run_mode ==# 'dispatch' ? 'Start prepared run' : 'Start participant'
endfunction

function! revue#runtime#Intent(draft) abort
  let intent = {}
  for field in ['kind', 'assignment', 'expected_version', 'participant', 'runtime', 'run_mode', 'run', 'resume_run', 'thread', 'reference', 'count', 'workspace']
    let intent[field] = deepcopy(a:draft[field])
  endfor
  return intent
endfunction

function! revue#runtime#Preview(draft) abort
  let runtime = a:draft.runtime
  if a:draft.run_mode ==# 'abandon'
    return ['# Abandon prepared run', a:draft.participant.label . ' · assignment #' . a:draft.assignment,
          \ 'Prepared run: ' . a:draft.run, 'Workspace: ' . a:draft.workspace,
          \ 'Release only this unstarted preparation. It cannot be dispatched afterward.',
          \ 'Assignment access, comments, outcomes and earlier agent sessions remain.',
          \ 'No process is started or stopped. Reload to prepare a new start or resume.']
  endif
  return ['# ' . revue#runtime#Label(a:draft),
        \ a:draft.participant.label . ' · assignment #' . a:draft.assignment,
        \ printf('%d selected messages · assigned source %s', a:draft.count, strpart(a:draft.reference.head, 0, 12)),
        \ 'Workspace: ' . a:draft.workspace,
        \ 'Runtime: ' . get(runtime, 'adapter', 'unconfigured') . ' · ' . get(runtime, 'executable', 'codex'),
        \ 'Access: ' . get(runtime, 'sandbox', 'workspace-write'),
        \ 'Uses the existing Codex login and configuration; no model override.',
        \ 'Requests inline replies and outcomes through the assignment’s MCP connection.',
        \ 'The agent checks current workspace files and is instructed to leave changes uncommitted.',
        \ a:draft.run_mode ==# 'resume' ? 'Resume exact Codex session ' . a:draft.thread : 'A new process starts only after confirmation.',
        \ 'Assignment cancellation revokes MCP access; it does not stop a process.']
endfunction

function! revue#runtime#Receipt(draft, receipt) abort
  if type(a:receipt) != v:t_dict || type(get(a:receipt, 'run', 0)) != v:t_string || empty(a:receipt.run) | return 0 | endif
  for field in ['id', 'assignment', 'run_mode']
    if type(get(a:receipt, field, 0)) != v:t_string || get(a:receipt, field, '') !=# a:draft[field] | return 0 | endif
  endfor
  if a:draft.run_mode ==# 'abandon' && (get(a:receipt, 'abandoned', 0) isnot v:true || get(a:receipt, 'state', '') !=# 'abandoned') | return 0 | endif
  return type(get(a:receipt, 'intent', 0)) == v:t_dict && get(a:receipt, 'intent', {}) ==# revue#runtime#Intent(a:draft) && (index(['dispatch', 'abandon'], a:draft.run_mode) < 0 || a:receipt.run ==# a:draft.run)
endfunction

function! revue#runtime#Valid(run, assignment) abort
  if type(a:run) != v:t_dict | return 0 | endif
  for field in ['id', 'thread', 'summary', 'error', 'workspace']
    if type(get(a:run, field, 0)) != v:t_string | return 0 | endif
  endfor
  for field in ['review', 'backend', 'connection']
    if get(a:run, field, '') !=# a:assignment[field] | return 0 | endif
  endfor
  if get(a:run, 'assignment', '') !=# a:assignment.id || get(a:run, 'reference', {}) !=# a:assignment.reference || empty(a:run.id) | return 0 | endif
  if type(get(a:run, 'process_held', 0)) != v:t_bool || type(get(a:run, 'execution_started', 0)) != v:t_bool | return 0 | endif
  let runtime = get(a:run, 'runtime', {})
  return type(runtime) == v:t_dict && get(runtime, 'adapter', '') ==# 'codex' && type(get(runtime, 'executable', 0)) == v:t_string &&
        \ index(['read-only', 'workspace-write'], get(runtime, 'sandbox', '')) >= 0 && index(['prepared', 'launching', 'running', 'completed', 'failed', 'unknown', 'abandoned'], get(a:run, 'state', '')) >= 0
endfunction
