let s:helper = expand('<sfile>:p:h:h:h') . '/python/reviewhub.py'

function! reviewhub#transport#Request(request, Done) abort
  let ctx = {'out': '', 'err': '', 'Done': a:Done, 'finished': 0}
  let command = get(g:, 'reviewhub_command', [get(g:, 'reviewhub_python', 'python3'), '-u', s:helper])
  let ctx.job = job_start(command, {
        \ 'in_mode': 'raw', 'out_mode': 'raw', 'err_mode': 'raw',
        \ 'out_cb': function('s:Output', [ctx]), 'err_cb': function('s:Error', [ctx]),
        \ 'close_cb': function('s:Closed', [ctx])})
  if job_status(ctx.job) ==# 'fail'
    call a:Done({'ok': v:false, 'error': 'Cannot start ReviewHub. Check g:reviewhub_python and Python 3.9+.'})
    return ctx
  endif
  call ch_sendraw(job_getchannel(ctx.job), json_encode(a:request) . "\n")
  call ch_close_in(job_getchannel(ctx.job))
  return ctx
endfunction

function! s:Output(ctx, channel, message) abort
  let a:ctx.out .= a:message
endfunction

function! s:Error(ctx, channel, message) abort
  let a:ctx.err .= a:message
endfunction

function! s:Closed(ctx, channel) abort
  if a:ctx.finished | return | endif
  let a:ctx.finished = 1
  try
    let result = json_decode(a:ctx.out)
    if type(result) != v:t_dict || !has_key(result, 'ok')
      throw 'Invalid result'
    endif
  catch
    let result = {'ok': v:false, 'error': 'Provider exited without a valid response. ' . a:ctx.err, 'unknown': v:true}
  endtry
  call a:ctx.Done(result)
endfunction
