# Metadata query (fallback when no `get_sf_metadata` output is pasted)

The primary way to get table context is the `get_sf_metadata` procedure (see Step 1 of
`SKILL.md`): the user runs it and pastes the JSON. Use that whenever it is available.

When the user has **not** installed `get_sf_metadata`, or wants a quick one-off, offer the
query in `assets/metadata_query.sql` instead. It is the same logic as the procedure's
**compact** mode, inlined as a plain batch (no `create procedure`, `declare`s instead of
parameters), so it returns the **exact same JSON shape**. Read that pasted JSON exactly as
you would the procedure's output; no separate parsing path is needed.

It runs against the **Software Factory model database** (SQL Server), regardless of the
dialect the end product targets.

## This query is a fixed asset — its declare block is tunable, its body is not

`assets/metadata_query.sql` is a byte-for-byte static template for everything from
`SET NOCOUNT ON;` onward. Regenerating a 300+ line nested query as part of a chat reply is
exactly how it gets mangled — a dropped join, a misaligned
`for json path`, a skipped line in a repeated block. So below the `declare` block, nothing —
no join, no comment, no JSON key — is ever edited, rewritten, "cleaned up", or regenerated
by you, regardless of what the request needs.

The `declare` block at the top is different: every value in it is meant to be tuned per
request — that's expected, not a violation. It still has to happen mechanically (`str_replace`
on the specific line, never a freehand rewrite of the block), so the rest of the file stays
guaranteed untouched.

## Which flags to set

Always set from context, mechanically:
- `@model_id`, `@branch_id` — from the conversation or a prior `get_sf_metadata` call.
- `@tab_ids` — scope to the table(s) the request is actually about; leave `null` only when
  the user needs every table.

Structural flags (`@include_details`, `@include_lookups`, `@include_tasks`,
`@include_reports`, `@include_crud`, `@include_descriptions`, `@include_domain_elements`)
default to `1` in the asset, which is normally what you want — a **Context** concept in
particular needs the detail-tab refs, tasks and reports these provide. Turn one off only if
the user wants a smaller payload.

Code-type flags default to `0`. Turn on the one matching the concept you're about to write or
extend, so the existing code of that type comes back as context:

| Concept (Step 2 of SKILL.md) | Flag to set to `1`          |
|-------------------------------|------------------------------|
| Default                       | `@include_default`           |
| Layout                         | `@include_layout`            |
| Context                        | `@include_context`           |
| Process                        | `@include_process`           |
| Trigger                        | `@include_trigger`           |
| Handler                        | `@include_handler`           |
| Function                       | `@include_function`          |
| Task (the task's own code)     | `@include_task_code`         |
| Badge                          | `@include_badge`              |
| Change detection               | `@include_change`            |
| (generic) stored procedure     | `@include_stored_procedure`  |
| View                           | `@include_view`              |
| Manual (free-form)             | `@include_manual`            |

**Subroutine and Prefilter still don't have an obvious flag here** — the "Not covered here"
note below already applies to Subroutine signatures, and Prefilters aren't a distinct
`prog_object_type_id` in this query. Don't guess a flag for these; ask the user if their
existing code is needed, or proceed on structural context alone.

Only turn on the flag(s) the current request actually needs — leave the rest at the asset's
defaults rather than requesting everything "just in case."

## Workflow

1. Copy the asset to the workspace, e.g. `cp /mnt/skills/user/thinkwise-sf-sql-logic/assets/metadata_query.sql /home/claude/metadata_query.sql`.
2. Use `str_replace` to set `@model_id`, `@branch_id`, `@tab_ids`, and any relevant
   `@include_*` flags — one mechanical edit per line, per the table above. Nothing below the
   `declare` block is ever touched.
3. Deliver the file to the user with `present_files` so what they get is the exact bytes on
   disk. If they also want it inline in the chat, paste it as a ```sql code block by copying
   the content straight from the `view` output of the final file — do not retype it from
   memory or from having read it earlier in the conversation.
4. If no file tools are available in the current context, `view` the asset and paste its
   content verbatim as the code block — a literal copy, never a reconstruction.

## Notes

- **This file keeps its own formatting** — uppercase keywords, trailing commas, one
  `declare` block — instead of the lowercase/leading-comma house style used elsewhere in
  this skill. That's intentional: it's the user's actual source, so it is never reformatted
  to match house style; reformatting a 300+ line query is itself a regeneration risk.
- **Version switch for the datatype source.** The `#dttp_map` insert reads the datatype from
  `dom_query` on SF 2026.2+ and from `dom` on older versions. Because a static batch that names
  a missing table fails to bind (error 208) even in an untaken `IF`, the asset picks the table
  at run time (`OBJECT_ID('dom_query', 'U')`) and runs the insert through `sp_executesql`. The
  dynamic SQL runs in a child scope that still sees the `#dttp_map` created just above it, and
  `@model_id` / `@branch_id` are passed as parameters. Leave this mechanism as-is.
- **Multiple RDBMS.** If the model targets more than one RDBMS, `dom_query` may hold a row
  per RDBMS and duplicate columns; tell the user to add
  `and dq.rdbms_type = '<your rdbms>'` to the `WHERE` inside the dynamic-SQL string of the
  `#dttp_map` insert themselves if that happens (doubling the quotes, since it lives in a string
  literal) — that's a manual edit to the query body, which is the one thing you never do yourself.
- **Datatype fallback:** the `dttp` `CASE` in `#dttp_map` has an `ELSE dq.dttp` branch, so any
  datatype outside the mapped single-letter list falls back to its original full type name.
  That means unmapped types show up as their full name in the `t` field even in compact mode —
  expected behaviour, not a bug.

## Not covered here

Process procedures and Subroutine signatures do not live in these tables: their variable and
outgoing-step names come from the process-flow definition or the subroutine definition. For
those, ask the user for the generated procedure's parameter list rather than a metadata
query.
