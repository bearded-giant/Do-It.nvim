#!/bin/bash

# backup all doit todo lists to a timestamped directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get-active-list.sh"

BACKUP_DIR=$(tmux show-option -gqv "@doit-backup-dir")
BACKUP_DIR="${BACKUP_DIR:-$DOIT_DATA_DIR/backups}"

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_PATH="$BACKUP_DIR/$TIMESTAMP"

mkdir -p "$BACKUP_PATH"

COPIED=0
for f in "$LISTS_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    cp "$f" "$BACKUP_PATH/"
    COPIED=$((COPIED + 1))
done

# also backup session state
if [[ -f "$DOIT_DATA_DIR/session.json" ]]; then
    cp "$DOIT_DATA_DIR/session.json" "$BACKUP_PATH/"
fi

if [[ "$COPIED" -eq 0 ]]; then
    echo "No lists found to backup"
    exit 1
fi

echo "Backed up $COPIED lists to $BACKUP_PATH"
