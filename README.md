# Hermes Agent Backup to VPS

A practical, zero-dependency guide to backing up your [Hermes Agent](https://github.com/NousResearch/hermes-agent) data to any Linux VPS using rsync over SSH.

## Why This Approach?

Hermes Agent stores valuable persistent data in `~/.hermes/` — skills, memory (Mnemosyne), conversation history, environment variables, and auth tokens. Losing this data means losing months of agent learning and customization.

Most backup tutorials suggest tarball archives or cloud storage. This guide uses a different approach:

- **rsync mirror** — your backup is a browsable directory, not a blob
- **Incremental** — only changed files are transferred each run
- **No cloud dependency** — your data stays on servers you control
- **Full-fidelity** — includes all files including secrets (API keys never leave your network)
- **Works for multiple Hermes instances** — one VPS can host backups for several agents

## How It Works

```
Your Hermes Server                    Backup VPS
┌──────────────────┐                ┌─────────────────────────┐
│ ~/.hermes/       │   rsync over   │ /root/backups/          │
│   ├── config.yaml│ ─── SSH ────▶  │   backup-hermes/        │
│   ├── skills/    │                │   └── <server-name>/    │
│   ├── state.db   │                │       ├── config.yaml   │
│   ├── mnemosyne/ │                │       ├── skills/       │
│   ├── cron/      │                │       ├── sessions/     │
│   └── .env       │                │       ├── cron/         │
│                  │                │       └── ...           │
│ /usr/local/lib/  │                │                          │
│   hermes-agent/  │                │                          │
└──────────────────┘                └─────────────────────────┘
```

## Prerequisites

- A Hermes Agent installation (any server)
- A Linux VPS reachable via SSH (any provider — DigitalOcean, Linode, Hetzner, Oracle Cloud, etc.)
- SSH key-based authentication between the two (set up in Step 1)

## Step-by-Step Setup

### 1. Prepare Your VPS

> **Step 1a — On your Hermes server:** Generate an SSH key if you do not have one:

```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

Copy the output (your public key).

> **Step 1b — On your backup VPS:** Add the public key to authorized keys:

```bash
echo "<paste the public key here>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

> **Step 1c — Back on your Hermes server:** Test the connection:

```bash
ssh -o StrictHostKeyChecking=accept-new root@<your-vps-ip> "hostname"
```

You should see the VPS hostname printed back.

### 2. Create the Backup Script

Save the backup script on your Hermes server:

```bash
mkdir -p ~/.hermes/scripts
curl -o ~/.hermes/scripts/hermes-backup.sh \
  https://raw.githubusercontent.com/MrElixir67/how-to-backup-hermes-on-your-vps/main/hermes-backup.sh
chmod +x ~/.hermes/scripts/hermes-backup.sh
```

*Alternatively, copy the script from the `hermes-backup.sh` file in this repository.*

### 3. Configure the Backup Target

Create a config file so the script knows where to send backups:

```bash
cat > ~/.hermes/scripts/backup-target.conf << 'EOF'
BACKUP_IP=<your-vps-ip>
BACKUP_USER=root
BACKUP_FOLDER=<your-server-name>
EOF
```

Replace `<your-vps-ip>` with your VPS IP address and `<your-server-name>` with a name that identifies this Hermes instance (e.g., `production`, `staging`, or your server's hostname).

### 4. Run a Test Backup

```bash
bash ~/.hermes/scripts/hermes-backup.sh
```

Expected output:

```
======= HERMES BACKUP =======
Folder:    production
Date:      2026-06-18_12-30-00
Target:    root@203.0.113.10:/root/backups/backup-hermes/production

[1/5] Backing up config & state...
  [OK] config.yaml
  [OK] skills/
  [OK] state.db
  [OK] .env
  [OK] auth.json
  [OK] cron/
  [OK] mnemosyne/

[2/5] Backing up Hermes source code...
  [OK] hermes-src/

[3/5] Creating local archive...
  [OK] ~/.hermes/backups/hermes-backup-production-YYYY-MM-DD_HH-MM-SS.tar.gz

[4/5] Cleaning old local archives...
  [OK] kept last 7

[5/5] Verification...
  [OK] remote backup accessible
  Remote size: 156M

Done in 6 seconds
```

Verify the backup on your VPS:

```bash
ssh root@<your-vps-ip> "ls -la /root/backups/backup-hermes/<your-server-name>/"
```

Expected output:

```
/root/backups/backup-hermes/production/
├── config.yaml
├── .env
├── auth.json
├── state.db
├── skills/
├── sessions/
├── cron/
├── mnemosyne/
├── hermes-src/
└── latest-archive.tar.gz
```

### 5. Schedule Automatic Backups

Using the Hermes cron scheduler (recommended):

```bash
hermes cron create \
  --name hermes-backup \
  --schedule "0 3 * * *" \
  --script hermes-backup.sh \
  --no-agent
```

Or using system cron:

```bash
(crontab -l 2>/dev/null | grep -v "hermes-backup"; \
 echo "0 3 * * * cd ~/.hermes/scripts && bash hermes-backup.sh") | crontab -
```

This runs the backup daily at 3 AM server time.

## What Gets Backed Up

| Path | Description |
|------|-------------|
| `~/.hermes/config.yaml` | Provider settings, tools, integrations |
| `~/.hermes/.env` | API keys and secrets |
| `~/.hermes/auth.json` | OAuth tokens |
| `~/.hermes/state.db` | Session database (conversation history) |
| `~/.hermes/skills/` | All custom skills and workflows |
| `~/.hermes/cron/` | Cron job definitions |
| `~/.hermes/mnemosyne/` | Persistent memory database |
| `/usr/local/lib/hermes-agent/` | Hermes source code (for full recovery) |

Excluded from source code backup: `.git`, `node_modules`, `venv`, `.venv`, `__pycache__`, `*.pyc`.

## Restore Guide

### Prerequisites

Download the restore script to your Hermes server:

```bash
curl -o ~/.hermes/scripts/hermes-restore.sh \
  https://raw.githubusercontent.com/MrElixir67/how-to-backup-hermes-on-your-vps/main/hermes-restore.sh
chmod +x ~/.hermes/scripts/hermes-restore.sh
```

### Restore from VPS Backup

```bash
bash ~/.hermes/scripts/hermes-restore.sh
```

You will be prompted to:
1. Select which backup folder to restore from (if multiple servers back up to the same VPS)
2. Enter the target server IP (for push-mode restore to a new server)
3. Confirm by typing `RESTORE`

What the restore does:
1. Backs up the current state to `~/.hermes.bak.<timestamp>`
2. Stops the Hermes gateway
3. Rsyncs everything from the VPS backup back to the Hermes server
4. Fixes permissions (600 for secrets)
5. Restarts the Hermes gateway

### Manual Restore

You can also browse your backup directly on the VPS via SCP, SFTP, or File Browser to selectively restore individual files:

```bash
# Restore a single skill
scp root@<vps-ip>:/root/backups/backup-hermes/<folder>/skills/my-skill.md ~/.hermes/skills/

# Restore everything
rsync -a root@<vps-ip>:/root/backups/backup-hermes/<folder>/ ~/.hermes/
```

## Multiple Hermes, One VPS

When multiple Hermes instances back up to the same VPS, each creates its own folder:

```
/root/backups/backup-hermes/
├── production/  # Main production Hermes
├── staging/     # Test environment
└── dev/         # Development machine
```

To add another Hermes instance:

1. Generate an SSH key on the new server
2. Add its public key to the VPS authorized_keys
3. Create `backup-target.conf` with a unique `BACKUP_FOLDER`
4. Deploy the same backup script (one universal script for all servers)

```bash
# On the new server
mkdir -p ~/.hermes/scripts
cat > ~/.hermes/scripts/backup-target.conf << 'EOF'
BACKUP_IP=<your-vps-ip>
BACKUP_USER=root
BACKUP_FOLDER=new-server-name
EOF
curl -o ~/.hermes/scripts/hermes-backup.sh \
  https://raw.githubusercontent.com/MrElixir67/how-to-backup-hermes-on-your-vps/main/hermes-backup.sh
chmod +x ~/.hermes/scripts/hermes-backup.sh
```

## Security Note

This backup includes sensitive data: API keys (`.env`), OAuth tokens (`auth.json`), and session history (`state.db`). Treat your backup VPS with the same security standards as your Hermes server:

- Use **SSH key authentication only** — never password-based auth for automated backups
- Restrict SSH access to specific IPs where possible
- Consider encrypting the backup folder with a tool like `gpg` or `age` for an extra layer of protection
- Regularly audit what is stored in the backup if you rotate API keys

## Best Practices

- **Set a descriptive `BACKUP_FOLDER`** — do not rely on the `hostname` default, especially when backing up multiple servers
- **Test your restore** — verify at least once that the restore procedure actually works before you need it
- **Keep the script updated** — the backup script is meant to be universal; improvements apply to all your Hermes instances
- **Monitor backup health** — regularly check that cron runs by verifying files on the VPS
- **Use SSH key auth** — never use password-based SSH for automated backups

## Files

| File | Purpose |
|------|---------|
| `README.md` | This guide |
| `hermes-backup.sh` | Universal backup script |
| `hermes-restore.sh` | Restore script with multi-backup selector |
| `LICENSE` | GNU General Public License v3.0 |

## License

GNU GPLv3
