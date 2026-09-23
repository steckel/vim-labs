vim9script

# review.vim — standalone diff review UI
#
# Navigate changed files against a base revision, view diffs, and add
# comments on specific lines. On submit, comments compile into a
# structured message. What happens to that message is up to the host:
# set g:RevueSubmitCallback to a funcref(message: string, context:
# dict<any>) to route it somewhere (an AI agent's conversation, a
# review-tool draft, a file). With no callback set, Submit() copies
# the message to the system clipboard.

var reviews: dict<dict<any>> = {}

# ── Public API ──────────────────────────────────────────────────────

# opts:
#   base:    revision to diff against (default: g:revue_default_base)
#   context: opaque dict passed through unchanged to the submit callback
export def Open(opts: dict<any> = {})
  var repo = revue#vcs#RepoRoot()
  if empty(repo)
    echohl WarningMsg
    echom 'revue: no supported repository here (git or jj)'
    echohl None
    return
  endif

  var base = get(opts, 'base', g:revue_default_base)
  var context = get(opts, 'context', {})
  var revision = revue#vcs#CurrentRevision(repo)

  var changes = revue#vcs#DiffNameStatus(repo, base)
  if empty(changes)
    echom $'revue: no changes vs {base}'
    return
  endif

  var uuid = RandomId(8)

  var state: dict<any> = {
    uuid:         uuid,
    context:      context,
    repo:         repo,
    base:         base,
    revision:     revision,
    changes:      changes,
    current_idx:  0,
    comments:     [],
    sidebar_bufnr: -1,
    base_bufnr:   -1,
    head_bufnr:   -1,
  }

  reviews[uuid] = state

  SetupDiffColors()
  CreateLayout(uuid)
  RenderSidebar(uuid)
  SwitchToFile(uuid, 0)

  echom $'revue: review mode — {len(changes)} file(s) changed. V to select, c to comment, s to submit.'
enddef

def SetupDiffColors()
  highlight DiffAdd    ctermbg=0   guibg=#073642
  highlight DiffDelete ctermbg=0   guibg=#073642 ctermfg=1  guifg=#dc322f
  highlight DiffChange ctermbg=0   guibg=#073642
  highlight DiffText   ctermbg=8   guibg=#094959 cterm=NONE gui=NONE

  highlight RevueSignAdd    ctermfg=2   guifg=#859900
  highlight RevueSignDelete ctermfg=1   guifg=#dc322f

  sign_define('RevueDiffAdd',    {text: '+', texthl: 'RevueSignAdd'})
  sign_define('RevueDiffDelete', {text: '-', texthl: 'RevueSignDelete'})
enddef

export def Close()
  var uuid = FindReviewUuid()
  if empty(uuid) || !has_key(reviews, uuid)
    return
  endif

  var state = reviews[uuid]
  ClearMoves(state)

  if state.base_bufnr != -1 && bufexists(state.base_bufnr)
    execute $'bwipeout! {state.base_bufnr}'
  endif

  if state.sidebar_bufnr != -1 && bufexists(state.sidebar_bufnr)
    execute $'bwipeout! {state.sidebar_bufnr}'
  endif

  for tab in gettabinfo()
    if gettabvar(tab.tabnr, 'revue_local_uuid', '') == uuid && tabpagenr('$') > 1
      execute $'tabclose {tab.tabnr}'
      break
    endif
  endfor

  remove(reviews, uuid)
enddef

# ── Layout ──────────────────────────────────────────────────────────
#
#  +----------------------------+------------------+------------------+
#  | Sidebar (30 cols)          | [base] file      | file (head)      |
#  | fixed-width, nofile        | read-only scratch| working tree     |
#  |                            |                  |                  |
#  | Review:                    |  diffthis        |  diffthis        |
#  | main -> feature            |                  |  +/- signs       |
#  | ------------------         |                  |  V,c to comment  |
#  | > M file.vim        [2]    |                  |                  |
#  |   A new_file.vim           |                  |                  |
#  |                            |                  |                  |
#  | Navigating / Commenting /  |                  |                  |
#  | Actions keybind hints      |                  |                  |
#  +----------------------------+------------------+------------------+

