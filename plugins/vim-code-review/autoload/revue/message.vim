" Shared message labels. Identity and permissions remain backend-owned.
function! revue#message#OneLine(text) abort
  return substitute(a:text, '\_s\+', ' ', 'g')
endfunction

function! revue#message#Date(date) abort
  let parts = matchlist(a:date, '^\(\d\{4}\)-\(\d\{2}\)-\(\d\{2}\)')
  if empty(parts) | return revue#message#OneLine(a:date) | endif
  let month = str2nr(parts[2])
  if month < 1 || month > 12 | return revue#message#OneLine(a:date) | endif
  return ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][month - 1] . ' ' . str2nr(parts[3]) . ', ' . parts[1]
endfunction

function! revue#message#Author(comment, ...) abort
  let author = revue#message#OneLine(a:comment.author)
  let owner = a:0 ? a:1 : ''
  let badges = []
  if get(a:comment, 'is_author', !empty(owner) && a:comment.author ==# owner) | call add(badges, 'Author') | endif
  let role = revue#message#OneLine(get(a:comment, 'author_role', ''))
  if !empty(role) && index(badges, role) < 0 | call add(badges, role) | endif
  if get(a:comment, 'author_type', '') ==# 'bot' | call add(badges, 'Bot') | endif
  return author . (empty(badges) ? '' : ' [' . join(badges, ' · ') . ']')
endfunction

function! revue#message#Metadata(comment) abort
  let parts = []
  let created = get(a:comment, 'created', '')
  if !empty(created) | call add(parts, revue#message#Date(created)) | endif
  if get(a:comment, 'edited', 0)
    call add(parts, 'Edited')
  elseif !empty(get(a:comment, 'updated', '')) && !empty(created) && a:comment.updated !=# created
    call add(parts, 'Updated ' . revue#message#Date(a:comment.updated))
  endif
  let publication = get(a:comment, 'publication', '')
  if publication ==# 'pending' | call add(parts, 'Pending review') | endif
  if publication ==# 'local' | call add(parts, 'Saved locally') | endif
  if publication ==# 'local_pending' | call add(parts, get(a:comment, 'pending_status', 'Pending')) | endif
  let application = get(a:comment, 'suggestion_application', {})
  if type(application) == v:t_dict && !empty(get(a:comment, 'version', '')) && get(application, 'message_version', '') ==# a:comment.version && index(['applied', 'observed'], get(application, 'state', '')) >= 0 && type(get(application, 'label', 0)) == v:t_string
    call add(parts, revue#message#OneLine(application.label))
  endif
  let decision = get(a:comment, 'decision', '')
  if !empty(decision) | call add(parts, revue#message#OneLine(decision)) | endif
  if !empty(decision) && !empty(get(a:comment, 'reviewed_head', ''))
    call add(parts, 'Source ' . strpart(revue#message#OneLine(a:comment.reviewed_head), 0, 12))
  endif
  return join(parts, ' · ')
endfunction

function! revue#message#Header(comment, ...) abort
  let author = revue#message#Author(a:comment, a:0 ? a:1 : '')
  let meta = revue#message#Metadata(a:comment)
  return author . (empty(meta) ? '' : ' · ' . meta)
endfunction

function! revue#message#Attribution(message) abort
  " Escape untrusted author text as Markdown, without generating a mention.
  let author = escape(revue#message#OneLine(a:message.author), '\`*_{}[]<>()#!|')
  let url = get(a:message, 'url', '')
  let source = revue#links#IsWeb(url) ? ' ([source](<' . url . '>))' : ''
  return '**' . author . '** wrote' . source . ':'
endfunction
