"""Validate the lab harness; scripted success is not human usability evidence."""
import importlib.util
import json
from pathlib import Path
import tempfile
from vim_pty import run

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('trial_launcher', ROOT / 'tools/ux_trial.py')
trial = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trial)
with tempfile.TemporaryDirectory(prefix='revue-trial-test-') as directory:
    for remapped in (False, True):
        for size in ((80, 24), (120, 40)):
            folder = trial.prepare(Path(directory), remapped)
            script = folder / 'check.vim'
            script.write_text('let g:revue_trial_settings = ' + json.dumps(str(folder / 'settings.json')) + '\n' +
                              "execute 'source ' . fnameescape(" + json.dumps(str(ROOT / 'tools/ux_trial.vim')) + ')\n' + r'''
try
  let source = [win_getid(), bufnr(), getpos('.')]
  call feedkeys("1\<CR>", 't')
  RevueThread
  call cursor(1,1)
  RevueNextMessage
  RevueNextMessage
  RevueNextMessage
  let selected = revue#discussion#Selected(revue#session#Inspect(g:trial_session), line('.'))
  call assert_equal('local-reply-2', selected.comment)
  call cursor(selected.body_start, match(getline(selected.body_start), 'Please cover') + 1)
  execute 'normal! v' . (strlen('Please cover an empty query too') - 1) . 'l'
  call feedkeys("\<Esc>", 'xt')
  call revue#session#Quote(1)
  let draft = join(getline(1,'$'), "\n")
  call assert_match('> Please cover an empty query too', draft)
  RevuePreview
  RevueClose
  call assert_equal(draft, join(getline(1,'$'), "\n"))
  RevueClose
  RevueClose
  call assert_equal(source, [win_getid(), bufnr(), getpos('.')])
  call assert_equal([], g:trial_write_attempts)
  call TrialSave()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors, $REVUE_CAP_STORE . '/errors')
if !empty(v:errors) | cquit | endif
qa!
''')
            run(script, dimensions=size)
            result = json.loads((folder / 'trace.json').read_text())
            assert result['service_calls'] == 0
            assert result['status'] == 'trace-only-not-a-usability-result'
            assert json.loads((folder / 'observer.json').read_text())['status'] == 'not-observed'
            assert {e['columns'] for e in result['events']} == {size[0]}
print('UX trial harness: PASS (default/remapped, 80/120 columns, exact selected quote and source return; no human observation claimed)')
