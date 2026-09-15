vim9script

# selection.vim — visual selection capture

export def Capture(): dict<any>
  var active = mode() =~# '[vV\x16]'
  var start_line = active ? min([line('v'), line('.')]) : line("'<")
  var end_line = active ? max([line('v'), line('.')]) : line("'>")

  if start_line == 0 || end_line == 0
    return {}
  endif

  var bufpath = expand('%:p')
  if empty(bufpath)
    return {}
  endif

  var base = get(b:, 'revue_repo', getcwd())
  var relpath = bufpath
  if bufpath[: len(base) - 1] == base
    relpath = bufpath[len(base) + 1 :]
  endif

  var lines: list<string> = getline(start_line, end_line)

  return {
    relpath:  relpath,
    start:    start_line,
    end:      end_line,
    lines:    lines,
    filetype: &filetype,
  }
enddef

export def Test()
  echom 'selection: Capture type check...'
  var result = Capture()
  assert_true(type(result) == v:t_dict)
  echom 'selection: PASS'
enddef
