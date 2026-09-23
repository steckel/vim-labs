vim9script

# git.vim — git backend for revue

export def RepoRoot(): string
  var output = system('git rev-parse --show-toplevel 2>/dev/null')
  if v:shell_error != 0
    return ''
  endif
  return trim(output)
enddef

export def CurrentRevision(repo: string): string
  var cmd = printf('git -C %s branch --show-current 2>/dev/null', shellescape(repo))
  return trim(system(cmd))
enddef

export def DiffNameStatus(repo: string, base: string): list<dict<any>>
  var cmd = printf(
    'git -C %s diff --no-color --name-status %s 2>/dev/null',
    shellescape(repo),
    shellescape(base)
  )
  var output = trim(system(cmd))
  if v:shell_error != 0 || empty(output)
    return []
  endif

  var result: list<dict<any>> = []
  for line in split(output, "\n")
    var parts = split(line, "\t")
    if len(parts) < 2
      continue
    endif
    # git reports renames/copies as "R100\told\tnew" (3 fields) — the
    # similarity suffix is dropped, and `file` must be the new path
    # (that's what exists in the working tree); `old_file` carries the
    # path to look up in the base ref, which still has it under the
    # old name.
    var code = parts[0][0]
    if (code == 'R' || code == 'C') && len(parts) >= 3
      result->add({status: code, file: parts[2], old_file: parts[1]})
    else
      result->add({status: code, file: parts[1]})
    endif
  endfor
  return result
enddef

export def ShowFile(repo: string, ref: string, relpath: string): dict<any>
  var cmd = printf(
    'git -C %s show %s:%s 2>/dev/null',
    shellescape(repo),
    shellescape(ref),
    shellescape(relpath)
  )
  var output = system(cmd)
  if v:shell_error != 0
    return {ok: false, content: '', is_new: true}
  endif
  return {ok: true, content: output, is_new: false}
enddef

export def RawDiff(repo: string, base: string, relpath: string, old_relpath: string = ''): string
  # A rename's post-image path alone won't match the pathspec against
  # the base tree — git needs both sides to find and diff it.
  var pathspec = (empty(old_relpath) || old_relpath == relpath)
    ? shellescape(relpath)
    : shellescape(old_relpath) .. ' ' .. shellescape(relpath)
  var cmd = printf(
    'git -C %s diff --no-color --no-ext-diff %s -- %s 2>/dev/null',
    shellescape(repo),
    shellescape(base),
    pathspec
  )
  return system(cmd)
enddef
