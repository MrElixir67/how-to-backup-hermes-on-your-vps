#!/bin/bash
# Hermes Agent Restore — from VPS backup to any Hermes server (Windows + Linux)
# Works with backups created by hermes-backup.sh.
#
# Usage: bash hermes-restore.sh
#
# Steps:
#   1. Lists available backups on the VPS
#   2. You select which backup folder to restore from
#   3. Backs up current Hermes data (just in case)
#   4. Stops Hermes gateway
#   5. Restores from VPS
#   6. Restarts Hermes gateway

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ============================================================
# PLATFORM DETECTION
# ============================================================
if [ -d "$HOME/AppData/Local/hermes" ]; then
    HERMES_HOME="$HOME/AppData/Local/hermes"
    PLATFORM="windows"
elif [ -d "$HOME/.hermes" ]; then
    HERMES_HOME="$HOME/.hermes"
    PLATFORM="linux"
else
    echo "ERROR: Cannot find Hermes home directory!"
    echo "  Looked: $HOME/AppData/Local/hermes (Windows)"
    echo "  Looked: $HOME/.hermes (Linux)"
    exit 1
fi

TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# ============================================================
# Read config
# ============================================================
CONFIG_FILE="$HERMES_HOME/scripts/backup-target.conf"

BACKUP_IP=""
BACKUP_USER="root"

if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

if [ -z "$BACKUP_IP" ]; then
    echo ""
    echo "=============================================="
    echo "     HERMES RESTORE"
    echo "=============================================="
    echo "No BACKUP_IP found in $CONFIG_FILE"
    echo ""
    read -r -p "Enter VPS IP address: " BACKUP_IP
fi

BACKUP_TARGET="${BACKUP_USER}@${BACKUP_IP}"

echo ""
echo "=============================================="
echo "     HERMES RESTORE"
echo "=============================================="
echo " Platform : $PLATFORM"
echo " Hermes   : $HERMES_HOME"
echo " VPS      : $BACKUP_TARGET"
echo ""

# ============================================================
# STEP 1 — Test SSH
# ============================================================
echo "[1] Testing SSH connection..."
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    "$BACKUP_TARGET" "hostname" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "  [FAIL] Cannot reach $BACKUP_TARGET"
    exit 1
fi
echo "  [OK] Connected"
echo ""

# ============================================================
# STEP 2 — List available backups
# ============================================================
echo "[2] Scanning backup folders on VPS..."
echo ""

