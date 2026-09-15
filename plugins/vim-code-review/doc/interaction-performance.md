# Review interaction performance

The September 14 follow-up measures the current review loop at several sizes,
separates provider waiting from Vim adoption, and addresses a measured
long-thread refresh pause. Raw results and evidence (local evidence: `../output/interaction-latency/validation.json`)
include commands, source hashes, fixture definitions and individual samples.

## Measured change

Both the inline card renderer and the selectable discussion reader previously
retained at most 128 bodies, even when their byte budgets had spare capacity.
A profile of a 250-message thread retained about 299 KB of inline rows and
47 KB of reader data. Updating one message caused 123 card bodies to be rendered
again. The source card and the separate reader both contributed to the pause.

Their entry limits are now 512. Each cache retains the existing **1 MiB
serialized-data limit**. This uses more of the available budget for many small
messages; it does not increase that byte limit. The existing eight-thread
retention limit, source/width/context invalidation, exact body matching and
release of removed bodies remain. Metadata, permissions and action labels still
update. These are cache limits, not a bound on Vim's entire heap or transient
rendering allocations. Actual memory use can increase within the retained limits.

The change does not truncate, collapse, hide or reorder comments. Raw text and
Markdown spans are unchanged; cached output is checked against fresh rendering.

## Repeated fixture measurements

All figures below are milliseconds, measured serially in real Vim processes on
the same machine. Each scenario has five fresh processes and ten samples of
each refresh kind per version. The fixture supplies source/data in memory with
a 150 ms delayed refresh callback, so these numbers exclude GitHub/network wait.

| Scenario | Cold open median, after | Warm reopen median, after | Changed adoption median, before → after | Largest observed changed adoption, before → after |
| --- | ---: | ---: | ---: | ---: |
| 100 general comments | 55.5 | 44.7 | 41.2 → 43.3 | 55.9 → 57.3 |
| 100-message thread | 390.9 | 347.4 | 86.6 → 86.3 | 101.5 → 98.9 |
| 250-message thread | 919.0 | 822.5 | **707.1 → 184.6** | **718.8 → 193.5** |
| 500 files / 2,000 messages, four per thread | 327.8 | 320.4 | 131.7 → 131.5 | 135.8 → 133.5 |

The long-thread improvement is about 74% in this fixture. The small differences
in the other scenarios do not establish a meaningful speedup or regression.
Unchanged adoption medians after the change were 12.1, 11.5, 15.8 and 119.6 ms
respectively. Complete individual observations, including timer gaps, are in
the summary (local evidence: `../output/interaction-latency/summary.json`).

Definitions matter:

- **Cold open:** first plugin review opening inside a fresh Vim process,
  including initial source adoption and decoration. Vim executable startup,
  fixture JSON loading and external source retrieval are outside this interval.
- **Warm reopen:** close and reopen the same review inside that Vim process,
  including reading the saved local state. This is not merely focusing an
  already-open review, and it does not retain the old session's body caches.
- **Changed adoption:** Vim's refresh adoption interval after a valid response;
  one message changes while the user is actually in Insert mode in a draft.
- **Timer gap:** longest observed gap in a 20 ms Vim timer that also feeds
  typing. It can reveal a pause but is not an OS-paint or key-to-pixel metric.

Every run verifies draft bytes, buffer/window, Insert mode, a preserved register,
visible changed text and the selected reply on return. Both versions use the
same fixture generation. Instrumented profiling uses disposable runtime copies;
its inclusive times identify work and must not be added together or mixed into
the uninstrumented performance samples.

## Real GitHub measurements

The companion measurement uses an explicit read-only wrapper around the normal
provider and Vim bridge. It allows only opening, file reads and feedback pages;
remote mutations are rejected. Initial snapshot acquisition is timed in a
separate Python process. The Vim run then opens the conversation and refreshes
while typing. Temporary drafts and raw service snapshots are deleted afterward;
retained traces contain timing, endpoint labels and correctness results.

The result record separates provider construction/authentication, per-request
API wall time, whole subprocess time, initial Vim conversation opening, refresh
read time and Vim adoption. Concurrent API request durations must not be summed
as though they were sequential. API wall time includes network and server wait;
it does not isolate server CPU. Repeating a public PR does not guarantee either
cold or warm GitHub caches.

Across five reads of the same public Neovim review, initial provider subprocess
acquisition had a 4.36 s median (4.02–5.08 s observed). Initial conversation
adoption in Vim had a 90.8 ms median. Refresh reads had a 4.47 s median, with
13.3 ms median Vim adoption. All five returned unchanged snapshots; the largest
observed typing-timer gap was 44.6 ms. These runs verify responsive waiting and
unchanged adoption, not changed live feedback or a service latency guarantee.
Individual live traces (local evidence: `../output/interaction-latency/remote.json`).

## Cold-opening follow-up

