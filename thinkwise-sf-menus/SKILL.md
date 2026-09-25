---
name: thinkwise-sf-menus
description: Reference guide for creating and maintaining application menus, groups, and items — including per-role visibility — in a Thinkwise Software Factory model. Use via an MCP connector with Software Factory access whenever creating, inspecting, or securing a menu, and before deciding whether a new screen/report/task belongs on an existing menu/group or needs a new one.
---

# Creating and Maintaining a Menu in the Thinkwise Software Factory

Reference for the menu's full shape: `menu` (container: one `menu_type` — list bar / tile / tree —
serving one or more platforms via `menu_platform`) → **group** (`list_bar_grp` / `tile_grp` /
`module_grp` — a labelled section) → **item** (`list_bar_item` / `tile` — points at exactly one
table, table variant, report, report variant, task, or task variant) → per-role visibility
(`role_menu_overview` / `role_list_bar_grp_overview` / `role_list_bar_item_overview` /
`role_tile_grp_overview` / `role_tile_overview`). Every entity, field, enum value, and task signature
below was confirmed live against a real connected model (`sf/manage_menu` domain, model `INSIGHTS`) —
not guessed from documentation.

Apply this whenever an MCP connector with Software Factory access is used to create, extend, reorganize,
or secure a menu.

## Golden rule: don't decide the structure silently — ask

The sections below give a real decision framework, but "which menu," "which group," and "new vs.
existing" are product decisions about what a user will look for and where — wrong guesses cost
findability and muscle memory, and are annoying to unwind later. **Whenever the framework below doesn't
make the answer obvious, stop and ask the user** which existing menu/group to extend, or confirm they
actually want a new one — do not silently pick the conservative-sounding option and proceed. This
applies especially to:

- Whether a new screen/report/task belongs on an **existing menu** or needs a **new one**.
- Whether it belongs in an **existing group** or needs a **new group**.
- **Which menu type (list bar / tile / tree) a brand-new menu should use.** Even when the profiles
  below point clearly to one type, state the recommendation and *confirm it with the user before
  creating the menu* — don't just proceed on your own read of the fit. This is a one-way door in
  practice: the three types aren't a config flag you flip later, they're a different structure and a
  different modeling experience, so get it confirmed before, not after, groups and items pile up on
  top of it.
- Any **delete** (`task_delete_menu`/`task_delete_list_bar_grp`/`task_delete_tile_grp`/etc.) or
  **role-grant change** that removes access someone currently has — confirm intent first, these are
  easy to get wrong quietly.

Only skip asking when the answer is genuinely unambiguous — e.g. the user names the exact group, or
there is exactly one menu of the relevant platform/type and the request obviously belongs in an
existing group already covering that subject.

### Step 0: propose a plan

Don't confirm these decisions one at a time as they come up mid-build — that produces a series of
disconnected yes/no prompts and lets an earlier answer quietly commit you before the later ones are
even asked. Before making the first `stage_resource`/`stage_task` call, work through
`references/menu_design_guide.md`'s "Recommended design workflow" (its steps 1-6: personas/goals,
legitimate starting points, organizing principle, clustering/naming, menu type, new-vs-existing menu)
against the actual request, and turn the result into **one written plan** that bundles every decision
at once — menu, group, item(s), type, naming, `order_no`, and role visibility. Present that whole plan
to the user and get their explicit confirmation on it as a package before creating anything. Only
after that confirmation move on to the "Creating things" mechanics below. If the user's answer changes
one part of the plan, re-confirm the updated plan as a whole rather than resuming piecemeal. This is
the `thinkwise_sf_base` "Confirm-before-mutate" convention applied at this skill's
own grain; it isn't superseded by anything below about these entities' write mechanics.

## What belongs in the menu at all

Before deciding *which* menu/group/type, decide whether the object is a legitimate starting point in
the first place — the menu is a curated set of places to begin, not an inventory of every model
object. Add a subject/task/report only when a real user starts or resumes work from it directly;
route anything that acts on a *selected* record (a contextual task, a record-specific report, a
child/detail table) onto that subject instead, not the menu.

Quick smell test — lean toward **not** a menu item when it's:
- a link/child/history/staging table naturally reached through a master-detail relationship,
- a task or report that requires a current record to make sense,
- a one-off migration/diagnostic/seed-data utility,
- a near-duplicate of something already reachable elsewhere with no distinct audience benefit.

For the full in/out criteria, organizing-principle choice, naming, ordering, group-size heuristics,
contextual-navigation alternatives, and anti-patterns, see
`references/menu_design_guide.md` — that's the design layer this section only summarizes; the rest of
this file covers how to wire whatever you land on through the API.

## The three levels

