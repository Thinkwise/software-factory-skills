# SF meta-model reference (dynamic assignment)

Authoritative structure of the **Software Factory's own base data model** — the tables a
SQL-typed control procedure queries to select target objects and stage assignments.
Distinct from `get_sf_metadata`, which describes the *end product*; this describes the SF
*itself*. Extracted from the SQL Server system catalog (keys + physical FKs are real).

Context variables available inside a SQL control procedure: `@model_id`, `@branch_id`.
Every read against these entities filters on both.

> Datatypes shown are the SF **domain** names (the SF is itself a Thinkwise app), not base
> SQL types. For assignment logic only column names, keys and relations matter.


---

## Program object naming

The `prog_object_id` of the object a template attaches to (differs from the generated
stored-procedure name, e.g. object `default_<tab>` vs proc `def_<tab>`):


| Concept          | prog_object_id            | Object type |
|------------------|---------------------------|-------------|
| Default          | `default_<tab_id>`        | tab/task/report |
| Layout           | `layout_<tab_id>`         | tab/task/report |
| Context          | `context_<tab_id>`        | tab |
| Badge            | `badge_<tab_id>`          | tab/task/report |
| Change detection | `chg_<tab_id>`            | tab |
| Insert handler   | `handle_<tab_id>_insert`  | tab |
| Update handler   | `handle_<tab_id>_update`  | tab |
| Delete handler   | `handle_<tab_id>_delete`  | tab |
| After trigger    | `<tab_id>_ti` / `_tu` / `_td` | tab |
| Instead-of trigger | `<tab_id>_ii` / `_iu` / `_id` | tab |
| Process          | `prc_<process_flow_id>`   | process flow |
| Subroutine proc  | `proc_<subroutine_id>`    | subroutine |
| Function         | `func_<subroutine_id>`    | subroutine |

Program object item id (dynamic assignment): `<template_id>_<object_id>`, where
`<object_id>` is the `tab_id` / `task_id` / `report_id`.


---

## Enable the concept first (use_* flags)

A template only takes effect if the concept is enabled on the object. Front-load an
`update` that switches the flag on **only where it is 0**, then stage the item.


| Concept          | Flag on tab             | Also on task/report |
|------------------|-------------------------|---------------------|
| Default          | `use_defaults`          | yes |
| Layout           | `use_layouts`           | yes |
| Badge            | `use_badges`            | yes |
| Context          | `use_contexts`          | no |
| Change detection | `use_change_detection`  | no |
| Insert handler   | `use_insert_handlers`   | no |
| Update handler   | `use_update_handlers`   | no |
| Delete handler   | `use_delete_handlers`   | no |

Task/report carry only `use_defaults`, `use_layouts`, `use_badges`.


---

## Tag layer (key-value selection dimension)

Most primary entities have a `<entity>_tag` table: **PK = parent PK + `tag_id`**, plus a
`value varchar(1000)`. They are system-versioned; read the current rows and ignore the
period columns. Tagged entities:

`tab_tag`, `col_tag`, `ref_tag`, `ref_col_tag`, `task_tag`, `task_parmtr_tag`, `report_tag`, `report_parmtr_tag`, `indx_tag`, `subroutine_tag`, `subroutine_parmtr_tag`

Link tables (`tab_task`, `tab_report`, `tab_task_parmtr`, `tab_report_parmtr`), `indx_col`
and `subroutine_return_col` have **no** tag table.

Idioms — include by tag: `exists (select 1 from <e>_tag x where <parent keys> and x.tag_id = 'ABC')`;
exclude by tag: `not exists (... x.tag_id = 'XYZ')`; value-driven: join and read `x.value`.


---

## Staging temp tables (write side, Staged strategy)

Created by the SF during generation; the control_proc_code only inserts. They carry **no**
`model_id` / `branch_id` / `control_proc_id` (implicit context). Key columns:


