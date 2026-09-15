vim9script

# jj.vim — jj (Jujutsu) backend for revue
#
# jj has no branches, only revisions (change ids) and bookmarks, and no
# separate "commit" step — the working copy is itself a mutable
# commit (`@`). `CurrentRevision` surfaces the working-copy change id,
# not a branch name.
#
# `--git`-format diffs come straight from jj in unified-diff form, so
# RawDiff needs no translation. jj's own rename detection isn't
# exercised by --summary/--git today (a plain move shows as D+A, not
# R) — `old_relpath` is accepted for interface parity with the git
# backend but unused here; revisit if jj adds copy/rename tracking to
# these outputs.

export def RepoRoot(): string
  var output = system('jj root 2>/dev/null')
  if v:shell_error != 0
    return ''
  endif
  return trim(output)
enddef

export def CurrentRevision(repo: string): string
  var cmd = printf(
    'jj -R %s log -r @ --no-graph -T %s 2>/dev/null',
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
  var cmd = printf(
    'jj -R %s diff --from %s --summary 2>/dev/null',
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
    'jj -R %s file show -r %s %s 2>/dev/null',
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
  var cmd = printf(
    'jj -R %s diff --from %s --git -- %s 2>/dev/null',
    shellescape(repo),
    shellescape(base),
    shellescape(relpath)
  )
  return system(cmd)
enddef
