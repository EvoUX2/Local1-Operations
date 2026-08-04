# Startup Remediation

## Repair

- Added one startup database authority script shared by preflight and PI launch.
- Removed database selection from ad hoc batch-file aliasing.
- Made `SQL_CONNECTION_STRING` the deterministic default Local 1 database source.
- Bound all PI database aliases to the same validated authority.
- Added explicit non-local protection with the sole override `-AllowExternalDb`.
- Added TCP reachability and read-only governed-substrate checks before PI launch.
- Added safe effective-connection output without credentials.
- Preserved `--no-launch-profile` so IDE profiles cannot silently alter Local 1.

## Required objects

- `pi.fact_incident`
- `pi.dim_property`
- `pi.dim_reporting_set`
- `pi.bridge_incident_reporting_set`

## Validation

From `C:\Allprojects`:

```bat
Start-Local1.cmd
```

Sentinel Web runtime authority now uses a dedicated runtime worktree and does not mutate the active development checkout branch.

Runtime contract:

- Development checkout: `C:\Allprojects\Sentinel Web`
- Runtime checkout: `C:\Allprojects\Local1\Sentinel-Web-Runtime`
- Runtime branch: `runtime/local1-sentinel-web`
- Upstream authority: `origin/main`
- Sync policy: `fetch origin --prune` + `merge --ff-only origin/main`
- Required parity: `rev-list --left-right --count "origin/main...HEAD"` equals `0 0`

Inspection commands:

```bat
git -C "C:\Allprojects\Sentinel Web" worktree list --porcelain
git -C "C:\Allprojects\Local1\Sentinel-Web-Runtime" status --short --branch
git -C "C:\Allprojects\Local1\Sentinel-Web-Runtime" rev-list --left-right --count "origin/main...HEAD"
```

Remediation rules:

- Missing runtime worktree: re-run `Start-Local1.cmd` to provision idempotently.
- Dirty runtime worktree: preserve/disposition changes; launcher fails closed.
- Runtime ahead or diverged: reconcile under an authorized work unit; launcher does not reset, rebase, or force-update.
- Missing `origin/main`: restore remote branch visibility; launcher fails closed.
- WU-001B evidence worktrees are never startup targets and must remain untouched.

The runtime SHA is recorded in startup output as evidence, but no permanent exact-SHA pinning is required for moving `origin/main` authority.

Expected preflight evidence:

```text
Server               : localhost:14333
Database             : SentinelStaging
Connection source    : SQL_CONNECTION_STRING
Configuration source : C:\Allprojects\SAXIO-Sentinel\runtime\local1\.env.local
Crime substrate      : VALID
```

External startup requires an explicit operator decision:

```bat
Start-Local1.cmd -AllowExternalDb
```

The external target must still be reachable, use database `SentinelStaging`, and contain all required governed tables. Otherwise startup fails before PI is launched.

## Final authority

```text
Local SQL
  -> localhost:14333
  -> SentinelStaging
  -> governed Crime substrate validation
  -> one connection assigned to SaxioDb, SentinelStaging, SentinelStagingDb
  -> PI API
```
