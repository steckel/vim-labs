" Inline comment cards. Virtual rows never alter the source snapshot.
function! s:Wrap(text, width, ...) abort
  let result = []
  let rest = substitute(a:text, '\t', '    ', 'g')
  let words = a:0 ? a:1 : 1
  while strdisplaywidth(rest) > a:width
    " Printable ASCII occupies one cell per byte. Include a lookahead byte:
    " if the boundary might precede a combining character, keep Vim's
    " character-aware path so the mark stays with its preceding character.
    let prefix = strpart(rest, 0, a:width + 1)
    let points = str2list(prefix)
    " Regex character classes can include attached combining marks. Numeric
    " code points establish that every byte really is printable ASCII.
    if len(points) == a:width + 1 && min(points) >= 32 && max(points) <= 126
      let part = strpart(prefix, 0, a:width)
    else
      let part = ''
      for char in split(rest, '\zs')
        if strdisplaywidth(part . char) > a:width | break | endif
        let part .= char
      endfor
    endif
    if empty(part) | let part = strcharpart(rest, 0, 1) | endif
    if words
      let cut = strridx(part, ' ')
      if cut > a:width / 3 | let part = strpart(part, 0, cut) | endif
    endif
    call add(result, part)
    let rest = strpart(rest, strlen(part))
    if words | let rest = substitute(rest, '^ *', '', '') | endif
  endwhile
  call add(result, rest)
  return result
endfunction

function! revue#comments#Wrap(text, width) abort
  return s:Wrap(a:text, max([1, a:width]))
endfunction

function! s:Row(text, width, type) abort
  return {'text': '│ ' . a:text . repeat(' ', max([0, a:width - 4 - strdisplaywidth(a:text)])) . ' │', 'type': a:type}
endfunction

function! s:Text(rows, text, width, type, ...) abort
  let prefix = a:0 ? a:1 : ''
  for text in s:Wrap(a:text, max([1, a:width - 4 - strdisplaywidth(prefix)]))
    call add(a:rows, s:Row(prefix . text, a:width, a:type))
    if a:0 > 1 | let prefix = a:2 | endif
  endfor
endfunction

function! s:RichText(rows, text, width, type, refs, styled, ...) abort
  let parsed = revue#markdown#Inline(substitute(a:text, '\t', '    ', 'g'), a:refs, 0, a:styled)
  let prefix = a:0 ? a:1 : ''
  let consumed = 0
  for text in s:Wrap(parsed.text, max([1, a:width - 4 - strdisplaywidth(prefix)]))
    let start = stridx(parsed.text, text, consumed)
    let row = s:Row(prefix . text, a:width, a:type)
    let row.spans = []
    for span in parsed.spans
      let left = max([start, span.col - 1])
      let right = min([start + strlen(text), span.col - 1 + span.length])
      if right > left | call add(row.spans, {'col': strlen('│ ' . prefix) + left - start + 1, 'length': right - left, 'kind': span.kind}) | endif
    endfor
    call add(a:rows, row)
    let consumed = start + strlen(text)
    if a:0 > 1 | let prefix = a:2 | endif
  endfor
endfunction

function! s:InsetEdge(rows, width, top) abort
  call add(a:rows, s:Row((a:top ? '┌' : '└') . repeat('─', a:width - 6) . (a:top ? '┐' : '┘'), a:width, 'RevueCardInset'))
endfunction

function! s:InsetText(rows, text, width, type) abort
  for text in s:Wrap(a:text, a:width - 8)
    call add(a:rows, s:Row('│ ' . text . repeat(' ', a:width - 8 - strdisplaywidth(text)) . ' │', a:width, a:type))
  endfor
endfunction

function! s:CodeLine(rows, text, width, type, prefix) abort
  let prefix = a:prefix
  for text in s:Wrap(a:text, max([1, a:width - 8 - strdisplaywidth(prefix)]), 0)
    let content = prefix . text
    call add(a:rows, s:Row('│ ' . content . repeat(' ', max([0, a:width - 8 - strdisplaywidth(content)])) . ' │', a:width, a:type))
    let prefix = repeat(' ', strdisplaywidth(prefix))
  endfor
endfunction