- `#prog_object` — `prog_object_id` (PK), `prog_object_type_id`, `tab_id`, `task_id`, `report_id`, `process_flow_id`, `process_action_id`, `subroutine_id`, `code_file_id`, `order_no`, `prog_object_file_spec`, `prog_object_status`. *Skip when attaching to an existing object.*
- `#prog_object_item` — `prog_object_id` (PK), `prog_object_item_id` (PK), `order_no`, `template_id`.
- `#prog_object_item_parmtr` — `prog_object_id`, `prog_object_item_id`, `parmtr_id`, `parmtr_value`, `order_no`, `no_line_when_empty`.
- `#prog_object_parmtr` — object-level params: `prog_object_id`, `parmtr_id`, `parmtr_value`, `order_no`, `no_line_when_empty`.

See the functionality docs for the complete column set.


---

## Validated pattern

1. Resolve targets once into a table variable (selection on `col`/tags/flags). Views
   (`type_of_table <> 0`) are valid targets for most concepts; do not exclude them by default.
2. Front-load `update <object> set use_<concept> = 1 ... where use_<concept> = 0` for targets.
3. Insert one `#prog_object_item` per target on the existing `<concept>_<object>` object,
   `template_id` = the template.
4. Insert `#prog_object_item_parmtr` per bracket parameter, `parmtr_value` = the resolved value.


---

## Entities


### tab

- PK: `model_id,branch_id,tab_id`

- FK: model_id -> branch.model_id; branch_id -> branch.branch_id; model_id -> custom_component.model_id; branch_id -> custom_component.branch_id; custom_component_id -> custom_component.custom_component_id; model_id -> icon.model_id; branch_id -> icon.branch_id; icon_id -> icon.icon_id; model_id -> partition_scheme.model_id; branch_id -> partition_scheme.branch_id; partition_scheme_id -> partition_scheme.partition_scheme_id; model_id -> refresh_grp.model_id; branch_id -> refresh_grp.branch_id; refresh_grp_id -> refresh_grp.refresh_grp_id; model_id -> screen_type.model_id; branch_id -> screen_type.branch_id; detail_screen_type_id -> screen_type.screen_type_id; main_screen_type_id -> screen_type.screen_type_id; popup_screen_type_id -> screen_type.screen_type_id; zoom_screen_type_id -> screen_type.screen_type_id; model_id -> storage.model_id; branch_id -> storage.branch_id; storage_id -> storage.storage_id; model_id -> tab.model_id; branch_id -> tab.branch_id; work_flow_tab_id -> tab.tab_id

