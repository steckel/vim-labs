vim9script

if exists('g:loaded_revue')
  finish
endif
g:loaded_revue = 1

# g:revue_default_base    — revision to diff against (default: 'main')
# g:RevueSubmitCallback — funcref(message: string, context: dict<any>),
#                           called on submit. Unset: comments go to the
#                           clipboard instead.
g:revue_default_base = get(g:, 'revue_default_base', 'main')

if empty(prop_type_get('RevueComment'))
  prop_type_add('RevueComment', {
    highlight: 'SpellCap',
    priority:  10,
  })
endif

if empty(prop_type_get('RevueCommentAnchor'))
  prop_type_add('RevueCommentAnchor', {
    highlight: 'SpellLocal',
    priority:  10,
  })
endif

command! -nargs=? Revue call revue#review#Open(empty(<q-args>) ? {} : {base: <q-args>})
command! -nargs=? -bang RevueLocal call revue#backends#local#Open(<q-args>, <bang>0)
command! -nargs=0 RevueLocalReviews call revue#backends#local#List()
command! -nargs=1 RevueLocalResume call revue#backends#local#Resume(<q-args>)

nnoremap <silent> <Plug>(revue-open) <Cmd>call revue#review#Open()<CR>