function! s:Fenced(rows, code, language, width, thread, context) abort
  let suggestion = a:language ==# 'suggestion' && !get(a:context, 'quoted', 0)
  call s:InsetEdge(a:rows, a:width, 1)
  call s:InsetText(a:rows, suggestion ? 'Suggested change' : a:language ==# 'suggestion' ? 'Quoted suggestion' : (empty(a:language) ? 'Code' : a:language), a:width, 'RevueCardInset')
  let start = get(a:thread, 'start', 0)
  let end = get(a:thread, 'line', 0)
  let source = get(a:context, 'lines', [])
  " Only compare a current anchor against its immutable source snapshot.
  let comparable = suggestion && !get(a:thread, 'outdated', 0) && start > 0 && end >= start && end <= len(source)
  " Narrow cards omit the numbered gutter rather than clipping code.
  let numbered = a:width >= 32
  if comparable
    for lnum in range(start, end)
      call s:CodeLine(a:rows, source[lnum - 1], a:width, 'RevueCardDelete', numbered ? printf('%5d - ', lnum) : '- ')
    endfor
  endif
  let lnum = comparable ? start : 0
  for line in a:code
    let prefix = suggestion ? (numbered && comparable ? printf('%5d + ', lnum) : '+ ') : ''
    call s:CodeLine(a:rows, line, a:width, suggestion ? 'RevueCardAdd' : 'RevueCardCode', prefix)
    let lnum += 1
  endfor
  call s:InsetEdge(a:rows, a:width, 0)
endfunction

function! s:Body(rows, body, width, thread, context) abort
  let lines = split(a:body, '\n', 1)
  let refs = get(a:context, 'references', revue#markdown#References(a:body))
  let styled = get(a:context, 'inline_styles', 0)
  let index = 0
  while index < len(lines)
    let line = lines[index]
    let fence = matchlist(line, '^ \{0,3}\(`\{3,}\|\~\{3,}\)\s*\(.*\)$')
    if line =~# '^ \{0,3}>' && a:width >= 16
      " Parse a quote container recursively so fenced code retains its own inset.
      let quoted = []
      while index < len(lines) && lines[index] =~# '^ \{0,3}>'
        call add(quoted, substitute(lines[index], '^ \{0,3}> \?', '', ''))
        let index += 1
      endwhile
      let inner = []
      let context = extend(copy(a:context), {'quoted': 1, 'references': refs})
      call s:Body(inner, join(quoted, "\n"), a:width - 2, a:thread, context)
      for row in inner
        let text = strcharpart(row.text, 2, strchars(row.text) - 4)
        let outer = s:Row('▎ ' . text, a:width, row.type ==# 'RevueCardBody' ? 'RevueCardQuote' : row.type)
        let outer.spans = map(deepcopy(get(row, 'spans', [])), {_, span -> extend(span, {'col': span.col + strlen('▎ ')})})
        call add(a:rows, outer)
      endfor
      continue
    elseif !empty(fence)
      let marker = strpart(fence[1], 0, 1)
      let closing = '^ \{0,3}' . escape(marker, '~') . '\{' . strlen(fence[1]) . ',}\s*$'
      let language = trim(fence[2])
      let code = []
      let index += 1
      while index < len(lines) && lines[index] !~# closing
        call add(code, lines[index])
        let index += 1
      endwhile
      call s:Fenced(a:rows, code, language, a:width, a:thread, a:context)
    elseif line =~# '^ \{0,3}\[[^]]\+\]:' && !empty(revue#markdown#References(line))
      let index += 1
      continue
    elseif line =~# '^\s*>'
      " Each quoted paragraph receives a rail; nested quotes keep their depth.
      let depth = 0
      while line =~# '^\s*>'
        let line = substitute(line, '^\s*> \?', '', '')
        let depth += 1
      endwhile
      let rail = repeat('▎', min([depth, 3])) . ' '
      call s:RichText(a:rows, line, a:width, 'RevueCardQuote', refs, styled, rail)
    elseif line =~# '^\s*\([-*+]\|\d\+[.)]\)\s\+'
      let item = matchlist(line, '^\(\s*\)\([-*+]\|\d\+[.)]\)\s\+\(.*\)$')
      let marker = item[2] =~# '^\d' ? item[2] . ' ' : '• '
      let indent = repeat(' ', min([strdisplaywidth(item[1]), max([0, a:width - 8 - strdisplaywidth(marker)])]))
      let prefix = indent . marker
      if strdisplaywidth(prefix) >= a:width - 5
        call s:RichText(a:rows, line, a:width, 'RevueCardBody', refs, styled)
      else
        call s:RichText(a:rows, item[3], a:width, 'RevueCardBody', refs, styled, prefix, repeat(' ', strdisplaywidth(prefix)))
      endif
    elseif line =~# '^ \{0,3}#\{1,6}\s\+'
      call s:RichText(a:rows, substitute(line, '^ \{0,3}#\{1,6}\s\+', '', ''), a:width, 'RevueCardHeading', refs, styled)
    elseif line =~# '^    \|^\t'
      call s:Text(a:rows, line, a:width, 'RevueCardCode')
    else
      call s:RichText(a:rows, line, a:width, 'RevueCardBody', refs, styled)
    endif
    let index += 1
  endwhile
endfunction

function! revue#comments#Rows(thread, width, ...) abort
  let width = max([12, a:width])
  let context = a:0 ? a:1 : {}
  if empty(a:thread.comments)
    if has_key(context, 'body_cache') | call filter(context.body_cache, '0') | endif
    return []
  endif
  " A caller may retain body rows for its displayed file. Metadata and actions
  " are always rebuilt; only body rendering depends on this exact scope.
  let caching = has_key(context, 'body_cache')
  if caching
    let cache = get(context, 'body_cache', {})
    let scope = {'width': width, 'styles': get(context, 'inline_styles', 0),
          \ 'references': get(context, 'references', v:null), 'quoted': get(context, 'quoted', 0),
          \ 'start': get(a:thread, 'start', 0), 'end': get(a:thread, 'line', 0),
          \ 'outdated': get(a:thread, 'outdated', 0),
          \ 'source': sha256(json_encode(get(context, 'lines', [])))}
    let previous = get(cache, 'scope', {}) ==# scope ? get(cache, 'items', {}) : {}
    let retained = {}
    let retained_bytes = 0
  endif
  let rows = [{'text': '╭' . repeat('─', width - 2) . '╮', 'type': 'RevueCardBorder'}]
  if revue#anchor#IsFile(a:thread) | call s:Text(rows, 'File discussion', width, 'RevueCardMeta') | endif
  if has_key(a:thread, 'resolved')
    let state = a:thread.resolved ? 'Resolved' : 'Unresolved'
    if a:thread.resolved && !empty(get(a:thread, 'resolved_by', '')) | let state .= ' · ' . revue#message#OneLine(a:thread.resolved_by) | endif
    call s:Text(rows, state, width, 'RevueCardMeta')
  endif
  let index = 0
  for comment in a:thread.comments
    if index > 0
      call add(rows, {'text': '├' . repeat('─', width - 2) . '┤', 'type': 'RevueCardBorder'})
    endif
    let title = (index ? '↳ ' : '') . revue#message#Header(comment, get(context, 'author', ''))
    if has_key(get(context, 'unread', {}), revue#activity#Key(get(a:thread, 'id', ''), comment)) | let title .= ' [new]' | endif
    call s:Text(rows, title, width, 'RevueCardHeader')
    call add(rows, s:Row('', width, 'RevueCardBody'))
    if caching
      let key = sha256(comment.body)
      let saved = get(previous, key, {})
      if has_key(saved, 'body') && saved.body ==# comment.body
        let body_rows = deepcopy(saved.rows)
      else
        let body_rows = []
        call s:Body(body_rows, comment.body, width, a:thread, context)
        let saved = {'body': comment.body, 'rows': deepcopy(body_rows)}
        let saved.bytes = strlen(json_encode(saved))
      endif
      " Retain only currently displayed bodies, with both entry and byte limits.
      " Cached rows stay separate from outer-width extension below.
      " Long discussions can have hundreds of small bodies. Keep the 1 MiB
      " byte budget while allowing them to reuse otherwise idle capacity.
      if !has_key(retained, key) && len(retained) < 512 && retained_bytes + saved.bytes <= 1048576
        let retained[key] = saved
        let retained_bytes += saved.bytes
      endif
      call extend(rows, body_rows)
    else
      call s:Body(rows, comment.body, width, a:thread, context)
    endif
    let reactions = revue#reaction#Summary(comment)
    if !empty(reactions) | call s:Text(rows, reactions, width, 'RevueCardMeta') | endif
    call add(rows, s:Row('', width, 'RevueCardBody'))
    let index += 1
  endfor
  if has_key(context, 'body_cache')
    let cache.scope = deepcopy(scope)
    let cache.items = retained
  endif
  call add(rows, {'text': '├' . repeat('─', width - 2) . '┤', 'type': 'RevueCardBorder'})
  let reply = get(get(a:thread, 'capabilities', {}), 'reply', {})
  let private_reply = !empty(a:thread.comments) && get(a:thread.comments[0], 'publication', '') ==# 'pending' && get(get(get(a:thread, 'capabilities', {}), 'pending_reply', {}), 'enabled', 0)
  if get(a:thread, 'local_pending', 0)
    call s:Text(rows, 'Edit · :ReviewEditFeedback', width, 'RevueCardAction')
    call s:Text(rows, 'Collect / export · :ReviewBatch', width, 'RevueCardMeta')
  else
    call s:Text(rows, private_reply ? 'Reply privately…  ' . get(context, 'reply_hint', 'r') : get(reply, 'enabled', 1) ? 'Reply to this thread…  ' . get(context, 'reply_hint', 'r') : 'Reply unavailable · ' . revue#message#OneLine(get(reply, 'reason', 'This thread does not allow replies.')), width, 'RevueCardAction')
    call s:Text(rows, 'Select / quote a message · ' . get(context, 'thread_hint', get(context, 'threads_hint', ':ReviewThread')), width, 'RevueCardMeta')
  endif
  if !empty(get(context, 'state_hint', '')) | call s:Text(rows, context.state_hint, width, 'RevueCardAction') | endif
  call add(rows, {'text': '╰' . repeat('─', width - 2) . '╯', 'type': 'RevueCardBorder'})
  " Limit reading width while carrying the card background across the source
  " pane. Otherwise Vim paints the unused virtual row with DiffChange's color.
  let outer = max([width, get(context, 'outer_width', width)])
  if outer > width
    for row in rows
      let last = strchars(row.text) - 1
      let row.text = row.type ==# 'RevueCardBorder'
            \ ? strcharpart(row.text, 0, 1) . repeat('─', outer - 2) . strcharpart(row.text, last)
            \ : strcharpart(row.text, 0, last) . repeat(' ', outer - width) . strcharpart(row.text, last)
    endfor
  endif
  return rows
endfunction

function! revue#comments#Types() abort
  return ['RevueCardBorder', 'RevueCardHeader', 'RevueCardHeading', 'RevueCardBody', 'RevueCardAction', 'RevueCardMeta', 'RevueCardQuote', 'RevueCardInset', 'RevueCardCode', 'RevueCardAdd', 'RevueCardDelete']
endfunction

function! revue#comments#Setup() abort
  highlight default RevueCardBorder ctermfg=67 ctermbg=234 guifg=#5986b3 guibg=#161b22
  highlight default RevueCardHeader cterm=bold ctermfg=255 ctermbg=237 gui=bold guifg=#f0f6fc guibg=#303946
  highlight default RevueCardHeading cterm=bold ctermfg=255 ctermbg=234 gui=bold guifg=#f0f6fc guibg=#161b22
  highlight default RevueCardBody ctermfg=252 ctermbg=234 guifg=#d6dce4 guibg=#161b22
  highlight default RevueCardAction ctermfg=75 ctermbg=235 guifg=#79b8ff guibg=#21262d
  highlight default RevueCardMeta ctermfg=245 ctermbg=235 guifg=#8b949e guibg=#21262d
  highlight default RevueCardGutter ctermfg=75 ctermbg=234 guifg=#79b8ff guibg=#161b22
  highlight default RevueCardQuote ctermfg=246 ctermbg=234 guifg=#8b949e guibg=#161b22
  highlight default RevueCardInset ctermfg=246 ctermbg=235 guifg=#8b949e guibg=#21262d
  highlight default RevueCardCode ctermfg=252 ctermbg=235 guifg=#c9d1d9 guibg=#21262d
  highlight default RevueCardAdd ctermfg=151 ctermbg=22 guifg=#aff5b4 guibg=#12261e
  highlight default RevueCardDelete ctermfg=217 ctermbg=52 guifg=#ffdcd7 guibg=#301b20
  for name in revue#comments#Types()
    if empty(prop_type_get(name))
      call prop_type_add(name, {'highlight': name, 'combine': 0})
    endif
  endfor
  call sign_define('RevueThreadBoundary', {'numhl': 'RevueCardGutter', 'linehl': ''})
endfunction
