#!/bin/bash
# Prime 수집 서버 설치(R-ADV-1120-2306). boot.sh 가 부름. 비밀값 0 — 서명 키는 이 서버가 스스로 만들고 밖으로 내보내지 않아요.
set -euo pipefail
KIT=/opt/prime-collector/kit
VAR=/var/lib/prime-collector
ETC=/etc/prime-collector
WAIT_MIN=${PRIME_WAIT_MIN:-15}
INSTALL_ONLY=${PRIME_INSTALL_ONLY:-0}
[[ "$INSTALL_ONLY" = 0 || "$INSTALL_ONLY" = 1 ]] || { echo "PRIME_INSTALL_ONLY must be 0 or 1"; exit 1; }
export DEBIAN_FRONTEND=noninteractive
step() { echo "[$(date +%H:%M:%S)] $*"; }
[ "$(id -u)" -eq 0 ] || { echo "sudo 로 실행해 주세요"; exit 1; }
case "$(uname -m)" in
  x86_64) DEB_ARCH=amd64 ;;
  aarch64|arm64) DEB_ARCH=arm64 ;;
  *) echo "지원하지 않는 CPU예요: x86_64 또는 aarch64가 필요해요."; exit 1 ;;
esac
step "1/6 기본 꾸러미 설치(3~5분)"
apt-get update -qq >/dev/null
apt-get install -y -qq python3 python3-venv python3-pip python3-cryptography python3-aiohttp xvfb x11vnc novnc openbox \
  fonts-noto-cjk curl ca-certificates procps sudo >/dev/null
step "2/6 Chrome"
if [ "$DEB_ARCH" = arm64 ]; then
  # Ubuntu chromium apt package is a snap transition package. Use the official
  # Playwright arm64 Chromium build; do not use an amd64 Chrome package on ARM.
  python3 -m venv /opt/prime-chromium-venv
  /opt/prime-chromium-venv/bin/pip install --disable-pip-version-check 'playwright==1.64.1' >/dev/null
  PLAYWRIGHT_BROWSERS_PATH=/opt/prime-browsers /opt/prime-chromium-venv/bin/playwright install --with-deps chromium >/dev/null
  BROWSER=$(PLAYWRIGHT_BROWSERS_PATH=/opt/prime-browsers /opt/prime-chromium-venv/bin/python -c 'from playwright.sync_api import sync_playwright; p=sync_playwright().start(); print(p.chromium.executable_path); p.stop()')
  [ -x "$BROWSER" ] || { echo "ARM Chromium 실행 파일이 없어요"; exit 1; }
  ln -sf "$BROWSER" /usr/local/bin/google-chrome
  # Ubuntu 24.04 restricts user namespaces outside packaged Chrome's path.
  # Permit the sandbox for this root-owned browser only; keep the system-wide
  # restriction and Chromium sandbox enabled.
  apt-get install -y -qq apparmor >/dev/null
  printf 'abi <abi/4.0>,\ninclude <tunables/global>\nprofile prime-chromium "%s" flags=(unconfined) {\n  userns,\n}\n' "$BROWSER" > /etc/apparmor.d/prime-chromium
  if [ -d /sys/kernel/security/apparmor ]; then
    apparmor_parser -r /etc/apparmor.d/prime-chromium
  fi
elif ! command -v google-chrome >/dev/null; then
  curl -fsSLo /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb
  apt-get install -y -qq /tmp/chrome.deb >/dev/null && rm -f /tmp/chrome.deb
fi
mkdir -p /etc/opt/chrome/policies/managed
cat > /etc/opt/chrome/policies/managed/prime.json <<'J'
{"PasswordManagerEnabled": false, "PasswordLeakDetectionEnabled": false, "AutofillAddressEnabled": false,
 "AutofillCreditCardEnabled": false, "SyncDisabled": true, "BrowserSignin": 0, "MetricsReportingEnabled": false}
