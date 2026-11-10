# thinkwise-sf-sql-logic

Writes the SQL for a Thinkwise Software Factory business-logic concept: the code fragment
that goes inside a control-procedure template. It figures out which concept applies, confirms
it with you, resolves the target columns from your model metadata, and returns only the
fragment in the Thinkwise house style. Defaults to SQL Server (T-SQL) and infers Oracle,
DB2 or PostgreSQL from context.

Covers: Default, Layout, Context, Process, Trigger, Task, Handler, Function, Badge, Change
detection, Subroutine and Prefilter.

Beyond a single static fragment, it can also produce a **parameterized template** (with
`[bracket]` parameters) and **dynamic (SQL) assignment** code — the template plus the
`control_proc_code` that stages the assignment across many objects.

## When to use

- You want to write, extend or fix the logic fragment for one of the concepts above
  (for example: "write a default that fills the volume from length/width/height", "make this
  field mandatory when the status is approved", "update the parent total after saving a
  line", "validate on save", "set the badge count").
- Trigger it explicitly with the slash command `/logic`, or just describe what you want and
  it will confirm the concept before writing anything.
- It works in claude.ai/ThinkIT and in Claude Code, with or without a connector. With an
  Indicium MCP connector it reads the table context from the Software Factory itself;
  without one, paste the `get_sf_metadata` output (JSON) for the relevant table(s), or let it
  hand you a one-off query to fetch that context when the procedure is not installed.
- You want to apply one template across many objects at once ("add this default to every
  table with an `active` column", "tag-based include/exclude"): it returns a parameterized
  template plus the `control_proc_code` for a SQL/Staged assignment.

## When not to use

- You want a full stored procedure, trigger or function with the `create/alter` wrapper,
  parameter list and standard declarations. The skill returns only the fragment that goes
  inside the generated template, not the surrounding object.
- The requirement is declarative and modeled rather than code, such as a check constraint,
  a computed/calculated column, an input constraint, or a plain column default value. Those
  live in the data model, not in a control procedure.
- You need help with data modeling, reviewing existing T-SQL, migrating a data model, or
  writing user stories. Other Thinkwise skills cover those.
- The task is general SQL unrelated to a Software Factory logic concept.

## Notes

- The deliverable is always just the fragment; the Software Factory generates the object
  around it.
- Values backed by a fixed value list are written as the raw `db_value` from the metadata.
- Output follows the Thinkwise SQL formatting guidelines (lower case, leading commas,
  aligned aliases/joins/comparisons, `begin`/`end`, column lists for inserts).
- Dynamic assignment reads the **SF meta-model** (`references/sf_metamodel.md`) — the SF's
  own base data model, program-object naming, the `use_*` enable map, the tag layer and the
  staging temp tables — not `get_sf_metadata`.
