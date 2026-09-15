" Shared decoration for real-text review surfaces. Text remains ordinary Vim text.
function! revue#surface#Clear(buf) abort
  call sign_unplace('RevueSurface', {'buffer': a:buf})
endfunction

function! revue#surface#Paint(buf, rows, offset) abort
  call revue#comments#Setup()
  call revue#markdown#Setup()
  let rownum = a:offset + 1
  for row in a:rows
    " A line highlight fills the window without padding or rewriting the body.
    " Text properties keep Markdown syntax from replacing the surface palette.
    call sign_define(row.type . 'Surface', {'linehl': row.type})
    call sign_place(0, 'RevueSurface', row.type . 'Surface', a:buf, {'lnum': rownum, 'priority': 5})
    if !empty(row.text)
      call prop_add(rownum, 1, {'bufnr': a:buf, 'type': row.type, 'length': strlen(row.text)})
    endif
    for span in get(row, 'spans', [])
      call prop_add(rownum, span.col, {'bufnr': a:buf, 'type': 'RevueInline' . span.kind, 'length': span.length})
    endfor
    let rownum += 1
  endfor
endfunction
