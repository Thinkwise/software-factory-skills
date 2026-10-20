# Local HTTPS and OAuth discovery for a self-hosted Indicium

Applies when the MCP endpoint is an Indicium hosted locally (typically IIS on
the user's own machine, e.g. `https://localhost/indicium/mcp`), or when a
client reports a certificate error or OAuth discovery fails.

Certificate stores, IIS bindings and app-pool settings all need an elevated
shell. An agent shell is usually not elevated, and a UAC prompt launched from
the agent may be cancelled or blocked — write the change as a PowerShell
script and hand the user the exact command to run from an elevated PowerShell.
This skill ships no scripts: write each one for the user's machine from the
goals in sections 2 and 3, and show it to the user before they run it. Make
every script stop on the first error (`$ErrorActionPreference = 'Stop'`), take
the values that differ per machine as parameters, and log what it did to a
transcript file you can read afterwards — the elevated window's output never
reaches the agent.

## 1. Symptom → layer

Diagnose which layer fails before changing anything. Test `http://` and
`https://` separately: if both return the same error, the problem is in
Indicium, not TLS.

| Symptom | Layer / cause | Next step |
|---|---|---|
| `GET <base>/mcp` → `405`, `Allow: POST` | Healthy — MCP accepts POST only | Test with a POST instead |
| Unauthenticated POST to `/mcp` → `401` with `WWW-Authenticate: Bearer resource_metadata=…` | Healthy — OAuth required | Continue the install |
| Client: "certificate validation failed", `UNABLE_TO_VERIFY_LEAF_SIGNATURE`, `DEPTH_ZERO_SELF_SIGNED_CERT`, `SELF_SIGNED_CERT_IN_CHAIN` | Client does not trust the server certificate | Section 2 |
| Works in curl / plain Node, fails in an Electron app | Bare self-signed leaf; Electron/Chromium (BoringSSL) will not use it as a trust anchor | Section 2 — reissue as CA + leaf |
| Windows `curl.exe` exit code `35` against a locally issued cert | Schannel revocation check; a local CA publishes no CRL | Add `--ssl-no-revoke` (diagnostics only) |
| `<base>/.well-known/openid-configuration` → `500` (often also over http) | Indicium cannot load its OpenID signing certificate | Section 3 |
| Plain `404` / IIS error page | Path not served over that scheme | See the 404 paragraph in SKILL.md Troubleshooting |

For any `500`, read the newest `<Indicium install folder>\Logs\Indicium-<yyyyMMdd>.txt`
(e.g. `C:\inetpub\wwwroot\indicium\Logs\`) and look for `[FTL]`/`[ERR]` lines
at the request time.

## 2. Local HTTPS for IIS-hosted Indicium

Never issue a bare self-signed `CN=localhost` leaf. Plain Node/OpenSSL and
Windows Schannel accept one once it is trusted, but Electron-based clients
(and Chromium) reject it with `UNABLE_TO_VERIFY_LEAF_SIGNATURE` even when it is
explicitly trusted — so a passing curl or Node test does not prove the client
will connect. Issue a local root CA and a leaf signed by it instead:

- **CA**: `basicConstraints` critical `CA:true, pathlen:0`; key usage
  `keyCertSign, cRLSign`. Trust its public certificate in `LocalMachine\Root`,
  then delete its private key so it cannot sign anything else.
- **Leaf**: `CN=localhost`; SANs `DNS:localhost`, `DNS:<machine name>`,
  `IP:127.0.0.1`, `IP:::1`; EKU serverAuth; `basicConstraints` critical
  `CA:false`; stored in `LocalMachine\My`.
- **IIS**: add an `https` binding on 443 to the site that hosts the Indicium
  application (find it by application path, not by assuming "Default Web
  Site") and assign the leaf to it.

### Writing the certificate script

Goal: one elevated script that does all of the above and can be re-run to
rotate both certificates. Parameters: an output folder (default a stable
per-user folder such as `$env:USERPROFILE\.certs\localhost`, so the PEM path
stays valid for `NODE_EXTRA_CA_CERTS`), the application path (default
`/indicium`) and the HTTPS port (default `443`). In order, it should:

1. **Remove earlier runs' certificates** from `LocalMachine\My` and
   `LocalMachine\Root` — recognise them by a fixed CA subject and leaf friendly
   name chosen for this purpose, and delete their keys too.
2. **Create the CA** with `New-SelfSignedCertificate` in `LocalMachine\My`:
   key usage CertSign, CRLSign, DigitalSignature; basic constraints through
   `-TextExtension '2.5.29.19={critical}{text}ca=1&pathlength=0'`; RSA 2048,
   SHA-256; long validity (e.g. 10 years).
3. **Create the leaf**, signed by the CA (`-Signer`): subject `CN=localhost`;
   SANs through extension `2.5.29.17` (`DNS=localhost&DNS=<COMPUTERNAME>&IPAddress=127.0.0.1&IPAddress=::1`);
   EKU serverAuth (`2.5.29.37`, `1.3.6.1.5.5.7.3.1`); critical `ca=0`; key usage
   DigitalSignature, KeyEncipherment; exportable key; shorter validity than the
   CA (e.g. 5 years).
4. **Trust and export the CA's public part**: export it as
   `localhost-ca.cer` and as a PEM file `localhost.pem` (Base64 with line
   breaks between `BEGIN/END CERTIFICATE`, ASCII), import the `.cer` into
   `LocalMachine\Root`, then delete the CA from `LocalMachine\My` including its
   private key.
5. **Bind the leaf in IIS**: find the site whose applications include the
   application path (fall back to "Default Web Site" only when none does), add
   an `https` binding on the port if it's missing, and replace the binding's
   certificate with the leaf.
6. **Print the next step**: the PEM path to put in `NODE_EXTRA_CA_CERTS`.

Afterwards, check the transcript and test the endpoint over `https://` with
curl (`--ssl-no-revoke`) and from the client that failed.

**Node-based clients** (Claude Code, the main process of Electron apps) do
not read the Windows Root store by default. Point them at the CA PEM with a
user-level environment variable:

```powershell
[Environment]::SetEnvironmentVariable('NODE_EXTRA_CA_CERTS', '<OutDir>\localhost.pem', 'User')
```

It is read only at process start: fully restart every client afterwards
(including VS Code, which passes its environment on to Claude Code). The
variable must point to the CA certificate, not the leaf.

When testing Electron TLS behaviour by launching an Electron binary from an
agent shell inside VS Code, unset `ELECTRON_RUN_AS_NODE` first — it is
inherited from the editor and makes Electron run as plain Node, which accepts
certificates Electron itself would reject.

## 3. OAuth discovery 500 (OpenID signing certificate)

Log signature:

```
[WRN] [Data security] Invalid storage configuration recognized for OpenID. Falling back to the certificate store.
[FTL] Unhandled exception: "Access is denied."
System.Security.Cryptography.CryptographicException: Access is denied.
   at System.Security.Cryptography.X509Certificates.X509Store.Open(OpenFlags flags)
   at Indicium.StartupExtensions.getOrCreateCertificateFromStore(String certificateName)
   at Indicium.StartupExtensions.getIdentityServerCertificate(...)
```

Indicium stores its OpenID (IdentityServer) signing certificate in Azure Key
Vault, AWS Secrets Manager, or otherwise the **Current User certificate store
of the app-pool identity**. `DataSecuritySettings` storage mode `LocalSystem`
does not cover the OpenID certificate, so changing `appsettings.json` alone
does not fix this. An IIS app pool that does not load its user profile has no
Current User store, hence "Access is denied".

Fix: set **Load User Profile = True** on the app pool that runs the Indicium
application (`processModel.loadUserProfile`, plus
`processModel.setProfileEnvironment`) and recycle it. Indicium creates the
certificate on the next discovery request.

Goal of the script: given the application path (default `/indicium`), find
the IIS application at that path across all sites (`WebAdministration`
module) and read its application pool — don't assume the pool name. Set both
`processModel` properties to `true` on that pool, recycle it, and print the
pool name and the new `loadUserProfile` value. Then retest
`<base>/.well-known/openid-configuration`.

The protected-resource metadata (`/.well-known/oauth-protected-resource/mcp`)
does not touch the signing key, so it can return `200` while discovery still
fails — always test `openid-configuration` itself.

**Aside — legacy data-protection config.** A startup warning *"Please migrate
to the DataSecuritySettings configuration instead of the
"DataProtectionSettings" configuration"* means `appsettings.json` still has the
legacy block. Back up the file, replace the legacy block with the following
(keeping the same folder), and restart Indicium. This is housekeeping, not a
fix for the 500:

```json
"DataSecuritySettings": {
  "Storage": {
    "Mode": "LocalSystem",
    "LocalSystem": { "StorageLocation": "C:\\indicium-keys\\" }
  }
}
```

`appsettings.json` contains database credentials — edit it with a targeted
text insertion/removal rather than printing or round-tripping the whole file.
Updating `web.config`'s timestamp restarts the IIS application, without
admin rights when the install folder is writable for the user.
