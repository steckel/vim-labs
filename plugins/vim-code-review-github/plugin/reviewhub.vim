if exists('g:loaded_reviewhub')
  finish
endif
let g:loaded_reviewhub = 1
command! -nargs=? Reviews call reviewhub#Open(<q-args>)
command! -nargs=1 ReviewOpen call reviewhub#OpenURL(<q-args>)
command! ReviewRefresh call reviewhub#Refresh()
nnoremap <silent> <Plug>(reviews-open) <Cmd>Reviews<CR>