- Columns (126): model_id(model_id), branch_id(branch_id), tab_id(tab_id), type_of_table(type_of_tab), create_view_method(create_view_method), main_screen_type_id(screen_type_id), detail_screen_type_id(screen_type_id), zoom_screen_type_id(screen_type_id), popup_screen_type_id(screen_type_id), look_up_display_col_id(col_id), default_look_up_control(look_up_control), default_refresh_combo_on_dropdown(no_yes), default_look_up_has_popup(no_yes), form_default_editable(no_yes), form_auto_save(no_yes), hide_buttons(no_yes), allow_add(no_yes), allow_copy(no_yes), allow_update(no_yes), allow_delete(no_yes), allow_copy_to_clipboard(no_yes), confirm_update(no_yes), confirm_delete(no_yes), refresh_after_insert(refresh), refresh_after_copy(refresh), refresh_after_update(refresh), refresh_after_delete(refresh), start_empty_with_filter(no_yes), allow_nav(no_yes), allow_sort(no_yes), allow_grp(no_yes), allow_filter(no_yes), allow_search(no_yes), allow_edit_grid(no_yes), allow_add_grid(no_yes), add_row_visibility(add_row_visibility), allow_import(no_yes), allow_export(no_yes), allow_mass_update(no_yes), grid_row_height(height), grid_default_editable(no_yes), auto_resize_grid_col(auto_resize_grid_col), grp_grid_default_expanded(no_yes), grp_grid_default_expanded_level(default_expanded_level), allow_print_preview(no_yes), drag_drop_default_enabled(no_yes), grp_box_visibility(grp_box_visibility), update_trigger_on_cols(no_yes), height_unit_type(height_unit_type), default_height_main_subject(height), work_flow_tab_id(tab_id), icon_id(icon_id), max_no_of_records(no_of_records), page_size(no_of_records), no_of_fields_locked(no_of_col), storage_id(storage_id), alias_schema_id(alias_schema_id), alias_tab_id(alias_tab_id), memory_optimized(memory_optimized_option), use_system_versioning(no_yes), system_versioning_retention_amount(recurrence), system_versioning_retention_unit(retention_type), partition_scheme_id(partition_scheme_id), partition_col_id(col_id), tab_description(description_multiline), type_of_object(type_of_object), derived_concepts(derived_concepts), visible_in_uml(no_yes), priority(priority), no_of_cols_in_form(no_of_col), form_col_min_width_factor(form_col_min_width_factor), label_width(width), field_width(width), field_height(height), height_between_fields(height), width_between_fields(width), show_no_of_record(no_yes), card_list_title(card_list_title), card_list_image(card_list_image), tree_display_col_id(col_id), tree_image_col_id(col_id), tree_type(tree_type), tree_default_expanded(no_yes), tree_default_expanded_level(default_expanded_level), tree_show_label(no_yes), custom_component_source(custom_component_source), custom_component_id(custom_component_id), custom_component_entry_point(custom_component_entry_point), custom_component_ref(custom_component_ref), generation_order_no(order_no), no_of_col(no_of_col), no_of_pk_col(no_of_pk_col), max_pk_col_no(max_pk_col_no), allow_offline(no_yes), offline_available(no_yes), offline_mutable(no_yes), refresh_offline_data_after_mutation(no_yes), refresh_grp_id(refresh_grp_id), use_defaults(no_yes), use_layouts(no_yes), use_layouts_add_button_type(no_yes), use_layouts_update_button_type(no_yes), use_layouts_delete_button_type(no_yes), use_layouts_confirm_button_type(no_yes), use_layouts_cancel_button_type(no_yes), use_contexts(no_yes), use_badges(no_yes), show_badge(no_yes), badge_interval(badge_interval), use_change_detection(no_yes), use_insert_handlers(no_yes), use_update_handlers(no_yes), use_delete_handlers(no_yes), auto_refresh(no_yes), auto_refresh_interval(auto_refresh_interval), use_insert_handlers_template(no_yes), use_update_handlers_template(no_yes), use_delete_handlers_template(no_yes), enable_multirow_select(no_yes), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### col

- PK: `model_id,branch_id,tab_id,col_id`

- FK: model_id -> col.model_id; branch_id -> col.branch_id; tab_id -> col.tab_id; parent_col_id -> col.col_id; model_id -> dom.model_id; branch_id -> dom.branch_id; dom_id -> dom.dom_id; model_id -> icon.model_id; branch_id -> icon.branch_id; form_next_grp_icon_id -> icon.icon_id; next_tab_icon_id -> icon.icon_id; model_id -> tab.model_id; branch_id -> tab.branch_id; tab_id -> tab.tab_id; view_tab_id -> tab.tab_id