| Level | Entities | Notes |
|---|---|---|
| **Menu** | `menu` | Keyed by `(model_id, branch_id, menu_id)`. `menu_type` (enum: `list_bar`=0, `tree`=1, `tile`=2) and `menu_platform` (bitmask, see below) are set once and define the whole container. |
| **Group** | `list_bar_grp` / `tile_grp` / `module_grp` | A labelled section heading. List bar and tile groups are **flat — no nesting**. `module_grp` alone has a self-referencing `grp_module_grp_id`, allowing true multi-level folders — see "Which type" below for why that's a narrow upside. |
| **Item** | `list_bar_item` / `tile` | Points at exactly one target via `menu_item_type` (enum: `tab`=0, `report`=2, `task`=3 — value `1` is `deprecated`) plus the matching `tab_id`/`tab_variant_id`, `report_id`/`report_variant_id`, or `task_id`/`task_variant_id`. |

## Which type to use

All three types can technically hold the same tabs, reports, and tasks — what separates them is the
audience, the item count, and (verified below) how well the API actually supports maintaining them.

| Type | Verdict | Use it for | Why |
|---|---|---|---|
| **List bar** (`list_bar`) | **Default** | Internal, back-office applications — several groups, each holding several-to-many items. | Dense, flat, well-supported API (see task reference below). Start here unless one of the others has a specific reason to win. |
| **Tile** (`tile`) | **Situational** | A small, curated set of entry points (roughly a dozen, not dozens); customer-facing portals/self-service where the audience isn't trained on the app; handheld/touch/kiosk; a landing "front door" before a list-bar back office. | `tile_size` (enum: `small`/`medium`/`wide`/`large`) gives visual prominence, but tiles don't compress — past a handful you're scrolling a wall of squares. |
| **Tree** (`tree`) | **Avoid** | Only a subject with genuine multi-level hierarchy that list bar/tile's flat groups truly can't express, and even then treat it as a last resort. | Legacy from the Windows/Web GUIs; Thinkwise has said Universal UI is bringing list bar "groups inside parent groups" nesting, closing tree's one advantage. **Also a real API gap in this domain**: `module_grp` has zero bound tasks (no create/rename/delete helpers — list bar and tile each have full sets, see below), and there is no `module_item`-equivalent entity exposed in this domain at all — tree's individual menu items aren't reachable through this API the way list bar/tile items are. If a tree menu already exists, treat it as migration debt toward list bar, not a foundation to keep building on. |

## New menu, or the existing one?

A `menu` is keyed to a **type + platform** combination, not to a role or a workflow.

**Create a new menu when** a genuinely new `menu_platform` target has no menu yet, or a truly distinct
application in the same model needs its own top-level entry point (rare — usually a module/role
concern, not a menu one).

**Stay on the existing menu when** the real need is per-role visibility (use grants — see below) or a
different look on a different device (there is no built-in responsive/conditional menu switching;
forking the menu just gives two menus to keep in sync). As of Thinkwise Platform 2026.1, Universal UI
is the only supported interface — treat `universal` (bit `8`) as the one menu type actively maintained
going forward; new work shouldn't default to spreading itself across legacy `windows`/`web`/`mobile`
menus.

**Whenever this leads to actually creating a new menu, verify the `menu_type` choice with the user
first** — state which of list bar / tile / tree the "Which type to use" table above points to and why,
and get their confirmation before creating it, even if the fit looks obvious. See the golden rule above.

`menu_platform` is a bitmask — one menu can cover several platforms at once:

| Platform | Value |
|---|---|
| `windows` | 1 *(legacy)* |
| `web` | 2 *(legacy)* |
| `mobile` | 4 *(legacy)* |
| `universal` | 8 *(current)* |

Combinations add (`windows_web`=3, `windows_web_mobile_universal`=15, etc.), e.g. a
real `customer_portal_tile` menu uses `menu_platform=10` (`mobile_universal`).

## New group, or an existing one?

List bar and tile groups are flat — a group name is a promise about what a user finds under it.

**Create a new group when** the items are a distinct business subject, workflow stage, or audience a
user would look for under its own label (a real model separates `CRM`, `HR`, `projects`, `finance`,
`control`, `settings` as six sibling groups on one list-bar menu — each a clearly different subject,
not a table-technical split).

**Add to an existing group when** the item is another variant of something already there, or a
follow-on step in the same workflow the group already represents.

**Don't fake nesting** with label prefixes ("Sales – Invoicing", "Sales – Reporting") — list bar/tile
groups can't nest, and it reads as clutter, not structure. A subject with genuine two-level hierarchy is
the one case `module_grp`'s nested groups earn their keep, weighed against tree's API limitations above.

## Placing items

- **One item per target** — don't overload one item for two purposes; add a second item instead.
- **Order by workflow, not alphabet** — see `order_no` below.
- **Reach for menu search before more structure.** Once a menu holds many items, turn on
  `menu.show_filter` rather than inventing another layer of grouping to compensate.
