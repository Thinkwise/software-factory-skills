# Variant naming, maintenance, and testing

Loaded on demand from `thinkwise_sf_variants`.

## Naming and documentation

Name variants by **purpose and audience**, not by number or implementation detail:

```text
production_order_shop_floor
production_order_planning_scheduler
production_order_history
certificate_customer_portal
customer_active_lookup
material_registration_receipt
picking_list_export_pdf
```

Avoid `variant_1`, `new_screen`, `test`, `copy`, `version_2`, `alternative` — names that describe
neither purpose nor implementation. Give every variant a description covering its intended audience,
entry points, key prefilters, permission restrictions, why the default doesn't already serve this
need, and whether it carries a grid/form/detail snapshot.

## Maintenance

- **Override the minimum.** Every override is an exception to inheritance; a sparse variant keeps
  benefiting from default improvements. Before taking any set-level snapshot (Setup task), **ask the
  user** whether the set genuinely needs to be stable independently of the default — if not, leave it
  inheriting.
- **Review `tab_variant_change` regularly** — after adding columns/tasks/reports to the default,
  after screen-type changes, and before every release. Reset any override that turns out to be
  accidental rather than intentional.
- **Track every reference before deleting or radically changing a variant.** `tab_variant_used`
  (key `pk_col`, carrying `tab_id`/`tab_variant_id` plus a `type_of_object` enum spanning the entire
  model's object catalog) is the live "Applied to" list — confirmed to cover menu items, details,
  look-ups, table tasks/reports, process actions (including `process_action_start_tab_variant` /
  `process_action_start_report_variant` process-flow starting points), and drag-and-drop links. A
  variant that looks unreferenced in one modeler screen may still be wired into a process flow —
  query this entity rather than assuming.
- **Avoid deep variant chains.** A table variant can point its look-ups and details at *other*
  table variants (see chaining above), which can themselves apply task/report variants. Keep each
  link in the chain purposeful and clearly named; a long chain becomes very hard to reason about at
  runtime.
- **Keep rights explicit.** The effective behaviour is role rights AND default rights AND variant
  restrictions AND prefilter/data-isolation logic, all at once. A variant that hides a menu item or
  task is not the same as securing it — an unbound or unassigned task is still reachable via the API
  regardless of what any variant shows.

## Testing

Per `thinkwise_sf_unit_tests`: unit-test the underlying task/default/layout/handler
logic once — variants reuse that same logic, so they don't each need their own copy of the same
test. The one exception is a **task variant that silently supplies a default** (e.g. a
`material_receipt` variant defaulting `transaction_type = RECEIPT`) — that hidden branch is real
business logic and deserves its own unit test on the underlying task. Beyond that, variant
correctness is a configuration/user-flow concern: verify each important variant opens from its
intended entry point, applies its prefilters, shows the right columns/details, hides the tasks/
reports it should, supplies correct defaults, and enforces the intended rights — prioritizing
customer portals, shop-floor/scanner workflows, financial approval screens, and any variant with a
large snapshot or a multi-level chain.
