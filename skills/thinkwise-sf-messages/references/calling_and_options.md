# Calling a message from SQL, parameters, options, and process-flow wiring

Loaded on demand from `thinkwise_sf_messages`.

## Calling a message from SQL

Verified live (SQL Server, real parameter names from a live model — not the generic placeholder names
docs sometimes show):

```sql
exec dbo.tsf_send_message
    @msg_id        = 'customer_blocked',
    @parmtr_string = @parameter_xml,
    @abort_ind     = 1;
```

`tsf_send_message`'s real parameters, in order: `msg_id`, `parmtr_string` (the parameter XML, see
below), `abort_ind`. This is itself an ordinary subroutine (see
`thinkwise_sf_subroutines`) — call it exactly like any other, with named parameters.

### Abort behavior

On SQL Server: `abort_ind = 0` continues the flow (database severity level 9); `1` or `NULL` treats the
action as reversed (database severity level 16) — these severity *levels* are a SQL Server engine
concept triggered by the call, distinct from the modeled `msg.severity` enum above. **Calling an
aborting message does not automatically roll back a SQL Server transaction.** Logic that must stop
should roll back and return explicitly:

```sql
exec dbo.tsf_send_message @msg_id = 'customer_blocked', @parmtr_string = null, @abort_ind = 1;
rollback;
return;
```

In a `try/catch`, an aborting message transfers control to the catch block — design the transaction and
error-handling path together, or code may continue, partially commit, or replace the useful modeled
message with a generic exception.

**Database-platform behavior differs — don't assume SQL Server behavior is portable.** Oracle raises an
application error for aborting messages; DB2 always aborts a sent message and additionally provides
`v_message_text` for informational output specifically inside Defaults/Layouts. Check
`branch_rdbms_type` (see `thinkwise_sf_control_procedures`) before writing an
abort/rollback pattern and confirm against the target platform's real behavior, not just the SQL Server
default above.

### Progress messages

For long-running SQL tasks, `tsf_send_progress`'s real parameters, verified: `msg_id`, `parmtr_string`,
`percentage`.

```sql
exec dbo.tsf_send_progress
    @msg_id        = 'orders_processed',
    @parmtr_string = @parameter_xml,
    @percentage    = 40;
```

`-1` displays indeterminate/marquee progress; `0`–`100` displays determinate progress. Use determinate
progress only when the denominator is reliable — don't run an expensive recount solely to feed the bar.
Update at meaningful intervals, not every row, and never present `100%` before the transaction/
downstream work has actually finished.

A third framework subroutine, `tsf_send_assertion_msg` (verified live, parameters `success_ind`,
`parmtr_string`), exists alongside these two — an assertion-style helper distinct from either.

## Parameters and translated text

Translations use positional placeholders `{0}`, `{1}`, … The caller supplies XML elements in that
order. **Always build the XML safely** — `for xml path('text')` (or an equivalent safe builder) escapes
`&`, `<`, `>`, quotes, and apostrophes; hand-built string concatenation breaks on ordinary business
values like `R&D` and can create injection or malformed-message problems:

```sql
declare @parameters nvarchar(500) = concat(
    (select @customer_name for xml path('text')),
    (select @order_number  for xml path('text'))
);

exec dbo.tsf_send_message @msg_id = 'order_cannot_be_released', @parmtr_string = @parameters, @abort_ind = 1;
```

Supported parameter elements: `<text>` (literal runtime value), `<tab>`/`<col>` (translated table/
column label), `<domelement>` (translated domain-element label), `<task>`/`<taskparam>`,
`<report>`/`<reportparam>`. Use a translated-object reference when the message should show the same
localized label the UI already uses for that object; put literal runtime values in `<text>`.

Best practices:
- Keep placeholder order consistent across every language; a translator may still reorder `{0}`/`{1}`
  in their own sentence — check the reordering still reads correctly.
