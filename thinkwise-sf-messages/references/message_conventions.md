# Message naming, reuse, text, security, and testing

Loaded on demand from `thinkwise_sf_messages`.

## Naming and reuse

Lower-case, descriptive `msg_id`s naming the condition or result: `order_cannot_be_released`,
`customer_already_exists`, `planning_completed`, `integration_temporarily_unavailable`. Avoid `msg_001`/
`error_2` (no business meaning), `task_order_message` (describes location, not condition),
`something_went_wrong` (not actionable), or reusing `record_not_found` for unrelated objects that need
different remedies.

Reuse a message only when semantics, severity, location, parameter contract, *and* remedy are genuinely
identical — create a separate message the moment the user needs different guidance, even behind the
same underlying technical exception. Treat the `msg_id` and its parameter order as an interface: check
`detail_ref_msg_process_action`/`detail_ref_msg_task`/`detail_ref_msg_task_variant_overview` (its actual
usage) before renaming, deleting, or reordering placeholders.

- **If it's ambiguous whether an existing message can be reused, or whether a new `msg_option` should
  share `yes`/`no` (see the shared-translation gotcha above) versus get its own distinct id, ask the
  user rather than guessing compatibility** — per `thinkwise_sf_base`'s "Ask, don't
  default" convention (see its Shared conventions section).

## Writing effective message text

Pattern: **Action/subject + problem or result + next step.**

- "Order {0} cannot be released because no routing is configured. Add a routing and try again."
- "Import completed: {0} rows added and {1} rows skipped. Open the import log for details."
- "The planning run will replace {0} manually scheduled operations. Continue?"

Guidelines: use the user's vocabulary, not database vocabulary; state the affected object when
ambiguity is possible; make remediation specific; avoid blame ("You entered…"); avoid unexplained
abbreviations; no period after a one-word button label; keep primary text short and point to a log/
subject for large detail sets; for bulk work, summarize counts and provide a reviewable exception list
rather than one message per row.

## Security and privacy

Never expose SQL text, connection strings, tokens, credentials, stack traces, or internal paths.
Minimize personal/commercially sensitive data in messages and logs. Avoid confirming whether an
unauthorized record exists. Sanitize values originating from external systems. Keep detailed
diagnostics in access-controlled logs, using correlation ids that support investigation without
revealing internals. Remember messages may be captured in browser logs, screenshots, monitoring, or API
responses — don't put anything in one you wouldn't put in a log line visible to a wider audience.

## Unit testing

Load `thinkwise_sf_unit_tests` for the full mechanics — it already covers the
`unit_test_msg` entity ("expected message(s) for the sad-flow/validation path") as part of any code
type's unit test. At minimum, cover: the message appears for the exact invalid condition; boundary/valid
cases do *not* emit it; abort vs. non-abort behavior matches the design; transactions fully roll back on
failure; a bulk operation produces one useful summary rather than a message storm; parameters handle
null/Unicode/max-length/XML-special-character values. For a database-capture message specifically, also
verify: the regex matches representative raw errors, near-misses don't match, priority selects the most
specific message when several patterns could apply, and named groups populate the correct placeholders.

## Common failure patterns

See `references/practical_examples.md` for worked examples alongside this list: popup overuse (routine
success/layout refreshes interrupting the user), message storms (row-by-row validation in a bulk
action — check `popup_for_each_row` first), wrong severity (a warning used where continuing would
violate an invariant), abort without rollback, rollback without return (later code runs and hides the
original failure), hand-built XML breaking on `&`/`<` in real data, leaked implementation details
(index/constraint ids shown directly), a broad capture regex catching unrelated errors, unstable
priority (a generic base-model capture winning over a specific business rule), translation drift
(languages with different/missing placeholders), vague confirmation text, presentation logic baked into
a reusable subroutine, success noise on every save, suppression used as a fix for a real defect, and an
integration parsing localized prose instead of a stable status code.
