#!/bin/bash
# Hermes Agent Restore — from VPS backup to any Hermes server
# Works with any VPS that has hermes-backup.sh backups stored.
#
# Usage: bash ~/.hermes/scripts/hermes-restore.sh

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# ===== CONFIGURE YOUR VPS HERE =====
BACKUP_IP="<YOUR_VPS_IP>"
BACKUP_USER="root"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

clear 2>/dev/null || true
echo "================================================"
echo "     HERMES RESTORE — from VPS"
echo "================================================"
echo ""

# ===== Step 1: List available backups =====
echo "[1] Scanning backup folders on VPS ($BACKUP_IP)..."
echo ""

BACKUP_LIST=$(ssh -n "$BACKUP_USER@$BACKUP_IP" '
if [ -d /root/backups/backup-hermes ]; then
  for d in /root/backups/backup-hermes/*/; do
    [ -d "$d" ] && echo "$(basename "$d")|$(du -sh "$d" | cut -f1)|$d"
  done
fi' 2>/dev/null)

if [ -z "$BACKUP_LIST" ]; then
    echo "ERROR: No backups found on $BACKUP_IP!"
    echo "  Expected location: /root/backups/backup-hermes/*/"
    exit 1
fi

# Parse into arrays
IFS=$'\n'
BACKUP_ITEMS=($BACKUP_LIST)
unset IFS

INDEX=0
NAMES=()
DIRS=()
for item in "${BACKUP_ITEMS[@]}"; do
    NAME=$(echo "$item" | cut -d'|' -f1)
    SIZE=$(echo "$item" | cut -d'|' -f2)
    DIR=$(echo "$item" | cut -d'|' -f3)
    NAMES+=("$NAME")
    DIRS+=("$DIR")
    echo "   $INDEX) $NAME  ($SIZE)"
    INDEX=$((INDEX + 1))
done

echo ""
read -r -p "Select backup number: " CHOICE
if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -ge "${#DIRS[@]}" ]; then
    echo "ERROR: Invalid selection!"
    exit 1
fi

BACKUP_DIR="${DIRS[$CHOICE]}"
BACKUP_NAME="${NAMES[$CHOICE]}"

# ===== Step 2: Ask for target server IP =====
echo ""
read -r -p "Target Hermes server IP: " TARGET_IP

if [ -z "$TARGET_IP" ]; then
    echo "ERROR: Target IP is required!"
    exit 1
fi

TARGET_USER="root"
TARGET_HOME="/root/.hermes"
TARGET_SRC="/usr/local/lib/hermes-agent"

echo ""
echo "================================================"
echo "  RESTORE: $BACKUP_NAME"
echo "  From:    $BACKUP_IP"
echo "  To:      $TARGET_IP"
echo "================================================"
echo ""
echo "WARNING: This will OVERWRITE all Hermes files on $TARGET_IP!"
echo ""
read -r -p "Type 'RESTORE' to continue: " CONFIRM
if [ "$CONFIRM" != "RESTORE" ]; then
    echo "Restore cancelled."
    exit 1
fi

# ===== Step 3: Backup current files on target =====
echo ""
echo "=== Step 1: Backing up current files on target ==="
ssh "$TARGET_USER@$TARGET_IP" "mkdir -p $TARGET_HOME.bak.$TIMESTAMP" 2>/dev/null
ssh "$TARGET_USER@$TARGET_IP" "cp $TARGET_HOME/config.yaml $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/.env $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/auth.json $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp $TARGET_HOME/state.db $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/skills $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/cron $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null; cp -r $TARGET_HOME/mnemosyne $TARGET_HOME.bak.$TIMESTAMP/ 2>/dev/null" 2>/dev/null
echo "  [OK] Old files saved to $TARGET_IP:$TARGET_HOME.bak.$TIMESTAMP"

# ===== Step 4: Stop Hermes on target =====
echo ""
echo "=== Step 2: Stopping Hermes gateway on target ==="
ssh "$TARGET_USER@$TARGET_IP" "pkill -f 'hermes.*gateway' 2>/dev/null || true; sleep 1" 2>/dev/null
echo "  [OK] Gateway stopped"

# ===== Step 5: Push backup to target =====
echo ""
echo "=== Step 3: Pushing backup to $TARGET_IP ==="
rsync -a "$BACKUP_USER@$BACKUP_IP:$BACKUP_DIR/config/config.yaml" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] config.yaml" || echo "  [SKIP] config.yaml"
rsync -a "$BACKUP_USER@$BACKUP_IP:$BACKUP_DIR/config/.env" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] .env" || echo "  [SKIP] .env"
rsync -a "$BACKUP_USER@$BACKUP_IP:$BACKUP_DIR/config/auth.json" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] auth.json" || echo "  [SKIP] auth.json"
rsync -a "$BACKUP_USER@$BACKUP_IP:$BACKUP_DIR/sessions/state.db" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/" 2>/dev/null && echo "  [OK] state.db" || echo "  [SKIP] state.db"
rsync -a --delete "$BACKUP_USER@$BACKUP_IP:$BACKUP_DIR/skills/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/skills/" 2>/dev/null && echo "  [OK] skills/" || echo "  [SKIP] skills/"
rsync -a --delete "$BACKUP_USER@$BACKUP_IP:$BACKUP_DIR/cron/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/cron/" 2>/dev/null && echo "  [OK] cron/" || echo "  [SKIP] cron/"
rsync -a --delete "$BACKUP_USER@$BACKUP_IP:$BACKUP_DIR/mnemosyne/" "$TARGET_USER@$TARGET_IP:$TARGET_HOME/mnemosyne/" 2>/dev/null && echo "  [OK] mnemosyne/" || echo "  [SKIP] mnemosyne/"

# ===== Step 6: Restore Hermes source =====
echo ""
echo "=== Step 4: Restoring Hermes source code ==="
if ssh "$BACKUP_USER@$BACKUP_IP" "test -d $BACKUP_DIR/hermes-src" 2>/dev/null; then
    rsync -a --delete \
      --exclude='.git' --exclude='node_modules' --exclude='venv' --exclude='.venv' \
      --exclude='__pycache__' --exclude='*.pyc' \
      "$BACKUP_USER@$BACKUP_IP:$BACKUP_DIR/hermes-src/" "$TARGET_USER@$TARGET_IP:$TARGET_SRC/" 2>/dev/null && echo "  [OK] hermes source"
else
    echo "  [SKIP] hermes source (not found in backup)"
fi

# ===== Step 7: Fix permissions =====
echo ""
echo "=== Step 5: Fixing permissions ==="
ssh "$TARGET_USER@$TARGET_IP" "chmod 600 $TARGET_HOME/.env $TARGET_HOME/auth.json $TARGET_HOME/state.db 2>/dev/null" 2>/dev/null
echo "  [OK] permissions"

# ===== Step 8: Restart Hermes on target =====
echo ""
echo "=== Step 6: Restarting Hermes gateway ==="
ssh "$TARGET_USER@$TARGET_IP" "cd $TARGET_SRC 2>/dev/null; nohup hermes gateway start > /dev/null 2>&1 &" 2>/dev/null
echo "  [OK] Hermes gateway restarted on $TARGET_IP"

echo ""
echo "================================================"
echo "  RESTORE COMPLETE"
echo "================================================"
echo "  Backup:  $BACKUP_NAME"
echo "  From:    $BACKUP_IP"
echo "  To:      $TARGET_IP"
echo "  Old files: $TARGET_HOME.bak.$TIMESTAMP"
echo ""
echo "NOTE: Configure cron on the restored server"
echo "to resume automatic backups."
echo ""
