vim9script

# vcs.vim — backend dispatch
#
# Picks a backend (git or jj) per working directory and forwards to
# it. Detection is cheap (a single rev-parse/root call) but cached per
# cwd anyway since Open() calls several of these in a row.
#
# jj is checked first: a repo colocated with git (jj's primary adoption
# path — `jj git init --colocate` on an existing git repo) answers yes
# to both `jj root` and `git rev-parse --show-toplevel`. Checking git
# first would silently give every colocated repo git semantics and jj
# would never be selected in the one setup it's most likely to be used.

var backend_cache: dict<string> = {}

def Backend(): string
  var cwd = getcwd()
  if has_key(backend_cache, cwd)
    return backend_cache[cwd]
  endif

  var result = ''
  if !empty(revue#vcs#jj#RepoRoot())
    result = 'jj'
  elseif !empty(revue#vcs#git#RepoRoot())
    result = 'git'
  endif

  backend_cache[cwd] = result
  return result
enddef

export def RepoRoot(): string
  var backend = Backend()
  if backend == 'git'
    return revue#vcs#git#RepoRoot()
  elseif backend == 'jj'
    return revue#vcs#jj#RepoRoot()
  endif
  return ''
enddef

export def CurrentRevision(repo: string): string
  var backend = Backend()
  if backend == 'git'
    return revue#vcs#git#CurrentRevision(repo)
  elseif backend == 'jj'
    return revue#vcs#jj#CurrentRevision(repo)
  endif
  return ''
enddef

export def DiffNameStatus(repo: string, base: string): list<dict<any>>
  var backend = Backend()
  if backend == 'git'
    return revue#vcs#git#DiffNameStatus(repo, base)
  elseif backend == 'jj'
    return revue#vcs#jj#DiffNameStatus(repo, base)
  endif
  return []
enddef

export def ShowFile(repo: string, ref: string, relpath: string): dict<any>
  var backend = Backend()
  if backend == 'git'
    return revue#vcs#git#ShowFile(repo, ref, relpath)
  elseif backend == 'jj'
    return revue#vcs#jj#ShowFile(repo, ref, relpath)
  endif
  return {ok: false, content: '', is_new: true}
enddef

export def RawDiff(repo: string, base: string, relpath: string, old_relpath: string = ''): string
  var backend = Backend()
  if backend == 'git'
    return revue#vcs#git#RawDiff(repo, base, relpath, old_relpath)
  elseif backend == 'jj'
    return revue#vcs#jj#RawDiff(repo, base, relpath, old_relpath)
  endif
  return ''
enddef
