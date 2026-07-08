# Hermes Agent Backup to VPS

A practical, zero-dependency guide to backing up your [Hermes Agent](https://github.com/NousResearch/hermes-agent) data to any Linux VPS using SSH.

Works on **Windows** (git-bash/MSYS) and **Linux**.

## Why This Approach?

Hermes Agent stores valuable persistent data — skills, memory, conversation history, config, and auth tokens. Losing this data means losing months of agent learning and customization.

- **No cloud dependency** — your data stays on servers you control
- **Browsable backup** — restore individual files without extracting archives
- **Universal** — same script works on Windows and Linux
- **Full-fidelity** — includes secrets (API keys never leave your network)
- **Works for multiple Hermes instances** — one VPS can host backups for several agents

## How It Works

```
Your Hermes Server (Windows/Linux)             Backup VPS
┌──────────────────────────┐                ┌────────────────────────────┐
│ Hermes home directory    │   SSH tunnel   │ /root/backups/             │
│                          │ ────────────▶  │   backup-hermes/           │
│ Windows: ~/AppData/     │                │   └── <server-name>/      │
│   Local/hermes/          │                │       ├── config.yaml      │
│ Linux: ~/.hermes/        │                │       ├── .env             │
│                          │                │       ├── state.db         │
│ ├── config.yaml          │                │       ├── skills/          │
│ ├── .env                 │                │       ├── sessions/        │
│ ├── auth.json            │                │       ├── cron/            │
│ ├── SOUL.md              │                │       ├── memories/        │
│ ├── state.db             │                │       ├── hooks/           │
│ ├── skills/              │                │       ├── pairing/         │
│ ├── sessions/            │                │       ├── scripts/         │
│ ├── cron/                │                │       └── ...              │
│ ├── memories/            │                │                            │
│ ├── hooks/               │                │                            │
│ ├── pairing/             │                │                            │
│ └── scripts/             │                │                            │
└──────────────────────────┘                └────────────────────────────┘
```

## Prerequisites

- A Hermes Agent installation (Windows with git-bash, or Linux)
- A Linux VPS reachable via SSH (any provider — DigitalOcean, Linode, Hetzner, Oracle Cloud, etc.)
- SSH key-based authentication between the two machines

## Step-by-Step Setup

### 1. Prepare Your VPS

#### Step 1a — On your Hermes server: Generate an SSH key

**Linux:**
```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

**Windows (git-bash):**
```bash
ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
cat ~/.ssh/id_ed25519.pub
```

Copy the output (your public key).

#### Step 1b — On your backup VPS: Add the public key

```bash
echo "<paste the public key here>" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

#### Step 1c — Back on your Hermes server: Test the connection

```bash
ssh -o StrictHostKeyChecking=accept-new root@<your-vps-ip> "hostname"
```

You should see the VPS hostname printed back.

### 2. Install the Backup Script

```bash
# Create the scripts directory if needed
mkdir -p ~/.hermes/scripts   # Linux
# or on Windows:
mkdir -p ~/AppData/Local/hermes/scripts

# Download the script
curl -o ~/.hermes/scripts/hermes-backup.sh \
  https://raw.githubusercontent.com/MrElixir67/how-to-backup-hermes-on-your-vps/main/hermes-backup.sh

# Or on Windows (git-bash):
curl -o ~/AppData/Local/hermes/scripts/hermes-backup.sh \
  https://raw.githubusercontent.com/MrElixir67/how-to-backup-hermes-on-your-vps/main/hermes-backup.sh

# Make it executable
chmod +x ~/.hermes/scripts/hermes-backup.sh   # Linux
chmod +x ~/AppData/Local/hermes/scripts/hermes-backup.sh   # Windows
```

*Alternatively, copy the script from the `hermes-backup.sh` file in this repository.*

### 3. Configure the Backup Target

Create a config file so the script knows where to send backups:

```bash
# Linux
cat > ~/.hermes/scripts/backup-target.conf << 'EOF'
BACKUP_IP=203.0.113.10
BACKUP_USER=root
BACKUP_FOLDER=my-server
EOF
```

```bash
# Windows (git-bash)
cat > ~/AppData/Local/hermes/scripts/backup-target.conf << 'EOF'
BACKUP_IP=203.0.113.10
BACKUP_USER=root
BACKUP_FOLDER=my-server
EOF
```

| Field | Description |
|-------|-------------|
| `BACKUP_IP` | Your VPS IP address |
| `BACKUP_USER` | SSH user (usually `root`) |
| `BACKUP_FOLDER` | A name to identify this Hermes instance (e.g., `production`, `laptop`, `elixia`) |

### 4. Run a Test Backup

```bash
bash ~/.hermes/scripts/hermes-backup.sh
```

Or specify target directly:

```bash
bash hermes-backup.sh 203.0.113.10 my-server
```

Expected output:

```
==============================================
     HERMES BACKUP
==============================================
 Platform   : windows      # or: linux
 Hermes home: /c/Users/me/AppData/Local/hermes
 Folder     : my-server
 Date       : 2026-07-09_04-32-36
 Target     : root@203.0.113.10:/root/backups/backup-hermes/my-server

[1/5] Testing SSH connection...
  [OK] Connected

[2/5] Preparing remote directory...
  [OK] /root/backups/backup-hermes/my-server ready

[3/5] Backing up Hermes data...
  [OK] All data transferred via tar pipe

[4/5] Creating local archive...
  [OK] /root/hermes-backup-my-server-2026-07-09_04-32-36.tar.gz (12M)
  [OK] Keeping last 7 local archives

[5/5] Verifying remote backup...
  [OK] Remote size: 64M | Files: 42

==============================================
     BACKUP COMPLETE
==============================================
 Status   : OK
 Platform : windows
 Duration : 6s
 Remote   : 203.0.113.10:/root/backups/backup-hermes/my-server
 Local    : /root/hermes-backup-my-server-2026-07-09_04-32-36.tar.gz
```

Verify the backup on your VPS:

```bash
ssh root@<your-vps-ip> "ls -la /root/backups/backup-hermes/my-server/"
```

### 5. Schedule Automatic Backups

#### Using Hermes cron (recommended):

```bash
hermes cron create \
  --name hermes-backup \
  --schedule "0 3 * * *" \
  --script hermes-backup.sh \
  --no-agent
```

#### Using system cron (Linux only):

```bash
(crontab -l 2>/dev/null | grep -v "hermes-backup"; \
 echo "0 3 * * * cd ~/.hermes/scripts && bash hermes-backup.sh") | crontab -
```

#### Using Windows Task Scheduler:

Create a basic task that runs:
```
C:\Program Files\Git\bin\bash.exe -l -c "~/AppData/Local/hermes/scripts/hermes-backup.sh"
```

## What Gets Backed Up

| File/Folder | Description | Critical? |
|-------------|-------------|-----------|
| `config.yaml` | Provider settings, tools, integrations | Yes |
| `.env` | API keys and secrets | Yes |
| `auth.json` | OAuth tokens | Yes |
| `SOUL.md` | Agent personality/persona | Yes |
| `state.db` | Session database (conversation history) | Yes |
| `channel_directory.json` | Channel/delivery routing config | Yes |
| `gateway_state.json` | Gateway runtime state | Yes |
| `processes.json` | Background process registry | Yes |
| `skills/` | All custom skills and workflows | Yes |
| `sessions/` | Per-session request dumps | Medium |
| `cron/` | Cron job definitions | Yes |
| `hooks/` | Custom event hooks | Yes |
| `memories/` | Persistent memory (agent knowledge) | Yes |
| `pairing/` | Paired device/auth data | Yes |
| `scripts/` | Custom automation scripts | Yes |

### Excluded

- Cache files (`*_cache.json`, `__pycache__/`, `*.pyc`)
- `node_modules/`, `venv/`, `.venv/`
- `.git/` directories
- `logs/`, `lsp/`, `image_cache/`, `audio_cache/`, `sandboxes/` (ephemeral)

## Restore Guide

### Restore from VPS Backup

```bash
# Make sure the restore script is installed
curl -o ~/.hermes/scripts/hermes-restore.sh \
  https://raw.githubusercontent.com/MrElixir67/how-to-backup-hermes-on-your-vps/main/hermes-restore.sh
chmod +x ~/.hermes/scripts/hermes-restore.sh

# Run the interactive restore
bash ~/.hermes/scripts/hermes-restore.sh
```

The script will:
1. Scan the VPS for available backups
2. Let you select which backup to restore
3. Back up current Hermes data to `.bak.<timestamp>`
4. Stop the Hermes gateway
5. Restore everything from VPS
6. Fix file permissions
7. Restart the Hermes gateway

### Manual Restore

You can also browse your backup directly on the VPS via SCP, SFTP, or File Browser to selectively restore individual files:

```bash
# Restore a single file via SCP
scp root@<vps-ip>:/root/backups/backup-hermes/<folder>/config.yaml ~/.hermes/

# Restore a single file (Windows git-bash)
scp root@<vps-ip>:/root/backups/backup-hermes/<folder>/config.yaml ~/AppData/Local/hermes/

# Restore everything via rsync (Linux)
rsync -a root@<vps-ip>:/root/backups/backup-hermes/<folder>/ ~/.hermes/

# Restore everything via tar pipe (Windows)
ssh root@<vps-ip> "tar czf - -C /root/backups/backup-hermes/<folder> ." | tar xzf - -C ~/AppData/Local/hermes/
```

## Multiple Hermes, One VPS

When multiple Hermes instances back up to the same VPS, each uses a unique `BACKUP_FOLDER`:

```
/root/backups/backup-hermes/
├── production/    # Main production Hermes (Linux)
├── staging/       # Test environment (Linux)
└── elixia/        # Development machine (Windows)
```

To add another Hermes instance:
1. Generate an SSH key on the new server
2. Add its public key to the VPS `~/.ssh/authorized_keys`
3. Create `backup-target.conf` with a unique `BACKUP_FOLDER`
4. Deploy the same backup script (one universal script for all servers)

## Platform Differences

| Aspect | Linux | Windows (git-bash) |
|--------|-------|-------------------|
| Hermes home | `~/.hermes/` | `~/AppData/Local/hermes/` |
| Transfer method | rsync (incremental) | tar pipe over SSH |
| Local archive | `/root/hermes-backup-*.tar.gz` | Same (root in MSYS) |
| Cron | system cron or Hermes cron | Task Scheduler or Hermes cron |
| Script path | `~/.hermes/scripts/` | `~/AppData/Local/hermes/scripts/` |

## Security Note

This backup includes sensitive data: API keys (`.env`), OAuth tokens (`auth.json`), and session history (`state.db`). Treat your backup VPS with the same security standards as your Hermes server:

- Use **SSH key authentication only** — never password-based auth
- Restrict SSH access to specific IPs where possible
- Consider encrypting sensitive files with `gpg` or `age` for an extra layer
- Regularly audit backups when you rotate API keys

## Best Practices

- **Set a descriptive `BACKUP_FOLDER`** — do not rely on hostname, especially when backing up multiple servers
- **Test your restore** — verify at least once that the restore procedure works before you need it
- **Monitor backup health** — regularly check that cron runs by verifying files on the VPS
- **Keep the script updated** — the backup script is universal; improvements apply to all your Hermes instances

## Files

| File | Purpose |
|------|---------|
| `README.md` | This guide |
| `hermes-backup.sh` | Universal backup script (Windows + Linux) |
| `hermes-restore.sh` | Restore script with interactive backup selector |
| `assets/architecture.svg` | Architecture diagram |
| `LICENSE` | GNU General Public License v3.0 |

## License

GNU GPLv3
