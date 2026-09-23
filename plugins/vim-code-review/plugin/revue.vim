vim9script

if exists('g:loaded_revue')
  finish
endif
g:loaded_revue = 1

# Empty selects HEAD for Git or @- for jj; an explicit setting overrides it.
g:revue_default_base = get(g:, 'revue_default_base', '')

command! -nargs=? -bang Review call revue#backends#local#Open(<q-args>, <bang>0)
command! -nargs=0 ReviewSaved call revue#backends#local#List()
command! -nargs=1 ReviewResume call revue#backends#local#Resume(<q-args>)

nnoremap <silent> <Plug>(revue-open) <Cmd>Review<CR>
