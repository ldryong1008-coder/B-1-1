#!/bin/bash

# ==========================================
# 시스템 상태 수집 및 로깅 스크립트 (monitor.sh)
# 작성자: agent-dev
# ==========================================

# 0. 설정 변수
LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"
APP_NAME="agent-app"
PORT=${AGENT_PORT:-15034}

# 로그 디렉토리가 없으면 생성 (권한이 있을 경우)
mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null

echo "====== SYSTEM MONITOR RESULT ======"
echo ""
echo "[HEALTH CHECK]"

# 1. 프로세스 체크
if pgrep -f "$APP_NAME" > /dev/null; then
    APP_PID=$(pgrep -f "$APP_NAME" | head -n 1)
    echo "Checking process '$APP_NAME'... [OK] (PID: $APP_PID)"
else
    echo "Checking process '$APP_NAME'... [FAIL]"
    exit 1
fi

# 2. 포트 체크 (ss 또는 netstat 활용)
if ss -tulnp 2>/dev/null | grep -q ":$PORT" || netstat -tulnp 2>/dev/null | grep -q ":$PORT"; then
    echo "Checking port $PORT... [OK]"
else
    echo "Checking port $PORT... [FAIL]"
    exit 1
fi

echo ""
echo "[RESOURCE MONITORING]"

# 3. 리소스 상태 수집
# CPU 사용률 (vmstat 기반)
CPU_IDLE=$(vmstat 1 2 | tail -1 | awk '{print $15}')
if [ -z "$CPU_IDLE" ]; then
    CPU_USAGE="0"
else
    CPU_USAGE=$((100 - CPU_IDLE))
fi

# 메모리 사용률
MEM_USAGE=$(free | grep Mem | awk '{printf("%.1f", $3/$2 * 100.0)}')

# 디스크 사용률 (루트 파티션 기준)
DISK_USED=$(df -h / | awk '$NF=="/"{print $5}' | sed 's/%//')

echo "CPU Usage  : ${CPU_USAGE}%"
echo "MEM Usage  : ${MEM_USAGE}%"
echo "DISK Used  : ${DISK_USED}%"
echo ""

# 4. 임계값 경고 처리
if [ "$CPU_USAGE" -gt 20 ]; then
    echo "[WARNING] CPU threshold exceeded (${CPU_USAGE}% > 20%)"
fi

if $(awk 'BEGIN{print ('$MEM_USAGE' > 10.0)}'); then
    echo "[WARNING] MEM threshold exceeded (${MEM_USAGE}% > 10%)"
fi

if [ "$DISK_USED" -gt 80 ]; then
    echo "[WARNING] DISK threshold exceeded (${DISK_USED}% > 80%)"
fi

# 5. 방화벽 상태 점검 (UFW 또는 firewalld)
FW_ACTIVE=false
if command -v ufw >/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    FW_ACTIVE=true
elif command -v firewall-cmd >/dev/null && sudo firewall-cmd --state 2>/dev/null | grep -q "running"; then
    FW_ACTIVE=true
fi

if [ "$FW_ACTIVE" = false ]; then
    echo "[WARNING] Firewall is not active or not properly configured."
fi

# 6. 로그 기록
DATE_STR=$(date "+%Y-%m-%d %H:%M:%S")
LOG_LINE="[$DATE_STR] PID:$APP_PID CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USED}%"
echo "$LOG_LINE" >> "$LOG_FILE"

echo ""
echo "[INFO] Log appended: $LOG_FILE"

# 7. 로그 파일 용량 관리 (10MB 초과 시 로테이션 - 최대 10개 유지)
if [ -f "$LOG_FILE" ]; then
    FILE_SIZE=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null)
    if [ "$FILE_SIZE" -ge 10485760 ]; then
        for i in {9..1}; do
            [ -f "${LOG_FILE}.$i" ] && mv "${LOG_FILE}.$i" "${LOG_FILE}.$((i+1))"
        done
        cp "$LOG_FILE" "${LOG_FILE}.1"
        > "$LOG_FILE"
    fi
fi
