# Reuse decisions and the generated-code comment header

Loaded on demand from `thinkwise_sf_control_procedures`.

### Reuse — decide in this order, before writing anything new

1. **Reuse as-is.** An existing template already does exactly what's needed — add an assignment to
   the new program object, nothing new written or reviewed.
2. **Reuse with parameters.** An existing template is right but for a different column/object — if
   it's already parameterized, add an assignment and supply the parameter values.
3. **Generalize a near-match.** A template is one specific case of a more general rule — promote the
   hardcoded parts to `[PARMTR]`s and re-assign it, including back to its original object with that
   object's own values, so both uses share one template.
4. **Write new.** Only once the above are ruled out — and even then, parameterize the object-specific
   parts so the *next* reuse doesn't require writing another one.

Search the model's existing control procedures/templates by purpose, not by object name, before
concluding nothing fits — a well-named template describes what it does.

**Reuse one template across many assignments instead of duplicating it.** If the same logic applies
to several columns/tables (e.g. "default this date column to today" on both `absence.start_date` and
`lead.converted_date`), write the template **once** with a `[PARMTR]`-style placeholder standing in
for the column's business-logic variable name:

```sql
if [date_col] is null then
    [date_col] := current_date;
end if;
```

Then create one `template_prog_object_item` row per target `(rdbms_type, prog_object_id)`, all
pointing at the same `control_proc_id`/`template_id`, and give each one its own
`template_prog_object_item_parmtr` row: `parmtr_id = 'date_col'`, `parmtr_value = 'p_start_date'` for
the absence assignment, `parmtr_value = 'p_converted_date'` for the lead assignment. Verified
production pattern for this: `refresh_after_execute_tasks` (model `62903_TASKS_AND_REPORTS`) — one
template assigned to four different task prog_objects, each supplying a different `TASK_NAME` value
via its own parameter row. Don't default to "one template per column" — that duplicates code that
should live in one place and just be re-parametrized per assignment.

**Adding new logic to an object that already has a large existing template? Add a second template
instead of editing the first in place.** A control procedure can have more than one
`control_proc_template`, each assigned to the same (or a different) `prog_object_id` at its own
`order_no` — this isn't limited to the reuse-across-assignments case above. When the change is purely
additive (new statements that don't depend on rewriting what's already there), create a new template
under the same `control_proc_id`, assign it through the normal static-assignment flow, and position it
relative to the existing item(s)' `order_no` (query `prog_object_item` first to see what's already
there, including any framework wrapper items). This avoids reading back and hand-reconstructing a long
existing `template_code` field from truncation-safe chunked reads just to safely append to it — a real
risk of introducing a transcription error into an otherwise-working script. Verified live on an
`UPGRADE`-group object seeding hundreds of lines of demo data across two existing templates; a third,
purely-additive template slotted in cleanly at a chosen `order_no` between them.

**Can't find the program object to assign to?** A table/view/task/subroutine just created doesn't
have Layout/Default/Handler/etc. program objects yet — those `prog_object` rows only exist after a
generation pass, not from creating the object itself. Run the **Generate code group** task
(`task_generate_code_grp`) for the relevant code group first — invokable from any control procedure in
that group, or directly from the Assigning screen (`static_assignment_overview`). **This creates the
missing `prog_object` placeholder(s) so you have something to assign to — it does not itself produce
`prog_object_generated_code`**; see "Actually generating code" above for the second, job-based task
that's still needed to produce real code afterward. Applies any time a target can't be found:
run this before concluding something's broken.

## Creating a brand-new Task

When the logic needs a task that doesn't exist yet, create the task first, then come back here to
assign its logic. Task creation order is enforced (`task` → `tab_task` → `task_parmtr`), a table task
does not receive the table's primary key for free, and only `STORED_PROCEDURE` tasks go through the
control-procedure Assigning flow.

The full mechanics live in `thinkwise_sf_tasks` — read it rather than the summary that
used to sit here.
