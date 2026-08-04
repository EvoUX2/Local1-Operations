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
  |     sentinel-staging-sql -> localhost:14333
  |
  +-- runtime\local1\startup-db-authority.ps1
  |     read .env.local
  |     select SQL_CONNECTION_STRING by default
  |     block non-local SQL unless -AllowExternalDb
  |     require database SentinelStaging
  |     verify TCP reachability
  |     verify four governed Crime tables read-only
  |     print server, database, connection source, configuration source
  |
  +-- EVO Auth/API
  |
  +-- runtime\local1\launch-pi-api.cmd
  |     |
  |     +-- runtime\local1\startup-db-authority.ps1 -LaunchPiApi
  |           repeat fail-fast validation
  |           load non-database Local 1 environment
  |           set all three PI connection aliases to one authority
  |           dotnet run --no-launch-profile
  |           Portfolio Intelligence API :5038
  |
  +-- Local Gateway :8080
  +-- Sentinel Web :5173 (from C:\Allprojects\Local1\Sentinel-Web-Runtime)
  +-- SAXIO Web :4201
  +-- final HTTP health verification
```

The PowerShell Runtime Manager instruction printer and IDE launch profiles are not part of this execution chain.