Initial profiling attributed about a quarter of a 250-message cold opening to
wrapping text. The wrapper repeatedly split each remaining line into characters
and measured the growing prefix. Printable ASCII can be cut by bytes instead,
provided the cut cannot detach a combining character. The optimized wrapper
checks a prefix plus one lookahead byte using numeric character values. Unicode
and control-character boundaries retain the original character-aware path.
Word wrapping, tab expansion, body text and style spans keep their existing
semantics; this change does not add a cache or change a cache budget.

The comparison harness checks 293 text cases at nine widths and both ambiguous
character width settings, plus five full card bodies at five widths with styling
on and off: 5,374 comparisons against the retained original implementation.
Permanent tests also assert exact chunks at combining-character boundaries.
Equivalence evidence (local evidence: `../output/cold-open/equivalence.json`).

The cold-opening measurements use five fresh Vim processes for each combination
of version, viewport (80×24 and 120×40), and scenario (100-message thread,
250-message thread, 500 files with four messages each). They time source opening,
same-process reopening and first entry into the selectable reader separately.
Automatic source focus is enabled and the reader uses a managed tab. This differs
from the earlier refresh benchmark, which disabled automatic focus; compare
before/after within each experiment rather than comparing their absolute times.
Source bytes, the final message's complete body and equal inline-row counts are
checked. Measurements are serial and exclude service wait, executable startup
and OS paint. Five observations do not establish a population tail latency.

| Viewport / scenario | Cold open median, before → after (ms) | Reopen median, before → after (ms) |
| --- | ---: | ---: |
| 80×24 / 100-message thread | 584.8 → 552.2 | 590.9 → 544.0 |
| 80×24 / 250-message thread | **1,420.8 → 1,327.3** | 1,408.2 → 1,316.0 |
| 80×24 / 500-file inventory | 341.3 → 341.8 | 338.3 → 338.9 |
| 120×40 / 100-message thread | 301.3 → 277.3 | 296.6 → 278.5 |
| 120×40 / 250-message thread | **690.8 → 632.1** | 695.8 → 630.8 |
| 120×40 / 500-file inventory | 327.3 → 332.2 | 321.7 → 327.3 |

Long-thread opening improves about 6.6% at 80 columns and 8.5% at 120 columns
in these samples. The reader's long-thread entry improves 1,246.5 → 1,183.2 ms
at 80 columns; its 462.1 → 464.4 ms change at 120 columns does not establish
a meaningful difference. The small inventory changes do not establish a
speedup. This is a modest wrapping improvement, not an instant-opening result.
Distributions (local evidence: `../output/cold-open/summary.json`) and
validation record (local evidence: `../output/cold-open/validation.json`) retain the full scope.

The first attempted viewport experiment was rejected: its pseudo-terminal size
was unset, so Vim reset the wider runs to 80×24. Those samples are excluded.
The corrected harness configures the actual pseudo-terminal dimensions before
launching Vim and asserts the viewport after each timed phase.
Rejected experiment explanation (local evidence: `../output/cold-open/invalid-viewport-samples/README.md`).

## Discussion entry and return

Profiling the 80-column source-to-discussion transition found about 707 ms of
inline-card rendering inside a 1,174 ms reader entry. Creating the reader tab
briefly inherited the source buffer during `WinEnter`; the resize handler then
reflowed comments in the source tab being left behind. This was independent of
the reader's own Markdown formatting.

The resize handler now reflows only when a canonical source pane is in the
current tab. Returning through native window/tab navigation catches up with the
visible width. Incoming data still calls the annotation renderer directly, so
hidden comments continue to receive changed bodies, permissions and state.

Closing a reader also used to cross intermediate source sizes and select the
same file again. The managed return now defers resize-only events until the
final layout is restored and reuses the already-loaded source when the same
comparison/file and both source panes remain available. Missing panes, changed
files and unloaded source retain the existing selection/recovery path. A
`finally` block restores resize handling even if closing or navigation fails.

The regression checks exact source cursor/width, unchanged complete card
properties across a normal read/return, native tab return at a different pane
width, and changed feedback while source is hidden. The retained baseline fails
the hidden-repaint assertion; the corrected implementation passes it and the
full Revue suite. [Regression](../test/reader_resize.vim).

The before/after journey benchmark uses actual 80×24 and 120×40 pseudo-terminals,
five fresh Vim processes per version and size, with two entry/return journeys
per process. Each journey selects the exact second message and returns to the
same source position. Entry and return include final Vim redraw/reflow; source
bytes, dimensions, register and full-card row counts are checked. This measures
the whole journey so an entry improvement cannot conceal merely moving its
cost to the return. Service wait, executable startup and OS paint are excluded.

