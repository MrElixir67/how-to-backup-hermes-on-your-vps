#!/bin/bash
# Hermes Agent Auto-Backup — Universal Hybrid (Windows + Linux)
# Creates a browsable backup of your Hermes Agent data on any Linux VPS.
#
# Usage:
#   bash hermes-backup.sh                                    # use config file
#   bash hermes-backup.sh <VPS_IP>                           # specify IP directly
#   bash hermes-backup.sh <VPS_IP> <FOLDER_NAME>             # specify IP + folder
#   BACKUP_IP=x BACKUP_FOLDER=y bash hermes-backup.sh        # env vars
#
# Config file: $HERMES_HOME/scripts/backup-target.conf
#   BACKUP_IP=203.0.113.10
#   BACKUP_USER=root
#   BACKUP_FOLDER=my-server       # optional, defaults to hostname
#
# Platform detection (auto):
#   Windows (git-bash/MSYS) — tar pipe over SSH
#   Linux/macOS — rsync over SSH (incremental, more efficient)
#
# Schedule via Hermes cron:
#   hermes cron create --name hermes-backup \
#     --schedule "0 3 * * *" \
#     --script hermes-backup.sh --no-agent

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

# ============================================================
# CONFIG — resolve target IP & folder name
# ============================================================
CONFIG_FILE="$HERMES_HOME/scripts/backup-target.conf"

if [ -n "$2" ]; then
    BACKUP_IP="$1"
    BACKUP_FOLDER="$2"
elif [ -n "$1" ]; then
    BACKUP_IP="$1"
elif [ -n "$BACKUP_IP" ] && [ -n "$BACKUP_FOLDER" ]; then
    :  # both from env vars
elif [ -n "$BACKUP_IP" ]; then
    :  # IP from env, folder defaults to hostname
