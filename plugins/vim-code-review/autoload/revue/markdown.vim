" A conservative single-line Markdown reader. Unsupported syntax stays literal.
function! s:Escaped(text, pos) abort
  let i = a:pos - 1
  while i >= 0 && strpart(a:text, i, 1) ==# '\' | let i -= 1 | endwhile
  return (a:pos - i - 1) % 2
endfunction

function! s:End(text, pos, open, close) abort
  let depth = 1
  let i = a:pos + 1
  while i < strlen(a:text)
    let char = strpart(a:text, i, 1)
    if !s:Escaped(a:text, i)
      if char ==# a:open | let depth += 1 | endif
      if char ==# a:close | let depth -= 1 | endif
      if depth == 0 | return i | endif
    endif
    let i += 1
  endwhile
  return -1
endfunction

function! s:Key(text) abort
  return tolower(trim(substitute(a:text, '\s\+', ' ', 'g')))
endfunction

function! s:Destination(text) abort
  let text = trim(a:text)
  if text =~# '^<'
    let end = stridx(text, '>')
    if end < 1 | return '' | endif
    let url = strpart(text, 1, end - 1)
    let rest = trim(strpart(text, end + 1))
  else
    let url = matchstr(text, '^\S\+')
    let rest = trim(strpart(text, strlen(url)))
  endif
  if !empty(rest) && rest !~# '^".*"$' && rest !~# "^'.*'$" && rest !~# '^(.*)$' | return '' | endif
  return substitute(url, '\\\([[:punct:]]\)', '\1', 'g')
endfunction

function! revue#markdown#References(body) abort
  let refs = {}
  let fence = ''
  for original in split(a:body, "\n", 1)
    let line = substitute(original, '^\%( \{0,3}> \?\)*', '', '')
    let opening = matchstr(line, '^ \{0,3}\zs\(`\{3,}\|\~\{3,}\)')
    if !empty(fence)
      if line =~# '^ \{0,3}' . escape(fence[0], '~') . '\{' . strlen(fence) . ',}\s*$' | let fence = '' | endif
      continue
    elseif !empty(opening)
      let fence = opening
      continue
    endif
    let match = matchlist(line, '^ \{0,3}\[\([^]]\+\)\]:\s*\(.*\)$')
    if !empty(match)
      let url = s:Destination(match[2])
      let key = s:Key(match[1])
      if !empty(url) && !has_key(refs, key) | let refs[key] = url | endif
    endif
  endfor
  return refs
endfunction

function! s:Link(text, pos, refs) abort
  let end = s:End(a:text, a:pos, '[', ']')
  if end < 0 | return {} | endif
  let label = strpart(a:text, a:pos + 1, end - a:pos - 1)
  let next = strpart(a:text, end + 1, 1)
  let final = end
  if next ==# '('
    let final = s:End(a:text, end + 1, '(', ')')
    if final < 0 | return {} | endif
    let destination = s:Destination(strpart(a:text, end + 2, final - end - 2))
  elseif next ==# '['
    let final = s:End(a:text, end + 1, '[', ']')
    if final < 0 | return {} | endif
    let reference = strpart(a:text, end + 2, final - end - 2)
    let destination = get(a:refs, s:Key(empty(reference) ? label : reference), '')
  else
    let destination = get(a:refs, s:Key(label), '')
  endif
  return empty(destination) ? {} : {'label': label, 'destination': destination, 'start': a:pos, 'end': final + 1}
endfunction

