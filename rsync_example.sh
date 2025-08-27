#!/bin/bash
set -euo pipefail

SRC="/Volumes/xxxx/"
DST="/Volumes/xxxx/xxxx_backup/"

echo "start backup HD-ADU3_6TB to HD-SGDA_6TB !!"

rsync -rlptDovzh --delete --progress \
  --exclude=".Spotlight-V100" \
  --exclude=".fseventsd" \
  --exclude=".TemporaryItems" \
  --exclude=".Trashes" \
  --exclude=".DS_Store" \
  "$SRC" "$DST"

echo "complete!"