- Columns (87): model_id(model_id), branch_id(branch_id), tab_id(tab_id), col_id(col_id), order_no(order_no), sub_order_no(sub_order_no), abs_order_no(abs_order_no), dom_id(dom_id), primary_key(no_yes), type_of_col(type_of_col), mand(no_yes), type_of_default_value(type_of_default_value), default_value(default_value), foreign_key(no_yes), identity_col(no_yes), seed(seed), increment(increment), data_col_id(col_id), file_storage_sub_folder(sub_folder), default_sort(no_yes), sort_no(sort_no), sort_order(sort_order), grp_until(no_yes), label_width(width), field_width(width), field_height_in_positions(no), field_no_of_positions_further(no), form_field_in_next_grp(no_yes), form_next_grp_label(label), form_next_grp_icon_id(icon_id), field_in_next_col(no_yes), field_on_next_tab(no_yes), next_tab_label(label), next_tab_icon_id(icon_id), next_tab_default_expanded(no_yes), grid_col_width(width), grid_field_in_next_grp(no_yes), grid_next_grp_label(label), case_type(case_type), include_in_insert(no_yes), include_in_copy(no_yes), include_in_copy_to_clipboard(no_yes), allow_sort(no_yes), include_in_global_filter(no_yes), visible_for_filter(visible_for_filter_search), filter_condition(filter_condition), filter_order_no(order_no), visible_for_search(visible_for_filter_search), search_condition(filter_condition), search_order_no(order_no), trigger_for_update(no_yes), view_tab_id(tab_id), alias_col_id(alias_col_id), col_description(description_multiline), type_of_object(type_of_object), form_order_no(order_no), form_type_of_col(type_of_col), grid_order_no(order_no), grid_type_of_col(type_of_col), show_aggregation_in_grid(no_yes), aggregation_summary_type(aggregation_type), card_list_type_of_col(type_of_col), card_list_order_no(order_no), card_list_label(no_yes), card_list_field_height_in_positions(no), calculated_field_type(calculated_field_type), file_offline_available(no_yes), default_input(no_yes), default_output(no_yes), layout_input(no_yes), layout_type_output(no_yes), layout_mand_output(no_yes), context_input(no_yes), function_input(no_yes), parent_col_id(col_id), use_for_optimistic_locking(no_yes), input_insert_handler(no_yes), input_update_handler(no_yes), has_alt_transl(no_yes), alt_transl_col_id(col_id), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### ref

- PK: `model_id,branch_id,ref_id`

- FK: model_id -> col.model_id; branch_id -> col.branch_id; source_tab_id -> col.tab_id; look_up_display_col_id -> col.col_id; model_id -> screen_area.model_id; branch_id -> screen_area.branch_id; screen_area_id -> screen_area.screen_area_id; model_id -> tab.model_id; branch_id -> tab.branch_id; source_tab_id -> tab.tab_id; target_tab_id -> tab.tab_id; model_id -> tab_variant.model_id; branch_id -> tab_variant.branch_id; target_tab_id -> tab_variant.tab_id; detail_tab_variant_id -> tab_variant.tab_variant_id; source_tab_id -> tab_variant.tab_id; look_up_tab_variant_id -> tab_variant.tab_variant_id

- Columns (36): model_id(model_id), branch_id(branch_id), ref_id(ref_id), ref_description(description_multiline), source_tab_id(tab_id), target_tab_id(tab_id), ref_add(ref_add), generate_ref_add_transl_object(no_yes), check_ref(no_yes), on_update(on_update), on_delete(on_delete), no_of_col(no_of_col), show_look_up(no_yes), different_look_up(no_yes), look_up_display_col_id(col_id), look_up_control(look_up_control), refresh_combo_on_dropdown(no_yes), look_up_has_popup(no_yes), look_up_tab_variant_id(tab_variant_id), show_detail(no_yes), detail_tab_variant_id(tab_variant_id), order_no(order_no), abs_order_no(abs_order_no), screen_area_id(screen_area_id), is_detail(no_yes), context_type_output(no_yes), alias_ref_id(alias_ref_id), visible_for_filter_detail(visible_for_filter_search), visible_for_filter_look_up(visible_for_filter_search), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### ref_col

- PK: `model_id,branch_id,ref_id,source_tab_id,source_col_id`

