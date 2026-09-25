# Worked example — a sales revenue cube

Loaded on demand from `thinkwise_sf_cubes`.

## Practical example — a sales revenue cube

Source subject: `sales_order_line`, grain = one invoiced order line.

- Dimensions: `order_date` (interval `date_month`, hierarchy: `order_date_year` as
  `cube_field_grp_id` parent of `order_date_quarter`, which is in turn the parent of
  `order_date_month`), `customer_id`, `product_id` grouped under `product_group_id`
  (`cube_field_grp_id` on the product field points at the product-group field), `region_id`.
- Values: `revenue` (`summary_type = sum`), `quantity` (`sum`), `unit_price`
  (`summary_type = sql_expression`, `cube_field_query.formula = t1.revenue / NULLIF(t1.quantity, 0)`
  — never a plain `average` of the stored unit price column, which would misweight lines of
  different quantity).
- Views:
  - **Revenue trend** — `order_date_month` in `cube_area_category_row`, `revenue` in
    `cube_area_value`, `default_cube_view_type = chart`, `chart_type = 2d_line`.
  - **Revenue by customer and product** — `customer_id` in `cube_area_category_row`,
    `product_group_id` in `cube_area_series_column`, `revenue`+`quantity` in `cube_area_value`,
    `show_top_x = 10` with `show_other = true` sorted by `revenue` (`sort_by_cube_field_id`), pivot
    presentation with `show_row_total`/`show_col_grand_total` on.
- Conditional layout: `condition_cube_field_id = revenue`, `numeric_condition = smaller_than`,
  `value = 0`, `apply_to_cell = true`, red background — flags a reversed/negative order line at a
  glance.
- Rights: `role_cube_overview.available = true` for Sales role; `dragging_fields_granted = true`
  only for the Analyst role; `role_cube_field_overview.editable` left `false` everywhere — this is a
  historical-analysis cube, not a planning input.
