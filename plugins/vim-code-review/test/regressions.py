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
        (repo / name).write_text('old\n')
    git('add', '.')
    git('commit', '-m', 'base')
    for name in names:
        (repo / name).write_text('new\n')
    script = repo / 'test.vim'
    script.write_text('''set nocompatible nomore
execute 'set runtimepath^=' . fnameescape('ROOT')
runtime plugin/revue.vim
cd REPO
try
 call revue#review#Open()
 call revue#review#NextFile()
 call assert_false(exists('g:revue_injected'))
 call revue#review#Close()
 enew
 file selection-fixture
 call setline(1, ['one', 'two', 'three', 'four', 'five'])
 xnoremap <buffer> c <Cmd>let g:capture_mode = [mode(), mode(1), line('v'), line('.'), expand('%:p')]<Bar>let g:captured = revue#selection#Capture()<CR>
 call feedkeys('ggVjc', 'xt')
 call assert_equal([1, 2], [g:captured.start, g:captured.end])
 call feedkeys("\\<Esc>", 'xt')
 call feedkeys('4GVjc', 'xt')
 call assert_equal([4, 5], [g:captured.start, g:captured.end])
 call feedkeys("\\<Esc>", 'xt')
 call feedkeys('5GVkc', 'xt')
 call assert_equal([4, 5], [g:captured.start, g:captured.end])
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
