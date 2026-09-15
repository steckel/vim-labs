vim9script

# test/run.vim — discovers and runs every `export def Test()` under
# autoload/, by convention: autoload/revue/foo.vim -> revue#foo#Test().
# Run via `test/run.sh`, or `vim -Nu NONE -es -S test/run.vim`.

var root = expand('<sfile>:p:h:h')
execute 'set runtimepath+=' .. fnameescape(root)

var failed = 0
var checked = 0

for f in globpath(root .. '/autoload', '**/*.vim', false, true)
  if join(readfile(f), "\n") !~ 'export def Test('
    continue
  endif

  var rel = f[len(root .. '/autoload/') : -5]
  var funcname = substitute(rel, '/', '#', 'g') .. '#Test'
  checked += 1

  # assert_true()/assert_equal() etc. don't throw on failure — they
  # append to v:errors — so a try/catch alone would silently pass a
  # test whose assertions failed but whose code otherwise ran fine.
  v:errors = []
  try
    function(funcname)()
    if !empty(v:errors)
      echom $'FAIL {funcname}: {join(v:errors, "; ")}'
      failed += 1
    endif
  catch
    echom $'FAIL {funcname}: {v:exception}'
    failed += 1
  endtry
endfor

if failed > 0
  echom $'{failed}/{checked} test(s) failed'
  cquit 1
endif

echom $'{checked}/{checked} test(s) passed'
qall!
