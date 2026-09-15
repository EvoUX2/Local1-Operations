# Local 1 Startup Chain

```text
C:\Allprojects\Start-Local1.cmd
  |
  +-- C:\Allprojects\runtime\runtime.manifest.json
  |     topology and startup-order evidence
  |
  +-- Sentinel Web runtime worktree authority
  |     development checkout: C:\Allprojects\Sentinel Web
  |     runtime checkout:     C:\Allprojects\Local1\Sentinel-Web-Runtime
  |     runtime branch:       runtime/local1-sentinel-web
  |     upstream authority:   origin/main
  |     synchronization:      fetch + fast-forward-only + parity (ahead/behind 0 0)
  |
  +-- docker compose -f SAXIO-Sentinel\docker-compose.local.yml up -d
  |     sentinel-staging-sql -> localhost:14333 (secondary Crime PI substrate only)
  |
  +-- SAXIO-Sentinel\runtime\local1\startup-db-authority.ps1
  |     read .env.local
  |     select ConnectionStrings__SentinelStagingDb by default
  |     require 67.225.176.136 / SentinelStaging
  |     Docker localhost,14333 only when -UseDockerSql
  |     verify TCP reachability
  |     verify governed Crime/ISCI tables read-only
  |     set SENTINEL_LOGIC_ROOT (Local1 junction or Sentinel-Logic)
  |     print server, database, HEAD SHA, SENTINEL_LOGIC_ROOT
  |
  +-- EVO Auth/API
  |
  +-- SAXIO-Sentinel\runtime\local1\launch-pi-api.cmd
  |     current SAXIO-Sentinel checkout (not C:\tmp\pi-runtime-5038-restoration)
  |     |
  |     +-- SAXIO-Sentinel\runtime\local1\startup-db-authority.ps1 -LaunchPiApi
  |           repeat fail-fast validation
  |           load Local 1 environment
  |           set SENTINEL_LOGIC_ROOT
  |           set all three PI connection aliases to one authority
  |           dotnet run --no-launch-profile from current SAXIO-Sentinel
  |           Portfolio Intelligence API :5038
  |
  +-- Local Gateway :8080
  +-- Sentinel Web :5173 (from C:\Allprojects\Local1\Sentinel-Web-Runtime)
  +-- SAXIO Web :4201
  +-- final HTTP health verification
```

The PowerShell Runtime Manager instruction printer and IDE launch profiles are not part of this execution chain.
