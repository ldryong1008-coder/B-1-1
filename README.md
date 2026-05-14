# B-1-1

# Linux Server Engineering & Automation Mission

## 1. 프로젝트 개요
본 프로젝트는 리눅스 환경에서 다중 사용자 환경의 권한 관리, 네트워크 보안 설정, 애플리케이션 배포 환경 구축 및 시스템 상태 관제(모니터링) 자동화 스크립트를 구현하는 것을 목표로 합니다. 서버 장애 시 '감'에 의존하지 않고, 정확한 로그와 데이터를 바탕으로 원인을 분석할 수 있는 엔지니어링 역량을 증명합니다.

## 2. 요구사항 수행 내역

### 2.1. 기본 보안 및 네트워크 설정
**1) SSH 포트 변경 및 Root 원격 접속 차단**
- **설정 파일:** `/etc/ssh/sshd_config`
- **변경 내역:** `Port 20022`, `PermitRootLogin no`
- **검증 명령어:** `ss -tulnp | grep sshd`

**2) 방화벽(UFW) 설정**
- **정책:** UFW 활성화 및 필요 포트만 허용
- **허용 포트:** `20022/tcp` (SSH), `15034/tcp` (APP)
- **검증 명령어:** `sudo ufw status`

### 2.2. 계정, 그룹 및 권한 체계 구성
협업과 최소 권한의 원칙을 적용하여 역할 기반 계정 및 그룹을 구성하였습니다.

- **그룹 구성:** - `agent-common`: admin, dev, test
  - `agent-core`: admin, dev
- **계정 구성:** `agent-admin`, `agent-dev`, `agent-test`
- **디렉토리 및 접근 권한 정책:**
  - `$AGENT_HOME/upload_files`: `agent-common` 그룹 (R/W 허용)
  - `$AGENT_HOME/api_keys`: `agent-core` 그룹 ONLY (R/W 허용)
  - `/var/log/agent-app`: `agent-core` 그룹 ONLY (R/W 허용)

### 2.3. 애플리케이션 실행 환경 및 키 파일 설정
`agent-admin` 계정의 `~/.bashrc`에 애플리케이션 구동을 위한 환경 변수를 고정하였습니다.

