" Read-only fixture audit; run from any directory with Vim -Nu NONE -i NONE -n -es -S.
set nocompatible nomore
let s:root = expand('<sfile>:p:h:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let g:revue_draft_dir = tempname()
call mkdir(g:revue_draft_dir, 'p', 0700)
let g:discovery_fixture = json_decode(join(readfile(s:root . '/test/fixtures/comment-ui.json'), "\n"))
let g:discovery_requests = []
function! DiscoveryAuditHost(request, Done) abort
  call add(g:discovery_requests, a:request.op)
  if a:request.op !=# 'file' | throw 'Audit permits fixture file reads only' | endif
  call a:Done({'ok': 1, 'data': deepcopy(g:discovery_fixture.content)})
endfunction
let s:result = {}
try
  let snap = deepcopy(g:discovery_fixture.snapshot)
  let extra = extend(deepcopy(snap.files[0]), {'id': 'other', 'path': 'other file.vim', 'old_path': 'other file.vim'})
  call add(snap.files, extra)
  let thread = extend(deepcopy(snap.threads[0]), {'id': 'other-thread', 'path': extra.path, 'resolved': v:false})
  let thread.comments[-1].id = 'deep-reply'
  let thread.comments[-1].body = repeat('Earlier prose. ', 40) . 'AUDIT_NEEDLE'
  call add(snap.threads, thread)
  let id = revue#session#Open(snap, function('DiscoveryAuditHost'), 0)
  let state = revue#session#Inspect(id)
  let s:result.inline_enter = maparg('<CR>', 'n')
  let s:result.native_search = [maparg('/', 'n'), maparg('?', 'n')]
  call revue#session#Viewed(1)
  let state = revue#session#Inspect(id)
  let s:result.viewed = revue#progress#State(state, state.snapshot, state.snapshot.files[0])
  call revue#session#Filter('file', 'path completion')
  let state = revue#session#Inspect(id)
  let s:result.filtered_indices = revue#discovery#Files(state)
  let s:result.filter_keeps_source = state.index == 0
  call revue#session#Discussions('AUDIT_NEEDLE')
  let s:result.discussion_mode = b:revue_view
  let state = revue#session#Inspect(id)
  let s:result.full_body_search_found = 0
  for [row, target] in items(state.discoveryrows)
    if get(target, 'message', '') ==# 'deep-reply'
      call cursor(str2nr(row), 1)
      let s:result.full_body_search_found = 1
      break
    endif
  endfor
  let s:result.search_target = deepcopy(get(state.discoveryrows, string(line('.')), {}))
  call revue#session#OpenDiscussion()
  let state = revue#session#Inspect(id)
  let s:result.opened_file = state.snapshot.files[state.index].path
  let s:result.revealed = has_key(state.revealed_files, 'other')
  let s:result.selected_message = get(get(state.messagemap, string(line('.')), {}), 'comment', '')
  call revue#session#CloseView()
  let s:result.return_mode = get(b:, 'revue_view', '')
  let state = revue#session#Inspect(id)
  let s:result.return_target = get(get(state.discoveryrows, string(line('.')), {}), 'message', '')
  call revue#session#Close()
  let id = revue#session#Open(snap, function('DiscoveryAuditHost'), 0)
  let state = revue#session#Inspect(id)
  let s:result.reopened_viewed = revue#progress#State(state, state.snapshot, state.snapshot.files[0])
  call revue#session#Viewed(0)
  let state = revue#session#Inspect(id)
  let s:result.unviewed = revue#progress#State(state, state.snapshot, state.snapshot.files[0])
  let s:result.requests = g:discovery_requests
  call revue#session#Close()
catch
  let s:result.probe_error = v:exception . ' at ' . v:throwpoint
finally
  call delete(g:revue_draft_dir, 'rf')
endtry
call writefile([json_encode(s:result)], s:root . '/doc/research/discovery-audit-results.json')
if has_key(s:result, 'probe_error') | cquit | endif
qa!