J
google-chrome --version
if [ "$DEB_ARCH" = arm64 ]; then
  install -d /etc/chromium/policies/managed
  install -m 644 /etc/opt/chrome/policies/managed/prime.json /etc/chromium/policies/managed/prime.json
fi
step "3/6 원격 화면 도구(cloudflared — 나가는 연결 전용)"
if ! command -v cloudflared >/dev/null; then
  curl -fsSLo /tmp/cf.deb "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${DEB_ARCH}.deb"
  dpkg -i /tmp/cf.deb >/dev/null && rm -f /tmp/cf.deb
fi
step "4/6 실행 사용자·폴더"
id prime >/dev/null 2>&1 || useradd --system --create-home --home-dir $VAR --shell /usr/sbin/nologin prime
install -d -o prime -g prime -m 700 $ETC $VAR
install -o prime -g prime -m 600 $KIT/config.json $ETC/config.json
chmod 755 $KIT/prime $KIT/prime-screen.sh
ln -sf $KIT/prime /usr/local/bin/prime
if [ "$INSTALL_ONLY" = 1 ]; then
  echo "INSTALL_ONLY_OK arch=$DEB_ARCH (서명 키 생성·등록·서비스 시작 안 함)"
  exit 0
fi
step "5/6 서명 키(이 서버 안에서만 만듦·권한 600)"
sudo -u prime -H python3 $KIT/agent.py code >/dev/null
ls -l $ETC/host_key.pem | awk '{print "   키 파일 권한 " $1 " 소유 " $3}'
step "6/6 서비스 등록(재부팅 뒤 자동 시작)"
if [ -d /run/systemd/system ]; then
  install -m 644 $KIT/prime-collector.service /etc/systemd/system/prime-collector.service
  systemctl daemon-reload
  systemctl enable --now prime-collector.service >/dev/null 2>&1
  systemctl restart prime-collector.service
  echo "   systemd: $(systemctl is-enabled prime-collector) / $(systemctl is-active prime-collector)"
  # R-ADV-1120-2325 저절로 낫기(1분 timer) · 원격 로그인 화면 요청 감지(path) — 끄기: systemctl disable --now prime-heal.timer
  for u in prime-heal.service prime-heal.timer prime-screen-req.service prime-screen-req.path; do
    [ -f $KIT/$u ] && install -m 644 $KIT/$u /etc/systemd/system/$u
  done
  systemctl daemon-reload
  [ -f $KIT/prime-heal.timer ] && systemctl enable --now prime-heal.timer >/dev/null 2>&1 || true
  [ -f $KIT/prime-screen-req.path ] && systemctl enable --now prime-screen-req.path >/dev/null 2>&1 || true
  echo "   저절로 낫기: $(systemctl is-active prime-heal.timer 2>/dev/null) · 원격 화면 요청 감지: $(systemctl is-active prime-screen-req.path 2>/dev/null)"
else
  pkill -u prime -f "agent.py run" 2>/dev/null || true
  sudo -u prime -H setsid python3 $KIT/agent.py run </dev/null >>$VAR/agent.out 2>&1 &
  echo "   systemd 없음(시험 환경) — 에이전트를 바로 띄웠어요"
fi
CODE=$(sudo -u prime -H python3 $KIT/agent.py code)
echo
echo "┌──────────────────────────────────────────┐"
echo "│  등록 코드:  $CODE                    │"
echo "│  이 8글자를 Claude 대화창에 보내 주세요.  │"
echo "└──────────────────────────────────────────┘"
echo "(창을 닫아도 돼요. 다시 보기: prime code)"
echo
for i in $(seq 1 $((WAIT_MIN*6))); do
  if [ -f $VAR/status.json ] && grep -q '"enabled"' $VAR/status.json; then echo "등록 완료 — 이제 이 서버가 스스로 일을 받아 와요."; exit 0; fi
  sleep 10
done
echo "아직 승인 전이에요. 승인되면 자동으로 시작돼요(확인: prime status)."
