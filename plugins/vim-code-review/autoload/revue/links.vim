" Find explicit web addresses in raw Markdown; this is not a GFM renderer.
" Code examples and reference definitions are intentionally included.
function! revue#links#Body(body) abort
  let result = []
  let seen = {}
  let row = 0
  for line in split(a:body, "\n", 1)
    let row += 1
    let offset = 0
    while 1
      let found = matchstrpos(line, '\chttps\?://[^[:space:][:cntrl:]<>"`]\+', offset)
      if found[1] < 0 | break | endif
      let offset = found[2]
      let url = found[0]
      " End at an unmatched closing delimiter, retaining balanced URL paths.
      let depth = {'(': 0, '[': 0, '{': 0}
      let pairs = {')': '(', ']': '[', '}': '{'}
      let size = 0
      for char in split(url, '\zs')
        if has_key(depth, char)
          let depth[char] += 1
        elseif has_key(pairs, char)
          if depth[pairs[char]] == 0 | break | endif
          let depth[pairs[char]] -= 1
        endif
        let size += strlen(char)
      endfor
      let url = strpart(url, 0, size)
      " Angle-delimited destinations have explicit bounds; preserve punctuation.
      let angled = found[1] > 0 && strpart(line, found[1] - 1, 1) ==# '<'
      let destination = found[1] > 1 && strpart(line, found[1] - 2, 2) ==# ']('
      if !angled && !destination | let url = substitute(url, '[.,;:!?'' ]\+$', '', '') | endif
      if revue#links#IsWeb(url) && !has_key(seen, url)
        let seen[url] = 1
        call add(result, {'url': url, 'line': row})
      endif
    endwhile
  endfor
  return result
endfunction

function! revue#links#IsWeb(url) abort
  return type(a:url) == v:t_string && a:url =~? '^https\?://[^/[:space:][:cntrl:]<>"`?#]\+\%([/?#][^[:space:][:cntrl:]<>"`]*\)\?$'
endfunction

" Semantic links exclude code examples. Relative destinations require backend
" resolved_links entries on the exact message; the frontend never guesses a base.
function! revue#links#Semantic(body, ...) abort
  let resolved = a:0 ? a:1 : {}
  let links = []
  let seen = {}
  for link in revue#markdown#Scan(a:body).links
    let destination = link.destination
    let url = revue#links#IsWeb(destination) ? destination : get(resolved, destination, '')
    let reason = revue#links#IsWeb(url) ? '' : 'The backend has not supplied a web destination for this link.'
    if !empty(reason) | let url = '' | endif
    let key = json_encode([link.label, destination])
    if has_key(seen, key) | continue | endif
    let seen[key] = 1
    call add(links, {'label': link.label, 'destination': destination, 'url': url, 'line': link.line, 'reason': reason})
  endfor
  return links
endfunction
