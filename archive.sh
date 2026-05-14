#!/bin/bash

# ==========================================
# 로그 보존/압축/삭제 정책 스크립트 (archive.sh) - 보너스 2
# ==========================================

LOG_DIR="${AGENT_LOG_DIR:-/var/log/agent-app}"
ARCHIVE_DIR="/var/log/monitor/agent-app/archive"

echo "====== LOG ARCHIVE AND CLEANUP ======"

# 1. 예외 처리
if [ ! -d "$LOG_DIR" ]; then
    echo "[ERROR] Log directory not found: $LOG_DIR"
    exit 1
fi

if [ ! -w "$LOG_DIR" ]; then
    echo "[ERROR] Insufficient permission to write in $LOG_DIR"
    exit 1
fi

mkdir -p "$ARCHIVE_DIR" 2>/dev/null
if [ ! -w "$ARCHIVE_DIR" ]; then
    echo "[ERROR] Cannot write to archive directory: $ARCHIVE_DIR"
    exit 1
fi

# 2. 7일 경과 로그 압축 및 아카이브 이동 (현재 기록 중인 monitor.log 자체는 제외)
ARCHIVED_COUNT=0
find "$LOG_DIR" -maxdepth 1 -name "monitor.log.*" -type f -mtime +7 | while read -r log_file; do
    echo "[INFO] Archiving $log_file..."
    gzip -c "$log_file" > "$ARCHIVE_DIR/$(basename "$log_file").$(date +%Y%m%d%H%M%S).gz" && rm "$log_file"
    ARCHIVED_COUNT=$((ARCHIVED_COUNT+1))
done

if [ "$ARCHIVED_COUNT" -eq 0 ]; then
    echo "[INFO] No old logs (older than 7 days) to archive."
fi

# 3. 30일 경과 아카이브 삭제
DEL_COUNT=$(find "$ARCHIVE_DIR" -name "*.gz" -type f -mtime +30 | wc -l)
if [ "$DEL_COUNT" -gt 0 ]; then
    find "$ARCHIVE_DIR" -name "*.gz" -type f -mtime +30 -exec rm {} \;
    echo "[INFO] Deleted $DEL_COUNT old archives (older than 30 days)."
else
    echo "[INFO] No archives older than 30 days to delete."
fi

echo "====== ARCHIVE PROCESS COMPLETED ======"
