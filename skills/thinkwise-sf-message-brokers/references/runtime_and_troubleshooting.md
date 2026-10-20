# Runtime, IAM and troubleshooting

## Deployment order

1. Generate definition → validate → generate code → execute source code (see
   `thinkwise_sf_deployment`). Regenerate the definition after every model change before generating
   code.
2. **Sync to IAM.** The broker, messages, subscriptions and mappings travel to IAM
   (`sf_message_broker*` tables); Indicium reads them from there. Variable/domain changes need a sync.
3. **Enable subscriptions in Indicium** and restart it (below).

## Indicium settings

Subscriptions are disabled by default so that several Indicium instances don't compete for the same
messages. On **exactly one** instance, in `appsettings.json`:

```json
"Agent": {
  "Enabled": true,
  "MessageBroker": { "MQTT": { "SubscriptionsEnabled": true } }
}
```

`Agent:Enabled` must be true as well (it hosts all background services, including scheduled system
flows). Restart Indicium after changing it, and after an application that has subscriptions is first
added to IAM. Publishing works without this setting.

## IAM per environment

Authorization → Applications → General settings → Message brokers overrides the connection and
authentication settings per application (Edit / Reset MQTT configuration back to the model defaults).
Without an override row (`iam_message_broker_mqtt`) the model's settings apply — so `localhost` in the
model means the machine Indicium runs on. Secrets (password, access token, client certificate and its
password) are set with the "Set message broker key values (encrypted)" task in IAM, or "Set MQTT key
values (encrypted)" in the Software Factory for development; they are **not** synced between the two.

## Diagnosis when nothing arrives

Work from the broker inwards:

1. **Broker reachable and the device publishing?** Subscribe with any MQTT client to the topics; retained
   messages appear immediately.
2. **Is Indicium subscribed?** On Mosquitto, compare `$SYS/broker/subscriptions/count` with the number
   of known clients' subscriptions. If Indicium is connected (it publishes) but adds no subscriptions,
   the `SubscriptionsEnabled` switch is off or Indicium wasn't restarted.
3. **Do the flows run?** Look in the Indicium log for
   `Unhandled exception in MQTT subscription process flow for topic '…'` — the inner message names the
   failing variable (type conversion) or the database error.
4. **Does the task run?** On SQL Server, `sys.dm_exec_procedure_stats` for the application database shows
   whether the receiving task procedures were executed at all.
5. **Runtime parameter errors** ("procedure … expects parameter '@x', which was not supplied") mean the
   deployed code was generated from an older definition — regenerate the definition, regenerate code,
   redeploy.

There is no MQTT-specific monitor; besides the Indicium log, the Process Flow Monitor and the IAM
system flow logs cover flow runs.

## Connection settings worth checking

Port 1883 plain / 8883 TLS; **insecure skip verify** only for testing; client ID prefix ≤ 5 characters;
clean start discards the session and subscriptions on disconnect; session expiry (default 300 s),
keep-alive (60 s) and connection timeout (10 000 ms). Authentication: none, username/password, OAuth
client credentials, access token (manual renewal), optionally a client certificate.

Not documented and not verified: reconnect/retry behaviour of the listener, parallel flow runs per
subscription, shared-subscription details, certificate formats.
