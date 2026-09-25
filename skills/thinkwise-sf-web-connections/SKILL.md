---
name: thinkwise-sf-web-connections
description: Reference guide for creating and using Web Connections and OAuth servers in a Thinkwise Software Factory model, the preferred mechanism for calling external HTTP/REST APIs. Covers authentication, endpoint and parameter setup, response parsing, and wiring a connection into a process flow. Use whenever an MCP connector with Software Factory access creates, inspects, or troubleshoots a web connection or OAuth server, in place of a one-off http_connector process action.
---

# Web Connections in the Thinkwise Software Factory

A **Web Connection** is a modeled, reusable definition of an external HTTP(S) API: one base URL and
authentication scheme (`web_connection`), with one or more named **endpoints** underneath it
(`web_connection_endpoint` — method, path, body). It replaces the legacy `http_connector` process
action, which re-enters URL/method/headers/auth on every single process action with no reuse, no
override mechanism, and no built-in response parsing.

Follow the connector's standard discovery→act flow; never guess entity/field/enum names — confirm
them via `get_entity_definition` first. **Two domains are involved, and mixing them up is the most
likely mistake:**

- **`sf/manage_webconnections`** — the connection/endpoint object graph itself: `web_connection`,
  `web_connection_endpoint` and every child (parameters, headers, query strings, form fields, output
  parameters), plus `oauth_server`. Build the connection here.
- **`sf/manage_process_flows`** — where the `web_connection` process action lives, plus its
  input/output *binding* entities (`process_action_web_connection_endpoint_parmtr_input_parmtr`,
  `process_action_web_connection_parmtr_input_parmtr`,
  `process_action_modeler_web_connection_endpoint_output`). Wire the already-built connection into a
  flow here — see `thinkwise_sf_process_flows`, which this skill complements rather than
  duplicates.

> **Correction to an earlier finding.** An earlier pass at the process-flows skill inspected
> `web_connection`/`web_connection_endpoint` only through `sf/manage_process_flows` (where a process
> action merely *references* a connection/endpoint by id) and concluded the objects exposed "almost no
> writable configuration." That conclusion was scoped to the wrong domain. Read directly from
> `sf/manage_webconnections`, both entities carry their full configuration — `base_url`,
> `authentication_type`, credentials, `endpoint_http_method`, `endpoint_path`, `type_of_body`,
> `endpoint_body`, etc. (see field tables below). Building a web connection from scratch is fully
> modeled through this API; it does not require the Software Factory's own UI.

## Entity map

```
web_connection                                    (sf/manage_webconnections)
├─ web_connection_parmtr                           connection-wide {param}, reused across endpoints
├─ web_connection_configuration(_overview)          per runtime-configuration / per-app override
└─ web_connection_endpoint                          one HTTP call shape
   ├─ web_connection_endpoint_parmtr                 endpoint-scoped input {param}
   ├─ web_connection_endpoint_query_string_parmtr    name/value, omit-when-empty
   ├─ web_connection_endpoint_request_header         name/value, omit-when-empty
   ├─ web_connection_endpoint_form_field              multipart/form fields, incl. file uploads
   └─ web_connection_endpoint_output_parmtr           value extracted from the response

oauth_server                                       (sf/manage_webconnections, branch-scoped, standalone)

process_action (process_action_type = web_connection, 602)     (sf/manage_process_flows)
├─ process_action_web_connection_endpoint_parmtr_input_parmtr   endpoint input → process variable / literal
├─ process_action_web_connection_parmtr_input_parmtr            connection input → process variable / literal
└─ process_action_modeler_web_connection_endpoint_output        endpoint output → process variable
```

Every entity under `web_connection` is keyed by `(model_id, branch_id, web_connection_id, …)`, cascading
one more key segment per nesting level (e.g. `web_connection_endpoint_parmtr` is keyed by
`(model_id, branch_id, web_connection_id, web_connection_endpoint_id, web_connection_endpoint_parmtr_id)`).
All of them carry `_model_history` shadow entities and a `task_show_history` bound task.
`oauth_server` sits at branch level, independent of any one connection — a single OAuth server can be
referenced by several web connections' `oauth_server_id`.

**Every child entity is a weak entity under its parent** — stage with `parent_entity_set` set to the
immediate parent (`web_connection` for `web_connection_endpoint`/`web_connection_parmtr`;
`web_connection_endpoint` for everything under an endpoint) and `parent_key` set to the parent's full
composite key, the same pattern used throughout the Software Factory API (see
`thinkwise_sf_process_flows` for the general weak-entity staging convention).

## Golden rule: confirm the integration design before building

