from pathlib import Path
from vim_pty import run

run(Path(__file__).with_suffix('.vim'))
run(Path(__file__).with_name('timeline_feedback.vim'))
run(Path(__file__).with_name('event_comparison.vim'))
print('timeline: PASS (older pages, deduplication, exact event/discussion return, bounded unloaded-target follow, cancellation, stale/malformed reads, draft retention)')
