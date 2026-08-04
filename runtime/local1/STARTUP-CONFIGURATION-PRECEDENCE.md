# Startup Configuration Precedence

## PI API provider precedence

For `WebApplication.CreateBuilder(args)`, later providers override earlier providers:

1. `appsettings.json`
2. `appsettings.{Environment}.json`
3. Development user-secrets, when the project has a `UserSecretsId` (this project does not)
4. Environment variables
5. Command-line configuration
6. Later in-memory aliases added by the application, but only when an alias was absent

Environment variables use `__` in place of `:`. For example, `ConnectionStrings__SentinelStagingDb` becomes `ConnectionStrings:SentinelStagingDb`.

## Process-environment precedence

Windows supplies machine variables, then user variables, to a new process. The launching shell contributes its process variables. A launch profile may add or replace process variables only when a profile is used.

The old Local 1 chain then loaded `.env.local` twice and assigned its values directly into each batch process. Those assignments overrode inherited machine, user, and shell values. `--no-launch-profile` excluded all `launchSettings.json` values.

## Repaired Local 1 authority

Default Local 1 startup now uses this explicit precedence:

1. `SQL_CONNECTION_STRING` in `.env.local` is the sole default PI database authority.
2. It must resolve to local host port `14333` and database `SentinelStaging`.
3. The authority script assigns that same value to `ConnectionStrings__SaxioDb`, `ConnectionStrings__SentinelStaging`, and `ConnectionStrings__SentinelStagingDb` in the PI child process.
4. These process values override JSON configuration.
5. `--no-launch-profile` remains intentional, preventing profile drift.
6. Command-line PI arguments set only the URL; they do not override connection strings.

With `-AllowExternalDb`, and only with that switch, the authority source changes to `ConnectionStrings__SentinelStagingDb` from `.env.local`. Database and required-substrate validation still apply.

## Sentinel Web runtime checkout authority

Local 1 now separates Sentinel Web development and runtime checkouts:

1. Development checkout remains at `C:\Allprojects\Sentinel Web` and is not mutated by startup.
2. Runtime checkout is `C:\Allprojects\Local1\Sentinel-Web-Runtime` on branch `runtime/local1-sentinel-web`.
3. Startup fetches `origin --prune`, then enforces parity with `origin/main` using fast-forward-only synchronization.
4. Startup blocks on dirty runtime trees, ahead/diverged runtime history, missing `origin/main`, or invalid runtime worktree registration.
5. Runtime SHA values are emitted as evidence during startup output; they are no longer pinned as permanent manifest constants.