A web connection encodes decisions that are awkward to unwind once endpoints and process flows
depend on them — which auth mechanism the target API demands, where its credentials live, and how
each response gets parsed. Apply the mcp_base skill's "Shared conventions" (confirm-before-mutate,
ask-don't-default) at the grain of this specific integration, before step 1 of Build order below.
Confirm with the user:

- **The external API and its base URL per environment** — which service, and whether dev/test/acc/prod
  need different `base_url` values (see [Overrides](#overrides--encryption)) or one value that's fine
  everywhere.
- **`authentication_type`, and where its credentials live** — stored on the base connection, deferred
  to the process flow (`use_deferred_credentials`), or stored encrypted (`encryption_used`). These are
  three distinct, largely mutually-exclusive mechanisms, not defaults to pick silently — see the
  `use_deferred_credentials` note under [Overrides & encryption](#overrides--encryption).
- **The endpoint list and each endpoint's parsing strategy** — which calls are actually needed, and
  whether each response is parsed with JSONPath, XPath, or a regex (see
  [Output parameters](#5--output-parameters--parsing-the-response)).

Get the user's explicit sign-off on this list before starting Build order step 1 — these choices are
the design, not implementation mechanics.

## Build order

1. `web_connection` — base URL, auth type, credentials (or `oauth_server_id` if auth type = OAuth)
2. `oauth_server`, only if auth type = OAuth and one doesn't already exist for this API — see
   `references/oauth.md`'s API-gap note before assuming this is fully configurable via this API
3. `web_connection_parmtr`, only if a value needs to be shared across multiple endpoints (e.g. a
   tenant id used in several paths)
4. `web_connection_endpoint` rows — one per distinct API call
5. Per endpoint: `web_connection_endpoint_parmtr`, `_query_string_parmtr`, `_request_header`,
   `_form_field` (multipart only), `_output_parmtr`
6. Wire into a process flow: a `web_connection`-type `process_action`, then the input/output binding
   rows — see `thinkwise_sf_process_flows`
7. Optional: runtime-configuration / IAM per-application overrides, encrypted credential storage

## 1–3 · Connection, authentication, and endpoints

Build the graph in order: **connection → authentication → endpoints → parameters**, and build all of
it in `sf/manage_webconnections` *before* touching the process-flow binding entities — a process
action cannot bind to an endpoint that doesn't exist yet.

One connection holds the base URL and auth; one endpoint per operation (method + relative path).
OAuth is configured on a separate `oauth_server` object referenced by the connection — see
`references/oauth.md`.

For the connection fields, every authentication type and what each needs, and endpoint setup, read
`references/connection_and_endpoints.md`.

## 4 · Parameters and response parsing

Input parameters carry values into the request (path, query, header or body) and can be
pre-processed; output parameters pull values back out of the response by path.

For both in full (parameter kinds and where each lands in the request, pre-processing options, the
response-parsing path syntax, and handling arrays and nested objects), read
`references/parameters_and_parsing.md`.

## Wiring into a process flow

Covered in depth by `thinkwise_sf_process_flows`; summarized here for the parts specific
to a web connection.

Add a `process_action` of type **`web_connection`** (602) in `sf/manage_process_flows`, with
`web_connection_id` and `web_connection_endpoint_id` both mandatory. The modeler then pre-seeds one
binding row per input/output parameter that endpoint (and any connection-level parameters it uses)
exposes — same pre-seeded, edit-only pattern as every other action type's I/O (query the placeholder
row first, then `edit` it; `add` against these child entities is rejected).

**Inputs** — `process_action_web_connection_endpoint_parmtr_input_parmtr` (per endpoint parameter) and
`process_action_web_connection_parmtr_input_parmtr` (per connection-level parameter used by this
endpoint):

- `assignment_method` — `variable` (pull from a `process_variable_id`) or `literal_constant` (a fixed
  `constant_value` typed into the model).

**Outputs** — `process_action_modeler_web_connection_endpoint_output`: one row per endpoint output
parameter, each with a `process_variable_id` to receive the extracted value.

If the API needs a bearer token obtained via OAuth, precede the `web_connection` action with an
`oauth_server_login_connector`/`oauth_user_login_connector` action and bind its access-token output to
the web connection's `bearer_token` input (only reachable this way if `authentication_type` = Bearer
token with the token supplied at run time, or via `use_deferred_credentials`) — or set
`authentication_type = oauth` directly on the connection and let it manage the exchange itself via
`oauth_server_id`, when the OAuth server field gap noted in `references/oauth.md` doesn't block that.

**Migrating an existing `http_connector` action:** the domain exposes a bound enrichment task on
`process_action`, `task_enrichment_conv_http_connector_to_web_connection` ("Convert HTTP connector to
Web connection with AI") — try this before hand-porting URL/headers/body manually.

## Overrides &amp; encryption

Because credentials differ by environment, base URL and authentication settings can be overridden
without touching the model:

- **Runtime configuration** (Software Factory → Maintenance) — `web_connection_configuration` /
  `web_connection_configuration_overview`, keyed additionally by `runtime_configuration_id`, mirroring
  every field on the base connection. `task_switch_web_connection_type` changes the auth type for one
  configuration; `task_reset_web_connection_configuration` reverts it to inherit the base connection.
- **Per-application override in IAM** (Authorization → Applications) — same fields, scoped to one
  deployed application instead of a runtime configuration.

Credential fields on either the base connection or an override can be stored encrypted
(`encryption_used`) via `task_encrypt_web_connection_key`, which takes the target
`authentication_type` plus whichever of `password` / `bearer_token` / `api_key_value` /
`client_certificate_password` applies.

> **`use_deferred_credentials` opts out of both overrides.** If set, authentication is supplied by the
> process flow itself at run time instead of being stored on the object, and as a direct consequence it
> can no longer be overridden per application in IAM or per runtime configuration. Pick one mechanism.
> **Ask the user explicitly before setting it** rather than defaulting to it as a convenience — it
> forecloses both override mechanisms at once and is not easily reversible once process flows are
> built assuming auth arrives this way.

## Worked examples

Three full walkthroughs — reading IAM's user table via Indicium, HubSpot's nested JSONPath response,
and mTLS + OAuth client credentials for a bank API — are in `references/worked_examples.md`. Purely
illustrative; skip unless you want a concrete precedent for one of these patterns.

## Known gotchas

- **Multipart form data on GET may be silently ignored.** One community report against an external
  API found the web connector's multipart form body wasn't applied on a GET request (an unfiltered
  full list came back instead of the filtered one) even though the process flow monitor showed the
  parameters as sent correctly. If this is hit, consider a support ticket and/or falling back to
  `http_connector` for just that one call rather than the whole integration.
- **JSON body escaping is per-parameter, not per-request** — a "non parsable body" response almost
  always means a parameter's pre-processing mode doesn't match whether its value is a scalar or
  already-serialized JSON. See the escaping gotcha above.
- **`use_deferred_credentials` disables both override mechanisms** — don't combine it with an
  expectation of environment-specific secrets stored in the model.
- **`oauth_server`'s real configuration fields are not exposed through `sf/manage_webconnections`**
  (only the key and `generated_by_control_proc_id`) — verify before promising a fully API-driven OAuth
  server setup; see `references/oauth.md`.
- **Managed identity** as an auth type has mostly been discussed as an HTTP-connector feature request
  in the community — confirm it behaves as expected for the target cloud before depending on it here.

## Naming

No dedicated web-connection naming convention has been observed beyond general Thinkwise guidance
(`thinkwise_sf_data_model`): lowercase snake_case, no abbreviations. In practice, name the
connection for the external service (`hubspot`, `azure_ad`, `iam`) and each endpoint for the operation
it performs (`get_contacts`, `create_invoice`, `usr`) rather than after the HTTP verb or URL shape.

## Translation

`web_connection_description`, `web_connection_endpoint_description`, and the parameter/output
descriptions are translatable objects, same as any other model object — don't leave new ones in the
source language only. See `thinkwise_sf_translations`.

## Pre-flight checklist

- Build the connection graph in `sf/manage_webconnections` **before** touching the process-flow
  binding entities in `sf/manage_process_flows` — the process action can't bind to a connection or
  endpoint that doesn't exist yet.
- Patch `authentication_type`, `endpoint_http_method`, `type_of_body`, and every other byte/enum field
  as the raw numeric or exact string value from its enum list — not a guessed label.
- Match a body-template parameter's pre-processing mode to what its *value* actually is (scalar vs.
  already-serialized JSON/XML) — this is the single most common cause of an unparsable request body.
- Before configuring OAuth: verify whether `oauth_server`'s client id/secret/endpoint fields are
  actually writable through this connector (the schema read shows only the key) rather than assuming
  the docs' field list is reachable via this API.
- Model output parameters (JSONPath/XPath/regex) rather than leaving response parsing to a downstream
  `extract_json` action or raw SQL — that's the whole point of preferring a web connection.
- Set `use_deferred_credentials` only when the flow-supplied-auth pattern is genuinely needed — it
  forecloses both the runtime-configuration and IAM per-application override mechanisms.

