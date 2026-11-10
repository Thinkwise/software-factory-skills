# Dynamic assignment (SQL control procedure)

For a dynamic request the control procedure's Assignment is **SQL** and the generation
Strategy is **Staged**. The `control_proc_code` runs at generation time, queries the SF
meta-model to select target objects, and writes rows into staging temp tables. The SF then
weaves the referenced template(s) into those objects during Generate source code.

Read `sf_metamodel.md` for the meta-model entities, program-object naming, the `use_*`
enable map, the tag layer and the staging temp-table columns. Read `parameters.md` for the
bracket syntax the template uses.

## Deliverable — two SQL files

1. **Source-code template** — the fragment, parameterized with `[brackets]` when column or
   object names vary across targets (see `parameters.md`). Saved under a `template_id`.
2. **control_proc_code** — the SQL below, referencing that `template_id`.

## The pattern

1. **Resolve targets once** into a table variable. Selection draws on `col` (column
   presence), the tag layer (include/exclude by `tag_id`), and `tab`/`task`/`report` flags
   (`type_of_table`, `allow_*`, etc.). Always filter on `@model_id` and `@branch_id`. Do not
   exclude views (`type_of_table <> 0`) by default — most concepts apply to views too.
   Type the collection variable with the SF **domain** of the id (e.g. `tab_id`), not a
   hardcoded `varchar(n)`: ids are domain-typed and a fixed length can be too short.
2. **Enable the concept first.** Front-load `update <object> set use_<concept> = 1 ... where
   use_<concept> = 0` for the targets, so the `<concept>_<object>` program object exists.
   Pick the flag from the `use_*` map; skip this step only if the concept has no flag.
   (Static assignment via the Assigning tab auto-enables a disabled concept; a SQL control
   procedure does not go through that task, hence this explicit update.)
3. **Stage the item.** One `#prog_object_item` per target on the existing
   `<concept>_<object_id>` object; `prog_object_item_id = <template_id>_<object_id>`;
   `template_id` = the template. Do **not** insert `#prog_object` when the object already
   exists (defaults/layouts/etc. on an enabled concept always do).
4. **Stage the parameters.** One `#prog_object_item_parmtr` per bracket parameter, with the
   resolved `parmtr_value`. Set `no_line_when_empty` per the parameter's intent.

## Worked example — DEFAULT "fill_active_from"

Assign to every base table that has both an `active` and an `active_from` column, skipping
tables tagged `XYZ`.

Template (`template_id = fill_active_from`, params `[active_col]`, `[from_col]`):

```sql
if @cursor_from_col_id = '[active_col]'
begin
    if @[active_col]   = 1
       and @[from_col] is null
    begin
        set @[from_col] = cast(getdate() as date)
    end
    else if @[active_col] = 0
    begin
        set @[from_col] = null
    end
end
```

control_proc_code:

```sql
declare @target table
(
    tab_id tab_id not null primary key
);

insert into @target (tab_id)
select t.tab_id
from tab t
where t.model_id      = @model_id
  and t.branch_id     = @branch_id
  and exists (select 1
              from col c
              where c.model_id  = @model_id
                and c.branch_id = @branch_id
                and c.tab_id    = t.tab_id
                and c.col_id    = 'active')
  and exists (select 1
              from col c
              where c.model_id  = @model_id
                and c.branch_id = @branch_id
                and c.tab_id    = t.tab_id
                and c.col_id    = 'active_from')
  and not exists (select 1
                  from tab_tag tt
                  where tt.model_id  = @model_id
                    and tt.branch_id = @branch_id
                    and tt.tab_id    = t.tab_id
                    and tt.tag_id    = 'XYZ');

--Enable the Default concept first, only where it is off.
update t
set t.use_defaults = 1
from tab t
where t.model_id     = @model_id
  and t.branch_id    = @branch_id
  and t.use_defaults = 0
  and exists (select 1 from @target tg where tg.tab_id = t.tab_id);

insert into #prog_object_item
(
     prog_object_id
    ,prog_object_item_id
    ,order_no
    ,template_id
)
select
     'default_' + tg.tab_id
    ,'fill_active_from_' + tg.tab_id
    ,100
    ,'fill_active_from'
from @target tg;

insert into #prog_object_item_parmtr
(
     prog_object_id
    ,prog_object_item_id
    ,parmtr_id
    ,parmtr_value
    ,order_no
    ,no_line_when_empty
)
select
     'default_' + tg.tab_id
    ,'fill_active_from_' + tg.tab_id
    ,p.parmtr_id
    ,p.parmtr_value
    ,p.order_no
    ,0
from @target tg
cross apply (values
     ('active_col', 'active',      1)
    ,('from_col',   'active_from', 2)
) p (parmtr_id, parmtr_value, order_no);
```

## Assumptions to flag to the user

State any of these that apply, so they can be verified against the model:

- Any `type_of_table` filter applied. Views are valid targets for most concepts, so views
  are excluded only on the user's explicit request — if a filter was added, say so.
- Column datatype expectations baked into the template (e.g. `active_from` is a date).
- Whether target column names are fixed or vary; parameterize when they vary.
- The `use_*` enable step targets exactly the concept being assigned.

## Ordering between control procedures

A SQL control procedure has a *Generation order no* (default 100). When two dynamic control
procedures depend on each other (one prepares model state the other selects on), set their
order numbers accordingly; otherwise leave the default.

## Formatting

Follow the house style from `conventions.md`: lower case, leading commas, aligned
joins/comparisons, `begin`/`end`, explicit column lists on inserts, `--comment` with no
space. The `control_proc_code` runs at generation time, so the runtime "avoid temp tables /
cursors" rules for defaults/triggers do **not** apply here — a table variable is fine.