- **환경 변수:**
  ```bash
  export AGENT_HOME=/home/agent-admin/agent-app
  export AGENT_PORT=15034
  export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
  export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
  export AGENT_LOG_DIR=/var/log/agent-app
키 파일 생성: $AGENT_KEY_PATH 경로에 agent_api_key_test 내용 작성 완료.

3. 자동화 스크립트 (소스코드)
3.1. 시스템 상태 관제 스크립트 (monitor.sh)
작성자: agent-dev

파일 경로: $AGENT_HOME/bin/monitor.sh

기능: 프로세스/포트 Health Check, 방화벽 상태 점검, 자원(CPU, MEM, DISK) 사용률 수집 및 임계치 경고, 로그 누적.

자동화: agent-admin의 crontab을 통해 매분 자동 실행.

Bash
#!/bin/bash

# 환경변수 로드
AGENT_HOME=${AGENT_HOME:-"/home/agent-admin/agent-app"}
LOG_DIR=${AGENT_LOG_DIR:-"/var/log/agent-app"}
LOG_FILE="$LOG_DIR/monitor.log"
APP_NAME="agent-app"
PORT=${AGENT_PORT:-15034}

echo "====== SYSTEM MONITOR RESULT ======"

# 1. Health Check
echo -n "[HEALTH CHECK] Checking process '$APP_NAME'... "
PID=$(pgrep -f "$APP_NAME" | head -n 1)

if [ -z "$PID" ]; then
    echo "FAILED"
    echo "[ERROR] Process is not running. Exiting."
    exit 1
else
    echo "[OK] (PID: $PID)"
fi

echo -n "Checking port $PORT... "
if ss -tulnp | grep -q ":$PORT"; then
    echo "[OK]"
else
    echo "FAILED"
    echo "[ERROR] Port $PORT is not in LISTEN state. Exiting."
    exit 1
fi

# 2. Firewall Check
echo -e "\n[SECURITY]"
UFW_STATUS=$(sudo ufw status | grep -i "active")
if [ -z "$UFW_STATUS" ]; then
    echo "[WARNING] UFW Firewall is not active."
else
    echo "Firewall is Active."
fi

# 3. Resource Collection
echo -e "\n[RESOURCE MONITORING]"
CPU_USAGE=$(ps -p $PID -o %cpu= | awk '{print $1}')
MEM_USAGE=$(ps -p $PID -o %mem= | awk '{print $1}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')

echo "CPU Usage : ${CPU_USAGE}%"
echo "MEM Usage : ${MEM_USAGE}%"
echo "DISK Used : ${DISK_USAGE}%"

# 4. Threshold Warning
CPU_WARN=$(awk -v cpu="${CPU_USAGE:-0}" 'BEGIN {if (cpu > 20.0) print 1; else print 0}')
MEM_WARN=$(awk -v mem="${MEM_USAGE:-0}" 'BEGIN {if (mem > 10.0) print 1; else print 0}')

echo ""
if [ "$CPU_WARN" -eq 1 ]; then echo "[WARNING] CPU threshold exceeded (${CPU_USAGE}% > 20%)"; fi
if [ "$MEM_WARN" -eq 1 ]; then echo "[WARNING] MEM threshold exceeded (${MEM_USAGE}% > 10%)"; fi
if [ "${DISK_USAGE:-0}" -gt 80 ]; then echo "[WARNING] DISK threshold exceeded (${DISK_USAGE}% > 80%)"; fi

# 5. Logging
NOW=$(date +"%Y-%m-%d %H:%M:%S")
LOG_LINE="[$NOW] PID:$PID CPU:${CPU_USAGE}% MEM:${MEM_USAGE}% DISK_USED:${DISK_USAGE}%"
echo "$LOG_LINE" >> "$LOG_FILE"
echo -e "\n[INFO] Log appended: $LOG_FILE"
3.2. 요약 리포트 자동 생성 (report.sh - 보너스 과제)
기능: 누적된 monitor.log를 분석하여 CPU 및 메모리 사용량의 평균, 최대, 최소 수치와 측정 횟수를 요약 출력합니다.

Bash
#!/bin/bash
LOG_FILE="/var/log/agent-app/monitor.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "[ERROR] Log file not found."
    exit 1
fi

echo "====== STATISTICS REPORT ======"

awk '
BEGIN { cpu_max = 0; cpu_min = 100; cpu_sum = 0; mem_max = 0; mem_min = 100; mem_sum = 0; count = 0 }
{
    time_str = $1 " " $2; gsub(/\[|\]/, "", time_str)
    match($4, /CPU:([0-9.]+)%/, cpu_arr); match($5, /MEM:([0-9.]+)%/, mem_arr)
    cpu = cpu_arr[1]; mem = mem_arr[1]
    
    if(cpu != "") {
        cpu_sum += cpu; mem_sum += mem; count++
        if(cpu > cpu_max) { cpu_max = cpu; cpu_max_time = time_str }
        if(cpu < cpu_min) { cpu_min = cpu; cpu_min_time = time_str }
        if(mem > mem_max) { mem_max = mem; mem_max_time = time_str }
        if(mem < mem_min) { mem_min = mem; mem_min_time = time_str }
    }
}
END {
    if(count > 0) {
        printf "[CPU]\n  Average : %.1f%%\n  Maximum : %.1f%% at %s\n  Minimum : %.1f%% at %s\n", cpu_sum/count, cpu_max, cpu_max_time, cpu_min, cpu_min_time
        printf "[Memory]\n  Average : %.1f%%\n  Maximum : %.1f%% at %s\n  Minimum : %.1f%% at %s\n", mem_sum/count, mem_max, mem_max_time, mem_min, mem_min_time
        printf "[Samples]\n  Data Points: %d samples\n", count
    } else { print "No data found." }
}' "$LOG_FILE"
4. 운영 및 검증 방법
1) 애플리케이션 실행 (Boot Sequence 검증)
Bash
su - agent-admin
$AGENT_HOME/agent-app
# "Agent READY" 문구 확인 및 15034 포트 LISTEN 확인
2) 모니터링 스크립트 수동 실행 및 로그 확인
Bash
su - agent-admin
$AGENT_HOME/bin/monitor.sh
tail -f /var/log/agent-app/monitor.log
3) Crontab 스케줄러 확인
Bash
su - agent-admin
crontab -l
# 출력: * * * * * /home/agent-admin/agent-app/bin/monitor.sh > /dev/null 2>&1
4) 로그 로테이트 (용량 관리)
/etc/logrotate.d/agent-app 설정 파일을 통해 monitor.log가 10MB 초과 시 압축/백업 되며 10개까지 유지되도록 설정됨.
