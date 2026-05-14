#!/bin/bash

# ==========================================
# 통계 리포트 생성 스크립트 (report.sh) - 보너스 1
# ==========================================

LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "Log file not found: $LOG_FILE"
    exit 1
fi

awk '
BEGIN {
    cpu_sum=0; cpu_max=0; cpu_min=999;
    mem_sum=0; mem_max=0; mem_min=999;
    count=0;
}
{
    # Log Format: [YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
    # $1="[YYYY-MM-DD", $2="HH:MM:SS]", $4="CPU:X%", $5="MEM:Y%"
    date_str = substr($1, 2) " " substr($2, 1, length($2)-1)
    
    split($4, c, ":"); gsub("%", "", c[2]); cpu=c[2]+0;
    split($5, m, ":"); gsub("%", "", m[2]); mem=m[2]+0;
    
    count++;
    
    cpu_sum += cpu;
    if(cpu > cpu_max) { cpu_max = cpu; cpu_max_dt = date_str }
    if(cpu < cpu_min) { cpu_min = cpu; cpu_min_dt = date_str }

    mem_sum += mem;
    if(mem > mem_max) { mem_max = mem; mem_max_dt = date_str }
    if(mem < mem_min) { mem_min = mem; mem_min_dt = date_str }
}
END {
    print "    ====== STATISTICS REPORT ======"
    if(count == 0) {
        print "      No data points found."
        exit
    }
    print "      [CPU]"
    printf "        Average : %.1f%%\n", (cpu_sum/count)
    printf "        Maximum : %.1f%% at %s\n", cpu_max, cpu_max_dt
    printf "        Minimum : %.1f%% at %s\n", cpu_min, cpu_min_dt
    
    print "      [Memory]"
    printf "        Average : %.1f%%\n", (mem_sum/count)
    printf "        Maximum : %.1f%% at %s\n", mem_max, mem_max_dt
    printf "        Minimum : %.1f%% at %s\n", mem_min, mem_min_dt
    
    print "      [Samples]"
    print "        Data Points: " count " samples"
}' "$LOG_FILE"