def CreateLayout(uuid: string)
  var state = reviews[uuid]

  tabnew
  state.review_tab = tabpagenr()
  t:revue_local_uuid = uuid

  execute $'topleft vertical :30new'
  execute $'file __RevueReview_{uuid}__'
  state.sidebar_bufnr = bufnr()
  SetupSidebarBuffer(uuid)

  wincmd l
enddef

def SetupSidebarBuffer(uuid: string)
  setlocal buftype=nofile
  setlocal bufhidden=hide
  setlocal noswapfile
  setlocal nobuflisted
  setlocal nowrap
  setlocal nonumber
  setlocal norelativenumber
  setlocal signcolumn=no
  setlocal cursorline
  setlocal winfixwidth
  setlocal filetype=revue-review

  b:revue_review_uuid = uuid

  nnoremap <buffer><silent> <CR>  <Cmd>call revue#review#OpenAtCursor()<CR>
  nnoremap <buffer><silent> ]f    <Cmd>call revue#review#NextFile()<CR>
  nnoremap <buffer><silent> [f    <Cmd>call revue#review#PrevFile()<CR>
  nnoremap <buffer><silent> s     <Cmd>call revue#review#Submit()<CR>
  nnoremap <buffer><silent> q     <Cmd>call revue#review#Close()<CR>
  nnoremap <buffer><silent> ?     <Cmd>call revue#review#ShowHelp()<CR>

  SetupSidebarHighlights()
enddef

def SetupSidebarHighlights()
  syntax clear
  syntax match RevueReviewHeader   /^  Review:/
  syntax match RevueReviewBranch   /^  .*\(->\|→\).*$/
  syntax match RevueReviewRule     /^  ─.*$/
  syntax match RevueReviewCurrent  /^▸ .*$/
  syntax match RevueReviewFile     /^  [MADRC] .*$/
  syntax match RevueReviewStatus   /^  [MADRC]/ contained containedin=RevueReviewFile
  syntax match RevueReviewBadge    /\[\d\+\]$/
  syntax match RevueReviewHelp     /^  [<\[].*$/
  syntax match RevueReviewPending  /^  .*pending.*/

  highlight link RevueReviewHeader    Title
  highlight link RevueReviewBranch    Directory
  highlight link RevueReviewRule      Comment
  highlight link RevueReviewCurrent   Statement
  highlight link RevueReviewFile      Normal
  highlight link RevueReviewStatus    Type
  highlight link RevueReviewBadge     WarningMsg
  highlight link RevueReviewHelp      Comment
  highlight link RevueReviewPending   WarningMsg
enddef

# ── Sidebar rendering ──────────────────────────────────────────────

var sidebar_line_map: dict<dict<any>> = {}

def RenderSidebar(uuid: string)
  var state = reviews[uuid]
  var bnr = state.sidebar_bufnr
  if bnr == -1 || !bufexists(bnr)
    return
  endif

  var lines: list<string> = []
  var lmap: dict<number> = {}

  lines->add($'  Review:')
  lines->add($'  {state.base} → {state.revision}')
  lines->add('  ' .. repeat("─", 26))
  lines->add('')

  var idx = 0
  for change in state.changes
    var lnum = len(lines) + 1
    var marker = idx == state.current_idx ? "▸" : ' '
    var badge = ''
    var comment_count = CommentsForFile(state, change.file)
    if comment_count > 0
      badge = $' [{comment_count}]'
    endif
    var path_label = has_key(change, 'old_file') ? change.old_file .. ' → ' .. change.file : change.file
    lines->add($'{marker} {change.status} {path_label}{badge}')
    lmap[string(lnum)] = idx
    idx += 1
  endfor

  lines->add('')

  var total = len(state.comments)
  if total > 0
    lines->add($'  {total} comment(s) pending')
  endif

  lines->add('')
  lines->add('  ' .. repeat("─", 26))
  lines->add('  Navigating:')
  lines->add('    <CR>    open file')
  lines->add('    ]f      next file')
  lines->add('    [f      prev file')
  lines->add('')
  lines->add('  Commenting:')
  lines->add('    V       select lines')
  lines->add('    c       add comment')
  lines->add('')
  lines->add('  Actions:')
  lines->add('    s       submit')
  lines->add('    q       close review')
  lines->add('    ?       help')

  setbufvar(bnr, '&modifiable', 1)
  deletebufline(bnr, 1, '$')
  setbufline(bnr, 1, lines)
  setbufvar(bnr, '&modifiable', 0)

  if !has_key(sidebar_line_map, uuid)
    sidebar_line_map[uuid] = {}
  endif
  sidebar_line_map[uuid] = lmap
enddef

def CommentsForFile(state: dict<any>, relpath: string): number
  var count = 0
  for comment in state.comments
    if comment.file == relpath
      count += 1
    endif
  endfor
  return count
enddef

# ── File navigation ────────────────────────────────────────────────

export def OpenAtCursor()
  var uuid = get(b:, 'revue_review_uuid', '')
  if empty(uuid) || !has_key(reviews, uuid)
    return
  endif

  var lnum = line('.')
  var lmap = get(sidebar_line_map, uuid, {})
  var idx = get(lmap, string(lnum), -1)
  if idx >= 0
    SwitchToFile(uuid, idx)
  endif
enddef

export def NextFile()
  var uuid = FindReviewUuid()
  if empty(uuid) || !has_key(reviews, uuid)
    return
  endif
  var state = reviews[uuid]
  if state.current_idx < len(state.changes) - 1
    SwitchToFile(uuid, state.current_idx + 1)
  endif
enddef

export def PrevFile()
  var uuid = FindReviewUuid()
  if empty(uuid) || !has_key(reviews, uuid)
    return
  endif
  var state = reviews[uuid]
  if state.current_idx > 0
    SwitchToFile(uuid, state.current_idx - 1)
  endif
enddef

def SwitchToFile(uuid: string, idx: number)
  var state = reviews[uuid]
  ClearMoves(state)
  state.current_idx = idx

  var change = state.changes[idx]
  var relpath = change.file
  var status = change.status
  # Renames/copies keep their old path in the base ref, not the new one.
  var base_relpath = get(change, 'old_file', relpath)

  if state.base_bufnr != -1 && bufexists(state.base_bufnr)
    execute $'bwipeout! {state.base_bufnr}'
    state.base_bufnr = -1
  endif

  diffoff!

  var sidebar_wid = bufwinid(state.sidebar_bufnr)
  wincmd l
  if winnr() == win_id2win(sidebar_wid)
    wincmd l
  endif

  if status == 'D'
    enew
    setlocal buftype=nofile
    setlocal bufhidden=wipe
    setlocal noswapfile
    execute 'file ' .. fnameescape($'revue-deleted-{uuid}-{idx}')
    setline(1, '(file deleted)')
    setlocal nomodifiable
  else
    var head_path = state.repo .. '/' .. relpath
    execute $'edit {fnameescape(head_path)}'
  endif

  var head_bufnr = bufnr()
  state.head_bufnr = head_bufnr
  b:revue_review_uuid = uuid
  b:revue_repo = state.repo
  setlocal signcolumn=auto

  nnoremap <buffer><silent> ]f <Cmd>call revue#review#NextFile()<CR>
  nnoremap <buffer><silent> [f <Cmd>call revue#review#PrevFile()<CR>
  xnoremap <buffer><silent> c <Cmd>call revue#review#CommentSelection()<CR>

  var ft = DetectFiletype(relpath)

  var base_result = revue#vcs#ShowFile(state.repo, state.base, base_relpath)

  aboveleft vnew
  setlocal buftype=nofile
  setlocal bufhidden=wipe
  setlocal noswapfile
  setlocal nomodifiable
  execute 'file ' .. fnameescape($'revue-base-{uuid}-{idx}')

  if base_result.ok
    setlocal modifiable
    setline(1, split(base_result.content, "\n"))
    setlocal nomodifiable
  else
    setlocal modifiable
    setline(1, '(new file)')
    setlocal nomodifiable
  endif

  if !empty(ft)
    &l:filetype = ft
  endif

  state.base_bufnr = bufnr()

  b:revue_review_uuid = uuid
  nnoremap <buffer><silent> ]f <Cmd>call revue#review#NextFile()<CR>
  nnoremap <buffer><silent> [f <Cmd>call revue#review#PrevFile()<CR>

  diffthis
  wincmd p
  diffthis

  PlaceDiffSigns(state, head_bufnr, relpath, base_relpath)
  RestoreAnnotations(state, head_bufnr)
  PaintMoves(state)
  RenderSidebar(uuid)

  if sidebar_wid != -1
    var target_line = -1
    var lmap = get(sidebar_line_map, uuid, {})
    for [lnum_str, file_idx] in items(lmap)
      if file_idx == idx
        target_line = str2nr(lnum_str)
        break
      endif
    endfor
    if target_line > 0
      win_execute(sidebar_wid, $'cursor({target_line}, 1)')
    endif
  endif

  var status_label = get(
    {M: 'modified', A: 'added', D: 'deleted', R: 'renamed', C: 'copied'},
    status, status
  )
  echom $'[{idx + 1}/{len(state.changes)}] {relpath} ({status_label}) — V to select, c to comment'
enddef

# ── Comment capture ─────────────────────────────────────────────────

export def CommentSelection()
  var uuid = FindReviewUuid()
  if empty(uuid) || !has_key(reviews, uuid)
    echohl WarningMsg
    echom 'revue: not in a review'
    echohl None
    return
  endif

  var state = reviews[uuid]
  var sel = revue#selection#Capture()
  if empty(sel)
    echohl WarningMsg
    echom 'revue: no selection'
    echohl None
    return
  endif

  var bufpath = expand('%:p')
  var relpath = bufpath
  if bufpath[: len(state.repo) - 1] == state.repo
    relpath = bufpath[len(state.repo) + 1 :]
  endif

  var text = input('Comment: ')
  if empty(text)
    return
  endif

  var comment: dict<any> = {
    id:    'cmt_' .. RandomId(6),
    file:  relpath,
    start: sel.start,
    end:   sel.end,
    text:  text,
    ts:    localtime(),
  }

  state.comments->add(comment)
  RenderAnnotation(bufnr(), comment)
  RenderSidebar(uuid)

  echom $'revue: comment added ({len(state.comments)} total)'
enddef

# ── Annotations ─────────────────────────────────────────────────────

def RenderAnnotation(bnr: number, comment: dict<any>)
  for lnum in range(comment.start, comment.end)
    try
      prop_add(lnum, 1, {
        type:    'RevueCommentAnchor',
        end_col: col([lnum, '$']),
        bufnr:   bnr,
      })
    catch
    endtry
  endfor

  try
    prop_add(comment.end, 0, {
      type:       'RevueComment',
      text:       '  // ' .. comment.text,
      text_align: 'after',
      bufnr:      bnr,
    })
  catch
    try
      prop_add(comment.end, col([comment.end, '$']), {
        type:  'RevueComment',
        bufnr: bnr,
      })
    catch
    endtry
  endtry
enddef

def RestoreAnnotations(state: dict<any>, bnr: number)
  var bufpath = expand('%:p')
  var relpath = bufpath
  if bufpath[: len(state.repo) - 1] == state.repo
    relpath = bufpath[len(state.repo) + 1 :]
  endif

  for comment in state.comments
    if comment.file == relpath
      RenderAnnotation(bnr, comment)
    endif
  endfor
enddef

export def ClearAnnotations(bnr: number)
  try
    prop_remove({type: 'RevueComment', bufnr: bnr, all: true})
    prop_remove({type: 'RevueCommentAnchor', bufnr: bnr, all: true})
  catch
  endtry
enddef

# ── Submit ──────────────────────────────────────────────────────────

export def Submit()
  var uuid = FindReviewUuid()
  if empty(uuid) || !has_key(reviews, uuid)
    return
  endif

  var state = reviews[uuid]

  if empty(state.comments)
    echom 'revue: no comments to submit'
    return
  endif

  var file_count = len(uniq(sort(mapnew(state.comments, (_, c) => c.file))))
  var choice = confirm(
    $'Submit {len(state.comments)} comment(s) across {file_count} file(s)?',
    "&Yes\n&No", 2
  )
  if choice != 1
    return
  endif

  var message = CompileMessage(state)
  var context = state.context
  if type(get(g:, 'RevueSubmitCallback', v:null)) == v:t_func
    g:RevueSubmitCallback(message, context)
  else
    setreg('+', message)
    setreg('"', message)
    echom 'revue: no submit callback configured — comments copied to the clipboard'
  endif
  Close()
enddef

# Provider-neutral entry point; the local :Review workflow remains available.
export def OpenReview(snapshot: dict<any>, Host: func, file_idx: number = -1): string
  return revue#backend#Open({id: 'provider-v1', connection: '', review: snapshot.key,
    snapshot: snapshot, Request: Host, legacy_key: snapshot.key}, file_idx)
