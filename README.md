# 서버 모니터링 및 자동화 운영 스크립트 구축 보고서

이 문서는 서버의 기본 보안 설정(SSH, 방화벽)부터 계정 및 권한 분리, 애플리케이션 실행 환경 구축, 그리고 시스템 자원 상태를 주기적으로 관제하는 자동화 스크립트 구현에 대한 모든 수행 내역과 결과 확인 방법을 정리한 문서입니다.

---

## 1. 수행 내역 (설정 및 명령어 기록)

### 1) SSH 포트 변경 및 Root 원격 접속 차단
- **설정 파일 수정:** `sudo nano /etc/ssh/sshd_config`
- **수정 내용:**
  ```ini
  Port 20022
  PermitRootLogin no
  ```
- **서비스 재시작:** `sudo systemctl restart sshd`
- **확인 방법:** `ss -tulnp | grep sshd` 명령으로 20022 포트 LISTEN 상태 확인 및 다른 터미널에서 `ssh root@localhost -p 20022` 시도로 접근이 거부(Permission denied)되는지 확인.

### 2) 방화벽(UFW) 설정
- **방화벽 활성화:** `sudo ufw enable`
- **필수 포트 허용:** 
  ```bash
  sudo ufw allow 20022/tcp
  sudo ufw allow 15034/tcp
  ```
- **확인 방법:** `sudo ufw status` 실행하여 20022/tcp와 15034/tcp만 ALLOW 목록에 활성화되어 있는지 확인.

### 3) 계정, 그룹 및 ACL 구성
- **그룹 생성:**
  ```bash
  sudo groupadd agent-common
  sudo groupadd agent-core
  ```
- **계정 생성 및 그룹 할당:**
  ```bash
  sudo useradd -m -s /bin/bash -G agent-common,agent-core agent-admin
  sudo useradd -m -s /bin/bash -G agent-common,agent-core agent-dev
  sudo useradd -m -s /bin/bash -G agent-common agent-test
  
  # 각 계정에 대한 비밀번호 설정 (예: sudo passwd agent-admin)
  ```

### 4) 디렉토리 구조 및 권한 설정
- **기본 디렉토리 생성 (기준: `$AGENT_HOME = /home/agent-admin/agent-app`):**
  ```bash
  sudo mkdir -p /home/agent-admin/agent-app/upload_files
  sudo mkdir -p /home/agent-admin/agent-app/api_keys
  sudo mkdir -p /home/agent-admin/agent-app/bin
  sudo mkdir -p /var/log/agent-app
  ```
- **소유권 및 권한 할당:**
  ```bash
  # 소유자 지정
  sudo chown -R agent-admin:agent-common /home/agent-admin/agent-app
  sudo chown root:agent-core /var/log/agent-app
  
  # 공유 디렉토리 권한 (agent-common 그룹 소속자는 R/W 가능)
  sudo chmod 770 /home/agent-admin/agent-app/upload_files
  
  # 보안 디렉토리 권한 (agent-core 그룹 소속자만 접근 가능하도록 변경)
  sudo chown -R agent-admin:agent-core /home/agent-admin/agent-app/api_keys
  sudo chmod 770 /home/agent-admin/agent-app/api_keys
  sudo chmod 770 /var/log/agent-app
  ```
- **키 파일 생성:**
  ```bash
  echo "agent_api_key_test" | sudo tee /home/agent-admin/agent-app/api_keys/t_secret.key
  sudo chown agent-admin:agent-core /home/agent-admin/agent-app/api_keys/t_secret.key
  sudo chmod 640 /home/agent-admin/agent-app/api_keys/t_secret.key
  ```

### 5) 환경 변수 설정 및 애플리케이션 실행
- **환경 변수 프로필 등록 (예: `~/.bashrc` 혹은 스크립트 실행 전 export):**
  ```bash
  export AGENT_HOME=/home/agent-admin/agent-app
  export AGENT_PORT=15034
  export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
  export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
  export AGENT_LOG_DIR=/var/log/agent-app
  ```
- **앱 실행 방법 (일반 계정에서 실행):**
  ```bash
  # 루트 권한이 아닌 일반 사용자(agent-admin 또는 agent-dev) 환경에서
  ./agent-app
  ```

### 6) 모니터링 스크립트 작성 및 Cron 등록
- **모니터링 스크립트 배치 및 권한 부여:**
  ```bash
  sudo cp monitor.sh /home/agent-admin/agent-app/bin/
  sudo chown agent-dev:agent-core /home/agent-admin/agent-app/bin/monitor.sh
  sudo chmod 750 /home/agent-admin/agent-app/bin/monitor.sh
  ```
- **crontab 등록 (agent-admin 계정에서 수행):**
  ```bash
  su - agent-admin
  crontab -e
  # 아래 내용을 입력하여 매분 실행되도록 등록
  * * * * * /home/agent-admin/agent-app/bin/monitor.sh
  ```

---

