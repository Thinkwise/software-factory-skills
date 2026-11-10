# OAuth servers

Entity `oauth_server`, Model overview → Branches → OAuth servers in the UI. Per the docs, a fully
configured OAuth server has: **Client ID**, **Client Secret**, **Client Credentials Delivery** (*in the
request body*, the default, or *as Basic Auth header*), **PKCE requirement** (on by default), and —
for the user-login connector specifically — **Request Refresh Token** and **Prompt behaviour**
(*Consent* / *Login* / *Select Account* / *None*), plus the authorization and token endpoint URLs.

> **Field exposure depends on the domain layout.**
> - **(Indicium · single-domain)** `oauth_server` in `sf/software_development` exposes the
>   configuration: `authorization_url`, `token_url`, `client_id`, `client_secret`, `scope`, `prompt`,
>   `request_refresh_token`, `response_type`, `client_authentication_mode` (body/header),
>   `require_pkce`, `encryption_used`, plus the bound task `task_encrypt_oauth_key` for an encrypted
>   client secret.
> - **(Indicium · split-domain)** `oauth_server` in `sf/manage_webconnections` returns **only**
>   `model_id`, `branch_id`, `oauth_server_id` and `generated_by_control_proc_id`. Search the other
>   domains for a writable `oauth_server` before planning the configuration as a manual step in the
>   Software Factory.
>
> Either way, read the entity definition before promising a user a hands-off OAuth server setup.

### The three OAuth process actions

These are ordinary `process_action_type` values on the process-flow side, not part of the
connection graph:

| Connector | Type value | Grant type | Key inputs | Key outputs | Status codes |
|---|---|---|---|---|---|
| OAuth Server Login | `oauth_server_login_connector` = 575 | Client credentials, no user interaction | Scope (overrides server default) | Access token, token type, expires-in | 0 ok · −1 unknown · −2 no configuration · −3 no scope defined |
| OAuth User Login | `oauth_user_login_connector` = 560 | Authorization code, needs user consent | Scope (optional), UsePrompt (default true) | Access token, granted scopes, expires-in, refresh token (if offline access), token type | 0 ok · −1 unknown · −2 user aborted · −3 server connection error · −5 unsupported token type |
| OAuth Refresh Token | `oauth_refresh_token_connector` = 570 | Refresh, exchanges a refresh token | Refresh token (from the user-login connector) | New access token, granted scopes, expires-in, refresh token, token type | 0 ok · −1 unknown · −2 no OAuth server configured · −3 missing input data |

> **Treat this status-code list as a snapshot, not a fixed contract.** As with the generic
> `web_connection` action's status code (see the main skill's Output-parameters section), check the
> live status-code translations in the model rather than assuming the table above is exhaustive or
> stable across versions.

The **OAuth Server Login connector does not support client certificates** — for an API needing OAuth
client-credentials *and* mTLS, do the token exchange through a plain web connection endpoint instead
(see the mTLS example in `references/worked_examples.md`).

User-login flows need the redirect URI whitelisted via the `OAuthRedirectURI` extended property in
IAM: `http://localhost/oauth-callback` (Windows GUI, 2-tier) or `<indicium URL>/oauth-callback`
(3-tier / Universal GUI).
