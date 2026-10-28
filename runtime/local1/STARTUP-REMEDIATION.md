# Startup Remediation

## Current Local 1 topology

Default Local 1 Crime PI substrate is `67.225.176.136` / `SentinelStaging`. Docker SQL (`localhost,14333`) is an explicit `-UseDockerSql` development/test override.

Local1-Operations orchestrates startup/stop. SAXIO-Sentinel owns PI/database selection.

## Orchestration repair

- `Start-Local1.cmd` launches PI through `SAXIO-Sentinel\runtime\local1\launch-pi-api.cmd`.
- Database selection is delegated to `SAXIO-Sentinel\runtime\local1\startup-db-authority.ps1`. Local1-Operations does not keep a copy of that script.
- Docker SQL credential resolution and Compose run only when `-UseDockerSql` is passed; default startup never starts Docker, checks the daemon, or numbers a Docker step.
- Start-Local1 resolves a SAXIO checkout that accepts TLS hostname `PW9FEZ.cus.win.liquidweb.com` (PR #856+) and passes `-Repository` / `-EnvironmentFile` into authority validation and PI launch.
- EVO Auth/API, Local Gateway, Sentinel Web, and SAXIO Web do not depend on Docker SQL in the default path.
- `-AllowExternalDb` is obsolete. It is accepted only to print a note.
- `Stop-Local1.cmd` is owned by this repository. It stops application listeners and leaves Docker SQL running.

## Required objects

These remain SAXIO Crime/ISCI substrate checks, not Local1-Operations schema:

- `pi.fact_incident`
- `pi.dim_property`
- `pi.dim_reporting_set`
- `pi.bridge_incident_reporting_set`
- `pi.bridge_incident_case_file`
- `pi.isci_taxonomy_node`
- `pi.isci_taxonomy_version`

## Validation

From `C:\Allprojects`:

```bat
Start-Local1.cmd
```

Default path must not start Docker SQL. Expected SAXIO preflight evidence:

```text
Server               : 67.225.176.136:1433
Database             : SentinelStaging
Connection source    : ConnectionStrings__SentinelStagingDb
Canonical target     : 67.225.176.136 / SentinelStaging
Docker SQL override  : False
```

Docker remains available as an explicit override:

```bat
Start-Local1.cmd -UseDockerSql
```

That path must require `localhost,14333` / `SentinelStaging` and must not become the default.

Sentinel Web runtime authority uses a dedicated runtime worktree and does not mutate the active development checkout branch.

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

## Final authority

```text
SAXIO-Sentinel runtime/local1
  -> default 67.225.176.136 / SentinelStaging
  -> optional -UseDockerSql localhost,14333 / SentinelStaging
  -> governed Crime substrate validation
  -> one SAXIO-selected connection assigned to SaxioDb, SentinelStaging, SentinelStagingDb
  -> PI API

Local1-Operations
  -> topology, worktrees, startup order, ports, health, stop
```
