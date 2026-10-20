---
name: thinkwise-sf-message-brokers
description: Reference guide for MQTT message brokers in a Thinkwise Software Factory model — broker connection settings, publishing modeled messages from a process flow, and subscriptions that start system flows with mapped process variables, plus the Indicium/IAM runtime setup. Use whenever an MCP connector with Software Factory access creates, inspects, or troubleshoots a message broker, message, subscription, or Publish message process action.
---

# Message brokers (MQTT) in the Thinkwise Software Factory

A **message broker** is a modeled connection to an MQTT broker (Mosquitto, EMQX, HiveMQ, Chariot or a
generic MQTT broker). Under it you model **messages** — topic and payload templates published by the
**Publish message** process action — and **subscriptions** — topic filters that start a **system flow**
for every arriving message, with parts of the message mapped onto process variables.

Publishing arrived in 2026.2 and subscriptions in 2026.3; MQTT is the only protocol. Last will, user
properties, payload format and request/reply ("reply expected") need MQTT 5.0. Check the platform
version before promising a feature.

**When to use what:**

| Need | Use |
|---|---|
| Device/machine/other system pushes events (telemetry, status, results) | Subscription → system flow |
| Application sends a command or event to devices/other systems | Message + Publish message action |
| Request/response with an HTTP API | `thinkwise_sf_web_connections` |
| Periodically fetch data | Scheduled system flow (see `thinkwise_sf_process_flows`) |

## Entity map

Every entity here is keyed by `model_id, branch_id, message_broker_id, …` and is added as a dependent
of its parent. Several are only addable through an `_overview` entity-set variant:

| Object | Add through | Parent | Notes |
|---|---|---|---|
| Broker | `message_broker` | `branch` | `message_protocol` mqtt; adding it auto-creates `message_broker_mqtt` (connection settings) — edit that row, don't add one |
| Message | `message_broker_message_mqtt_overview` | `message_broker` | Topic, payload, QoS, retain, expiry, content type, payload format, reply expected |
| Message input parameter | `message_broker_message_mqtt_input_parmtr_overview` | the message overview row | Name, default value, pre-processing |
| Subscription | `message_broker_subscription_mqtt_overview` | `message_broker` | `process_flow_id`, `mqtt_topic_filter`, `max_qos_level` in one record |
| Variable mapping | `message_broker_subscription_mapping_mqtt` | the subscription overview row | One row per process variable |
| Publish action | `process_action` type `950` (`publish_message`) | `process_flow` | `message_broker_id`, `message_broker_message_id` |

Read field lists, enums and keys from the entity metadata; this table only carries what the metadata
doesn't say (which variant to add through, and the auto-created settings row).

## Plan first

Before creating anything, agree with the user on the **MQTT contract** — it outlives the model:

- **Topics** per direction, with the variable part as a placeholder (`devices/{device_id}/state`).
- **Payload format** per topic (JSON shape, field names, which fields can be null/absent).
- **Which topics are retained** and at which QoS; which messages may arrive at high frequency.
- **Correlation**: how a result is matched to the command that caused it (an id echoed back).
- **One system flow per subscribed topic** and what each one stores; what gets logged.
- **Fire-and-forget or reply expected** for each published message.

## Build order

1. Broker (connection settings on the auto-created `message_broker_mqtt` row).
2. Messages and their input parameters.
3. Tables/tasks that store or prepare the data (task logic per `thinkwise_sf_tasks` /
   `thinkwise_sf_control_procedures`).
4. System flows with their **process variables first**, then the actions (Execute system task, …).
5. Subscriptions, then their variable mappings.
6. User flows that publish: a task or table task as starting point → Publish message → stop.
7. Map the Publish message inputs (Software Factory UI, see gotchas) and the task outputs.
8. Generate, validate, deploy, sync to IAM, enable subscriptions in Indicium, restart.

## Publishing

For message templates and `{parameter}` placeholders, input pre-processing (JSON/XML string value,
Base64), the Publish message action and its input/output mapping, publish status codes, reply-expected
request/response, and the command-with-correlation-id pattern, read `references/publishing.md`.

## Subscriptions

For topic filters (`+`, `#`, `$share/<group>/`, `{placeholder}` levels), the mapping sources and
transformations (JSON path, XPath, regex, Base64), type conversion into process variables (JSON
booleans), nested payloads, retained-message ordering, and designing the receiving system flow, read
`references/subscriptions.md`.

## Runtime, IAM and troubleshooting

For the Indicium `Agent:MessageBroker:MQTT:SubscriptionsEnabled` switch, IAM per-application overrides
and encrypted key values, deployment order, and a step-by-step diagnosis when nothing arrives, read
`references/runtime_and_troubleshooting.md`.

## Worked example

For a complete robot remote-control blueprint (command publish with correlation id; state, result,
status and config subscriptions; blocked-state notification; SQL for the receiving tasks), read
`references/worked_example.md`.

## Known gotchas

- **Publish message inputs can't be mapped through the API.** The pre-seeded rows in
  `process_action_modeler_message_broker_message_input` reject edits (even a single-row read by key
  fails). Build everything else, then tell the user to map each input to its process variable in the
  Software Factory UI. Unmapped inputs silently fall back to their default value.
- **Subscriptions are off by default in Indicium.** Without `Agent:MessageBroker:MQTT:SubscriptionsEnabled
  = true` Indicium still publishes but never processes incoming messages, and logs nothing about it.
- **JSON `true`/`false` can't be mapped into bit or numeric process variables** — the flow fails with
  "invalid value for its '<variable>' parameter". Map such fields to a short varchar domain and
  convert in SQL.
- **Client ID prefix is at most 5 characters** — Indicium appends 18 characters and MQTT allows 23.
- **A subscription's process flow must be a system flow**, and its variables must exist before
  mappings can reference them; the flow becomes read-only on the subscription once mappings exist.
- **Placeholders are inserted as text.** Quote them in a JSON payload template (`"x":"{x}"`) so a null
  or empty value still yields valid JSON, and make the receiver accept quoted numbers.
- **Broker secrets are not synced** between the Software Factory and IAM — set them per environment.

## Naming

Name brokers after the system they reach (`mqtt_robot`, `plant_broker`), messages after the action
they request (`robot_command`), subscriptions after the topic purpose (`robot_state`), and their system
flows `<subject>_<event>_received` (`robot_state_received`). Ids share their namespace with other
model objects; check for collisions first.

## Pre-flight checklist

- Platform version supports what's planned (publish 2026.2+, subscriptions 2026.3+, MQTT 5.0 features).
- Topic/payload contract agreed with the user, including nullable fields and retained topics.
- Process variables created before actions and mappings; every task output mapped explicitly.
- Boolean JSON fields mapped to a text domain, converted in the task.
- User told to map the Publish message inputs in the Software Factory UI.
- After deploy: IAM synced, subscriptions enabled on exactly one Indicium instance, Indicium restarted.

## Sources

- Message brokers (SF): https://docs.thinkwisesoftware.com/docs/sf/message_brokers
- Process actions (Publish message, status codes): https://docs.thinkwisesoftware.com/docs/sf/process_flows_actions
- Indicium configuration (`Agent:MessageBroker`): https://docs.thinkwisesoftware.com/docs/deployment/indicium_configuration
- IAM application message brokers: https://docs.thinkwisesoftware.com/docs/iam/applications
- Release blogs: https://docs.thinkwisesoftware.com/blog/2026_2, https://docs.thinkwisesoftware.com/blog/2026_3
