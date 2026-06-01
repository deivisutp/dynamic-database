#  Architecture Overview

## Automatic Migration System

### Design Pattern: Docker Exec Sidecar

```
┌─────────────────────────────────────────────────────────────┐
│                    Docker Compose                           │
│                                                             │
│  ┌──────────────────────────┐                              │
│  │ oracle-database-baseline │                              │
│  │  (gvenzl/oracle-xe)      │                              │
│  │                          │                              │
│  │  ┌──────────────────┐    │                              │
│  │  │  Oracle XE 21c   │    │                              │
│  │  │ - CDB: XE        │    │                              │
│  │  │ - PDB: XEPDB1    │    │                              │
│  │  │ - User: my_user  │                              │
│  │  └──────────────────┘    │                              │
│  │                          │                              │
│  │  Mounted volumes:        │                              │
│  │  ./migrations ->         │                              │
│  │    /opt/oracle/scripts/  │                              │
│  │    setup/                │                              │
│  └──────────────────────────┘                              │
│            ▲                                                │
│            │                                                │
│            │ docker exec                                    │
│            │ (runs sqlplus inside DB container)            │
│            │                                                │
│  ┌──────────────────────────┐                              │
│  │  migration-runner        │                              │
│  │  (alpine:latest)         │                              │
│  │                          │                              │
│  │  1. Wait for DB healthy  │                              │
│  │  2. Install docker CLI   │                              │
│  │  3. Sleep 10 seconds     │                              │
│  │  4. docker exec into DB  │                              │
│  │  5. Run all .sql files   │                              │
│  │  6. Verify table count   │                              │
│  │  7. Exit (success/fail)  │                              │
│  │                          │                              │
│  │  Mounted:                │                              │
│  │  /var/run/docker.sock    │ ◄─── Access to Docker daemon │
│  └──────────────────────────┘                              │                   
└─────────────────────────────────────────────────────────────┘
```
## Component Breakdown

### 1. Oracle Database Container (`database_baseline_db`)

**Image:** `gvenzl/oracle-xe:21-slim`

**What it does:**
- Starts Oracle XE 21c
- Creates pluggable database XEPDB1
- Creates user `my_user` with password `abacate123`
- Exposes port 1521

**Mounted volumes:**
- `./migrations` → `/opt/oracle/scripts/setup/` (migration SQL files)
- `database_baseline_data` → `/opt/oracle/oradata` (persistent database)

**Healthcheck:** Ensures database is ready before migration-runner starts

### 2. Migration Runner Container (`database_migration_runner`)

**Image:** `alpine:latest` (5MB)

**What it does:**
```bash
1. Install docker CLI (apk add docker-cli)
2. Wait 10 seconds for DB to stabilize
3. Execute: docker exec database_baseline_db bash -c '...'
   - This runs a bash script INSIDE the database container
   - Uses sqlplus (already installed in DB container)
   - Loops through all *.sql files in /opt/oracle/scripts/setup/
   - Executes each with: sqlplus my_user/abacate123@XEPDB1 @script.sql
4. Verify table count
5. Exit with code 0 (success) or 1 (failure)
```

**Why Alpine?**
- Tiny (5MB vs 2GB for Oracle image)
- Has `sh` for scripting
- Can install docker-cli via `apk`
- No database overhead

**Why Docker Socket?**
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```
This allows the Alpine container to run `docker exec` commands to access other containers.

## Execution Flow

### Timeline

```
T=0s    docker-compose up -d
        ├─ Start oracle-database-baseline
        └─ migration-runner waits (depends_on: service_healthy)

T=30s   Database: Uncompressing files...

T=60s   Database: Starting Oracle instance...

T=120s  Database: XEPDB1 pluggable database ready
        Database: Creating user 'my_user'
        Database: Healthcheck passes ✓

T=121s  migration-runner starts
        ├─ Install docker-cli (10s)
        └─ Sleep 10s

T=141s  migration-runner: docker exec database_baseline_db bash -c '...'
        ├─ cd /opt/oracle/scripts/setup
        ├─ for script in *.sql; do
        │    sqlplus -s my_user/abacate123@XEPDB1 @$script
        │  done

T=142s  001_create_schema.sql (5s)
T=147s  002_create_tables.sql (2-4 min)
T=387s  003_primary_keys.sql (1-2 min)
T=507s  004_foreign_keys.sql (2-3 min)
T=687s  005_indexes.sql (2-3 min)
T=700s  006_seed_data.sql (2-3 min)
T=867s  Verification: SELECT COUNT(*) = 1044 ✓
T=870s  migration-runner exits (code 0)

