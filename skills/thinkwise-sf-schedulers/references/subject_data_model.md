# The subject a Scheduler points at — keys, hierarchy, and view subjects

Loaded on demand from `thinkwise_sf_schedulers`.

## Data model: the subject the Scheduler points at

The table or view the Scheduler is configured against (the **subject**) is the activity list — every
row is one activity, plus (optionally) resource-only rows with no activity. Get this right before
touching any Scheduler-specific configuration; the great majority of scheduler bugs (drag-drop 400
errors, appointments that silently fail to move, resources that don't group correctly) trace back to
the subject's data model, not the Scheduler settings layered on top of it.

**What the subject needs:**
- A column (or lookup) identifying the resource an activity belongs to.
- A start date/datetime column and an end date/datetime column — both nullable at the row level (see
  "Resource rows with no activity" below), even though the Scheduler configuration requires you to
  nominate both.
- Optionally a title column and a tooltip column.
- A primary key that is **stable, non-nullable, and does not shift under drag-and-drop.**

### Primary key: single non-nullable column, not a composite of resource + date

Give the subject its own surrogate identity column as the primary key — even when the activity
conceptually "belongs to" a resource, don't fold `resource_id` or a date column into the key. Dragging
an activity *updates* exactly those columns (resource-dragging rewrites the resource FK, date-dragging
rewrites the dates); a key that changes identity on every drag is a modeling smell and breaks anything
that references the row. the `PROJECT_MANAGER` reference model's scheduler subject
(`project_planning_scheduler`) has `no_of_pk_col = 1`, `max_pk_col_no = 1` — a single-column primary
key (`resource_scheduler_id`, `varchar`, mandatory) — never a composite of resource and dates.

**Known issue — nullable primary keys.** A subject built from a `UNION` of several sources (leave
requests, sick leave, regular activities combined into one feed) tends to end up with a key column
that's `NULL` for some branches. Community reports have traced drag-and-drop 400 errors directly to
this, confirmed by Thinkwise as *"a nullable primary key is not supported."* Synthesize a non-null row
identifier per branch instead of trusting whichever source column happens to line up across all of
them.

### Technique: prefixed synthetic keys for a hierarchy spanning multiple tables

Verified, real technique from `PROJECT_MANAGER`'s subject — a **department → team → employee**
resource hierarchy built from three physically different tables, unioned into one view. Shape of the
pattern: one `SELECT … UNION ALL …` branch per level/table (department, team, employee, plus the
activity-bearing table), where every branch prefixes its native ID before it reaches
`resource_scheduler_id` (`d_`, `t_`, `e_`, `pt_`) — this is what lets one non-nullable `VARCHAR` primary
key column serve several different source tables without collision (`d_7` and `e_7` are obviously not
the same row). Each branch's `parent_resource` reuses the exact same prefixed format as the level above
it, which is all a hierarchy grouping needs (see "Resource grouping" below); the activity branch's
`resource_id` reuses the assigned employee's own prefixed key rather than minting a new one. Reach for
this whenever a resource hierarchy spans genuinely different tables rather than one self-referencing
one. For the full worked SQL (all four branches, verbatim), read
`references/hierarchy_key_example.md`.

**Bonus — this can eliminate the need for an instead-of trigger on resource-dragging.** Because
`resource_id` is the *same prefixed string* on the resource's own row and on every activity assigned to
it, dragging an activity onto a different resource just copies that string across verbatim — no FK
lookup translation required. Building the grouping key as a plain, format-matched string rather than a
raw numeric FK is a legitimate way to avoid the instead-of trigger described below entirely.

### Resource rows with no activity

To show a resource even when it currently has no appointments, include a row for it with an empty
start and end date. This is why start/end date are "required" only in the sense that the Scheduler
configuration needs you to nominate which columns play that role — at the row level they're nullable,
and a null start/end is exactly how "resource with nothing scheduled" is represented. Verified: every
resource-only branch in the `PROJECT_MANAGER` example above selects `null as title`, `null as
start_date`, `null as end_date`.

### If the subject is a view: reference direction and the instead-of trigger

Scheduler subjects are very often views. Two rules matter, both defer-linked:

- **Reference direction is the same as for any table** — the PK-owner (the real table) is
  `source_tab_id` and the FK-holder (the view) is `target_tab_id`, exactly as table-to-table. Set
  `check_ref = false`, since a view carries no physical FK constraint; the direction itself does not
  change. Full explanation in `thinkwise_sf_data_model`.
- **Resource dragging needs an instead-of trigger on most view subjects.** Dragging an activity to
  another resource updates the "group by" column to the target resource's value; since lookup-value
  translation isn't applied automatically on that write, a view subject typically needs an
  *instead-of update* trigger translating the incoming value back into the correct underlying foreign
  key before it lands — unless the subject uses the prefixed-synthetic-key trick above, which sidesteps
  the need for one.

### Migrating off the legacy Resource/Task/Worktime model

The old Windows GUI Resource Scheduler extender pattern split **Resource**, **Task/Activity** and
**Worktime** into three separate subjects. The Universal Scheduler wants **one** subject where each
resource can produce multiple rows (one per activity) — exactly the `UNION ALL` shape above. There's no
first-class "worktime" concept anymore; model working/non-working time as ordinary activities styled
differently (see "'Work time' — a resource-availability/capacity pattern" under time-cell colouring
below), not as a parallel table. Full comparison
table and migration checklist in `references/legacy_migration.md`.
