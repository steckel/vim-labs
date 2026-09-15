#!/bin/sh
# Runs test/run.vim and prints its output. Vim's -es mode swallows
# :echom, so we redirect messages to a temp file and cat it after.
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
log="$(mktemp)"
trap 'rm -f "$log"' EXIT

status=0
vim -Nu NONE --not-a-term \
  -c "redir! > $log" \
  -c "source $root/test/run.vim" \
  -c "redir END" \
  -c "qa!" >/dev/null 2>&1 || status=$?

cat "$log"
if [ "$status" -ne 0 ]; then exit "$status"; fi
vim -Nu NONE -n -es -S "$root/test/comments.vim"
printf '\ncomments: PASS (card wrapping, expanded threads, source anchors, replies, refresh)\n'
vim -Nu NONE -i NONE -n -es -S "$root/test/card_cache.vim"
printf 'card body cache: PASS (fresh-render equivalence, context changes, independent rows, bounded retention)\n'
vim -Nu NONE -i NONE -n -es -S "$root/test/messages.vim"
printf 'messages: PASS (metadata, nested quotes/code, lists, Unicode, focus, raw copy/quote)\n'
python3 "$root/test/links.py"
python3 "$root/test/rich_replies.py"
python3 "$root/test/edits.py"
python3 "$root/test/message_history.py"
python3 "$root/test/reactions.py"
python3 "$root/test/reaction_members.py"
python3 "$root/test/service_progress.py"
python3 "$root/test/pending.py"
python3 "$root/test/pending_discard.py"
python3 "$root/test/private_delete.py"
python3 "$root/test/published_delete.py"
python3 "$root/test/pending_edits.py"
python3 "$root/test/pending_create.py"
python3 "$root/test/pending_replies.py"
python3 "$root/test/action_guide.py"
python3 "$root/test/thread_entry.py"
python3 "$root/test/ux_trial.py"
vim -Nu NONE -i NONE -n -es -S "$root/test/interactions.vim"
printf 'interactions: PASS (panel targets, native mappings, focus, quote/copy, preview, refresh)\n'
vim -Nu NONE -i NONE -n -es -S "$root/test/layout.vim"
printf 'layout: PASS (80/120/200 columns, long threads, focus/return, sidebar, resize)\n'
python3 "$root/test/reading_tabs.py"
python3 "$root/test/reader_resize.py"
python3 "$root/test/initial_layout.py"
vim -Nu NONE -i NONE -n -es -S "$root/test/chrome.vim"
printf 'chrome: PASS (compact context, quiet bars, full preview details, narrow return, permissions, quoted paths)\n'
vim -Nu NONE -i NONE -n -es -S "$root/test/backends.vim"
printf 'backends: PASS (connection isolation, refresh routing, legacy draft keys)\n'
python3 "$root/test/local_backend.py"
python3 "$root/test/participants.py"
python3 "$root/test/runtime.py"
python3 "$root/test/assignment_ui.py"
python3 "$root/test/capabilities.py"
python3 "$root/test/batches.py"
python3 "$root/test/staging.py"
python3 "$root/test/thread_state.py"
python3 "$root/test/activity.py"
python3 "$root/test/comparisons.py"
python3 "$root/test/reanchor.py"
python3 "$root/test/history.py"
python3 "$root/test/ranges.py"
python3 "$root/test/thread_context.py"
python3 "$root/test/discovery.py"
python3 "$root/test/inventory.py"
python3 "$root/test/feedback_pages.py"
python3 "$root/test/feedback_lookup.py"
python3 "$root/test/private_pages.py"
python3 "$root/test/refresh.py"
python3 "$root/test/refresh_unchanged.py"
python3 "$root/test/timeline.py"
python3 "$root/test/readiness.py"
python3 "$root/test/suggestions.py"
python3 "$root/test/apply_suggestion.py"
python3 "$root/test/file_comments.py"
python3 "$root/test/unchanged_lines.py"
python3 "$root/test/captures.py"