enddef

def CompileMessage(state: dict<any>): string
  var parts: list<string> = []
  parts->add('Review feedback on the current changes:')
  parts->add('')

  var by_file: dict<list<dict<any>>> = {}
  for comment in state.comments
    if !has_key(by_file, comment.file)
      by_file[comment.file] = []
    endif
    by_file[comment.file]->add(comment)
  endfor

  for [file, comments] in items(by_file)
    comments->sort((a, b) => a.start - b.start)
    parts->add($'### {file}')
    parts->add('')
    for comment in comments
      parts->add($'**Lines {comment.start}-{comment.end}:** {comment.text}')
    endfor
    parts->add('')
  endfor

  return join(parts, "\n")
enddef

# ── Help ────────────────────────────────────────────────────────────

export def ShowHelp()
  var uuid = get(b:, 'revue_review_uuid', '')
  if empty(uuid) || !has_key(reviews, uuid)
    return
  endif
  var state = reviews[uuid]
  var bnr = state.sidebar_bufnr

  var help_lines = [
    '  Review mode:',
    '',
    '  j/k        Navigate file list',
    '  <CR>       Open file in diff',
    '  ]f / [f    Next / prev file',
    '',
    '  V + select, then c',
    '             Add comment',
    '',
    '  s          Submit comments',
    '  q          Close review',
    '  ?          This help',
    '',
    '  Press R to return...',
  ]

  setbufvar(bnr, '&modifiable', 1)
  deletebufline(bnr, 1, '$')
  setbufline(bnr, 1, help_lines)
  setbufvar(bnr, '&modifiable', 0)

  nnoremap <buffer><silent> R <Cmd>call revue#review#RefreshSidebar()<CR>