- Put the complete sentence in the translation; don't concatenate translated fragments in SQL.
- Include only values that help the user identify or fix the problem.
- Format dates/numbers/quantities/currencies for the user's locale when the runtime doesn't already.
- Test null, empty, long, Unicode, and XML-special-character values.
- Never embed secrets or sensitive identifiers.
- Prefer one meaningful aggregate message over one popup per row in bulk processing — see
  "Task confirmation messages" below for the modeled control that prevents exactly this.

## Message options — and a shared-translation gotcha

Each `msg_option` has a translated option name, a `response_type` (affirmative/negative), a
`msg_option_status_code`, an optional icon, and `order_no`. Use options when the decision is small and
discrete; use a task popup when the user must enter structured data; use a separate screen when the
decision needs substantial context.

**Verified live, and easy to get wrong: an option's translated label is keyed by its bare
`msg_option_id` alone — not scoped by `msg_id` — so every message that uses `msg_option_id = 'yes'`
shares the exact same `transl_object_transl` row (`type_of_object = 496`, `transl_object_id = 'yes'`).**
Confirmed by reading the identical row (same `transl` text "Yes") under two entirely unrelated messages'
`yes` options. This means:
- Reusing `yes`/`no` across many messages is fine, even desirable, when the generic "Yes"/"No" label is
  correct — it's one translation to maintain, and it stays consistent app-wide.
- **Editing the shared `yes`/`no` translation to fit one specific message's wording changes it on every
  other message using plain `yes`/`no` too**, silently. If a message needs its own distinct wording
  (e.g. "Release anyway" instead of a generic "Yes"), give that option a distinct `msg_option_id`
  entirely (verified real examples from the base model: `yes_continue`, `yes_always`) — don't reuse
  `yes` and then edit its shared translation.

Best practices for option text:
- Label with verbs and outcomes: **Release anyway**, **Return to planning**, **Cancel** — not bare
  "Yes"/"No" once the consequence needs to be explicit.
- Give affirmative/negative options a real correspondence with process-flow green/red arrows (see
  below); don't make the user guess from button position alone.
- Handle close, cancel, timeout, and unexpected status values downstream.
- Keep the default/focused option safe for destructive actions.
- Test every route, including messages with multiple affirmative *and* multiple negative options.

## Wiring into a process flow — the Show message action

Verified live against `process_action`'s metadata (this isn't yet documented in
`thinkwise_sf_process_flows` — cross-reference this section from there):

- **Action type**: `process_action.process_action_type = show_msg` (enum value `350`) — the docs/
  research sometimes call this "Show message"; the modeled enum id is `show_msg`.
- **Which message**: set `process_action.msg_id` directly on the action.
- **Routing on the chosen option, precisely**: `process_step.last_process_action_successful` (the
  ordinary `not_successful`/`successful`/`always` step condition used by every action type) is too
  coarse for a message with more than one affirmative or more than one negative option — it can't
  distinguish `yes` (`0`) from `yes_always` (`1`), for instance. To route on the **exact numeric status
  code**, capture it into a process variable and branch on that instead: the `show_msg` action has a
  pre-seeded `process_action_modeler_fixed_output` row keyed `output_parmtr_id = 'status_code'`
  (verified — this is a generic output present on the fixed-output enum, not `msg`-specific naming).
  Following the same pre-seeded/edit-only pattern documented in
  `thinkwise_sf_process_flows`'s "Wiring runtime values" section: query for that existing
  row (filtered by `process_action_id`), edit it to set `process_variable_id` to a matching-domain
  `process_variable`, then follow the action with one or more `decision` actions testing that variable's
  value against the specific `msg_option_status_code`s to route each branch.
- For a genuinely binary yes/no message, the plain `last_process_action_successful =
  successful`/`not_successful` step condition is enough — affirmative maps to `successful`, negative to
  `not_successful` — and the status-code capture above is unnecessary.

Keep the technical work in tasks/subroutines and let the process flow coordinate the user interaction —
a `show_msg` action should only ever present and branch, never itself contain business logic (see
`thinkwise_sf_process_flows`'s "Process logic and control procedures" section for where
that logic actually belongs).
