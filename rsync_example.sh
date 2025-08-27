#!/bin/bash
set -euo pipefail

# === 設定 ===
SRC="${SRC:-/Volumes/xxxxx/}"
DST="${DST:-/Volumes/xxxxx/xxxxxx_backup/}"
LOG_DIR="${LOG_DIR:-$HOME}"
PREVIEW="${PREVIEW:-0}"          # 1 ならリネームを実行せず一覧のみ
# ===========

ts="$(date +%Y%m%d_%H%M%S)"
RENAME_LOG="$LOG_DIR/sanitize_rename_map_$ts.csv"
RSYNC_LOG="$LOG_DIR/rsync_run_$ts.log"

echo "Source: $SRC"
echo "Dest  : $DST"
echo "Preview mode: $PREVIEW"
echo "Logs  : $RENAME_LOG , $RSYNC_LOG"

# パス確認
for p in "$SRC" "$DST"; do
  if [[ ! -d "$p" ]]; then
    echo "Error: path not found -> $p" >&2
    exit 1
  fi
done

# 宛先 FS 判定（Windows 系ならサニタイズ発動）
FS_RAW="$(diskutil info "$(dirname "$DST")" 2>/dev/null | grep -E 'File System Personality|Type \(Bundle\)' || true)"
FS_LC="$(echo "$FS_RAW" | tr '[:upper:]' '[:lower:]')"
IS_WINLIKE=0
if echo "$FS_LC" | grep -qE 'exfat|ntfs|ms-dos|fat32|fat'; then
  IS_WINLIKE=1
fi
echo "Detected FS: ${FS_RAW:-unknown}"
echo "Windows-like FS: $IS_WINLIKE"

# CSV ヘッダ
echo "old_path,new_path" > "$RENAME_LOG"

# サニタイズ実行（Windows 互換が必要な場合のみ）
if [[ "$IS_WINLIKE" -eq 1 ]]; then
  echo "Sanitizing filenames in SOURCE for Windows-compat (preview=$PREVIEW)..."
  /usr/bin/python3 - "$SRC" "$PREVIEW" "$RENAME_LOG" <<'PY'
import os, sys, csv

SRC = sys.argv[1]
PREVIEW = sys.argv[2] == "1"
LOGPATH = sys.argv[3]

BAD_CHARS = '<>:"/\\|?*'
TRANS = str.maketrans({c:'_' for c in BAD_CHARS})
RESERVED = {*(f'COM{i}' for i in range(1,10)),
            *(f'LPT{i}' for i in range(1,10)),
            'CON','PRN','AUX','NUL'}

def sanitize(name):
    new = name.translate(TRANS).rstrip(' .')
    if not new:
        new = '_'
    root = new.split('.')[0].upper()
    if root in RESERVED:
        new = '_' + new
    return new

def unique_path(dirpath, newname):
    cand = newname
    base, ext = os.path.splitext(newname)
    i = 1
    while os.path.exists(os.path.join(dirpath, cand)) and i < 1000:
        cand = f"{base}__{i}{ext}"
        i += 1
    return cand

rows = []
# ディレクトリを先に改名するため topdown=True で dirnames を書き換える
for dirpath, dirnames, filenames in os.walk(SRC, topdown=True):
    # . と .. はスキップ、ルートの安全性
    # ディレクトリ
    for idx in range(len(dirnames)):
        d = dirnames[idx]
        old = os.path.join(dirpath, d)
        newname = sanitize(d)
        if newname != d:
            new = os.path.join(dirpath, unique_path(dirpath, newname))
            rows.append((old, new))
            if not PREVIEW:
                try:
                    os.rename(old, new)
                    dirnames[idx] = os.path.basename(new)
                except OSError as e:
                    print(f"[dir rename failed] {old}: {e}", file=sys.stderr)
    # ファイル
    for f in filenames:
        old = os.path.join(dirpath, f)
        newname = sanitize(f)
        if newname != f:
            new = os.path.join(dirpath, unique_path(dirpath, newname))
            rows.append((old, new))
            if not PREVIEW:
                try:
                    os.rename(old, new)
                except OSError as e:
                    print(f"[file rename failed] {old}: {e}", file=sys.stderr)

# ログ出力（相対ではなく絶対パス）
with open(LOGPATH, 'a', newline='') as fp:
    w = csv.writer(fp)
    for old, new in rows:
        w.writerow([old, new])

print(f"Sanitize candidates: {len(rows)}")
PY
else
  echo "Destination is not Windows-like FS. Skipping sanitize."
fi

# プレビューのみなら終了
if [[ "$PREVIEW" -eq 1 ]]; then
  echo "Preview complete. See $RENAME_LOG"
  exit 0
fi

# rsync オプション（堅牢）
RSYNC_OPTS=(-rlptovzh
  --partial --partial-dir=".rsync-partial"
  --delete-delay --progress
  --exclude=".Spotlight-V100"
  --exclude=".fseventsd"
  --exclude=".TemporaryItems"
  --exclude=".Trashes"
  --exclude=".DS_Store"
)

# exFAT/NTFS 等はタイムスタンプ分解能の差を吸収
if [[ "$IS_WINLIKE" -eq 1 ]]; then
  RSYNC_OPTS+=(--modify-window=2)
fi

echo "Running rsync..."
mkdir -p "$DST"
rsync "${RSYNC_OPTS[@]}" "$SRC" "$DST" | tee "$RSYNC_LOG"
echo "Done. Logs: $RSYNC_LOG , rename map: $RENAME_LOG"



