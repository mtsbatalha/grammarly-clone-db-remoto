# Grammarly Clone - Fresh Install Scripts

## Quick Start

### Linux/Mac
```bash
# Interactive mode (asks for confirmation)
bash scripts/linux/setup.sh

# Automated mode (no confirmation)
bash scripts/linux/setup.sh --yes
```

### Windows
```powershell
# Interactive mode
.\scripts\windows\setup.ps1

# Automated mode  
.\scripts\windows\setup.ps1 -AutoConfirm
```

## What It Does

The setup script performs a **complete fresh installation**:

1. ✅ Stops and removes all containers
2. ✅ Deletes all Docker volumes (⚠️ **DATABASE WILL BE LOST**)
3. ✅ Removes any problematic `.env` files
4. ✅ Rebuilds all containers from scratch
5. ✅ Waits for PostgreSQL to be ready
6. ✅ Runs Prisma database migrations
7. ✅ Verifies all services are healthy
8. ✅ Shows service status and access URLs

## When to Use

Use this script when you need to:
- 🆕 **First-time setup** on a new server
- 🔄 **Reset everything** to factory defaults
- 🐛 **Fix persistent issues** that regular restart can't solve
- 🧪 **Test deployment** from clean slate

## Post-Installation

After installation completes:

1. Open **http://localhost:5173** in your browser
2. **Register** a new user account
3. Start using Grammarly Clone!

## Troubleshooting

If setup fails:

```bash
# Check container status
docker ps -a

# View API logs
docker logs grammarly_remotedb_api

# View PostgreSQL logs (Remote DB)
# Check Neon dashboard

# Check detailed status
bash scripts/linux/status.sh --detailed
```

## Important Notes

> [!CAUTION]
> This script **DELETES ALL DATA**! Use `scripts/linux/backup.sh` (Linux) or `scripts/windows/backup.ps1` (Windows) first if you need to preserve data.

> [!TIP]
> For regular restarts without data loss, use `scripts/linux/restart-containers.sh` or `scripts/windows/restart-containers.ps1` instead.
