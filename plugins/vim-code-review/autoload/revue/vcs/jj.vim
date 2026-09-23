vim9script

# jj.vim — jj (Jujutsu) backend for revue
#
# jj has no branches, only revisions (change ids) and bookmarks, and no
# separate "commit" step — the working copy is itself a mutable
# commit (`@`). `CurrentRevision` surfaces the working-copy change id,
# not a branch name.
#
# `--git`-format diffs come straight from jj in unified-diff form, so
# RawDiff needs no translation. Machine-readable paths preserve jj's
# rename/copy pairing; summary paths such as "dir/{old => new}.py"
# are display labels, not filenames.

# `cd <repo> && jj` is used instead of `jj -R <repo>` because `-R` does not
# change the working directory, causing `jj diff` and `jj file show` to emit
# and resolve paths relative to Vim's current working directory rather than
# the repository root when invoked from a subdirectory.

export def RepoRoot(): string
  var output = system('jj root 2>/dev/null')
  if v:shell_error != 0
    return ''
  endif
  return trim(output)
enddef

export def CurrentRevision(repo: string): string
  var cmd = printf(
    'cd %s && jj log -r @ --no-graph -T %s 2>/dev/null',
    shellescape(repo),
    shellescape('change_id.short(8)')
  )
  var output = trim(system(cmd))
  if v:shell_error != 0
    return ''
  endif
  return output
enddef

export def DiffNameStatus(repo: string, base: string): list<dict<any>>
  var template = '"[" ++ json(status_char) ++ "," ++ json(path) ++ "," ++ json(source.path()) ++ "]\n"'
  var structured = system(printf(
    'cd %s && jj diff --color=never --from %s --template %s 2>/dev/null',
    shellescape(repo), shellescape(base), shellescape(template)))
  if v:shell_error == 0
    var entries: list<dict<any>> = []
    for line in split(structured, "\n")
      var fields = json_decode(line)
      var entry = {status: fields[0], file: fields[1]}
      if fields[0] == 'R' || fields[0] == 'C'
        entry.old_file = fields[2]
      endif
      entries->add(entry)
    endfor
    return entries
  endif

  # Older jj versions without diff templates still report ordinary A/M/D
  # entries through --summary.
  var cmd = printf(
    'cd %s && jj diff --color=never --from %s --summary 2>/dev/null',
    shellescape(repo),
    shellescape(base)
  )
  var output = trim(system(cmd))
  if v:shell_error != 0 || empty(output)
    return []
  endif

  var result: list<dict<any>> = []
  for line in split(output, "\n")
    var sp = stridx(line, ' ')
    if sp == -1
      continue
    endif
    result->add({status: line[0], file: line[sp + 1 :]})
  endfor
  return result
enddef

export def ShowFile(repo: string, ref: string, relpath: string): dict<any>
  var cmd = printf(
    'cd %s && jj file show -r %s -- %s 2>/dev/null',
    shellescape(repo),
    shellescape(ref),
    shellescape('file:' .. json_encode(relpath))
  )
  var output = system(cmd)
  if v:shell_error != 0
    return {ok: false, content: '', is_new: true}
  endif
  return {ok: true, content: output, is_new: false}
enddef

export def RawDiff(repo: string, base: string, relpath: string, old_relpath: string = ''): string
  var paths = shellescape('file:' .. json_encode(relpath))
  if !empty(old_relpath) && old_relpath != relpath
    paths ..= ' ' .. shellescape('file:' .. json_encode(old_relpath))
  endif
  var cmd = printf(
    'cd %s && jj diff --color=never --from %s --git -- %s 2>/dev/null',
    shellescape(repo),
    shellescape(base),
    paths
  )
  return system(cmd)
enddef