- **When more than one existing group is a plausible fit, ask — don't silently pick the "closest"
  one.** The same goes for a non-obvious placement within the group (order relative to neighbors) or
  icon choice: state the option you'd lean toward and why, and get the user's confirmation, rather than
  resolving the ambiguity on your own judgment.

## Security: grant, don't fork

Every level carries its own per-role overview entity, each with a `granted` flag and a `rights_icon`:

| Level | Overview entity | Key |
|---|---|---|
| Menu | `role_menu_overview` | `(model_id, branch_id, role_id, menu_id)` |
| List bar group | `role_list_bar_grp_overview` | `(…, menu_id, list_bar_grp_id)` |
| List bar item | `role_list_bar_item_overview` | `(…, list_bar_grp_id, list_bar_item_id)` |
| Tile group | `role_tile_grp_overview` | `(…, menu_id, tile_grp_id)` |
| Tile | `role_tile_overview` | `(…, tile_grp_id, tile_id)` |

`rights_icon` enum: `super_user`=1, `grant`=2, `read`=3, `hidden`=4, `unauthorized`=5.

a row already exists for **every role** at every level (e.g. querying
`role_menu_overview` for one menu returned one row per role in the model, each already `granted: true`
or `false`). This is the same "overview" pattern seen elsewhere in the platform (an implicit row per
candidate combination) — **locate the existing row by its full key and edit `granted`; don't try to add
one.** Group/item overview rows also carry an `available` flag, distinct from `granted` — treat
`available` as whether this role's group is even eligible to be configured here, and `granted` as the
actual on/off switch you're setting. `rights_icon` reads as the resulting computed state rather than a
field to set directly — patch `granted` and re-read `rights_icon` to confirm the effect, rather than
writing to `rights_icon` itself.

**This is why "different roles need different menus" is almost never a real reason to create a second
menu** — set the grant at whichever level (menu/group/item) matches what should actually be hidden.

## Creating menus, groups, items, and role rights

Call `get_entity_definition` on `menu`/`list_bar_grp`/`list_bar_item` (and the `role_*_overview`
siblings) for fields, keys and bound tasks — batch them in one call, since the object graph is known
up front. What the metadata won't tell you:

- **No bound "create" task exists for `menu`** — create it as a plain record with `menu_id` and
  `menu_type` set.
- **`menu_platform` can come back `readonly` at create**, already defaulted to `8` (`universal`).
  That is not an error, and universal is the only actively-maintained target anyway.
- **If a bare add is rejected, stage the `menu` as a dependent record of `branch`**
  (`parent_entity_set: "branch"`, `parent_key: {model_id, branch_id}`).
- **`task_copy_menu` clones a whole group/item structure** — the fast start for a new platform
  variant of a menu you already have.

For the full per-entity walkthrough (every create/rename/copy/delete task with its parameters, group
and item creation order, the `role_*_overview` grant mechanics, and the per-entity write quirks),
read `references/entity_reference.md`.

Menu objects translate differently from most model objects (the group/item label lives on a bare id,
not per menu) — see `references/menu_translation_notes.md` before translating one.

## Pre-flight checklist

- **Ask before deciding structure.** New menu vs. existing, new group vs. existing — if the framework
  above doesn't make it obvious, ask the user rather than guessing.
- **Always verify the menu type before creating a new menu** — state the recommended `menu_type`
  (list bar / tile / tree) and why, and get the user's confirmation first, even when the fit seems
  obvious.
- Default to **list bar**; reach for **tile** only for small item counts or customer-facing/touch
  contexts; treat **tree** as something to migrate away from, not build on — it has real, verified API
  gaps (no bound tasks on `module_grp`, no exposed item entity) on top of the UX case against it.
- The bound create-item tasks (`task_create_list_bar_item`/`task_create_tile`) can fail on commit with
  a mandatory-field error on `menu_item_type` that they expose no way to set — create items as a
  dependent-record add under the parent group instead; it works reliably and sets every field
  (description, target, order) in one step. Creating a `list_bar_grp`/`tile_grp` **does** require an ID
  up front.
- When setting `tab_id`/`report_id`/`task_id` (or any lookup) by display text, verify the field actually
  populated — display text with extra wording beyond the plain identifier can silently fail to resolve,
  with no error raised.
- Don't rely on `task_move_*`/`task_renumber_*` for scripted reordering — they're zero-parameter
  drag-drop artifacts. Edit `order_no` directly instead.
- To hide/show something per role, **locate the existing `role_*_overview` row and edit `granted`** —
  never try to add a new one; a row already exists for every role at every level.
- Query `menu_tab`/`menu_report`/`menu_task` before renaming or removing a table/report/task referenced
  by any menu.

