# Local1-Operations

Local1-Operations is the cross-repository orchestration authority for the Local 1 developer runtime.

It exists so a single governed startup/stop path can provision worktrees, order services, coordinate ports and health checks, and wire environment across independently owned product repositories. It does not replace those repositories' product or runtime authority.

## What this repository owns

- Cross-repository Local 1 topology (`runtime.manifest.json`)
- Startup and stop orchestration (`Start-Local1.cmd`, `Stop-Local1.cmd`)
- Runtime worktree provisioning (Sentinel Web, Sentinel-Logic)
- Service startup ordering
- Port and health coordination
- Environment wiring between repositories

## What this repository does not own

- SAXIO database semantics
- PI data or substrate selection
- Sentinel intelligence contracts
- Product-specific runtime behavior already governed by the owning repository

## Relationship to product repositories

| Repository | Local 1 role | Authority boundary |
|---|---|---|
| **SAXIO-Sentinel** | Portfolio Intelligence API and Crime PI database authority | Owns `runtime/local1/startup-db-authority.ps1` and `runtime/local1/launch-pi-api.cmd`. Local1-Operations invokes those scripts; it does not duplicate their database-selection semantics. |
| **Sentinel-Logic** | Crime/intelligence contracts consumed by PI and Sentinel Web | Local1-Operations provisions a clean runtime worktree and junction. It does not change Logic contracts. |
| **Sentinel Web** | Crime/Sentinel UI on `:5173` | Local1-Operations provisions `Local1\Sentinel-Web-Runtime` from `origin/main`. It does not mutate the development checkout. |
| **Evo-Service** | EVO Auth/API on `:5000` | Local1-Operations starts and health-checks the host API. It does not own Evo domain/runtime semantics. |
| **Evo-Web / SAXIO Web** | SAXIO Web on `:4201` | Local1-Operations starts `npm run start:local` and health-checks the port. |
| **local-gateway** | Path router on `:8080` (`/app`, `/sentinel`) | Local1-Operations starts and health-checks the gateway. |

## Canonical Local 1 entrypoints

Operator commands at the AllProjects root are wrappers. The governed source lives in this repository.

| Action | Operator entrypoint | Source of truth |
|---|---|---|
| Start | `C:\Allprojects\Start-Local1.cmd` | `C:\Allprojects\Local1-Operations\Start-Local1.cmd` |
| Stop | `C:\Allprojects\Stop-Local1.cmd` | `C:\Allprojects\Local1-Operations\Stop-Local1.cmd` |
| Topology | (read by the launcher) | `C:\Allprojects\Local1-Operations\runtime.manifest.json` |

```bat
C:\Allprojects\Start-Local1.cmd
C:\Allprojects\Start-Local1.cmd -UseDockerSql
C:\Allprojects\Start-Local1.cmd -ValidateOnly
C:\Allprojects\Stop-Local1.cmd
```

`-UseDockerSql` is the explicit local development/test override that starts Docker SQL (`localhost,14333` / `SentinelStaging`). It is not the default Crime PI substrate.

`-AllowExternalDb` is obsolete. The normal Crime PI database is `67.225.176.136` / `SentinelStaging`, as established by merged SAXIO-Sentinel runtime authority.

`Stop-Local1.cmd` stops Local 1 application listeners (EVO, PI, gateway, Sentinel Web, SAXIO Web, Vite HMR). It does not stop Docker SQL.

## Default runtime topology

1. Sentinel Web runtime worktree (`Local1\Sentinel-Web-Runtime`)
2. Sentinel-Logic runtime worktree and junction (`Local1\Sentinel-Logic-Runtime` → `Local1\Sentinel-Logic`)
3. Optional Docker SQL, only with `-UseDockerSql`
4. SAXIO-Sentinel PI database authority, then PI API `:5038`
5. EVO Auth/API `:5000`
6. Local Gateway `:8080`
7. Sentinel Web `:5173`
8. SAXIO Web `:4201`

See `runtime/local1/STARTUP-CHAIN.md` for the executable chain.
