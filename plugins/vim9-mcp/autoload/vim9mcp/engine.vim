vim9script
import './model.vim' as M
import './changes.vim' as C
import './editor.vim' as E

export def Dispatch(method: string, args: dict<any>): dict<any>
  var result: dict<any>
  try
    if method == 'get_context'
      result = M.Context(args)
      result.providers = E.Providers()
      result.jobs = keys(get(g:, 'vim9_mcp_jobs', {}))
      result.workflows = keys(get(g:, 'vim9_mcp_workflows', {}))
      result.advanced = !!get(g:, 'vim9_mcp_advanced', false)
    elseif method == 'read_buffer'
      result = M.Snapshot(args)
    elseif method == 'search'
      result = C.Search(args)
    elseif method == 'prepare_changes'
      result = C.Prepare(args)
    elseif method == 'apply_changes'
      result = C.Apply(args)
    elseif method == 'undo_change'
      result = C.Undo(args)
    elseif method == 'review_changes'
      result = C.Review(args)
    elseif method == 'transform'
      result = C.Transform(args)
    elseif method == 'save_buffer'
      result = E.Save(args)
    elseif method == 'open_buffer'
      result = E.Open(args)
    elseif method == 'navigate'
      result = E.Navigate(args)
    elseif method == 'publish_findings'
      result = E.Publish(args)
    elseif method == 'get_events'
      result = M.Events(get(args, 'after', 0))
    elseif method == 'get_history'
      result = {history: M.History()}
    elseif method == 'inspect_editor'
      result = E.Inspect(args)
    elseif method == 'help'
      result = E.Help(args.topic)
    elseif method == 'invoke_provider'
      result = E.Invoke(args)
    elseif method == 'start_job'
      result = E.StartJob(args.name)
    elseif method == 'get_job'
      result = E.GetJob(args.job_id)
    elseif method == 'stop_job'
      result = E.StopJob(args.job_id)
    elseif method == 'execute_ex'
      result = E.Advanced(args.command)
    elseif method == 'record_macro' || method == 'execute_macro'
      result = E.Macro(args, method == 'execute_macro')
    elseif method == 'workspace'
      result = E.Workspace(args)
    elseif method == 'get_workflow'
      var workflows: dict<any> = get(g:, 'vim9_mcp_workflows', {})
      if !has_key(workflows, args.name)
        throw 'workflow_unavailable'
      endif
      result = {steps: workflows[args.name]}
    else
      throw 'unknown_tool'
    endif
    if !has_key(result, 'ok')
      result.ok = true
    endif
    return result
  catch
    var message = v:exception
    return {ok: false, code: matchstr(message, '^[a-z_]*') == '' ? 'vim_error' : matchstr(message, '^[a-z_]*'), message: message, throwpoint: v:throwpoint}
  endtry
enddef

defcompile