| Viewport / journey | Entry median, before → after (ms) | Return median, before → after (ms) | Total median, before → after (ms) |
| --- | ---: | ---: | ---: |
| 80×24 / first | 1,160.8 → 463.5 | 666.3 → 20.6 | **1,827.3 → 484.3** |
| 80×24 / repeated | 1,162.3 → 464.9 | 663.0 → 20.6 | 1,827.7 → 485.2 |
| 120×40 / first | 462.8 → 467.9 | 100.5 → 43.1 | **562.6 → 510.6** |
| 120×40 / repeated | 466.1 → 462.4 | 101.0 → 43.0 | 567.3 → 505.4 |

The narrow first journey is about 73% faster in this fixture. Wide entry itself
is essentially unchanged; the benefit there is returning without reselecting
the file. Total medians are computed from complete journey samples, not from
adding independent medians. All 40 journeys pass the source, position, viewport
and complete-card checks. These are one-machine samples, not population tails.
Samples and distributions (local evidence: `../output/reader-entry/summary.json`),
validation and limits (local evidence: `../output/reader-entry/validation.json`).

## Initial pane sizing and provider delivery

The narrow source-opening profile found two complete annotation passes: one
before automatic focus and another afterward. Initial focus now happens before
the file request, so synchronous delivery renders directly at the final width.
The instrumented 250-message fixture changes from two annotation passes to one.
Source coordinates, final pane geometry and expanded comments are unchanged.

This is a **synchronous-delivery improvement**, not evidence that GitHub loads
twice as fast. The bundled local backend and GitHub companion use asynchronous
jobs; their file callbacks can already arrive after focus has been established.
The accompanying delayed-delivery experiment checks this distinction rather
than treating all initial opening as the same path.

The benchmark runs five fresh Vim processes per version, delivery mode,
viewport and scenario: 60 synchronous samples across 100/250-message threads
and 500-file inventories, plus 20 delayed 250-message samples. The delayed
fixture schedules delivery after 50 ms. It records the Open call, the file
adoption callback and final-ready time separately; final-ready includes that
fixture wait plus explicit final Vim reflow/redraw. Source/card widths, full
row counts, final-message retention and terminal dimensions must match across
versions. No real network or service time is measured.

The regression covers synchronous, delayed and failed delivery at 80×24,
120×40 and short 120×24 viewports, plus automatic focus disabled. It checks
that layout is ready when the request starts, completed cards are retained,
delayed completion preserves the user's current window, and restoring the
layout restores the original split sizes. The PTY helper now accepts explicit
dimensions so these tests do not rely on `:set columns` surviving terminal
events. [Regression](../test/initial_layout.vim).

| Delivery / viewport / scenario | Final-ready median, before → after (ms) |
| --- | ---: |
| Synchronous / 80×24 / 100 messages | 548.7 → 268.9 |
| Synchronous / 80×24 / 250 messages | **1,320.2 → 612.3** |
| Synchronous / 80×24 / 500 files | 339.5 → 328.5 |
| Synchronous / 120×40 / 100 messages | 285.9 → 289.6 |
| Synchronous / 120×40 / 250 messages | 662.7 → 668.1 |
| Synchronous / 120×40 / 500 files | 326.9 → 335.0 |
| Delayed / 80×24 / 250 messages | 661.6 → 669.6 |
| Delayed / 120×40 / 250 messages | 716.7 → 720.6 |

The synchronous narrow 250-message fixture is about 54% faster. The wider,
inventory and delayed samples do not establish a meaningful improvement.
Delayed callback adoption itself is 569.0 → 576.5 ms at 80 columns and
603.5 → 605.6 ms at 120 columns. Its Open-call time is only about 25 ms because
the file has not arrived yet; that number must not be reported as review-ready
latency. All 80 samples preserve the final geometry and complete-card counts.
Samples (local evidence: `../output/initial-layout/summary.json`),
validation (local evidence: `../output/initial-layout/validation.json`).

## Remaining limits and next action

The synchronous duplicate-render defect is addressed. The earlier ~1.33-second
fixture opening is no longer a reason to queue another speculative optimization,
and it was not a measurement of actual asynchronous GitHub loading. The latest
delayed callback still spends about 0.58–0.61 seconds adopting 250 messages;
reader entry remains about 0.46 seconds. A 500-file inventory has measurable
cost even for unchanged refreshes. These are residual measured costs, not
unmet latency targets: no product SLA has been established.

The performance evidence requested by the current backlog is now available.
Prioritize the remaining exact-reply usability and historical-context work;
reopen performance refinement when a real workflow, changed live feedback or
new scale exposes a concrete problem. Preserve the current fixture baselines
for regression checks, rather than increasing caches or hiding comments.

The recorded sample maxima describe these runs, not production tail-latency
percentiles or a responsiveness SLA. Different bodies, terminal sizes, machines,
service permissions and network conditions can change costs. No unfamiliar-user
study or OS screenshot is claimed by this performance work. Existing visual
fixtures remain applicable because this change preserves rendered output.
