# Connector profiles, surfaces and meta-model versions

The `thinkwise-sf-*` skills are used from more than one environment. A rule that is right in one can be
wrong or meaningless in another, so identify the environment once (base check §1) and read every
scope-tagged rule against it.

## The four axes

| Axis | Value | Recognise it by |
|---|---|---|
| **Connector profile** | **Indicium MCP** (official) | tools `search_domain_capabilities`, `get_entity_definition`, `get_task_definition`, `execute_odata_query`, `stage_resource`, `stage_task`, `patch_resource`, `commit_resource`, `abort_resource` |
| | **Legacy sf-mcp-server** (unofficial, older) | tools `create_entity`, `query_entities` (direct OData create/read, no staging) |
| | **No connector** | neither tool set present; work from metadata the user pastes (e.g. `get_sf_metadata` JSON) and hand over SQL or a plan |
| **Domain layout** (Indicium only) | **split-domain** | several domains such as `sf/manage_tasks`, `sf/manage_process_flows`, `sf/manage_subroutines`, `manage_unit_tests` |
| | **single-domain** | one domain, `sf/software_development` |
| **Surface** | **Claude Code** | `AskUserQuestion` tool, local file system, connectors added with `claude mcp` |
| | **claude.ai / ThinkIT** (ThinkIT is a claude.ai-based workspace) | `ask_user_input_v0` button tool, connectors added in claude.ai settings, no local files |
| **Meta-model** | **current** (SF 2026.2) | domain elements in `elemnt`; the datatype is set on `dom` (`dom.dttp_id`) and `dom_query` is filled from it per RDBMS; `dom.case_type` exists, `col.case_type` and `dom.prog_lang_id` don't |
| | **older** | `dom.prog_lang_id`, `dom.user_defined_dttp`, `dom_elmnt`, `tab.work_flow_tab_id`, `col.case_type` |

**Not every Indicium MCP connector is a Software Factory.** Any Thinkwise application exposed through
Indicium offers the same tool names (e.g. a demo application whose only domain is `tw_oost/Admin`).
Count a connector as Software Factory access only when its server instructions name an `sf/…` domain.

The domain layout is a property of the Indicium instance's configuration, not of the Software Factory
version. Read it from the connector's server instructions first — they name the domain key(s) ("There
is only one domain, whose key is `sf/software_development`"); otherwise use `search_capabilities`.
Avoid `get_available_domains` for this: on a single-domain instance its answer ran to ~290,000
characters, far past a tool-result limit. Never assume the layout from another session.

## Scope tags

Skills tag a rule only where behaviour differs between environments. Read an untagged rule as valid
everywhere its skill applies.

| Tag | Applies when |
|---|---|
| `(Indicium · split-domain)` | Indicium MCP with split domains |
| `(Indicium · single-domain)` | Indicium MCP with the single `sf/software_development` domain |
| `(legacy sf-mcp-server)` | the older unofficial connector |
| `(Claude Code)` / `(claude.ai/ThinkIT)` | that surface |
| `(older meta-model)` | the older meta-model field set |

**A rule tagged for another environment:** try it once; if refused, use the alternative the skill gives
next to it. Don't record it as broken — record the difference with the right tag (see
`thinkwise-skill-maintenance`).

## What carries over between profiles

| | Indicium MCP | Legacy sf-mcp-server | No connector |
|---|---|---|---|
| Entity and field names, enums, naming conventions in the sf-* skills | yes | yes (check older meta-model) | yes |
| Staging hazards in base (refusal shape, property order, branch lock, `value_kind`) | yes | no — writes are direct; a refusal is an HTTP error | n/a |
| Adds under a parent (`parent_entity_set`, `detail_nav`, variant entity sets) | yes | no — create the row with its full key | n/a |
| Bound tasks (`task_generate_code_grp`, `task_create_*`, jobs) | yes | not offered | manual in the Software Factory |
| Domain names in skills | per layout | not used | not used |

## Asking the user

Use the surface's structured question tool — `AskUserQuestion` (Claude Code) or `ask_user_input_v0`
(claude.ai/ThinkIT). Without either, ask a short numbered question in text. Skills say "ask the user";
this is what it means.

## Differences seen between domain layouts

Same Software Factory version (2026.2), different Indicium domain layout:

| Entity / action | split-domain | single-domain |
|---|---|---|
| `process_variable` add | flat add accepted (`sf/manage_process_flows`) | flat add refused; add `process_variable.process_variable_modeler` under `process_flow` |
| `tile` add | under `tile_grp` via `tile.gui_modeler_tile` | under-parent add answers `detail_nav_not_found`; a flat add with the full key works |
| `web_connection_endpoint_parmtr` add | under `web_connection_endpoint` via `..._parmtr.gui_modeler_web_connection_endpoint_parmtr` | under-parent add answers `detail_nav_not_found`; a flat add with the full key works |
| `web_connection_endpoint_output_parmtr` add | not verified; try under `web_connection_endpoint` first | same as the endpoint parameter: a flat add with the full key works |
| `map_data_mapping` row | every add route and the `map_data_mapping_overview` edit failed | edit the pre-listed candidate in `map_data_mapping_overview`; a flat add stages with read-only null keys |
| `scheduler.add_activity_task_id` patch | refused (`unknown_property`) | accepted; it then opens `activity_start_task_parmtr_id` |
| `scheduler_view`, `scheduler_view_resource_col`, `scheduler_view_conditional_layout` | read-only in `sf/manage_datamodel`, writable in `sf/manage_scheduler` | writable |
| `subroutine` | writable only in `sf/manage_subroutines` (read-only stub in `sf/manage_control_procedures`) | writable |
| `oauth_server` configuration fields (`authorization_url`, `token_url`, `client_id`, `client_secret`, `scope`, …) | only the key fields exposed in `sf/manage_webconnections` | all exposed, plus `task_encrypt_oauth_key` |

In a split layout the **same entity can be read-only in one domain and writable in another**: when an
entity looks read-only, search the other domains before planning a manual step.
