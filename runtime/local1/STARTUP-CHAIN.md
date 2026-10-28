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
  +-- resolve SAXIO Crime PI source (PR #856+ hostname mapping required)
  |     prefer LOCAL1_SAXIO_REPO, else SAXIO-Sentinel if it accepts
  |     PW9FEZ.cus.win.liquidweb.com, else a Local1 `_wt\saxio*` checkout
  |     secrets remain: SAXIO-Sentinel\runtime\local1\.env.local
  |
  +-- [optional, -UseDockerSql only]
  |     Local1-Operations\runtime\local1\Start-Local1Sql.ps1
  |       docker compose -f <resolved-SAXIO>\docker-compose.local.yml up -d
  |       sentinel-staging-sql -> localhost:14333
  |       not part of default numbered startup; Docker daemon is never checked by default
  |
  +-- <resolved-SAXIO>\runtime\local1\startup-db-authority.ps1
  |     SAXIO owns PI/database selection
  |     default: ConnectionStrings__SentinelStagingDb
  |              67.225.176.136 / SentinelStaging
  |              TLS hostname PW9FEZ.cus.win.liquidweb.com accepted (same host)
  |     -UseDockerSql: SQL_CONNECTION_STRING
  |                    localhost,14333 / SentinelStaging
  |     -AllowExternalDb is obsolete (note only; not an authority)
  |     verify TCP reachability
  |     verify governed Crime/ISCI tables read-only
  |     set SENTINEL_LOGIC_ROOT (Local1 junction or Sentinel-Logic)
  |     print server, database, HEAD SHA, SENTINEL_LOGIC_ROOT
  |
  +-- [1/5] EVO Auth/API :5000
  |     C:\Allprojects\Evo-Services\Evo-Service
  |
  +-- [2/5] PI via startup-db-authority.ps1 -LaunchPiApi
  |     -Repository <resolved-SAXIO> -EnvironmentFile <canonical .env.local>
  |     not C:\tmp\pi-runtime-5038-restoration
  |     Portfolio Intelligence API :5038
  |
  +-- [3/5] Local Gateway :8080
  +-- [4/5] Sentinel Web :5173 (from C:\Allprojects\Local1\Sentinel-Web-Runtime)
  +-- [5/5] SAXIO Web :4201
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