- FK: model_id -> col.model_id; branch_id -> col.branch_id; source_tab_id -> col.tab_id; source_col_id -> col.col_id; target_tab_id -> col.tab_id; target_col_id -> col.col_id; model_id -> ref.model_id; branch_id -> ref.branch_id; ref_id -> ref.ref_id

- Columns (17): model_id(model_id), branch_id(branch_id), ref_id(ref_id), source_tab_id(tab_id), source_col_id(col_id), target_tab_id(tab_id), target_col_id(col_id), order_no(order_no), abs_order_no(abs_order_no), use_detail_null_comparison(no_yes), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### indx

- PK: `model_id,branch_id,indx_id`

- FK: model_id -> indx.model_id; branch_id -> indx.branch_id; full_text_key_indx_id -> indx.indx_id; model_id -> storage.model_id; branch_id -> storage.branch_id; storage_id -> storage.storage_id; model_id -> tab.model_id; branch_id -> tab.branch_id; tab_id -> tab.tab_id

- Columns (22): model_id(model_id), branch_id(branch_id), indx_id(indx_id), tab_id(tab_id), primary_key(no_yes), foreign_key(no_yes), type_of_indx(type_of_indx), unique_indx(no_yes), ignore_null(no_yes), full_text_catalog_id(full_text_catalog_id), full_text_key_indx_id(indx_id), storage_id(storage_id), alias_indx_id(alias_indx_id), indx_description(description_multiline), no_of_col(no_of_col), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### indx_col

- PK: `model_id,branch_id,indx_id,tab_id,col_id`

- FK: model_id -> col.model_id; branch_id -> col.branch_id; tab_id -> col.tab_id; col_id -> col.col_id; model_id -> indx.model_id; branch_id -> indx.branch_id; indx_id -> indx.indx_id

- Columns (16): model_id(model_id), branch_id(branch_id), indx_id(indx_id), tab_id(tab_id), col_id(col_id), sort_order(sort_order), included(no_yes), order_no(order_no), abs_order_no(abs_order_no), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### task

- PK: `model_id,branch_id,task_id`

- FK: ascii_code -> ascii_code.ascii_code; model_id -> branch.model_id; branch_id -> branch.branch_id; model_id -> icon.model_id; branch_id -> icon.branch_id; icon_id -> icon.icon_id; model_id -> msg.model_id; branch_id -> msg.branch_id; confirmation_msg_id -> msg.msg_id; shift_code -> shift_code.shift_code; task_type_id -> task_type.task_type_id

- Columns (43): model_id(model_id), branch_id(branch_id), task_id(task_id), task_type_id(task_type_id), type_of_communication(type_of_communication), object_name(object_name), task_description(description_multiline), single_transaction(no_yes), no_of_cols_in_form(no_of_col), form_col_min_width_factor(form_col_min_width_factor), ask_confirmation(no_yes), confirmation_msg_id(msg_id), popup_for_each_row(no_yes), shift_code(shift_code), ascii_code(ascii_code), icon_id(icon_id), show_badge(no_yes), badge_interval(badge_interval), alias_task_id(alias_task_id), display_parmtr_id(task_parmtr_id), repeat_after_execute(no_yes), type_of_object(type_of_object), generation_order_no(order_no), offline_executable(no_yes), use_defaults(no_yes), use_layouts(no_yes), use_layouts_add_button_type(no_yes), use_layouts_update_button_type(no_yes), use_layouts_delete_button_type(no_yes), use_layouts_confirm_button_type(no_yes), use_layouts_cancel_button_type(no_yes), use_badges(no_yes), confirm_button_has_alt_transl(no_yes), alt_transl_confirm_button(popup_button_label), cancel_button_has_alt_transl(no_yes), alt_transl_cancel_button(popup_button_label), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### tab_task

- PK: `model_id,branch_id,tab_id,task_id`

