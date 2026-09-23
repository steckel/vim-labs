" Conservative, backend-independent moved-block detection over unified patches.
" Only removed/added lines participate; unchanged context is never a move.
function! s:Lines(files) abort
  let sides = {'base': [], 'head': []}
  for file in a:files
    let old = 0
    let new = 0
    let left = 0
    let right = 0
    for line in split(get(file, 'patch', ''), "\n", 1)
      let hunk = matchlist(line, '^@@ -\(\d\+\)\%(,\(\d\+\)\)\? +\(\d\+\)\%(,\(\d\+\)\)\? @@')
      if !empty(hunk)
        let [old, new] = [str2nr(hunk[1]), str2nr(hunk[3])]
        let left = empty(hunk[2]) ? 1 : str2nr(hunk[2])
        let right = empty(hunk[4]) ? 1 : str2nr(hunk[4])
      elseif strpart(line, 0, 1) ==# '-' && left > 0
        call add(sides.base, {'file': file.id, 'path': get(file, 'old_path', file.path), 'line': old, 'text': strpart(line, 1)})
        let old += 1
        let left -= 1
      elseif strpart(line, 0, 1) ==# '+' && right > 0
        call add(sides.head, {'file': file.id, 'path': file.path, 'line': new, 'text': strpart(line, 1)})
        let new += 1
        let right -= 1
      elseif strpart(line, 0, 1) ==# ' ' && left > 0 && right > 0
        let old += 1
        let new += 1
        let left -= 1
        let right -= 1
      endif
    endfor
  endfor
  return sides
endfunction

function! s:Adjacent(lines, first, second) abort
  return a:first >= 0 && a:second < len(a:lines) && a:lines[a:first].file ==# a:lines[a:second].file && a:lines[a:first].line + 1 == a:lines[a:second].line
endfunction

function! revue#moves#Detect(files) abort
  if !get(g:, 'revue_moved_lines', 1) | return [] | endif
  let sides = s:Lines(a:files)
  let index = {'base': {}, 'head': {}}
  for side in ['base', 'head']
    for i in range(len(sides[side]))
      let text = sides[side][i].text
      if !has_key(index[side], text) | let index[side][text] = [] | endif
      call add(index[side][text], i)
    endfor
  endfor
  let used = {'base': {}, 'head': {}}
  let result = []
  for i in range(len(sides.base))
    let text = sides.base[i].text
    let targets = get(index.head, text, [])
    " A unique nonblank seed avoids guessing between repeated boilerplate.
    if has_key(used.base, string(i)) || empty(trim(text)) || len(index.base[text]) != 1 || len(targets) != 1 | continue | endif
    let j = targets[0]
    if has_key(used.head, string(j)) | continue | endif
    let [first, target, last, ending] = [i, j, i, j]
    while s:Adjacent(sides.base, first - 1, first) && s:Adjacent(sides.head, target - 1, target) &&
          \ !has_key(used.base, string(first - 1)) && !has_key(used.head, string(target - 1)) && sides.base[first - 1].text ==# sides.head[target - 1].text
      let first -= 1
      let target -= 1
    endwhile
    while s:Adjacent(sides.base, last, last + 1) && s:Adjacent(sides.head, ending, ending + 1) &&
          \ !has_key(used.base, string(last + 1)) && !has_key(used.head, string(ending + 1)) && sides.base[last + 1].text ==# sides.head[ending + 1].text
      let last += 1
      let ending += 1
    endwhile
    let before = sides.base[first : last]
    let after = sides.head[target : ending]
    let content = join(map(copy(before), {_, row -> row.text}), "\n")
    " Consume rejected blocks too, so a large same-range match stays linear.
    for row in range(first, last) | let used.base[string(row)] = 1 | endfor
    for row in range(target, ending) | let used.head[string(row)] = 1 | endfor
    " Ignore tiny punctuation-only matches and replacements at the same range.
    if strchars(substitute(content, '[^[:alnum:]]', '', 'g')) < 20 ||
          \ (before[0].path ==# after[0].path && before[0].line == after[0].line) | continue | endif
    call add(result, {'base': before, 'head': after})
  endfor
  return result
endfunction

function! revue#moves#Clear(buf, group) abort
  if !bufexists(a:buf) | return | endif
  call sign_unplace(a:group, {'buffer': a:buf})
  if !empty(prop_type_get('ReviewMovedLabel'))
    call prop_remove({'bufnr': a:buf, 'type': 'ReviewMovedLabel', 'all': 1}, 1, len(getbufline(a:buf, 1, '$')))
  endif
endfunction

function! revue#moves#Paint(buf, side, file, moves, group) abort
  call revue#moves#Clear(a:buf, a:group)
  if !get(g:, 'revue_moved_lines', 1) | return | endif
  highlight default ReviewMoved ctermfg=6 guifg=#2aa198
  highlight default ReviewMovedLine ctermbg=23 guibg=#123b40
  highlight default link ReviewMovedLabel ReviewMoved
  call sign_define('ReviewMovedFrom', {'text': 'M>', 'texthl': 'ReviewMoved', 'linehl': 'ReviewMovedLine'})
  call sign_define('ReviewMovedTo', {'text': '<M', 'texthl': 'ReviewMoved', 'linehl': 'ReviewMovedLine'})
  if empty(prop_type_get('ReviewMovedLabel')) | call prop_type_add('ReviewMovedLabel', {'highlight': 'ReviewMovedLabel'}) | endif
  for move in a:moves
    let rows = move[a:side]
    if rows[0].file !=# a:file | continue | endif
    " Editable quick-review buffers may have diverged since the VCS diff.
    if getbufline(a:buf, rows[0].line, rows[-1].line) !=# map(copy(rows), {_, r -> r.text}) | continue | endif
    for row in rows
      call sign_place(0, a:group, a:side ==# 'base' ? 'ReviewMovedFrom' : 'ReviewMovedTo', a:buf, {'lnum': row.line, 'priority': 120})
    endfor
    let other = move[a:side ==# 'base' ? 'head' : 'base']
    let label = (a:side ==# 'base' ? 'Moved to ' : 'Moved from ') . other[0].path . ':' . other[0].line . '-' . other[-1].line
    try
      call prop_add(rows[0].line, 0, {'bufnr': a:buf, 'type': 'ReviewMovedLabel', 'text': label, 'text_align': 'above'})
    catch
      " The gutter markers remain usable without virtual text support.
    endtry
  endfor
endfunction
