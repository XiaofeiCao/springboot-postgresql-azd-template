# Spring Boot + passwordless PostgreSQL prototype

A deliberately prepared Java 21/Maven Notes API, hand-authored `azure.yaml`, Bicep infrastructure, and locally installed `azure.springboot` extension. No scanning, translation, Dockerfile fallback, azd core modifications, or extension publication.

**Local status:** eight application tests pass with real PostgreSQL integration coverage. The installed extension builds a Linux/AMD64 buildpack image containing the latest `notes` schema configuration; that image passed real PostgreSQL CRUD, validation, persistence across database restart, and readiness/liveness outage checks at 0.5 CPU / 1 GiB, with approximately **201.5 MiB** observed runtime memory. All acceptance-owned local containers and the test network were removed. Fresh local-template initialization, selected-environment extension configuration, TLS bundle export, repeatability, and explicit-setting conflict rejection also passed. Bicep compilation, local SQL bootstrap/grants, and released-azd hook/image-artifact ordering passed offline. These resource/health observations are local Docker evidence, not Azure Container Apps measurements.

**Azure status (2026-10-13):** a live West US trial provisioned the declared infrastructure, verified developer Entra access to PostgreSQL, and completed database principal/schema/grant bootstrap. The trial identified and corrected the Azure CLI tenant/subscription argument conflict, missing Docker client CA trust, and Windows newline handling for token transport. Deployed application managed-identity CRUD, local application developer-authenticated CRUD, repeat deployment, and cloud cleanup are still being verified. Infrastructure creation and a successful database connection are not complete end-to-end application acceptance.

