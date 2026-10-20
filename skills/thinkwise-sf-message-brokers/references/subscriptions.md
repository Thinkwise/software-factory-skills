# Subscriptions

A subscription (`message_broker_subscription_mqtt_overview` under the broker) listens to one topic
filter and starts its **system flow** once per arriving message. Create the system flow and its process
variables first; the flow becomes read-only on the subscription once mappings exist.

## Topic filters

- MQTT wildcards `+` (one level) and `#` (rest of the topic), and the `$share/<group>/` prefix for
  shared subscriptions. No whitespace.
- A `{name}` level is a placeholder: it subscribes as a single-level wildcard and makes that level
  available to the mappings as a **topic parameter** (`robots/{robot_id}/state` → `robot_id`).
- **Max QoS level**: 0 for high-frequency telemetry where a lost message is replaced by the next, 1 for
  results and status changes.
- Two subscriptions with the same filter are a validation error
  (`val_message_broker_subscription_duplicate_topic_filter`).

## Mapping message parts onto process variables

One `message_broker_subscription_mapping_mqtt` row per process variable (each variable at most once per
subscription). `mqtt_message_output_mapping` picks the source:

| Source | Use |
|---|---|
| Payload | The body; combine with JSON path / XPath / regex to pick one value, or leave raw |
| Topic parameter | The value of a `{name}` level (`mqtt_topic_parmtr` = the placeholder name) |
| Original topic / actual topic | The topic text (original vs. actual differs only in edge cases; unverified) |
| User property | An MQTT 5.0 user property (`mqtt_usr_property_name`) |
| Retain, content type, payload format indicator, correlation data | Message metadata |

Transformations: Base64 decode, **JSON path** (`$.x`, `$.target.x`), always as array, XPath, regex. A
JSON path to an absent or null element gives a null variable — design the receiving task for nulls.

## Type conversion — map to the variable's domain, booleans excepted

Mapped values are converted to the process variable's domain. Numbers and text convert; **JSON
`true`/`false` do not convert to a bit or numeric domain** and the whole flow run fails
("process flow … was provided with an invalid value for its '<variable>' parameter"). Give such
variables (and the receiving task parameters) a short varchar domain, e.g. `json_boolean` varchar(5),
and convert in SQL: `iif(@docked = 'true', 1, 0)`. Changing a variable's domain changes the IAM model,
so it needs a definition regeneration, deployment and IAM sync.

## Nested and variable payloads

Map single values with JSON paths. For arrays or deeply nested structures (e.g. a list of obstacles),
map the **raw payload** to an nvarchar(max) variable and unpack it in the task with `isjson`,
`json_value` and `openjson … with (…)`.

## Retained messages and ordering

On (re)subscribe the broker replays every retained message on matching topics, in no guaranteed order
across topics. Every receiving task must therefore **upsert** the parent record (create the device row
on first contact from whichever topic arrives first) and must not assume another topic was processed
before it.

## Designing the receiving system flow

- `start` → **Execute system task** (the task does all SQL work) → `stop`. Map every variable to the
  task's input parameters explicitly — nothing auto-maps by name.
- Optional follow-up: a **decision** on task outputs (e.g. `is_blocked`, `notify_user`) leading to
  **Send user notification** with `send_noti_usr_id`/`send_noti_text` from variables and a literal
  title/notification type.
- **High-frequency topics are a hot path** (a message per step/second): keep the task cheap, update
  derived values only when something actually changed, and don't write a log row per message.
- Log the low-frequency topics (results, status, config) to an MQTT log table for demos and support.
- Device status with an MQTT **Last Will** (`offline`) is the reliable way to show a device as offline
  even when its process is killed.