function! revue#markdown#Inline(text, refs, ...) abort
  let result = {'text': '', 'spans': [], 'raw_spans': [], 'links': []}
  let styled = a:0 > 1 && a:2
  let i = 0
  while i < strlen(a:text)
    " Plain runs cannot open inline syntax. Copy their original bytes at once
    " instead of allocating a suffix and checking escapes for every character.
    " Stop at backslashes too, so escaping and Unicode byte offsets retain the
    " same handling as the single-character parser below.
    let next = match(a:text, '[\\`[<*_~]', i)
    if next != i
      let end = next < 0 ? strlen(a:text) : next
      let result.text .= strpart(a:text, i, end - i)
      let i = end
      continue
    endif
    let char = strcharpart(strpart(a:text, i), 0, 1)
    let end = -1
    let style = ''
    let link = {}
    if !s:Escaped(a:text, i)
      if char ==# '`'
        let marker = matchstr(strpart(a:text, i), '^`\+')
        let scan = i + strlen(marker)
        while scan < strlen(a:text)
          let found = matchstrpos(a:text, '`\+', scan)
          if found[1] < 0 | break | endif
          if found[0] ==# marker | let end = found[2] | break | endif
          let scan = found[2]
        endwhile
        let style = 'Code'
      elseif char ==# '[' && (i == 0 || strpart(a:text, i - 1, 1) !=# '!')
        let link = s:Link(a:text, i, a:refs)
        if !empty(link) | let end = link.end | let style = 'Link' | endif
      elseif char ==# '<'
        let closing = stridx(a:text, '>', i + 1)
        let url = closing > 0 ? strpart(a:text, i + 1, closing - i - 1) : ''
        if revue#links#IsWeb(url)
          let end = closing + 1
          let link = {'label': url, 'destination': url, 'start': i, 'end': end}
          let style = 'Link'
        endif
      elseif char ==# '*' || char ==# '_' || strpart(a:text, i, 2) ==# '~~'
        let marker = matchstr(strpart(a:text, i), '^\(\*\{1,3}\|_\{1,3}\|\~\~\)')
        let start = i + strlen(marker)
        let closing = stridx(a:text, marker, start)
        let inside = closing > start ? strpart(a:text, start, closing - start) : ''
        let word = char ==# '_' && i > 0 && strpart(a:text, i - 1, 1) =~# '[[:alnum:]]'
        if !word && !empty(inside) && inside !~# '^\s\|\s$' && !s:Escaped(a:text, closing)
          let end = closing + strlen(marker)
          let style = marker ==# '~~' ? 'Strike' : strlen(marker) == 3 ? 'StrongEmphasis' : strlen(marker) == 2 ? 'Strong' : 'Emphasis'
        endif
      endif
    endif
    if end > i
      let raw = strpart(a:text, i, end - i)
      let nested = {}
      if index(['Strong', 'Emphasis', 'StrongEmphasis', 'Strike'], style) >= 0 && (a:0 ? a:1 : 0) < 8
        let nested = revue#markdown#Inline(strpart(raw, strlen(marker), strlen(raw) - 2 * strlen(marker)), a:refs, (a:0 ? a:1 : 0) + 1, styled)
      endif
      let visible_marker = styled ? '' : get(l:, 'marker', '')
      let text = !empty(nested) ? visible_marker . nested.text . visible_marker : !empty(link) ? link.label . ' ↗' : styled && style ==# 'Code' ? strpart(raw, strlen(marker), strlen(raw) - 2 * strlen(marker)) : raw
      call add(result.raw_spans, {'col': i + 1, 'length': end - i, 'kind': style})
      call add(result.spans, {'col': strlen(result.text) + 1, 'length': strlen(text), 'kind': style})
      if !empty(nested)
        call extend(result.raw_spans, map(nested.raw_spans, {_, span -> extend(span, {'col': span.col + i + strlen(marker)})}))
        call extend(result.spans, map(nested.spans, {_, span -> extend(span, {'col': span.col + strlen(result.text) + strlen(visible_marker)})}))
        call extend(result.links, map(nested.links, {_, item -> extend(item, {'start': item.start + i + strlen(marker), 'end': item.end + i + strlen(marker)})}))
      endif
      if !empty(link) | call add(result.links, link) | endif
      let result.text .= text
      let i = end
    else
      if styled && char ==# '\' && strpart(a:text, i + 1, 1) =~# '[[:punct:]]'
        let result.text .= strpart(a:text, i + 1, 1)
        let i += 2
      else
        let result.text .= char
        let i += strlen(char)
      endif
    endif
  endwhile
  return result
endfunction

