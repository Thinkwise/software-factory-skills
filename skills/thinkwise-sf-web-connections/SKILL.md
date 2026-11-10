---
name: thinkwise-sf-web-connections
description: Reference guide for creating and using Web Connections and OAuth servers in a Thinkwise Software Factory model, the preferred mechanism for calling external HTTP/REST APIs. Covers authentication, endpoint and parameter setup, response parsing, and wiring a connection into a process flow. Use whenever an MCP connector with Software Factory access creates, inspects, or troubleshoots a web connection or OAuth server, in place of a one-off http_connector process action.
---

# Web Connections in the Thinkwise Software Factory

A **Web Connection** is a modeled, reusable definition of an external HTTP(S) API: one base URL and
authentication scheme (`web_connection`), with one or more named **endpoints** underneath it
(`web_connection_endpoint` — method, path, body). It replaces the legacy `http_connector` process
action, which re-enters URL/method/headers/auth on every single process action with no reuse, no
override mechanism, and no built-in response parsing. For event-style integration over MQTT
(publish/subscribe instead of request/response), see `thinkwise-sf-message-brokers`.

**Domain:** split-domain instances use two — `sf/manage_webconnections` for the connection graph and
`sf/manage_process_flows` for the process-flow side; single-domain `sf/software_development` holds
both; otherwise find them with `search_domain_capabilities`. The work has two halves:

- **The connection graph** — `web_connection`, `web_connection_endpoint` and every child (parameters,
  headers, query strings, form fields, output parameters), plus `oauth_server`. Build the connection
  here first.
- **The process-flow side** — the `web_connection` process action plus its input/output *binding*
  entities (`process_action_web_connection_endpoint_parmtr_input_parmtr`,
  `process_action_web_connection_parmtr_input_parmtr`,
  `process_action_modeler_web_connection_endpoint_output`). Wire the already-built connection into a
  flow here — see `thinkwise-sf-process-flows`, which this skill complements rather than
  duplicates.

> **(Indicium · split-domain)** `sf/manage_process_flows` also exposes `web_connection`/
> `web_connection_endpoint`, but only as the object a process action references by id, with almost no
> writable configuration. Read and write them in `sf/manage_webconnections`, where both carry their
> full configuration — `base_url`, `authentication_type`, credentials, `endpoint_http_method`,
> `endpoint_path`, `type_of_body`, `endpoint_body`, etc. Building a web connection from scratch is fully
> possible through the write API; it does not require the Software Factory's own UI.

## Entity map

