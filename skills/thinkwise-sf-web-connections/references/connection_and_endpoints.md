# Web connection, authentication types, and endpoint setup

Loaded on demand from `thinkwise_sf_web_connections`.

## 1 · The web connection

Entity `web_connection` — one per external service/base URL.

| Field | Type | Notes |
|---|---|---|
| `web_connection_id` | key | Object name — see [Naming](#naming). |
| `web_connection_description` | string | Display label. |
| `base_url` | string | Scheme + host + fixed path prefix, e.g. `https://api.hubspot.com`. Overridable per environment — see [Overrides](#overrides--encryption). |
| `authentication_type` | `Edm.Byte` enum | `none`=0 · `basic_credentials`=1 · `bearer_token`=2 · `api_key`=3 · `managed_identity`=4 · `oauth`=5. Patch the raw integer, not the string label — same gotcha as `process_action_type` in the process-flows skill. |
| `user_name` / `password` | string | Auth type = Basic credentials. |
| `bearer_token` | string | Auth type = Bearer token. Pair with an upstream OAuth process action if the token needs periodic refresh — see [Wiring into a process flow](#wiring-into-a-process-flow). |
| `api_key_name` / `api_key_value` | string | Auth type = API key. |
| `api_key_parmtr_location` | `Edm.Byte` enum | `header_parmtr`=0 · `query_parmtr`=1 — where the key is injected. |
| `oauth_server_id` | ref → `oauth_server` | Auth type = OAuth. |
| `use_deferred_credentials` | flag | Push authentication into the *process flow* instead of storing it on the connection (supplied via web connection parameters at run time). **Once set, auth settings can no longer be overridden per application in IAM or per runtime configuration** — pick one mechanism, not both. |
| `client_certificate_file` | file (`.pfx`) | Mutual-TLS / client certificate auth — combines with any `authentication_type`, e.g. OAuth client-credentials *plus* mTLS. See the mTLS example in `references/worked_examples.md`. |
| `client_certificate_password` | string | Password protecting the `.pfx`. |
| `encryption_used` | flag | Store the credential fields encrypted (3-tier / Universal GUI branch-level encryption feature) — see [Overrides](#overrides--encryption). |

If the target API's required `authentication_type` or its credential-encryption policy (`encryption_used`)
isn't specified by the user, **ask** rather than defaulting to `none`/unencrypted — see
[Golden rule](#golden-rule-confirm-the-integration-design-before-building).

**Bound tasks:** `task_copy_web_connection`, `task_rename_web_connection`, `task_delete_web_connection`,
`task_encrypt_web_connection_key` (writes an encrypted credential value for a given
`authentication_type`), `task_reset_encrypt_web_connection_key`, `task_unlink_generated_object`,
`task_show_history`. Renaming cascades to every usage site automatically, same as elsewhere in the
Software Factory.

A connection can itself be model-generated (`generated_by_control_proc_id` set) — this is how
Thinkstore integration scripts scaffold connections programmatically; don't be surprised to find one
already wired up with this field populated.

**Not yet live-verified through this connector:** which of the above fields the write API treats as
strictly mandatory at creation vs. safely omittable. Default to setting several fields together in one
`stage_resource` call, per the tool's own recommended flow ("set the fields you know via properties in
this call to save a round-trip") — a multi-field drop is a real, confirmed failure mode on some entities
elsewhere in this skill set (see `thinkwise_sf_base`'s hazard note), but it isn't a
default assumption to apply pre-emptively here without having actually observed it on `web_connection`.
Re-read the `fields` block after the combined call to confirm every property landed; only fall back to
one-field-at-a-time isolation if a drop is actually observed on this entity.

## 2 · Authentication types

| Value | Name | Fields used | Notes |
|---|---|---|---|
| 0 | `none` | — | Public/unauthenticated API. |
| 1 | `basic_credentials` | `user_name`, `password` | Sent as `Authorization: Basic`. |
| 2 | `bearer_token` | `bearer_token` | Sent as `Authorization: Bearer <token>`. |
| 3 | `api_key` | `api_key_name`, `api_key_value`, `api_key_parmtr_location` | Injected as a header or query string param per `api_key_parmtr_location`. |
| 4 | `managed_identity` | — | Cloud-platform managed identity, no stored secret. Has been an active community feature request specifically for the *HTTP* connector — confirm current behavior for the target cloud (Azure) against the live model/version before depending on it for a web connection. |
| 5 | `oauth` | `oauth_server_id` | Delegates token acquisition to a configured OAuth server — see below. |

A client certificate (`client_certificate_file`/`_password`) is independent of `authentication_type`
and layers on top of it; it is not itself a 7th auth-type value.

## OAuth servers

OAuth server configuration (`oauth_server`, its known API gap) and the three OAuth process actions
(Server Login, User Login, Refresh Token — types, inputs/outputs, status codes) are covered in
`references/oauth.md`. Load it before configuring `authentication_type = oauth` on a connection or
wiring an OAuth process action into a flow.

## 3 · Endpoints

Entity `web_connection_endpoint` — one HTTP call shape under a connection.

| Field | Type | Notes |
|---|---|---|
| `web_connection_endpoint_id` | key | Object name, e.g. `get_contacts`. |
| `endpoint_http_method` | string enum | `GET` · `POST` · `PUT` · `PATCH` · `DELETE` · `HEAD` · `OPTIONS` · `TRACE` — values are the method names themselves, not numeric codes. |
| `endpoint_path` | string | Appended to `base_url`. `{token}` segments become endpoint input parameters automatically, e.g. `{table}({key})/appl.preview_{file_column}`. |
| `type_of_body` | `Edm.Byte` enum | `multipart_form`=0 · `form_url_encoded`=1 · `json`=2 · `xml`=3 · `yaml`=4 · `plain_text`=5 · `other`=6 · `none`=9. |
| `content_type_body` | string | `Content-Type` header sent — auto-suggested from `type_of_body`, overridable. |
| `endpoint_body` | string | Literal request-body template with `{param}` substitutions. |
| `endpoint_full_url` | computed, read-only | Preview of `base_url` + `endpoint_path`. |

**Query string parameters** (`web_connection_endpoint_query_string_parmtr`, key
`query_string_parmtr_name`): `query_string_parmtr_value` plus `omit_when_empty` to drop the param
entirely rather than send it blank.

**Request headers** (`web_connection_endpoint_request_header`, key `request_header_name`):
`request_header_value` plus `omit_when_empty`.

**Form fields** — multipart or form-url-encoded bodies (`web_connection_endpoint_form_field`, key
`form_field_name` + a generated `web_connection_endpoint_form_field_id`): `form_field_value`,
`omit_when_empty`, `derive_content_type_form_field` (infer content type from the file name),
`content_type_form_field` (explicit MIME type), `file_name` (parameterizable, e.g. `{file_name}`, for
binary uploads).

**Bound tasks:** `task_copy_web_connection_endpoint`, `task_rename_web_connection_endpoint`,
`task_delete_web_connection_endpoint`, plus rename/delete pairs for endpoint input parameters and
output parameters.
