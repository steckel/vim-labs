" Vim's native diff groups are global. Restore them after the last review,
" without overwriting colors a user changed while a review was open.
let s:users = 0
let s:before = []
let s:installed = []
function! revue#diff#Enter() abort
  if s:users == 0 && get(g:, 'revue_diff_colors', 1)
    let s:before = map(['DiffAdd', 'DiffDelete', 'DiffChange', 'DiffText'], {_, name -> hlget(name)[0]})
    highlight DiffAdd ctermbg=0 guibg=#073642
    highlight DiffDelete ctermbg=0 guibg=#073642 ctermfg=1 guifg=#dc322f
    highlight DiffChange ctermbg=0 guibg=#073642
    highlight DiffText ctermbg=8 guibg=#094959 cterm=NONE gui=NONE
    let s:installed = map(copy(s:before), {_, group -> hlget(group.name)[0]})
  endif
  let s:users += 1
endfunction

function! revue#diff#Leave() abort
  let s:users = max([0, s:users - 1])
  if s:users == 0
    for i in range(len(s:installed))
      if hlget(s:installed[i].name)[0] ==# s:installed[i]
        call hlset([extend(copy(s:before[i]), {'force': v:true})])
      endif
    endfor
    let s:before = []
    let s:installed = []
  endif
endfunction

" Parse changed source coordinates once for gutter signs and moved blocks.
function! revue#diff#Lines(files) abort
  let sides = {'base': [], 'head': []}
  for file in a:files
    let old = 0
    let new = 0
    let left = 0
    let right = 0
    let edit = 0
    for line in split(get(file, 'patch', ''), "\n", 1)
      let hunk = matchlist(line, '^@@ -\(\d\+\)\%(,\(\d\+\)\)\? +\(\d\+\)\%(,\(\d\+\)\)\? @@')
      if !empty(hunk)
        let edit += 1
        let [old, new] = [str2nr(hunk[1]), str2nr(hunk[3])]
        let left = empty(hunk[2]) ? 1 : str2nr(hunk[2])
        let right = empty(hunk[4]) ? 1 : str2nr(hunk[4])
      elseif strpart(line, 0, 1) ==# '-' && left > 0
        call add(sides.base, {'file': file.id, 'path': get(file, 'old_path', file.path), 'line': old, 'text': strpart(line, 1), 'edit': edit})
        let old += 1
        let left -= 1
      elseif strpart(line, 0, 1) ==# '+' && right > 0
        call add(sides.head, {'file': file.id, 'path': file.path, 'line': new, 'text': strpart(line, 1), 'edit': edit})
        let new += 1
        let right -= 1
      elseif strpart(line, 0, 1) ==# ' ' && left > 0 && right > 0
        let edit += 1
        let old += 1
        let new += 1
        let left -= 1
        let right -= 1
      endif
    endfor
  endfor
  return sides
endfunction

function! revue#diff#Clear(buf, group) abort
  if bufexists(a:buf) | call sign_unplace(a:group, {'buffer': a:buf}) | endif
endfunction

function! revue#diff#Paint(buf, side, file, group) abort
  call revue#diff#Clear(a:buf, a:group)
  highlight default ReviewDiffAdd ctermfg=2 guifg=#859900
  highlight default ReviewDiffDelete ctermfg=1 guifg=#dc322f
  call sign_define('ReviewDiffAdd', {'text': '+', 'texthl': 'ReviewDiffAdd'})
  call sign_define('ReviewDiffDelete', {'text': '-', 'texthl': 'ReviewDiffDelete'})
  let lines = getbufline(a:buf, 1, '$')
  for row in revue#diff#Lines([a:file])[a:side]
    " Partial/provider patches must not label missing or mismatched source.
    if row.line < 1 || row.line > len(lines) || lines[row.line - 1] !=# row.text | continue | endif
    call sign_place(0, a:group, a:side ==# 'head' ? 'ReviewDiffAdd' : 'ReviewDiffDelete',
          \ a:buf, {'lnum': row.line, 'priority': 110})
  endfor
endfunction