- FK: model_id -> col.model_id; branch_id -> col.branch_id; tab_id -> col.tab_id; grid_double_click_col_id -> col.col_id; model_id -> screen_area.model_id; branch_id -> screen_area.branch_id; screen_area_id -> screen_area.screen_area_id; model_id -> tab.model_id; branch_id -> tab.branch_id; tab_id -> tab.tab_id; model_id -> tab_task_grp.model_id; branch_id -> tab_task_grp.branch_id; tab_id -> tab_task_grp.tab_id; tab_task_grp_id -> tab_task_grp.tab_task_grp_id; model_id -> task.model_id; branch_id -> task.branch_id; task_id -> task.task_id; model_id -> task_variant.model_id; branch_id -> task_variant.branch_id; task_id -> task_variant.task_id; task_variant_id -> task_variant.task_variant_id

- Columns (25): model_id(model_id), branch_id(branch_id), tab_id(tab_id), task_id(task_id), task_variant_id(task_variant_id), show_tab_task(no_yes), enable_tab_task_when_empty(no_yes), refresh_after_execute(refresh), refresh_offline_data_after_execute(no_yes), tab_task_grp_id(tab_task_grp_id), order_no(order_no), abs_order_no(abs_order_no), context_type_output(no_yes), grid_double_click(no_yes), grid_double_click_col_id(col_id), custom_display_type(action_display_type), primary_action(no_yes), screen_area_id(screen_area_id), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### task_parmtr

- PK: `model_id,branch_id,task_id,task_parmtr_id`

- FK: model_id -> dom.model_id; branch_id -> dom.branch_id; dom_id -> dom.dom_id; model_id -> icon.model_id; branch_id -> icon.branch_id; form_next_grp_icon_id -> icon.icon_id; next_tab_icon_id -> icon.icon_id; model_id -> task.model_id; branch_id -> task.branch_id; task_id -> task.task_id

- Columns (44): model_id(model_id), branch_id(branch_id), task_id(task_id), task_parmtr_id(task_parmtr_id), order_no(order_no), abs_order_no(abs_order_no), dom_id(dom_id), type_of_col(type_of_col), mand(no_yes), type_of_default_value(type_of_default_value), default_value(default_value), file_storage_folder(product_folder_spec), file_storage_sub_folder(sub_folder), data_parmtr_id(task_parmtr_id), task_output(no_yes), case_type(case_type), label_width(width), field_width(width), field_height_in_positions(no), field_no_of_positions_further(no), form_field_in_next_grp(no_yes), form_next_grp_label(label), form_next_grp_icon_id(icon_id), field_in_next_col(no_yes), field_on_next_tab(no_yes), next_tab_label(label), next_tab_icon_id(icon_id), alias_task_parmtr_id(alias_task_parmtr_id), has_alt_transl(no_yes), alt_transl_task_parmtr_id(task_parmtr_id), task_input(no_yes), default_input(no_yes), default_output(no_yes), layout_input(no_yes), layout_type_output(no_yes), layout_mand_output(no_yes), task_parmtr_description(description_multiline), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### tab_task_parmtr

- PK: `model_id,branch_id,tab_id,task_id,col_id,task_parmtr_id`

- FK: model_id -> col.model_id; branch_id -> col.branch_id; tab_id -> col.tab_id; col_id -> col.col_id; model_id -> tab_task.model_id; branch_id -> tab_task.branch_id; tab_id -> tab_task.tab_id; task_id -> tab_task.task_id; model_id -> task_parmtr.model_id; branch_id -> task_parmtr.branch_id; task_id -> task_parmtr.task_id; task_parmtr_id -> task_parmtr.task_parmtr_id

- Columns (13): model_id(model_id), branch_id(branch_id), tab_id(tab_id), task_id(task_id), col_id(col_id), task_parmtr_id(task_parmtr_id), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### report

- PK: `model_id,branch_id,report_id`