enddef

export def RefreshSidebar()
  var uuid = get(b:, 'revue_review_uuid', '')
  if !empty(uuid) && has_key(reviews, uuid)
    PaintMoves(reviews[uuid])
    RenderSidebar(uuid)
  endif
enddef

# ── Helpers ─────────────────────────────────────────────────────────

def FindReviewUuid(): string
  var uuid = get(b:, 'revue_review_uuid', '')
  if !empty(uuid)
    return uuid
  endif
  if len(reviews) == 1
    return keys(reviews)[0]
  endif
  return ''
enddef

# Changes in an editable source invalidate both ends of a displayed move.
export def InvalidateMoves(uuid: string)
  if has_key(reviews, uuid)
    ClearMoves(reviews[uuid])
  endif
enddef

def ClearMoves(state: dict<any>)
  for bnr in [state.head_bufnr, state.base_bufnr]
    if bnr > 0
      revue#moves#Clear(bnr, 'ReviewMoves_' .. state.uuid)
    endif
  endfor
  if state.head_bufnr > 0
    augroup ReviewMoveEdits
      execute $'autocmd! * <buffer={state.head_bufnr}>'
    augroup END
  endif
enddef

def PaintMoves(state: dict<any>)
  ClearMoves(state)
  if !get(g:, 'revue_moved_lines', 1)
    return
  endif
  var files: list<dict<any>> = []
  for change in state.changes
    var old_path = get(change, 'old_file', change.file)
    files->add({id: change.file, path: change.file, old_path: old_path,
      patch: revue#vcs#RawDiff(state.repo, state.base, change.file, old_path)})
  endfor
  var moves = revue#moves#Detect(files)
  var path = state.changes[state.current_idx].file
  revue#moves#Paint(state.base_bufnr, 'base', path, moves, 'ReviewMoves_' .. state.uuid)
  revue#moves#Paint(state.head_bufnr, 'head', path, moves, 'ReviewMoves_' .. state.uuid)
  augroup ReviewMoveEdits
    execute $'autocmd TextChanged,TextChangedI,BufWritePost,BufWinLeave <buffer={state.head_bufnr}> call revue#review#InvalidateMoves("{state.uuid}")'
  augroup END
enddef

def PlaceDiffSigns(state: dict<any>, bnr: number, relpath: string, base_relpath: string)
  sign_unplace('RevueDiffGroup', {buffer: bnr})

  var diff_output = revue#vcs#RawDiff(state.repo, state.base, relpath, base_relpath)
  if empty(diff_output)
    return
  endif

  var sign_id = 1
  for line in split(diff_output, "\n")
    var hunk = matchlist(line, '^@@ -\(\d\+\),\?\(\d*\) +\(\d\+\),\?\(\d*\) @@')
    if !empty(hunk)
      var new_start = str2nr(hunk[3])
      var new_count = empty(hunk[4]) ? 1 : str2nr(hunk[4])

      if new_count == 0
        var marker_line = max([1, new_start])
        sign_place(sign_id, 'RevueDiffGroup', 'RevueDiffDelete', bnr, {lnum: marker_line})
        sign_id += 1
      else
        for lnum in range(new_start, new_start + new_count - 1)
          sign_place(sign_id, 'RevueDiffGroup', 'RevueDiffAdd', bnr, {lnum: lnum})
          sign_id += 1
        endfor
      endif
    endif
  endfor
enddef

def DetectFiletype(relpath: string): string
  var ext = fnamemodify(relpath, ':e')
  if ext !~# '^\w\+$'
    return ''
  endif
  var ft_map: dict<string> = {
    vim: 'vim', py: 'python', js: 'javascript', ts: 'typescript',
    tsx: 'typescriptreact', jsx: 'javascriptreact', rb: 'ruby',
    rs: 'rust', go: 'go', java: 'java', c: 'c', cpp: 'cpp', h: 'c',
    sh: 'sh', bash: 'sh', zsh: 'zsh', lua: 'lua', json: 'json',
    yaml: 'yaml', yml: 'yaml', toml: 'toml', md: 'markdown',
    html: 'html', css: 'css', sql: 'sql',
  }
  return get(ft_map, ext, ext)
enddef

def RandomId(n: number): string
  var chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
  var result = ''
  for i in range(n)
    result ..= chars[rand() % len(chars)]
  endfor
  return result
enddef

export def Test()
  echom 'review: CompileMessage...'
  var mock_state: dict<any> = {
    comments: [
      {id: 'a', file: 'foo.py', start: 1, end: 3, text: 'Fix this', ts: 0},
      {id: 'b', file: 'foo.py', start: 10, end: 12, text: 'And this', ts: 0},
    ],
  }
  var msg = CompileMessage(mock_state)
  assert_true(msg =~ 'foo.py')
  assert_true(msg =~ 'Fix this')
  echom 'review: PASS'
enddef
