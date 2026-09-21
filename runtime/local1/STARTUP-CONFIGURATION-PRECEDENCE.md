# Startup Configuration Precedence

## PI database authority

Local1-Operations does not select the Crime PI database.

SAXIO-Sentinel owns PI/database substrate selection through:

- `SAXIO-Sentinel\runtime\local1\startup-db-authority.ps1`
- `SAXIO-Sentinel\runtime\local1\launch-pi-api.cmd`
- `SAXIO-Sentinel\runtime\local1\.env.local`

Local 1 startup invokes those scripts. It does not keep a parallel database-selection implementation.

Established SAXIO Local 1 behavior that orchestration must follow:

1. Default Crime PI substrate is `67.225.176.136` / `SentinelStaging`, from `ConnectionStrings__SentinelStagingDb`.
2. `-UseDockerSql` is the explicit development/test override. It uses `SQL_CONNECTION_STRING` and requires `localhost,14333` / `SentinelStaging`.
3. `-AllowExternalDb` is obsolete. The launcher accepts it only to print a note; it is not an authority and does not change the default.
4. SAXIO assigns the selected connection to `ConnectionStrings__SaxioDb`, `ConnectionStrings__SentinelStaging`, and `ConnectionStrings__SentinelStagingDb` in the PI child process.
5. `--no-launch-profile` remains intentional, preventing profile drift.
6. Command-line PI arguments set only the URL; they do not override connection strings.

## PI API provider precedence

For `WebApplication.CreateBuilder(args)`, later providers override earlier providers. This remains SAXIO runtime behavior, not a Local1-Operations rule:

1. `appsettings.json`
2. `appsettings.{Environment}.json`
3. Development user-secrets, when the project has a `UserSecretsId` (this project does not)
4. Environment variables
5. Command-line configuration
6. Later in-memory aliases added by the application, but only when an alias was absent

Environment variables use `__` in place of `:`. For example, `ConnectionStrings__SentinelStagingDb` becomes `ConnectionStrings:SentinelStagingDb`.

## Process-environment precedence

Windows supplies machine variables, then user variables, to a new process. The launching shell contributes its process variables. A launch profile may add or replace process variables only when a profile is used.

Local 1 does not load `.env.local` in the CMD launcher. SAXIO's authority script loads that file for PI launch.

## Sentinel Web runtime checkout authority

Local 1 separates Sentinel Web development and runtime checkouts:

1. Development checkout remains at `C:\Allprojects\Sentinel Web` and is not mutated by startup.
2. Runtime checkout is `C:\Allprojects\Local1\Sentinel-Web-Runtime` on branch `runtime/local1-sentinel-web`.
3. Startup fetches `origin --prune`, then enforces parity with `origin/main` using fast-forward-only synchronization.
4. Startup blocks on dirty runtime trees, ahead/diverged runtime history, missing `origin/main`, or invalid runtime worktree registration.
5. Runtime SHA values are emitted as evidence during startup output; they are no longer pinned as permanent manifest constants.

## Sentinel-Logic runtime checkout authority

Local 1 separates Sentinel-Logic development and runtime checkouts:

1. Development checkout remains at `C:\Allprojects\Sentinel-Logic` and is not mutated by startup.
2. Runtime checkout is `C:\Allprojects\Local1\Sentinel-Logic-Runtime` on branch `runtime/local1-sentinel-logic`.
3. `C:\Allprojects\Local1\Sentinel-Logic` is a junction to the runtime checkout.
4. Sentinel Web's `sentinel-logic` dependency must resolve through that governed junction.