- FK: ascii_code -> ascii_code.ascii_code; model_id -> branch.model_id; branch_id -> branch.branch_id; model_id -> icon.model_id; branch_id -> icon.branch_id; icon_id -> icon.icon_id; model_id -> printer.model_id; branch_id -> printer.branch_id; printer_id -> printer.printer_id; report_type_id -> report_type_action.report_type_id; report_action -> report_type_action.report_action; report_type_id -> report_type.report_type_id; shift_code -> shift_code.shift_code

- Columns (42): model_id(model_id), branch_id(branch_id), report_id(report_id), report_type_id(report_type_id), file_spec(report_spec_name), file_spec_data(binary_file), path_spec(path_spec), type_of_communication(type_of_communication), report_description(description_multiline), printer_id(printer_id), report_action(report_action), no_of_copies(no_of_copies), no_of_cols_in_form(no_of_col), form_col_min_width_factor(form_col_min_width_factor), popup_for_each_row(no_yes), shift_code(shift_code), ascii_code(ascii_code), icon_id(icon_id), show_badge(no_yes), badge_interval(badge_interval), alias_report_id(alias_report_id), display_parmtr_id(report_parmtr_id), type_of_object(type_of_object), use_defaults(no_yes), use_layouts(no_yes), use_layouts_add_button_type(no_yes), use_layouts_update_button_type(no_yes), use_layouts_delete_button_type(no_yes), use_layouts_confirm_button_type(no_yes), use_layouts_cancel_button_type(no_yes), use_badges(no_yes), confirm_button_has_alt_transl(no_yes), alt_transl_confirm_button(popup_button_label), cancel_button_has_alt_transl(no_yes), alt_transl_cancel_button(popup_button_label), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### tab_report

- PK: `model_id,branch_id,tab_id,report_id`

- FK: model_id -> report.model_id; branch_id -> report.branch_id; report_id -> report.report_id; model_id -> report_variant.model_id; branch_id -> report_variant.branch_id; report_id -> report_variant.report_id; report_variant_id -> report_variant.report_variant_id; model_id -> screen_area.model_id; branch_id -> screen_area.branch_id; screen_area_id -> screen_area.screen_area_id; model_id -> tab_report_grp.model_id; branch_id -> tab_report_grp.branch_id; tab_id -> tab_report_grp.tab_id; tab_report_grp_id -> tab_report_grp.tab_report_grp_id; model_id -> tab.model_id; branch_id -> tab.branch_id; tab_id -> tab.tab_id

- Columns (22): model_id(model_id), branch_id(branch_id), tab_id(tab_id), report_id(report_id), report_variant_id(report_variant_id), show_tab_report(no_yes), enable_tab_report_when_empty(no_yes), refresh_after_execute(refresh), tab_report_grp_id(tab_report_grp_id), order_no(order_no), abs_order_no(abs_order_no), context_type_output(no_yes), custom_display_type(action_display_type), primary_action(no_yes), screen_area_id(screen_area_id), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### report_parmtr

- PK: `model_id,branch_id,report_id,report_parmtr_id`

- FK: model_id -> dom.model_id; branch_id -> dom.branch_id; dom_id -> dom.dom_id; model_id -> icon.model_id; branch_id -> icon.branch_id; form_next_grp_icon_id -> icon.icon_id; next_tab_icon_id -> icon.icon_id; model_id -> report.model_id; branch_id -> report.branch_id; report_id -> report.report_id

- Columns (44): model_id(model_id), branch_id(branch_id), report_id(report_id), report_parmtr_id(report_parmtr_id), order_no(order_no), abs_order_no(abs_order_no), dom_id(dom_id), type_of_col(type_of_col), mand(no_yes), type_of_default_value(type_of_default_value), default_value(default_value), file_storage_folder(product_folder_spec), file_storage_sub_folder(sub_folder), data_parmtr_id(report_parmtr_id), case_type(case_type), label_width(width), field_width(width), field_height_in_positions(no), field_no_of_positions_further(no), form_field_in_next_grp(no_yes), form_next_grp_label(label), form_next_grp_icon_id(icon_id), field_in_next_col(no_yes), field_on_next_tab(no_yes), next_tab_label(label), next_tab_icon_id(icon_id), alias_report_parmtr_id(alias_report_parmtr_id), report_property(report_property), has_alt_transl(no_yes), alt_transl_report_parmtr_id(report_parmtr_id), report_input(no_yes), default_input(no_yes), default_output(no_yes), layout_input(no_yes), layout_type_output(no_yes), layout_mand_output(no_yes), report_parmtr_description(description_multiline), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### tab_report_parmtr

