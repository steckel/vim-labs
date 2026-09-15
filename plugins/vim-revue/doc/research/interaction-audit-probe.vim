" Read-only backend audit. Run from the repository root:
" vim -Nu NONE -i NONE -n -es -S doc/research/interaction-audit-probe.vim
" Uses a disposable outbox; records observations, not expected future behavior.
set nocompatible nomore
let s:root = expand('<sfile>:p:h:h:h')
execute 'set runtimepath^=' . fnameescape(s:root)
let g:revue_draft_dir = tempname()
call mkdir(g:revue_draft_dir, 'p', 0700)
let g:audit_fixture = json_decode(join(readfile(s:root . '/test/fixtures/comment-ui.json'), "\n"))
let g:audit_calls = []
function! AuditHost(request, Done) abort
  if a:request.op ==# 'file'
    call a:Done({'ok': 1, 'data': g:audit_fixture.content})
  elseif a:request.op ==# 'refresh'
    call a:Done({'ok': 1, 'data': deepcopy(g:audit_fixture.snapshot)})
  else
    " Never connect to a provider or accept a new write.
    call add(g:audit_calls, {'kind': a:request.draft.kind, 'reconcile': a:request.reconcile})
    if !a:request.reconcile | throw 'Audit prohibits new writes' | endif
    call a:Done({'ok': 0, 'unknown': 0, 'error': 'Fixture: receipt read denied'})
  endif
endfunction
let s:result = {}
try
  let snap = g:audit_fixture.snapshot
  let single = {'id': 'audit-single', 'kind': 'reply', 'thread': 'local-thread',
        \ 'body': 'Fixture only', 'state': 'unknown', 'head': snap.head,
        \ 'base_tip': snap.base, 'snapshot': snap.snapshot}
  let item = extend(deepcopy(single), {'id': 'audit-item', 'state': 'draft'})
  let batch = {'id': 'audit-batch', 'kind': 'batch', 'items': [item], 'body': '',
        \ 'state': 'unknown', 'head': snap.head, 'base_tip': snap.base, 'snapshot': snap.snapshot}
  call writefile([json_encode({'version': 1, 'key': snap.key, 'drafts': [single, batch]})],
        \ g:revue_draft_dir . '/' . sha256(snap.key) . '.json')
  let id = revue#session#Open(snap, function('AuditHost'), 0)
  let session = revue#session#Inspect(id)
  let s:result.native_diff_keys = [maparg(']c', 'n'), maparg('[c', 'n')]
  let s:result.backward_search_key = maparg('?', 'n')
  let s:result.inline_enter = maparg('<CR>', 'n')
  let s:result.resolve_command_exists = exists(':RevueResolve')
  try
    RevueResolve
    let s:result.resolve_result = 'returned'
  catch
    let s:result.resolve_result = v:exception
  endtry
  call revue#session#Threads()
  call revue#session#Help()
  let s:result.help_thread_targets = deepcopy(revue#session#Inspect(id).threadmap)
  let s:result.help_reply_command = exists(':RevueReply')
  call revue#session#Refresh()
  let s:result.view_after_help_refresh = b:revue_view
  call win_gotoid(session.treewin)
  for [row, target] in items(revue#session#Inspect(id).rows)
    if get(target, 'id', '') ==# single.id
      call cursor(str2nr(row), 1)
      call revue#session#Activate()
      break
    endif
  endfor
  call revue#session#Send()
  let s:result.single_after_failed_receipt_read = revue#session#Inspect(id).drafts[0].state
  let s:result.single_editable = &modifiable
  call revue#session#CloseView()
  call revue#session#Batch(batch.id)
  call revue#session#SendBatch()
  let s:result.batch_after_failed_receipt_read = revue#session#Inspect(id).drafts[1].state
  call revue#session#UnpackBatch()
  let s:result.draft_kinds_after_unpack = map(copy(revue#session#Inspect(id).drafts), {_, d -> d.kind})
  let s:result.requests = g:audit_calls
  call revue#session#Close()
catch
  let s:result.probe_error = v:exception . ' at ' . v:throwpoint
finally
  call delete(g:revue_draft_dir, 'rf')
endtry
call writefile([json_encode(s:result)], s:root . '/doc/research/interaction-audit-results.json')
if has_key(s:result, 'probe_error') | cquit | endif
qa!
