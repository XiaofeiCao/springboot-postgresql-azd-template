# Notes API

Java 21, Spring Boot 4.1.1, Maven 3.10.0; JDBC persistence in real PostgreSQL only.
`POST /notes` accepts `{"title":"Title","content":"Text"}` and returns 201 with a
relative `Location`; `GET /notes/{uuid}` returns a note or 404; `GET /notes` lists
notes newest first. Title is required (max 200 characters); content is required
(max 10,000 characters). Invalid input returns 400 problem details; database
failures return a sanitized 503. This minimal sample has no API authentication:
restrict ingress before exposing it publicly.

## Run locally

Set `JAVA_HOME` to a JDK 21 installation. Start a disposable PostgreSQL database
(do not use these sample credentials in production):

```powershell
docker run --rm --name notes-postgres -e POSTGRES_DB=notes -e POSTGRES_USER=notes -e POSTGRES_PASSWORD=local-only -p 5432:5432 postgres:17.6-alpine
```

In another terminal:

```powershell
$env:SPRING_PROFILES_ACTIVE = "local"
$env:POSTGRES_PASSWORD = "local-only"
.\mvnw.cmd spring-boot:run
```

The `local` profile alone uses password authentication and disables TLS.
`POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DATABASE`, `POSTGRES_USERNAME`
default to `localhost`, `5432`, `notes`, `notes`. `PORT` defaults to `8080`.
Select exactly one datasource profile (`local` or `azure`); there is no implicit
local fallback. Linux/macOS commands use `./mvnw` and exported variables.

## Azure passwordless

Set `SPRING_PROFILES_ACTIVE=azure`, `POSTGRES_HOST` to the server's full DNS name,
`POSTGRES_DATABASE`, `POSTGRES_USERNAME`, and `POSTGRES_SSL_ROOT_CERT` to a readable
PEM CA bundle. TLS is mandatory with `sslmode=verify-full` (hostname and CA
verification); supply the server's current trusted roots, not a leaf certificate.
Never weaken this to `require` or disable TLS. The app does not download trust
material at startup.
The pinned Ubuntu-based Buildpacks image includes a readable system PEM bundle at
`/etc/ssl/certs/ca-certificates.crt`; use that path for hosted deployments.
Developer machines must supply their own readable PEM path (the Linux image path
does not apply to Windows).

The released `com.azure:azure-identity-extensions:1.2.10` plugin is
`com.azure.identity.extensions.jdbc.postgresql.AzurePostgresqlAuthenticationPlugin`
(not `PSQLAuthenticationPlugin`). Its `authenticationPluginClassName` PostgreSQL
driver callback obtains a token for each new physical connection; Azure Identity
handles token caching/renewal, rather than fixing an expiring token in Hikari's
password. The dependency uses `com.azure:azure-identity:1.18.7`.

- **Developer:** leave `POSTGRES_MANAGED_IDENTITY_ENABLED=false` (default).
  The plugin uses `DefaultAzureCredential`; sign in with `az login` in the correct
  tenant, or another supported developer credential. Set `AZURE_TENANT_ID` when
  needed. `POSTGRES_USERNAME` must be the exact Entra-backed PostgreSQL role
  created for that developer (often a UPN); it is not the managed identity role.
- **Hosted:** set `POSTGRES_MANAGED_IDENTITY_ENABLED=true`. The documented
  `azure.managedIdentityEnabled` option forces `ManagedIdentityCredential`,
  avoiding accidental developer/environment fallback. Set `AZURE_CLIENT_ID`
  only for a user-assigned managed identity; leave it unset for system-assigned.
  `POSTGRES_USERNAME` is the exact PostgreSQL role mapped to that identity, not
  its client ID and not a developer UPN.

Both principals must already be mapped on the server by an Entra administrator,
have database connectivity and access, and have `USAGE`/`CREATE` on the pre-created
`notes` schema for startup initialization plus `SELECT`/`INSERT` on `notes.notes`.
The Azure JDBC `currentSchema` is `notes` by default; `POSTGRES_SCHEMA` overrides
it. The local profile uses PostgreSQL's default `public` schema. No Azure
resources or database principals are provisioned by this app. Do not set a
database password in Azure. Only public Azure PostgreSQL is configured here.
See the [official plugin contract](https://github.com/Azure/azure-sdk-for-java/blob/main/sdk/identity/azure-identity-extensions/Azure-Database-for-PostgreSQL-README.md).

## Health, tests, and image

`/actuator/health/liveness` checks process liveness; readiness at
`/actuator/health/readiness` additionally checks `db` and returns 503 when
PostgreSQL is unavailable. Only health is exposed; no connection details appear.
`schema.sql` runs on every startup with `CREATE TABLE IF NOT EXISTS` in the
connection's configured schema, preserving notes; it does not create the schema
or serve as a migration system.

```powershell
.\mvnw.cmd test                  # non-container validation/error unit tests
.\mvnw.cmd verify                # also Testcontainers PostgreSQL + real HTTP tests; Docker required
.\mvnw.cmd spring-boot:build-image -DskipTests
```

Integration tests fail (are not silently skipped) when Docker is unavailable.
Buildpacks produce `notes-api:local` with Java 21 for Linux amd64. The builder
(`paketobuildpacks/builder-jammy-base:0.4.660`) and compatible run image
(`paketobuildpacks/run-jammy-base:0.1.283`) are digest pinned in `pom.xml`.
Nothing is published. Run the image with the same runtime profile/configuration.
For Azure, use the image's system CA bundle above, or mount an alternate current
CA bundle read-only and set `POSTGRES_SSL_ROOT_CERT` to its container path.
