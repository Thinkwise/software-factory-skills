# Publishing messages

## The message definition

A message (`message_broker_message_mqtt_overview` under the broker) carries:

- **Topic** — may contain `{parameter}` placeholders, e.g. `robots/{robot_id}/cmd`; the placeholder
  is substituted at publish time.
- **Payload** — a text template with `{parameter}` placeholders. Placeholders also work in the content
  type and user property values.
- **QoS** (0/1/2), **retain**, **expiry interval** (s), **content type** (MIME), **payload format**
  (unspecified / UTF-8 text; MQTT 5.0).
- **Reply expected** + **reply timeout** (MQTT 5.0) — the Publish message action then waits for the
  reply and exposes it through output parameters.
- **User properties** (MQTT 5.0) — key/value pairs.

Input parameters (`message_broker_message_mqtt_input_parmtr_overview`) have a default value and a
**pre-processing** option: none, JSON string value (escapes quotes), XML string value (entity-encodes)
or Base64. Use JSON string value for any free text inserted into a JSON payload.

Output parameters retrieve the reply payload, a reply user property, or the MQTT publish/reply error
code, with optional transformations (Base64 decode, JSON path, always as array, XPath, regex).

## Payload templates — values arrive as text

A placeholder is replaced by the parameter's text value, so a template like `{"x": {x}}` yields invalid
JSON when `x` is null or empty. Quote every placeholder (`"x":"{x}"`) and make the receiving side accept
quoted numbers, or normalize nulls before publishing (e.g. a task that replaces null with a harmless
default and returns it as an output). Send only fields the receiver tolerates; a receiver that ignores
unknown or irrelevant fields lets one message definition serve many commands.

## The Publish message process action

Type `950` (`publish_message`) with `message_broker_id` and `message_broker_message_id`. It works in a
user flow (e.g. started by a table task) and in a system flow.

- **Inputs** are pre-seeded rows in `process_action_modeler_message_broker_message_input`, one per
  message input parameter. Through the API these rows can't be edited (and can't be read by key), so
  map them in the Software Factory UI: Process flow → action → Input tab → each parameter to its
  process variable. Unmapped parameters use their default value; nothing warns about it.
- **Outputs** (status code, reply payload, …) map to process variables. Status `0` = OK, `1` = OK but no
  subscribers; negative values are errors (`-5` cannot connect, `-6` connect timeout, `-20` invalid
  topic, `-3x` decode/transformation errors). Route on the status when delivery matters.

## Command + correlation pattern (fire-and-forget with an asynchronous result)

For devices that report the outcome of a command on a separate result topic:

1. A **task** (one shared template for all command buttons) inserts the command row, sets
   `correlation_id = concat('<prefix>-', scope_identity())`, normalizes the payload values and returns
   them as task outputs (input+output parameters; see `thinkwise_sf_tasks`).
2. A **user flow** has each command task (table task) as a starting point, maps every task output to a
   process variable, and continues to **one** Publish message action whose inputs are those variables.
   One flow and one message serve every command.
3. The device echoes the id in its result; the **result subscription's** system flow finds the command
   row by `correlation_id` and stores the outcome. Results without a known id (commands from other
   clients) are registered as external rows instead of being dropped.
4. Commands stay in a "sent" state until the result arrives — make that visible (status column, sent-at
   age) so a lost message or offline device is noticed.

Use **reply expected** instead only when the device answers on the MQTT 5.0 response topic and the user
can wait for the answer.
