#!/usr/bin/env python3
"""Local UI regressions for the audit's filename and selection failures."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='revue-regression-') as directory:
    repo = Path(directory)
    def git(*args):
        subprocess.run(['git', '-C', str(repo), *args], check=True, capture_output=True)
    git('init', '-b', 'main')
    git('config', 'user.name', 'Fixture')
    git('config', 'user.email', 'fixture@example.invalid')
    names = ["a|call extend(g:, {'revue_injected': 1})", "z.vim|call extend(g:, {'revue_injected': 1})"]
    for name in names:
        (repo / name).write_text('old\n' * 5)
    git('add', '.')
    git('commit', '-m', 'base')
    for name in names:
        (repo / name).write_text('one\ntwo\nthree\nfour\nfive\n')
    script = repo / 'test.vim'
    script.write_text('''set nocompatible nomore
execute 'set runtimepath^=' . fnameescape('ROOT')
runtime plugin/revue.vim
let g:revue_local_dir = 'REPO/store'
let g:revue_draft_dir = 'REPO/drafts'
let g:revue_auto_focus = 0
cd REPO
function! WaitFor(Fn) abort
 let started = reltime()
 while !a:Fn() && reltimefloat(reltime(started)) < 10 | sleep 10m | endwhile
 if !a:Fn() | throw 'Review did not load: ' . execute('messages') | endif
endfunction
try
 Review HEAD
 call WaitFor({-> !empty(get(b:, 'revue_session', ''))})
 let g:id = b:revue_session
 call WaitFor({-> !empty(revue#session#Inspect(g:id).loaded)})
 call win_gotoid(revue#session#Inspect(g:id).headwin)
 ReviewNextFile
 call WaitFor({-> !empty(revue#session#Inspect(g:id).loaded)})
 call assert_false(exists('g:revue_injected'))
 for [keys, expected] in [['ggVjc', [1, 2]], ['4GVjc', [4, 5]], ['5GVkc', [4, 5]]]
   call feedkeys(keys, 'xt')
   let draft = revue#session#Inspect(g:id).drafts[-1]
   call assert_equal(expected, [draft.start, draft.end])
   call setline(1, 'Range feedback ' . string(expected))
   ReviewClose
 endfor
 call assert_equal(['one', 'two', 'three', 'four', 'five'], getline(1, '$'))
 call revue#session#Close()
catch
 call add(v:errors, v:exception . ' at ' . v:throwpoint . ' state=' . string(get(g:, 'capture_mode', [])))
endtry
call writefile(v:errors, 'REPO/errors')
qa!
'''.replace('ROOT', str(root)).replace('REPO', str(repo)))
    subprocess.run(['vim', '-Nu', 'NONE', '-n', '--not-a-term', '-S', str(script)], check=True, capture_output=True)
    errors = (repo / 'errors').read_text()
    if errors:
        raise SystemExit(errors)
print('PASS: hostile scratch names/extensions and first/repeated/reversed active selections')