## 2. 필수 증거 자료 체크리스트 (결과 확인 내역)
- [x] **SSH 포트 변경(20022) 및 Root 차단:** `sshd_config` 수정 내역과 `ss -tulnp`를 통한 20022 포트 정상 리슨 확인.
- [x] **방화벽 활성화 및 포트 제한:** `ufw status` 명령어 수행 시 `20022/tcp`, `15034/tcp` 포트만 ALLOW 목록에 활성화 확인.
- [x] **계정/그룹/ACL 구성:** `id agent-dev`, `id agent-test` 명령어로 각각 `agent-common` 및 `agent-core` 그룹 포함 여부 확인.
- [x] **디렉토리 구조 및 권한:** `ls -ld` 명령을 통해 `upload_files`는 `agent-common`, `api_keys` 및 로그 디렉토리는 `agent-core`로 소유 그룹과 R/W 접근 권한이 분리됨 확인.
- [x] **앱 Boot Sequence 5단계 [OK] 확인:** 터미널에서 앱 실행 시, 검증 5단계를 통과하여 마지막에 "Agent READY" 문구가 출력됨을 확인.
- [x] **monitor.sh 실행 결과:** 스크립트 단독 실행 시 프로세스(OK), 포트(OK), CPU/MEM/DISK 임계치 확인 문구가 정상 출력됨을 확인.
- [x] **/var/log/agent-app/monitor.log 누적 기록:** `tail -f /var/log/agent-app/monitor.log`로 정해진 포맷에 맞춘 데이터 누적 여부 확인.
- [x] **Crontab 1분 주기 동작 확인:** `crontab -l` 목록 등록 여부 확인 및 1분 후 `monitor.log` 파일 자동 증가분 확인.

---

## 3. 과제 목표 (서술형 설명)

1. **SSH 포트 변경과 Root 원격 접속 차단이 왜 기본 보안에 해당하는가?**
   - **설명:** 기본 포트(22번)를 사용하면 봇(Bot)을 이용한 무차별 대입 공격(Brute-Force Attack)의 표적이 되기 쉽습니다. 따라서 포트를 변경하여 자동화 공격 시도를 크게 줄입니다. 또한, 시스템의 최고 권한자인 Root 계정의 원격 접속을 차단하면, 비밀번호가 유출되더라도 일반 계정을 통한 접속이라는 1차 방어막이 형성되어 시스템 장악(Root 탈취)의 위협을 최소화할 수 있습니다.

2. **UFW 등 방화벽에서 "필요 포트만 허용(White-list)"하는 정책의 중요성**
   - **설명:** 모든 포트를 열어두면 공격자가 취약점이 존재하는 다른 서비스 데몬으로 쉽게 접근할 수 있습니다. 운영에 반드시 필요한 SSH 포트(20022)와 애플리케이션 포트(15034)만을 명시적으로 허용하면 잠재적인 공격 표면(Attack Surface)을 획기적으로 줄여, 안전한 운영 환경을 보장합니다.

3. **역할 기반 계정/그룹과 ACL을 통해 “공유 디렉토리”와 “보안 디렉토리”를 분리하는 이유**
   - **설명:** 시스템 내에는 시스템 관리자, 개발자, 테스터 등 다양한 역할이 존재합니다. 모든 사용자에게 동일한 권한을 부여하면 실수나 악의적인 접근으로 핵심 데이터(예: 키 파일, 로그 파일)가 위변조되거나 삭제될 수 있습니다. `agent-common` 그룹을 통해 협업이 필요한 일반 파일을 공유하고, 민감 정보가 담긴 디렉토리는 `agent-core` 등 특정 그룹만 접근하도록 ACL(접근 제어 목록) 혹은 권한을 설정함으로써 "최소 권한의 원칙"을 구현할 수 있습니다.

4. **환경 변수(AGENT_HOME 등)로 실행 환경을 고정하는 이유와 검증 방법**
   - **설명:** 앱 구동에 필요한 포트, 디렉토리 경로, 키 위치 등을 소스 코드 내에 하드 코딩하면 환경(개발, 테스트, 운영)이 바뀔 때마다 코드를 매번 수정해야 하는 문제가 발생합니다. 환경 변수를 사용하면 코드를 수정하지 않고 유연하게 실행 환경을 변경할 수 있습니다. 검증은 애플리케이션 실행 전 `echo $AGENT_HOME`으로 값이 세팅되어 있는지 확인하거나, 앱 실행 초기 Boot Sequence 상에서 환경 변수를 체크하여 실패/성공을 띄우는 방식으로 검증합니다.

5. **쉘 스크립트 모니터링/로깅 구축 및 Crontab을 활용한 로그 보존 정책의 필요성**
   - **설명:** 서비스에 장애가 발생하면 과거 시스템 자원 상태(CPU, 메모리, 포트 상태) 데이터가 있어야 정확한 원인을 분석할 수 있습니다. 쉘 스크립트로 상태를 자동 수집하고, `crontab`을 통해 사람의 개입 없이 상시 관제 체계를 유지합니다. 추가적으로 로그가 끝없이 쌓여 디스크 용량을 초과하는 장애를 막기 위해, 주기적으로 로그를 회전(Log Rotation)하고 압축/삭제(아카이빙)하는 정책이 시스템 안정성에 필수적입니다.

---

## 4. 자동화 스크립트 구현 내용
이 작업 디렉토리에는 시스템 관제를 자동화하기 위한 3가지 Bash 스크립트가 포함되어 있습니다. 모든 스크립트는 `Bash` 기반으로 작성되었으며, 지정된 요구사항과 보너스 요건을 충족합니다.

* **`monitor.sh`**:
  - 앱 프로세스와 포트(15034) 상태 점검
  - CPU, Memory, Disk 자원 사용률 수집 및 임계치 경고
  - 방화벽 활성화 상태 점검
  - `/var/log/agent-app/monitor.log` 파일에 로그 지속 기록 및 10MB 크기 제한 로테이션 수행.

* **`report.sh`** (보너스 과제 1):
  - `monitor.log`의 데이터를 분석하여 CPU, Memory의 최소, 최대, 평균 사용량 및 샘플 수를 콘솔로 포맷팅하여 출력.

* **`archive.sh`** (보너스 과제 2):
  - 주기적으로 실행되며, 7일이 지난 모니터링 로그 파일을 `.gz` 포맷으로 압축하고 별도 아카이브 디렉토리로 이동.
  - 30일이 초과한 아카이브 파일은 자동 삭제하여 디스크를 안전하게 보호 및 관리.