**Prototype dependency:** this repository contains the template, not the `azure.springboot` extension source or binary. Build and install extension **0.0.1** from the [prototype fork branch](https://github.com/XiaofeiCao/azure-dev/tree/xiaofeicao-spring-boot-mvp/cli/azd/extensions/azure.springboot) before initialization. It is not available from the public extension registry; cloning this template repository alone does not provide `azd springboot` commands.

## Prerequisites

- Released **azd 1.35.1**, pinned in `azure.yaml`. Use an isolated executable/configuration rather than replacing an existing installation.
- PowerShell 7 (`pwsh`) on Windows, Linux, or macOS; Azure CLI; Docker running **Linux** containers.
- Java **21** for local Maven execution; the API includes Maven Wrapper. Set `JAVA_HOME` and put its `bin` directory on `PATH`.
- `pack` on `PATH` for the extension's Cloud Native Buildpacks build (scoped tool verified: **0.40.9**). The extension pins `paketobuildpacks/builder-noble-java-tiny@sha256:b95da27fce97b58037f0c11ae934760c50730da4c9a24976205b53638592eba9`, requests Java 21, and checks the resulting image is Linux/AMD64. Use `--pack-path` for an isolated executable. No successful image build is implied by tool-version verification.
- Go matching the extension's `go.mod`, only to build the local extension.
- `psql` **17 or newer**, or Docker access to the `postgres:17` CLI image, for the SQL bootstrap. Native `psql` uses your operating-system trust store; the Docker client uses its Linux trust store.
- An approved Azure subscription/tenant, permission to deploy resources and assign the app identity's `AcrPull` role, an approved developer's **object ID in the target tenant** and PostgreSQL login name, and that developer's explicit public outbound IPv4 address.
- `configure` exports the public CA bundle from the pinned Ubuntu run image into ignored `.local/postgresql-roots.pem`, or preserves a supplied `POSTGRES_DEVELOPER_SSL_ROOT_CERT` PEM path. `run` supplies that local path as `POSTGRES_SSL_ROOT_CERT`. The deployed image uses `/etc/ssl/certs/ca-certificates.crt`; this readable bundle was verified in the buildpack image.

No account, subscription, personal identity, production token, or password is hardcoded in this template. Guest users must use their object ID in the resource tenant, the actual configured PostgreSQL administrator login name, and an Azure CLI login that can obtain tokens in that tenant.

Generated `.local/` certificate bundles are excluded by both `.gitignore` and `.azdignore`, along with azd state, tools, test evidence, and build outputs. Released azd 1.35.1 local-template initialization respects `.gitignore` and applies `.azdignore` before copying. Use `azd init -t <template>` or an exclusion-aware source copy; a raw recursive `Copy-Item` does not honor ignore files. Each initialized project regenerates its own developer bundle/configuration instead of copying another machine's absolute path.

## Local extension build/install and fresh initialization

The extension source is at `cli\azd\extensions\azure.springboot` on branch `xiaofeicao-spring-boot-mvp` of [XiaofeiCao/azure-dev](https://github.com/XiaofeiCao/azure-dev/tree/xiaofeicao-spring-boot-mvp). It is not included in this template repository or guaranteed to exist in an upstream azd checkout. The template's build/install helper creates a file-based local registry; it does **not** publish an extension.

Fetch just the prototype source:

```powershell
git clone --filter=blob:none --sparse --single-branch --branch xiaofeicao-spring-boot-mvp `
    https://github.com/XiaofeiCao/azure-dev.git springboot-extension-source
git -C springboot-extension-source sparse-checkout set cli/azd/extensions/azure.springboot
```

PowerShell example (replace the paths):

```powershell
$template = '<absolute-path-to-springboot-postgresql-template>'
$extension = '<azd-worktree>\cli\azd\extensions\azure.springboot'
$azd = '<isolated-azd-1.35.1-directory>\azd.exe'
# The release ZIP extracts azd-windows-amd64.exe. Give hooks a scoped azd.exe alias.
$extractedAzd = Join-Path (Split-Path $azd -Parent) 'azd-windows-amd64.exe'
if (-not (Test-Path -LiteralPath $azd)) {
    Copy-Item -LiteralPath $extractedAzd -Destination $azd
}
$config = Join-Path (Get-Location) '.springboot-azd-config'
& (Join-Path $template 'scripts\build-extension.ps1') `
    -ExtensionPath $extension -ConfigDir $config -AzdPath $azd

# The install helper restores the previous process configuration; opt in for this shell.
$env:AZD_CONFIG_DIR = $config
$env:AZURE_DEV_COLLECT_TELEMETRY = 'no'
$env:PATH = "$(Split-Path $azd -Parent)$([IO.Path]::PathSeparator)$env:PATH"
# The directory must expose the executable as azd.exe (azd on Unix), because hooks invoke azd.
& $azd version
& $azd springboot version

New-Item -ItemType Directory -Path 'notes-demo'
Set-Location 'notes-demo'
& $azd init --template $template . --environment notes-demo --no-prompt
```

The explicit `.` initializes the current `notes-demo` directory instead of creating a nested template-named directory. `--environment notes-demo` creates/selects the environment during initialization; no separate `azd env new` command is needed.

Use the same isolated config/executable for initialization, extension commands, and all hooks. The local source must remain available if reinstalling. The extension is required at version **0.0.1**; this is not a public registry package.

After installing the extension, you can also initialize from this GitHub repository into a new, empty project directory:

```powershell
azd init -t XiaofeiCao/springboot-postgresql-azd-template . --environment notes-demo --no-prompt
```

## Azure approval gates and explicit environment inputs

**The following commands are instructions, not evidence that they have been run.** Before logging in or incurring costs, obtain approval for the exact subscription, tenant, region, identity, resources, and estimated charges. Verify PostgreSQL `Standard_B1ms` availability, provider registration, policy restrictions, permission to create the Entra administrator, and role-assignment permissions. Do not silently substitute a larger SKU if availability or policy rejects the plan.

Sign in explicitly with Azure CLI and azd after authentication approval; use the approved tenant/subscription without changing unrelated global defaults:

```powershell
# Keep Azure CLI authentication/defaults separate from normal user configuration.
$env:AZURE_CONFIG_DIR = '<absolute-path-to-isolated-azure-cli-config>'
az login --tenant '<tenant-id>'
azd auth login --tenant-id '<tenant-id>'
azd env set AZURE_SUBSCRIPTION_ID '<subscription-id>'
azd env set AZURE_LOCATION '<approved-region>'
azd env set AZURE_TENANT_ID '<tenant-id>'
azd env set POSTGRES_ADMIN_OBJECT_ID '<approved-developer-object-id-in-target-tenant>'
azd env set POSTGRES_ADMIN_USERNAME '<approved-postgresql-admin-login>'
azd env set DEVELOPER_IPV4 '<approved-public-outbound-ipv4>'
# Optional: a separately approved second individual address, never a range.
azd env set DEVELOPER_IPV4_SECONDARY '<second-approved-public-outbound-ipv4>'
# Only after explicitly approving the cross-subscription firewall exception below:
azd env set ALLOW_AZURE_SERVICES true
# Optional: provide a developer PEM bundle instead of configure's automatic public CA export.
azd env set POSTGRES_DEVELOPER_SSL_ROOT_CERT '<absolute-path-to-trusted-ca-bundle.pem>'
```

All Bicep parameter-file values use the nested `parameters.<name>.value` structure. There are no database passwords in the parameters or outputs. `preprovision` rejects missing administrator/IP inputs and absent firewall acknowledgement; it does not infer your public IP or query personal identity.

### Explicit public-network tradeoff

The server accepts TLS connections on its public endpoint, but firewall rules are:

1. One exact approved developer IPv4 address, used for both local API execution and host-side bootstrap. An optional `DEVELOPER_IPV4_SECONDARY` creates a second individual rule only after separate approval. Neither observation guarantees PostgreSQL egress when NAT/VPN routing varies; stop on connectivity failure rather than widening the rules.
2. The special Azure-services rule `0.0.0.0`–`0.0.0.0`, gated by `ALLOW_AZURE_SERVICES=true`, needed for this public-network Container Apps design.

**The Azure-services exception is not restricted to your subscription, tenant, or Container App.** Other Azure customers' Azure-hosted clients can reach the database network endpoint; Entra authentication and SQL permissions still apply. It is not an allow-all-internet range, but it is broader than production least privilege. No `0.0.0.0`–`255.255.255.255` rule is created. Do not enable it if policy forbids this exposure. A private endpoint/delegated-subnet design and Container Apps VNet connectivity would be a separate design change, not an automatic fallback. If your developer outbound address changes, explicitly approve the replacement and rerun provision.

The Notes HTTP endpoint itself is public and has **no user authentication**. It is a demonstration API: never send sensitive data, and delete the trial promptly.

## Provision, package, and deploy

After cost approval:

```powershell
azd up
```

The explicit custom `up` workflow is **provision → deploy**. The deploy hook runs `azd package --all`; the project package hook refreshes settings with `azd springboot configure --project-dir <root>`, then invokes `azd springboot build --project-dir <root>` to build from `api` with pack, publish once to ACR, and save `SPRINGBOOT_IMAGE`. Core Java/Container Apps packaging uses **`docker.imagePassthrough: true`**, consuming the fully qualified image unchanged, rather than rebuilding it.

The service retains `language: java` but intentionally supplies `image`, not `project`: the azd YAML schema forbids declaring both for Container Apps. The extension's bounded build command explicitly uses `<root>/api`; it does not infer source from arbitrary services.

The ordering is intentional: azd 1.35.1's default `up` graph can overlap packaging and provisioning, but publishing requires the provisioned registry. Also, standalone `azd deploy` packages through service operations and does not itself invoke project `prepackage`; the explicit `predeploy` package command closes that lifecycle gap. Running an extra manual `azd package` and then `azd deploy` intentionally builds twice across those two commands; normally just run deploy.

`postprovision` first bootstraps database identity/grants, then invokes `azd springboot configure --project-dir <root>`. Hook failures stop the workflow. azd reloads environment state after each hook, so the package process observes the extension's saved image. The deploy hook finishes before deployment services resolve their image.

After deployment, `postdeploy` invokes `azd springboot apply --project-dir <root>`. That extension command explicitly applies its separately saved managed-identity Spring settings to the selected Container App using `az containerapp update --set-env-vars ... --output none`; saving azd environment values alone is not runtime configuration. `configure` must run first, and apply validates the user-assigned `AZURE_CLIENT_ID` GUID. This is an additional cloud operation during an approved deploy, not an offline test. It preserves explicit client-ID selection and TLS settings and must never persist or print access tokens. The `.springboot-template` marker bounds extension commands to this prepared sample.

Because applying settings can create/update a revision, `postdeploy` then polls the credential-free HTTPS `/actuator/health/readiness` endpoint for up to **300 seconds**, requiring status `UP`. This readiness group includes the database check. Cold starts and transient failures are retried; timeout fails the workflow rather than claiming readiness from a successful Azure CLI update. This check still does not substitute for the required deployed/local CRUD and repeatability acceptance.

Separate commands and repeated runs:

```powershell
azd provision       # Reapplies infrastructure, repeats SQL bootstrap and extension configuration.
azd deploy --all    # Automatically packages through the extension before deployment.
azd up             # Same sequential behavior on repeat; uses the previously published app image during provision.
```

Initial provision uses `mcr.microsoft.com/azuredocs/containerapps-helloworld:latest` (port 80, no API probes) only as a bootstrap placeholder. The supported **controlled-revision** files `infra/api.bicep` and `infra/api.parameters.json` are deployed by azd's Container Apps target. They consume `SERVICE_API_IMAGE_NAME`, switch ingress to port 8080, apply the extension's managed-identity Spring settings, and install the API's startup/liveness/database-backed readiness probes. Merely changing the placeholder's image would leave its port wrong; these revision files must not be removed.

### Runtime/output contract

| Output/settings | Consumer |
| --- | --- |
| `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DATABASE` | Extension configuration, local application, SQL bootstrap |
| `POSTGRES_USERNAME` | Approved developer's PostgreSQL Entra login; **local only** |
| `POSTGRES_MANAGED_IDENTITY_USERNAME`, `POSTGRES_MANAGED_IDENTITY_OBJECT_ID` | App SQL role name/service-principal object ID; bootstrap uses the **object ID**, not the client ID |
| `POSTGRES_ADMIN_OBJECT_ID` | Approved developer administrator object ID |
| `AZURE_CLIENT_ID` | Explicit user-assigned identity selection in the deployed JDBC plugin |
| `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID` | Explicit authentication target; bootstrap Azure CLI token request |
| `AZURE_CONTAINER_REGISTRY_ENDPOINT`, `AZURE_CONTAINER_REGISTRY_NAME` | Extension image publication |
| `AZURE_CONTAINER_APP_NAME`, `AZURE_RESOURCE_GROUP` | azd resource targeting and scoped cleanup |
| `SPRINGBOOT_IMAGE` | Extension-produced fully qualified remote image; azd image passthrough |
| `SPRINGBOOT_DEPLOYED_SPRING_DATASOURCE_URL`, `SPRINGBOOT_DEPLOYED_SPRING_DATASOURCE_USERNAME`, `SPRINGBOOT_DEPLOYED_SPRING_PROFILES_ACTIVE` | Extension-generated **deployed** Spring settings, read by `infra/api.parameters.json` |
| `SERVICE_API_ENDPOINT_URL` | Deployed endpoint |

Deployed Bicep additionally sets `POSTGRES_MANAGED_IDENTITY_ENABLED=true`, the app identity's `POSTGRES_USERNAME`, `AZURE_CLIENT_ID`, the tenant, and `POSTGRES_SSL_ROOT_CERT=/etc/ssl/certs/ca-certificates.crt`. Local runs must keep managed identity disabled and use the developer username instead. Java uses the passwordless JDBC authentication plugin with `sslmode=verify-full`, validating hostname and CA trust; the plugin acquires fresh Entra tokens as connections are created. No bearer token is saved as a Spring datasource password.

### Database bootstrap

`scripts/bootstrap-database.ps1` obtains a PostgreSQL token using:

```text
az account get-access-token --resource https://ossrdbms-aad.database.windows.net
```

It selects the subscription explicitly, first verifies that its tenant matches `AZURE_TENANT_ID`, and authenticates as the approved developer administrator. Azure CLI rejects supplying both `--tenant` and `--subscription` to `get-access-token`; the verified subscription selects the token tenant. Native `psql` receives the token only in its child-process environment. The Docker fallback passes it through stdin to a shell that exports it **inside the running process**; it is never put in Docker arguments, Docker container configuration, mounted files, azd state, or terminal output. Do not run credential-bearing operations under PowerShell tracing/transcription or external process-environment capture. Client output is deliberately withheld on failure.

1. Connect to the **`postgres`** database, as required by the Azure extension, and call `pg_catalog.pgaadauth_create_principal_with_oid(role, objectId, 'service', false, false)`.
2. On repeat, validate that the existing role still maps to the expected non-admin service identity; refuse mismatches instead of silently remapping them.
3. Connect to the **`notes`** database; create the `notes` schema, grant connection/schema/table/sequence/default privileges, and set the app/developer role search path.
4. Grant the app role to the developer so local execution can read/write tables created by the app identity. This is a deliberately shared demonstration database, not independent per-user isolation.

Azure RBAC `AcrPull` does **not** grant database access. Bootstrap is required even when role assignments succeeded. The app initializes its idempotent Notes table inside the granted schema.

Bootstrap uses `verify-full`, with a 20-second connection timeout. Native `psql` uses its system trust store (`PGSSLROOTCERT=system`). The Docker `postgres:17` client may not include a system CA bundle; bootstrap prepares the extension's public `POSTGRES_DEVELOPER_SSL_ROOT_CERT` bundle if needed and mounts it read-only into the client. Token transport uses an explicit Unix newline so Windows CRLF does not corrupt the Linux client's token. Bootstrap never disables certificate or hostname verification. If bootstrap fails, check approved public IP, target tenant/login, the administrator mapping, CA trust, and an existing role mismatch. After correcting the cause, run `azd provision` or rerun the bootstrap followed by `azd springboot configure`.

## Run locally against Azure PostgreSQL

After approved provision/bootstrap, log in as the approved developer in the isolated Azure CLI context and run:

```powershell
azd springboot configure --project-dir (Get-Location).Path
azd springboot run --project-dir (Get-Location).Path
```

`configure` saves `POSTGRES_DEVELOPER_SSL_ROOT_CERT`, exporting a public bundle if none is supplied. `run` injects it as `POSTGRES_SSL_ROOT_CERT` together with the provisioned database outputs, schema `notes`, developer username, and `POSTGRES_MANAGED_IDENTITY_ENABLED=false`; it filters deployed identity credentials. A Windows certificate-store directory is not a PEM bundle. Keep local developer and deployed managed-identity settings separate.

The API offers `POST /notes`, `GET /notes/{id}`, `GET /notes`, and `/actuator/health/readiness`. After deployment, test both the deployed and local applications against the **same Azure database**:

```powershell
$values = azd env get-values --output json | ConvertFrom-Json
$endpoint = $values.SERVICE_API_ENDPOINT_URL
$note = Invoke-RestMethod "$endpoint/notes" -Method Post -ContentType 'application/json' `
    -Body '{"title":"Azure prototype","content":"Managed identity persisted this note."}'
Invoke-RestMethod "$endpoint/notes/$($note.id)"
Invoke-RestMethod "$endpoint/notes"
Invoke-RestMethod "$endpoint/actuator/health/readiness"
# With local Maven still running:
Invoke-RestMethod "http://localhost:8080/notes/$($note.id)"
```

Cold starts are expected with zero minimum replicas. A readiness response must include the database check; do not count an HTTP response from the bootstrap image as success.

## Offline validation

No cloud commands are needed:

```powershell
.\scripts\test-infrastructure.ps1 -BicepPath '<path-to-bicep-executable>'
.\scripts\test-lifecycle.ps1 -AzdPath '<released-azd-1.35.1-executable>' `
    -EvidenceDir '<new-directory-for-non-secret-lifecycle-evidence>'
.\scripts\test-readiness.ps1
.\scripts\test-bootstrap-auth.ps1
# See api/README.md for real PostgreSQL application integration tests.
```

The infrastructure test compiles both Bicep entry points, parses PowerShell and parameter JSON, starts one isolated local `postgres:17` container (no published ports), and verifies principal creation/repeatability, grants, app/developer CRUD privileges, and identity mismatch rejection. Azure-only `pgaadauth` functions are **local shims** for these tests: this does not prove live Entra mapping. The named test container is removed in `finally`; the pulled image remains cached.

The lifecycle test runs the **actual released azd 1.35.1** executable with an isolated config and a Java/Container Apps image-passthrough fixture. The first project `prepackage` hook sees an old sentinel image and changes its saved environment value. A second project hook, the service `prepackage` hook, and project `postpackage` hook all observe the replacement; `package.json` must contain only the replacement remote artifact. `trace.jsonl` records that exact order. This verifies hook ordering and parent-process environment refresh before image consumption. The `registry.invalid` references are deliberate **nonexistent sentinel images**, not a successful extension-produced image: no images are built/pulled/pushed and no cloud API is called. Actual buildpack-image/extension acceptance remains separate.

The readiness test mocks Azure CLI and HTTP to verify apply-before-readiness ordering, `UP` success, retry on `DOWN`, timeout failure, and credential-bearing/unsafe endpoint rejection without disclosure. It is not evidence of live application health.

## Costs and cleanup

Declared trial resources:

- PostgreSQL Flexible Server **Burstable Standard_B1ms**, PostgreSQL 16, **32 GiB** Premium storage, storage autogrow disabled, **7-day** local backup retention, no HA, no replicas.
- ACR **Basic**, admin authentication disabled.
- Container Apps **Consumption**, **0 minimum / 1 maximum replica**, **0.5 vCPU / 1 GiB** memory. The installed-extension image passed local startup/CRUD/outage acceptance at this CPU/memory limit, with approximately 201.5 MiB observed runtime memory. Azure startup, token acquisition, and live readiness remain unverified.
- One app user-assigned identity with registry-scoped `AcrPull`.
- One Log Analytics workspace (30-day retention, a 0.1 GiB/day ingestion cap). The cap is **not an enforceable total spending limit**; database, storage, backup, registry, network, and logging can still incur charges while the app is scaled to zero.

Recheck current region/SKU/backup/logging prices before any trial. The 2026-10-13 West US retail-price check estimated about US$2.44 for a continuous 24-hour trial before additional backup/storage, requests, egress, and tax, without free allowances. This is not a billing cap or a guarantee of current prices.

Cleanup only the selected, trial-owned azd environment after reviewing its subscription/resource group:

```powershell
azd env get-values --output json
azd down
```

Do not delete unrelated groups or identities. After any failed or successful cloud trial, inventory the selected resource group and environment's retained resources/backups before claiming cleanup. Keep the extension installation/config directory until no longer needed; restore the previous `AZD_CONFIG_DIR`, `AZURE_CONFIG_DIR`, `PATH`, and telemetry settings instead of altering normal user configuration. Do not delete broad directories or shared Docker images/volumes.

## Verified source contracts

- [Released azd 1.35.1 up workflow](https://github.com/Azure/azure-dev/blob/azure-dev-cli_1.35.1/cli/azd/cmd/up.go): custom sequential workflow support; default graph can overlap package/provision.
- [Released hook runner](https://github.com/Azure/azure-dev/blob/azure-dev-cli_1.35.1/cli/azd/pkg/ext/hooks_runner.go): environment reload before/after hooks.
- [Released image passthrough](https://github.com/Azure/azure-dev/blob/azure-dev-cli_1.35.1/cli/azd/pkg/project/container_helper.go): resolves `service.image` from the reloaded environment and bypasses core image build.
- [Released Container Apps deploy target](https://github.com/Azure/azure-dev/blob/azure-dev-cli_1.35.1/cli/azd/pkg/project/service_target_containerapp.go): `infra/api.bicep` plus parameters invokes controlled-revision deployment.
- [PostgreSQL ARM schema](https://learn.microsoft.com/azure/templates/microsoft.dbforpostgresql/2024-08-01/flexibleservers), [administrator schema](https://learn.microsoft.com/azure/templates/microsoft.dbforpostgresql/2024-08-01/flexibleservers/administrators), and [Entra SQL principal mapping](https://learn.microsoft.com/azure/postgresql/security/security-manage-entra-users).

These contracts and local tests are not substitutes for approved live deployment, repeatability, real developer/managed-identity reads/writes, and verified cleanup.