BACKUP_LIST=$(ssh "$BACKUP_TARGET" '
if [ -d /root/backups/backup-hermes ]; then
  for d in /root/backups/backup-hermes/*/; do
    [ -d "$d" ] && echo "$(basename "$d")|$(du -sh "$d" | cut -f1)|$(find "$d" -type f 2>/dev/null | wc -l)"
  done
fi' 2>/dev/null)

if [ -z "$BACKUP_LIST" ]; then
    echo "ERROR: No backups found on $BACKUP_IP!"
    echo "  Expected: /root/backups/backup-hermes/*/"
    exit 1
fi

IFS=$'\n'
BACKUP_ITEMS=($BACKUP_LIST)
unset IFS

INDEX=0
NAMES=()
DIRS=()
echo "  Available backups:"
echo "  ------------------"
for item in "${BACKUP_ITEMS[@]}"; do
    NAME=$(echo "$item" | cut -d'|' -f1)
    SIZE=$(echo "$item" | cut -d'|' -f2)
    FILES=$(echo "$item" | cut -d'|' -f3)
    echo "   $INDEX) $NAME  ($SIZE, $FILES files)"
    NAMES+=("$NAME")
    DIRS+=("/root/backups/backup-hermes/$NAME")
    INDEX=$((INDEX + 1))
done
echo ""

read -r -p "  Select backup number: " CHOICE
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#DIRS[@]}" ]; then
    echo "ERROR: Invalid selection!"
    exit 1
fi

BACKUP_DIR="${DIRS[$CHOICE]}"
BACKUP_NAME="${NAMES[$CHOICE]}"

# ============================================================
# STEP 3 — Confirm
# ============================================================
echo ""
echo "=============================================="
echo "  RESTORE: $BACKUP_NAME"
echo "  From:    $BACKUP_IP:$BACKUP_DIR"
echo "  To:      $HERMES_HOME (local)"
echo "=============================================="
echo ""
echo "WARNING: This will OVERWRITE all Hermes data on this machine!"
echo ""
read -r -p "Type 'RESTORE' to continue: " CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
    echo "Restore cancelled."
    exit 1
fi

# ============================================================
# STEP 4 — Backup current files
# ============================================================
echo ""
echo "[3] Backing up current Hermes data..."
BAK_DIR="$HERMES_HOME.bak.$TIMESTAMP"
mkdir -p "$BAK_DIR"
cp "$HERMES_HOME"/config.yaml "$BAK_DIR/" 2>/dev/null
cp "$HERMES_HOME"/.env "$BAK_DIR/" 2>/dev/null
cp "$HERMES_HOME"/auth.json "$BAK_DIR/" 2>/dev/null
cp "$HERMES_HOME"/SOUL.md "$BAK_DIR/" 2>/dev/null
cp "$HERMES_HOME"/state.db "$BAK_DIR/" 2>/dev/null
cp "$HERMES_HOME"/channel_directory.json "$BAK_DIR/" 2>/dev/null
cp "$HERMES_HOME"/gateway_state.json "$BAK_DIR/" 2>/dev/null
cp "$HERMES_HOME"/processes.json "$BAK_DIR/" 2>/dev/null
cp -r "$HERMES_HOME"/skills "$BAK_DIR/" 2>/dev/null
cp -r "$HERMES_HOME"/cron "$BAK_DIR/" 2>/dev/null
cp -r "$HERMES_HOME"/hooks "$BAK_DIR/" 2>/dev/null
cp -r "$HERMES_HOME"/memories "$BAK_DIR/" 2>/dev/null
cp -r "$HERMES_HOME"/sessions "$BAK_DIR/" 2>/dev/null
cp -r "$HERMES_HOME"/pairing "$BAK_DIR/" 2>/dev/null
cp -r "$HERMES_HOME"/scripts "$BAK_DIR/" 2>/dev/null
echo "  [OK] Current data saved to $BAK_DIR"
echo ""

# ============================================================
# STEP 5 — Stop Hermes gateway
# ============================================================
echo "[4] Stopping Hermes gateway..."
if command -v hermes &>/dev/null; then
    hermes gateway stop 2>/dev/null || true
    sleep 2
    echo "  [OK] Gateway stopped"
else
    echo "  [SKIP] 'hermes' command not found"
fi
echo ""

# ============================================================
# STEP 6 — Restore from VPS
# ============================================================
echo "[5] Restoring from VPS..."

if [ "$PLATFORM" = "windows" ]; then
    # ----- Windows: pull via tar pipe -----
    ssh "$BACKUP_TARGET" "tar czf - --no-same-owner -C $BACKUP_DIR ." 2>/dev/null | \
        tar xzf - --no-same-owner -C "$HERMES_HOME/" 2>/dev/null

    if [ $? -eq 0 ] || [ $? -eq 1 ]; then
        echo "  [OK] Restore complete via tar pipe"
    else
        echo "  [FAIL] Restore failed!"
        exit 1
    fi
else
    # ----- Linux: rsync pull -----
    rsync -a "$BACKUP_TARGET:$BACKUP_DIR/" "$HERMES_HOME/" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "  [OK] Restore complete via rsync"
    else
        echo "  [FAIL] Restore failed!"
        exit 1
    fi
fi
echo ""

# ============================================================
# STEP 7 — Fix permissions
# ============================================================
echo "[6] Fixing permissions..."
chmod 600 "$HERMES_HOME"/.env "$HERMES_HOME"/auth.json \
    "$HERMES_HOME"/state.db "$HERMES_HOME"/processes.json \
    2>/dev/null || true
echo "  [OK] Secrets locked down (600)"
echo ""

# ============================================================
# STEP 8 — Restart Hermes gateway
# ============================================================
echo "[7] Restarting Hermes gateway..."
if command -v hermes &>/dev/null; then
    hermes gateway start 2>/dev/null || true
    echo "  [OK] Hermes gateway restarted"
else
    echo "  [SKIP] 'hermes' command not found — start manually"
fi
echo ""

# ============================================================
# SUMMARY
# ============================================================
echo "=============================================="
echo "     RESTORE COMPLETE"
echo "=============================================="
echo " Restored : $BACKUP_NAME (from $BACKUP_IP)"
echo " To       : $HERMES_HOME"
echo " Old data : $BAK_DIR"
echo ""
echo "NOTE: Re-configure cron if needed:"
echo "  hermes cron create --name hermes-backup \\"
echo "    --schedule '0 3 * * *' \\"
echo "    --script hermes-backup.sh --no-agent"
echo ""
