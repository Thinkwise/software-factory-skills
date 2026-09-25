# Process flow naming conventions and canvas alignment

Loaded on demand from `thinkwise_sf_process_flows`.

## Alignment

Layout lives entirely on `process_action`: `x_coordinate`, `y_coordinate`, `width`, `height` — plain
numbers, no separate design table, no persisted grid-snap metadata (snapping is designer-UI behavior
only). A convention taken from a real flow's actual coordinates: keep `width`/`height` constant across
every action, run the main "happy path" along one horizontal lane (`y_coordinate` unchanged), and step
`x_coordinate` by a fixed increment (~48–56 units) per action. Give a `decision`'s branches their own
row above/below the main lane, then reconverge them back onto the main `y` before `stop`. Since none of
this is mandatory, it's safe to omit at creation time and set once the flow's logic is proven — but do
set it before calling the flow finished, since an unlaid-out canvas is hard for the next person (or
agent) to read.

## Naming

**A process flow's `process_flow_id` must never reuse an existing task's `task_id` or a report's
`report_id`/`tab_report_id` in the same model.** Nothing in the write API actually rejects this
collision — staging a `process_flow` with an id identical to an existing task's id was accepted
without a validation warning — which is exactly why this has to be enforced by discipline rather than
relied on as a platform guarantee: query existing `task` and `report`/`tab_report` ids in the target
model first and confirm no overlap before picking a `process_flow_id`.

**Before naming a new flow, look at the other process flows already in the model** and match
whatever local convention they establish — conventions observed vary genuinely by model/team, so
there is no single universal answer:

- **Plain business flows** (the common case): snake_case, no fixed prefix, named for the outcome or
  trigger rather than a strict word order — `sales_invoice_approve_print`,
  `calculate_and_store_route`, `customer_create_contact_person`, `deep_link_to_sales_invoice`. Pick
  whichever ordering (object_verb vs. verb_object vs. outcome-first) the sibling flows in this model
  already use, rather than introducing a new one.
- **System/background flows**, when a project wants them visually distinguishable from interactive
  ones, commonly take a **`system_flow_`** prefix (`system_flow_clean_up`,
  `system_flow_automatic_thinkstore_refresh`) — Thinkwise's own built-in framework flow
  (`tsf_system_flow_run_tsf_optimize`) uses `tsf_system_flow_` for the same reason. This is a chosen
  convention, not an enforced one: plenty of real system flows (e.g. `save_customer_coordinates`,
  `check_uta_vm_status`) have no such prefix at all — `is_system_flow` is a computed property, never
  something the name has to signal.
- Some teams use a lighter **`flow_`** or **`pf_`** micro-prefix instead, especially for many small,
  similar flows following one template (`flow_copy_<x>_to_new_record` repeated per table).
- All observed names are lowercase snake_case — no camelCase, no spaces, ever.

- **If the model has no existing process flows to pattern-match against and no other convention is
  obvious, don't default silently** — per `thinkwise_sf_base`'s "Shared
  conventions" (ask, don't default), propose plain outcome-descriptive snake_case with no prefix as
  your recommendation (matching general Thinkwise naming guidelines — see
  `thinkwise_sf_data_model`, purpose over plumbing, same principle as control procedure
  naming) and get the user to confirm or correct it before committing to a `process_flow_id`.

## Translation

The flow's own description, its actions' descriptions, any message text, and process variable
descriptions are all translatable objects. Don't leave newly-created text in the source language only
— load `thinkwise_sf_translations` for the `transl_object`/`transl_object_transl`
mechanics and the approval workflow before considering a new process flow finished.
