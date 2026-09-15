set nocompatible nomore
execute 'set runtimepath^=' . fnameescape(expand('<sfile>:p:h:h'))
let g:revue_draft_dir = $REVUE_PARTICIPANT_DRAFTS
let config = json_decode(join(readfile($REVUE_PARTICIPANT_CONFIG), "\n"))
try
  call revue#backends#local#Resume(config.review, $REVUE_LOCAL_STORE)
  let attempts = 0
  while attempts < 500 && (!exists('t:revue_session') || empty(revue#session#Inspect(t:revue_session).loaded))
    sleep 10m
    let attempts += 1
  endwhile
  RevueThreads
  call cursor(1,1)
  RevueNextMessage
  RevueNextMessage
  let selected = revue#discussion#Selected(revue#session#Inspect(t:revue_session), line('.'))
  call assert_equal(config.agent_message, selected.comment)
  call assert_match('Agent', getline(selected.start))
  call assert_notmatch('Author', getline(selected.start))
  call assert_false(selected.message.capabilities.edit.enabled)
  RevueQuote
  call assert_match('> > Explain this change', join(getline(1,'$'), "\n"))
  RevueClose
  call assert_equal(config.agent_message, revue#discussion#Selected(revue#session#Inspect(t:revue_session),line('.')).comment)
  call revue#session#Close()
catch
  call add(v:errors, v:exception . ' at ' . v:throwpoint)
endtry
call writefile(v:errors,$REVUE_PARTICIPANT_ERRORS)
if !empty(v:errors) | cquit | endif
qa!
