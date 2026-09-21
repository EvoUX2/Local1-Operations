# Local 1 Startup Chain

```text
C:\Allprojects\Start-Local1.cmd
  |
  +-- C:\Allprojects\Local1-Operations\Start-Local1.cmd
  |     operator wrapper delegates here
  |
  +-- C:\Allprojects\Local1-Operations\runtime.manifest.json
  |     topology and startup-order evidence
  |
  +-- Sentinel Web runtime worktree authority
  |     development checkout: C:\Allprojects\Sentinel Web
  |     runtime checkout:     C:\Allprojects\Local1\Sentinel-Web-Runtime
  |     runtime branch:       runtime/local1-sentinel-web
  |     upstream authority:   origin/main
  |     synchronization:      fetch + fast-forward-only + parity (ahead/behind 0 0)
  |
  +-- Sentinel-Logic runtime worktree authority
  |     development checkout: C:\Allprojects\Sentinel-Logic
  |     runtime checkout:     C:\Allprojects\Local1\Sentinel-Logic-Runtime
  |     junction:             C:\Allprojects\Local1\Sentinel-Logic
  |     runtime branch:       runtime/local1-sentinel-logic
  |     upstream authority:   origin/main
  |
  +-- [optional, -UseDockerSql only]
  |     Local1-Operations\runtime\local1\Start-Local1Sql.ps1
  |       docker compose -f SAXIO-Sentinel\docker-compose.local.yml up -d
  |       sentinel-staging-sql -> localhost:14333
  |
  +-- SAXIO-Sentinel\runtime\local1\startup-db-authority.ps1
  |     SAXIO owns PI/database selection
  |     default: ConnectionStrings__SentinelStagingDb
  |              67.225.176.136 / SentinelStaging
  |     -UseDockerSql: SQL_CONNECTION_STRING
  |                    localhost,14333 / SentinelStaging
  |     -AllowExternalDb is obsolete (note only; not an authority)
  |     verify TCP reachability
  |     verify governed Crime/ISCI tables read-only
  |     set SENTINEL_LOGIC_ROOT (Local1 junction or Sentinel-Logic)
  |     print server, database, HEAD SHA, SENTINEL_LOGIC_ROOT
  |
  +-- EVO Auth/API :5000
  |     C:\Allprojects\Evo-Services\Evo-Service
  |
  +-- SAXIO-Sentinel\runtime\local1\launch-pi-api.cmd
  |     current SAXIO-Sentinel checkout (not C:\tmp\pi-runtime-5038-restoration)
  |     |
  |     +-- SAXIO-Sentinel\runtime\local1\startup-db-authority.ps1 -LaunchPiApi
  |           repeat fail-fast validation
  |           load Local 1 environment
  |           set SENTINEL_LOGIC_ROOT
  |           set all three PI connection aliases to one SAXIO-selected authority
  |           dotnet run --no-launch-profile from current SAXIO-Sentinel
  |           Portfolio Intelligence API :5038
  |
  +-- Local Gateway :8080
  +-- Sentinel Web :5173 (from C:\Allprojects\Local1\Sentinel-Web-Runtime)
  +-- SAXIO Web :4201
  +-- final HTTP health verification
```

Stop chain:

```text
C:\Allprojects\Stop-Local1.cmd
  |
  +-- C:\Allprojects\Local1-Operations\Stop-Local1.cmd
        terminate listeners on 5000, 5038, 8080, 5173, 4201, 24678
        do not stop Docker SQL (14333)
```

The PowerShell Runtime Manager instruction printer and IDE launch profiles are not part of this execution chain.