- PK: `model_id,branch_id,tab_id,report_id,col_id,report_parmtr_id`

- FK: model_id -> col.model_id; branch_id -> col.branch_id; tab_id -> col.tab_id; col_id -> col.col_id; model_id -> report_parmtr.model_id; branch_id -> report_parmtr.branch_id; report_id -> report_parmtr.report_id; report_parmtr_id -> report_parmtr.report_parmtr_id; model_id -> tab_report.model_id; branch_id -> tab_report.branch_id; tab_id -> tab_report.tab_id; report_id -> tab_report.report_id

- Columns (13): model_id(model_id), branch_id(branch_id), tab_id(tab_id), report_id(report_id), col_id(col_id), report_parmtr_id(report_parmtr_id), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### subroutine

- PK: `model_id,branch_id,subroutine_id`

- FK: model_id -> dom.model_id; branch_id -> dom.branch_id; return_scalar_dom_id -> dom.dom_id; model_id -> subroutine_type.model_id; branch_id -> subroutine_type.branch_id; subroutine_type_id -> subroutine_type.subroutine_type_id

- Columns (21): model_id(model_id), branch_id(branch_id), subroutine_id(subroutine_id), subroutine_type_id(subroutine_type_id), return_value(subroutine_return_value), return_scalar_dom_id(dom_id), return_table_id(tab_id), subroutine_description(description_multiline), single_transaction(no_yes), generation_order_no(order_no), alias_subroutine_id(alias_subroutine_id), api(no_yes), basic_api(no_yes), api_alias(api_alias), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### subroutine_parmtr

- PK: `model_id,branch_id,subroutine_id,subroutine_parmtr_id`

- FK: model_id -> dom.model_id; branch_id -> dom.branch_id; dom_id -> dom.dom_id; model_id -> subroutine.model_id; branch_id -> subroutine.branch_id; subroutine_id -> subroutine.subroutine_id

- Columns (21): model_id(model_id), branch_id(branch_id), subroutine_id(subroutine_id), subroutine_parmtr_id(subroutine_parmtr_id), dom_id(dom_id), order_no(order_no), abs_order_no(abs_order_no), input_parmtr(no_yes), output_parmtr(no_yes), alias_subroutine_parmtr_id(alias_subroutine_parmtr_id), api_alias(api_alias), subroutine_parmtr_description(description_multiline), type_of_subroutine_parmtr_default(type_of_subroutine_parmtr_default), default_value(default_value), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))


### subroutine_return_col

- PK: `model_id,branch_id,subroutine_id,subroutine_return_col_id`

- FK: model_id -> dom.model_id; branch_id -> dom.branch_id; dom_id -> dom.dom_id; model_id -> subroutine.model_id; branch_id -> subroutine.branch_id; subroutine_id -> subroutine.subroutine_id

- Columns (16): model_id(model_id), branch_id(branch_id), subroutine_id(subroutine_id), subroutine_return_col_id(subroutine_return_col_id), dom_id(dom_id), primary_key(no_yes), mand(no_yes), order_no(order_no), abs_order_no(abs_order_no), insert_user(tsf_user), insert_date_time(date_time), update_user(tsf_user), update_date_time(date_time), generated_by_control_proc_id(control_proc_id), tsf_valid_from(datetime2(2)), tsf_valid_to(datetime2(2))