Total: ~5-10 minutes
```

### Container States

```bash
# Before migration starts
$ docker ps
database_baseline_db    Up 2 minutes (healthy)
database_migration_runner    Up 5 seconds

# During migration
$ docker ps
database_baseline_db    Up 5 minutes (healthy)
database_migration_runner    Up 3 minutes

# After migration complete
$ docker ps
database_baseline_db    Up 15 minutes (healthy)

$ docker ps -a
database_baseline_db         Up 15 minutes (healthy)
database_migration_runner    Exited (0) 1 minute ago
```

## Network Architecture

```
┌─────────────────────────────────────┐
│      database_network (bridge)      │
│                                     │
│  oracle-database-baseline:1521      │
│  ↓                                  │
│  Host: oracle-database-baseline     │
│  Service: XEPDB1                    │
│  User: my_user/abacate123           │
│                                     │
│  ← Connected via docker exec        │
│    (not network connection!)        │
└─────────────────────────────────────┘
```

**Important:** The migration-runner doesn't connect via network! It uses `docker exec` which runs commands directly inside the database container's namespace.

## File Structure

```
emr-dynamic-database-database/
├── docker-compose.yml         # Defines all services
├── migrations/
│   ├── 001_create_schema.sql  # Schema setup
│   ├── 002_create_tables.sql  # 1,044 tables
│   ├── 003_primary_keys.sql   # PK constraints
│   ├── 004_foreign_keys.sql   # FK constraints
│   └── 005_indexes.sql        # Indexes
|   └── 006_seed_data.sql      # Data
└── scripts/
    └── (legacy scripts, not used by automatic runner)
```

## Security Considerations

### Docker Socket Access

```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro  # Read-only!
```

**Risk:** Containers with docker socket access can control the host's Docker daemon.

**Mitigation:**
- Mounted as `:ro` (read-only)
- Only used for `docker exec` (not docker run/rm)
- Container exits immediately after migration
- No persistent risk (container doesn't stay running)

### Database Credentials

Currently hardcoded in `docker-compose.yml`:
```yaml
- ORACLE_USER=my_user
- ORACLE_PASSWORD=abacate123
```

**For production:** Use Docker secrets or environment variables:
```bash
export DB_PASSWORD=<secure-password>
docker-compose up -d
```

## Advantages of This Design

✅ **Single Database:** Only one Oracle instance (4GB RAM)  
✅ **Small Overhead:** Alpine is 5MB vs 2GB Oracle image  
✅ **Direct Execution:** Uses sqlplus inside DB container (no network latency)  
✅ **Clean Logs:** Separate container for migration logs  
✅ **Automatic:** Runs on `docker-compose up -d`  
✅ **Idempotent:** Safe to restart (migrations only run on fresh DB)  
✅ **Verifiable:** Exit code 0 = success, 1 = failure  

## Troubleshooting Reference

### Migration Runner Shows Second Database Starting

**Symptom:** Logs show "CONTAINER: starting up Oracle Database..."

**Cause:** Using Oracle image instead of Alpine

**Fix:** Check docker-compose.yml:
```yaml
migration-runner:
  image: alpine:latest  # ✓ Correct
  # NOT: gvenzl/oracle-xe:21-slim  # ✗ Wrong
```

### Permission Denied on Docker Socket

**Symptom:** "Cannot connect to Docker daemon"

**Fix:** Ensure volume is mounted:
```yaml
volumes:
  - /var/run/docker.sock:/var/run/docker.sock:ro
```

On Linux, may need to add user to docker group or run as root.

### Migrations Not Executing

**Symptom:** Container exits immediately without running migrations

**Fix:** Check that DB is healthy:
```bash
docker inspect database_baseline_db | grep -i health
```

Ensure depends_on is configured:
```yaml
depends_on:
  oracle-database-baseline:
    condition: service_healthy
```

## Future Enhancements

### Option 1: External Migration Tool Container

Use a dedicated Oracle client image:
```yaml
migration-runner:
  image: gvenzl/oracle-sqlcl  # SQL*Plus client only
  # No database overhead
```

### Option 2: Init Container Pattern

Run migrations as an init container that blocks database startup:
```yaml
oracle-database-baseline:
  depends_on:
    migration-preparer:
      condition: service_completed_successfully
```

### Option 3: Kubernetes Job

For Kubernetes deployments:
```yaml
kind: Job
metadata:
  name: db-migration
spec:
  template:
    spec:
      containers:
      - name: migrate
        image: migration-runner:v1
        command: ["./run_migrations.sh"]
      restartPolicy: OnFailure
```