function! revue#markdown#Scan(body) abort
  let result = {'links': [], 'spans': []}
  let refs = revue#markdown#References(a:body)
  let fence = ''
  let row = 0
  for line in split(a:body, "\n", 1)
    let row += 1
    let content = substitute(line, '^\%( \{0,3}> \?\)*', '', '')
    let opening = matchstr(content, '^ \{0,3}\zs\(`\{3,}\|\~\{3,}\)')
    if !empty(fence)
      if content =~# '^ \{0,3}' . escape(fence[0], '~') . '\{' . strlen(fence) . ',}\s*$' | let fence = '' | endif
      continue
    elseif !empty(opening)
      let fence = opening
      continue
    elseif content =~# '^ \{0,3}\[[^]]\+\]:' || content =~# '^    \|^\t'
      continue
    endif
    let parsed = revue#markdown#Inline(line, refs)
    call extend(result.spans, map(parsed.raw_spans, {_, span -> extend(span, {'line': row})}))
    call extend(result.links, map(parsed.links, {_, link -> extend(link, {'line': row})}))
    " Bare URLs are links only outside code and existing Markdown destinations.
    for url in revue#links#Body(line)
      let pos = stridx(line, url.url)
      while pos >= 0
        if empty(filter(copy(parsed.raw_spans), {_, span -> index(['Code', 'Link'], span.kind) >= 0 && pos >= span.col - 1 && pos < span.col - 1 + span.length}))
          call add(result.links, {'line': row, 'start': pos, 'end': pos + strlen(url.url), 'label': url.url, 'destination': url.url})
          call add(result.spans, {'line': row, 'col': pos + 1, 'length': strlen(url.url), 'kind': 'Link'})
        endif
        let pos = stridx(line, url.url, pos + strlen(url.url))
      endwhile
    endfor
  endfor
  call sort(result.links, {a, b -> a.line == b.line ? a.start - b.start : a.line - b.line})
  return result
endfunction

function! revue#markdown#Setup() abort
  highlight default RevueInlineCode ctermfg=223 ctermbg=237 guifg=#f2cc8f guibg=#30363d
  highlight default RevueInlineStrong cterm=bold gui=bold
  highlight default RevueInlineEmphasis cterm=italic gui=italic
  highlight default RevueInlineStrongEmphasis cterm=bold,italic gui=bold,italic
  highlight default RevueInlineStrike cterm=strikethrough gui=strikethrough
  highlight default RevueInlineLink cterm=underline ctermfg=75 gui=underline guifg=#79c0ff
  for kind in ['Code', 'Strong', 'Emphasis', 'StrongEmphasis', 'Strike', 'Link']
    let name = 'RevueInline' . kind
    if empty(prop_type_get(name)) | call prop_type_add(name, {'highlight': name, 'combine': 1, 'priority': 30}) | endif
  endfor
endfunction

function! revue#markdown#Highlight(buf, first, body) abort
  call revue#markdown#Setup()
  call s:Highlight(a:buf, a:first, revue#markdown#Scan(a:body).spans)
endfunction

function! s:Highlight(buf, first, spans) abort
  for span in a:spans
    call prop_add(a:first + span.line - 1, span.col, {'bufnr': a:buf, 'type': 'RevueInline' . span.kind, 'length': span.length})
  endfor
endfunction

function! revue#markdown#View(buf, view) abort
  call revue#markdown#Setup()
  let previous = getbufvar(a:buf, 'revue_markdown_cache', {})
  let retained = {}
  let retained_bytes = 0
  let seen = {}
  for target in values(a:view.messages)
    if has_key(seen, string(target.body_start)) | continue | endif
    let seen[string(target.body_start)] = 1
    let body = join(a:view.lines[target.body_start - 1 : target.body_end - 1], "\n")
    let key = sha256(body)
    let saved = get(previous, key, {})
    if !has_key(saved, 'body') || saved.body !=# body
      let saved = {'body': body, 'spans': revue#markdown#Scan(body).spans}
      let saved.bytes = strlen(json_encode(saved))
    endif
    " Spans are relative to the literal body, so insertion/reordering cannot
    " attach styling to another message. Keep only this view's bounded input.
    call s:Highlight(a:buf, target.body_start, saved.spans)
    if !has_key(retained, key) && len(retained) < 512 && retained_bytes + saved.bytes <= 1048576
      let retained[key] = saved
      let retained_bytes += saved.bytes
    endif
  endfor
  call setbufvar(a:buf, 'revue_markdown_cache', retained)
endfunction
