" Interactive local specimen; the provider cannot publish anything.
let g:revue_card_preview = json_decode(join(readfile(expand('<sfile>:p:h') . '/fixtures/comment-ui.json'), "\n"))
function! RevueCardPreviewHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:revue_card_preview.content})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': g:revue_card_preview.snapshot})
  else
    call a:Done({'ok': 0, 'error': 'Local UI preview: publishing is unavailable.', 'unknown': 0})
  endif
endfunction
call revue#session#Open(g:revue_card_preview.snapshot, function('RevueCardPreviewHost'), 0)