```
web_connection                                    (connection graph)
├─ web_connection_parmtr                           connection-wide {param}, reused across endpoints
├─ web_connection_configuration(_overview)          per runtime-configuration / per-app override
└─ web_connection_endpoint                          one HTTP call shape
   ├─ web_connection_endpoint_parmtr                 endpoint-scoped input {param}
   ├─ web_connection_endpoint_query_string_parmtr    name/value, omit-when-empty
   ├─ web_connection_endpoint_request_header         name/value, omit-when-empty
   ├─ web_connection_endpoint_form_field              multipart/form fields, incl. file uploads
   └─ web_connection_endpoint_output_parmtr           value extracted from the response

oauth_server                                       (connection graph, branch-scoped, standalone)

process_action (process_action_type = web_connection, 602)     (process-flow side)
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
composite key (see `thinkwise-sf-base` for the general weak-entity staging convention). Exception:
`web_connection_endpoint_parmtr` — see `references/parameters_and_parsing.md`.

## Golden rule: confirm the integration design before building

A web connection encodes decisions that are awkward to unwind once endpoints and process flows
depend on them — which auth mechanism the target API demands, where its credentials live, and how
each response gets parsed. Apply `thinkwise-sf-base`'s "Shared conventions" (confirm-before-mutate,
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
   `references/oauth.md`'s field-exposure note before assuming this is fully configurable via the API
3. `web_connection_parmtr`, only if a value needs to be shared across multiple endpoints (e.g. a
   tenant id used in several paths)
4. `web_connection_endpoint` rows — one per distinct API call
5. Per endpoint: `web_connection_endpoint_parmtr`, `_query_string_parmtr`, `_request_header`,
   `_form_field` (multipart only), `_output_parmtr` — add every `{param}` used in the path/body as its
   own parameter row; a token in the text does not create one
6. Wire into a process flow: a `web_connection`-type `process_action`, then the input/output binding
   rows — see `thinkwise-sf-process-flows`
7. Optional: runtime-configuration / IAM per-application overrides, encrypted credential storage

## 1–3 · Connection, authentication, and endpoints

Build the graph in order: **connection → authentication → endpoints → parameters**, and build all of
it *before* touching the process-flow binding entities — a process action cannot bind to an endpoint
that doesn't exist yet.

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

Covered in depth by `thinkwise-sf-process-flows`; summarized here for the parts specific
to a web connection.

Add a `process_action` of type **`web_connection`** (602), with
`web_connection_id` and `web_connection_endpoint_id` both mandatory — send the endpoint after the
connection, since setting `web_connection_id` clears it (see `thinkwise-sf-process-flows`). The
modeler then pre-seeds one
binding row per input/output parameter that endpoint (and any connection-level parameters it uses)
exposes — same pre-seeded, edit-only pattern as every other action type's I/O (query the placeholder
row first, then `edit` it; `add` against these child entities is rejected).

**Inputs** — map an endpoint input by editing its pre-seeded
`process_action_modeler_web_connection_endpoint_input` row (one per endpoint parameter, under the
process action); the edit creates the stored `process_action_web_connection_endpoint_parmtr_input_parmtr`
row. Connection-level parameters used by this endpoint are stored in
`process_action_web_connection_parmtr_input_parmtr`. On each:

- `assignment_method` — `variable` (pull from a `process_variable_id`) or `literal_constant` (a fixed
  `constant_value` typed into the model).

Read the stored `..._parmtr_input_parmtr` row back to confirm the mapping.

**Outputs** — `process_action_modeler_web_connection_endpoint_output`: one row per endpoint output
parameter, each with a `process_variable_id` to receive the extracted value.

If the API needs a bearer token obtained via OAuth, precede the `web_connection` action with an
`oauth_server_login_connector`/`oauth_user_login_connector` action and bind its access-token output to
the web connection's `bearer_token` input (only reachable this way if `authentication_type` = Bearer
token with the token supplied at run time, or via `use_deferred_credentials`) — or set
`authentication_type = oauth` directly on the connection and let it manage the exchange itself via
`oauth_server_id`, when the `oauth_server` fields are reachable (see `references/oauth.md`).

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
- **(Indicium · split-domain)** `oauth_server`'s configuration fields are not exposed through
  `sf/manage_webconnections` (only the key and `generated_by_control_proc_id`); single-domain
  `sf/software_development` exposes them. Check the entity definition before promising a fully
  API-driven OAuth server setup; see `references/oauth.md`.
- **Managed identity** as an auth type has mostly been discussed as an HTTP-connector feature request
  in the community — confirm it behaves as expected for the target cloud before depending on it here.

## Naming

No dedicated web-connection naming convention has been observed beyond general Thinkwise guidance
(`thinkwise-sf-data-model`): lowercase snake_case, no abbreviations. In practice, name the
connection for the external service (`hubspot`, `azure_ad`, `iam`) and each endpoint for the operation
it performs (`get_contacts`, `create_invoice`, `usr`) rather than after the HTTP verb or URL shape.

## Translation

`web_connection_description`, `web_connection_endpoint_description`, and the parameter/output
descriptions are translatable objects, same as any other model object — don't leave new ones in the
source language only. Their `transl_object` rows don't exist right after creation; look for them
again after the next definition generation and fill them then. Deleting a connection, endpoint or parameter leaves its `transl_object` rows
behind — delete the orphans too. See `thinkwise-sf-translations`.

## Pre-flight checklist

- Build the connection graph **before** touching the process-flow binding entities — the process
  action can't bind to a connection or endpoint that doesn't exist yet.
- Patch `authentication_type`, `endpoint_http_method`, `type_of_body`, and every other byte/enum field
  as the raw numeric or exact string value from its enum list — not a guessed label.
- Match a body-template parameter's pre-processing mode to what its *value* actually is (scalar vs.
  already-serialized JSON/XML) — this is the single most common cause of an unparsable request body.
- Before configuring OAuth: check whether `oauth_server`'s entity definition lists the client
  id/secret/URL fields (split-domain shows only the key) rather than assuming they are reachable.
- Model output parameters (JSONPath/XPath/regex) rather than leaving response parsing to a downstream
  `extract_json` action or raw SQL — that's the whole point of preferring a web connection.
- Set `use_deferred_credentials` only when the flow-supplied-auth pattern is genuinely needed — it
  forecloses both the runtime-configuration and IAM per-application override mechanisms.

