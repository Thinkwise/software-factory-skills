# Web connection input parameters, pre-processing, and response parsing

Loaded on demand from `thinkwise_sf_web_connections`.

## 4 · Input parameters &amp; pre-processing

Two parameter scopes share the same shape: `web_connection_parmtr` (connection-wide — reusable across
every endpoint, e.g. a tenant id) and `web_connection_endpoint_parmtr` (single endpoint only).
Reference either with `{parameter_name}` anywhere textual — path, query string value, header value,
form field value, or body template. Renaming (`task_rename_web_connection_parmtr` /
`_endpoint_parmtr`) rewrites every usage site automatically, tracked in the read-only
`*_parmtr_usage` entities.

- `default_value` — constant fallback if the process flow doesn't supply one.
- `*_pre_processing` — how the raw value is escaped/encoded before substitution:

| Value | Name | Effect |
|---|---|---|
| 0 | `pre_processing_auto` | Chosen automatically based on where the parameter is used (query string vs. JSON body vs. XML body, etc.). |
| 1 | `pre_processing_query_string_value` | URL-encode special characters. |
| 2 | `pre_processing_json` | Escape as a JSON string value (escapes `"`). |
| 3 | `pre_processing_xml` | Escape as an XML string value. |
| 4 | `pre_processing_base64` | Base64-encode the value. |
| 9 | `pre_processing_none` | Substitute verbatim — required when the parameter's value is itself a pre-built JSON fragment/array. |

> **Escaping gotcha, from a real migration.** A JSON-body parameter is auto-escaped by default, so
> dropping `{param}` straight into a body template usually fails with "non parsable body" unless the
> value is a plain scalar. If the value is already-serialized JSON (e.g. a nested array from
> `FOR JSON PATH`), keep the body template **static** — `{ "documents": {document_array} }` — and set
> that parameter's pre-processing to `pre_processing_none`. Splicing the whole pre-built object in as
> `{request_body}` with default escaping, or hand-writing the structure with per-field scalar
> substitutions inside it, both produced unparsable bodies in practice. See
> `references/worked_examples.md`.

## 5 · Output parameters — parsing the response

Entity `web_connection_endpoint_output_parmtr`.

| Field | Type | Notes |
|---|---|---|
| `endpoint_output_mapping` | `Edm.Byte` enum | `http_status_code`=0 · `response_body`=1 · `response_header`=2 — where the value is read from. |
| `endpoint_output_response_header` | string | Header name, when mapping = response header. |
| `base64_decode` | flag | Decode the extracted value from Base64 before returning it. |
| `json_path_expression` | string | JSONPath applied to the response body, e.g. `$.results..properties`. |
| `always_as_array` | flag | Force the JSONPath result to be wrapped as an array even for a single match — keeps downstream parsing consistent. |
| `xpath_expression` | string | XPath applied to an XML response body. |
| `regular_expression` | string | Regex applied to extract a substring — works on any text response, not just JSON/XML. |

Normally only one of JSONPath / XPath / Regex is set per output parameter, matching whatever format
the API actually returns (independent of `type_of_body`, which only governs the outgoing request
body). Beyond the endpoint's own output parameters, the `web_connection` process action also exposes a
generic **status code** (0 = success; negative values for send/parse/timeout failures — check the live
status-code translations in the model rather than assuming a fixed list) and the raw **HTTP status
code** (200, 404, 500 …) regardless of any JSONPath/XPath mapping.
