vim9script
if exists('g:loaded_vim9_mcp')
  finish
endif
if v:version < 900 || !has('vim9script') || !has('channel') || !has('job') || !has('timers')
  echoerr 'vim9-mcp requires Vim 9+ with +vim9script, +channel, +job, and +timers'
  finish
endif
import '../autoload/vim9mcp/connection.vim' as Connection
import '../autoload/vim9mcp/model.vim' as Model
import '../autoload/vim9mcp/changes.vim' as Changes
g:loaded_vim9_mcp = true

command! VimMCPConnect Connection.Connect()
command! VimMCPDisconnect Connection.Disconnect()
command! VimMCPStatus echo Connection.Status()
command! VimMCPHistory echo Model.History()
command! -nargs=1 VimMCPReview Changes.Review({change_id: <q-args>})
command! -range VimMCPShareSelection Model.CaptureSelection()
xnoremap <silent> <Plug>(VimMCPShareSelection) :<C-U>VimMCPShareSelection<CR>

augroup vim9_mcp
  autocmd!
  autocmd BufReadPost * Connection.Lifecycle('read', str2nr(expand('<abuf>')))
  autocmd BufWritePost * Connection.Lifecycle('saved', str2nr(expand('<abuf>')))
  autocmd BufEnter * Connection.Lifecycle('enter', str2nr(expand('<abuf>')))
  autocmd BufUnload * Connection.Lifecycle('unload', str2nr(expand('<abuf>')))
  autocmd BufWipeout * Connection.Lifecycle('wipe', str2nr(expand('<abuf>')))
  autocmd BufFilePost * Connection.Lifecycle('renamed', str2nr(expand('<abuf>')))
  autocmd VimLeavePre * Connection.Disconnect()
augroup END

if get(g:, 'vim9_mcp_autoconnect', true)
  if v:vim_did_enter
    Connection.Connect()
  else
    autocmd vim9_mcp VimEnter * Connection.Connect()
  endif
endif