elif [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
else
    echo "ERROR: No backup target configured!"
    echo "  Option 1: bash hermes-backup.sh <VPS_IP> [FOLDER_NAME]"
    echo "  Option 2: create $CONFIG_FILE with:"
    echo "    BACKUP_IP=<VPS_IP>"
    echo "    BACKUP_FOLDER=my-server"
    exit 1
fi

BACKUP_USER="${BACKUP_USER:-root}"
BACKUP_TARGET="${BACKUP_USER}@${BACKUP_IP}"
BACKUP_FOLDER="${BACKUP_FOLDER:-$(hostname -s)}"
REMOTE_DIR="/root/backups/backup-hermes/$BACKUP_FOLDER"

DATE=$(date +%Y-%m-%d_%H-%M-%S)
START_TS=$(date +%s)

# ============================================================
# LOCAL ARCHIVE (optional, for extra safety)
# ============================================================
LOCAL_ARCHIVE="$HOME/hermes-backup-${BACKUP_FOLDER}-${DATE}.tar.gz"
MAX_LOCAL=7

echo "=============================================="
echo "     HERMES BACKUP"
echo "=============================================="
echo " Platform   : $PLATFORM"
echo " Hermes home: $HERMES_HOME"
echo " Folder     : $BACKUP_FOLDER"
echo " Date       : $DATE"
echo " Target     : $BACKUP_TARGET:$REMOTE_DIR"
echo ""

# ============================================================
# STEP 1 — Test SSH connection
# ============================================================
echo "[1/5] Testing SSH connection..."
ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
    "$BACKUP_TARGET" "hostname" >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "  [FAIL] Cannot reach $BACKUP_TARGET"
    echo "  Check: IP reachable? SSH key installed?"
    exit 1
fi
echo "  [OK] Connected"
echo ""

# ============================================================
# STEP 2 — Create remote directory
# ============================================================
echo "[2/5] Preparing remote directory..."
ssh "$BACKUP_TARGET" "mkdir -p $REMOTE_DIR" >/dev/null 2>&1
echo "  [OK] $REMOTE_DIR ready"
echo ""

# ============================================================
# STEP 3 — Backup data
# ============================================================
echo "[3/5] Backing up Hermes data..."

if [ "$PLATFORM" = "windows" ]; then
    # ----- Windows: tar pipe over SSH -----
    # rsync not available on git-bash; use tar | ssh | tar instead.

    cd "$HERMES_HOME" || { echo "  [FAIL] Cannot access $HERMES_HOME"; exit 1; }

    tar czf - --no-same-owner \
        config.yaml .env auth.json SOUL.md \
        state.db channel_directory.json gateway_state.json processes.json \
        skills cron hooks memories sessions pairing scripts \
        2>/dev/null | \
        ssh "$BACKUP_TARGET" "tar xzf - --no-same-owner -C $REMOTE_DIR/" \
            >/dev/null 2>&1

    if [ ${PIPESTATUS[0]} -eq 0 ] || [ ${PIPESTATUS[0]} -eq 1 ]; then
        echo "  [OK] All data transferred via tar pipe"
    else
        echo "  [FAIL] Backup transfer failed!"
        exit 1
    fi
else
    # ----- Linux: rsync (incremental, efficient) -----
    # Config files
    for f in config.yaml .env auth.json SOUL.md \
             channel_directory.json gateway_state.json processes.json; do
        [ -f "$HERMES_HOME/$f" ] && \
            rsync -a --delete "$HERMES_HOME/$f" \
                "$BACKUP_TARGET:$REMOTE_DIR/" >/dev/null 2>&1 && \
            echo "  [OK] $f" || echo "  [SKIP] $f"
    done

    # Database
    [ -f "$HERMES_HOME/state.db" ] && \
        rsync -a "$HERMES_HOME/state.db" \
            "$BACKUP_TARGET:$REMOTE_DIR/" >/dev/null 2>&1 && \
        echo "  [OK] state.db"

    # Folders
    for dir in skills cron hooks memories sessions pairing scripts; do
        if [ -d "$HERMES_HOME/$dir" ]; then
            rsync -a --delete "$HERMES_HOME/$dir/" \
                "$BACKUP_TARGET:$REMOTE_DIR/$dir/" >/dev/null 2>&1 && \
                echo "  [OK] $dir/" || echo "  [FAIL] $dir/"
        fi
    done
fi
echo ""

# ============================================================
# STEP 4 — Create local archive (both platforms)
# ============================================================
echo "[4/5] Creating local archive..."
tar czf "$LOCAL_ARCHIVE" --no-same-owner --exclude='.git' --exclude='node_modules' \
    --exclude='__pycache__' --exclude='*.pyc' \
    -C "$HERMES_HOME" \
    config.yaml .env auth.json SOUL.md state.db \
    channel_directory.json gateway_state.json processes.json \
    skills cron hooks memories sessions pairing scripts \
    2>/dev/null

if [ -f "$LOCAL_ARCHIVE" ]; then
    ARCHIVE_SIZE=$(du -h "$LOCAL_ARCHIVE" | cut -f1)
    echo "  [OK] $LOCAL_ARCHIVE ($ARCHIVE_SIZE)"
else
    echo "  [SKIP] Local archive not created"
fi

# Clean old local archives
ls -1t "$HOME"/hermes-backup-*.tar.gz 2>/dev/null | \
    tail -n +$((MAX_LOCAL+1)) | xargs rm -f 2>/dev/null
echo "  [OK] Keeping last $MAX_LOCAL local archives"
echo ""

# ============================================================
# STEP 5 — Verify
# ============================================================
echo "[5/5] Verifying remote backup..."
CT_SIZE=$(ssh "$BACKUP_TARGET" "du -sh $REMOTE_DIR 2>/dev/null | cut -f1")
CT_FILES=$(ssh "$BACKUP_TARGET" \
    "find $REMOTE_DIR -type f 2>/dev/null | wc -l")
echo "  [OK] Remote size: $CT_SIZE | Files: $CT_FILES"
echo ""

# ============================================================
# SUMMARY
# ============================================================
END_TS=$(date +%s)
DURATION=$((END_TS - START_TS))
echo "=============================================="
echo "     BACKUP COMPLETE"
echo "=============================================="
echo " Status   : OK"
echo " Platform : $PLATFORM"
echo " Duration : ${DURATION}s"
echo " Remote   : $BACKUP_IP:$REMOTE_DIR"
echo " Local    : $LOCAL_ARCHIVE"
echo ""
